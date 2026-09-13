-- Knowledge Base objects on the server.
--
-- An "object" is a `.unearth` file: a World and its economy today, a Timeline
-- later. Objects used to be local-only, which meant a collaborator could open
-- the same Knowledge Base and never see the other's map or cities. This
-- migration gives them durable rows and revisions in the same shape documents
-- already use.
--
-- Design notes:
--   * The object id is the id inside the `.unearth` JSON, chosen by the
--     creating client, so an object keeps one identity across renames and on
--     every machine.
--   * Writes go through `publish_object` only; clients receive no insert or
--     update grant. The optimistic revision check raises the same `40001`
--     conflict documents use, via the existing publish gate.
--   * `kb:<kbId>` stays server-authored: the trigger below is what publishes
--     `object_published`, and the payload is identifiers only. Peers read the
--     durable rows from Postgres.

create table if not exists public.kb_objects (
  id uuid primary key,
  kb_id uuid not null references public.knowledge_bases(id) on delete cascade,
  kind text not null,
  path text not null,
  title text not null default '',
  current_revision_id uuid,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One live object per path, exactly like documents. A second object may reuse
-- the path only after the first is canonically deleted.
create unique index if not exists kb_objects_live_path_idx
  on public.kb_objects (kb_id, path)
  where deleted_at is null;

create index if not exists kb_objects_kb_idx
  on public.kb_objects (kb_id);

create table if not exists public.kb_object_revisions (
  id uuid primary key default gen_random_uuid(),
  kb_id uuid not null references public.knowledge_bases(id) on delete cascade,
  object_id uuid not null references public.kb_objects(id) on delete cascade,
  parent_revision_id uuid references public.kb_object_revisions(id)
    on delete set null,
  content jsonb not null,
  content_hash text not null,
  author_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create index if not exists kb_object_revisions_object_idx
  on public.kb_object_revisions (object_id, created_at);

alter table public.kb_objects
  drop constraint if exists kb_objects_current_revision_fkey;
alter table public.kb_objects
  add constraint kb_objects_current_revision_fkey
  foreign key (current_revision_id)
  references public.kb_object_revisions(id)
  on delete set null;

alter table public.kb_objects enable row level security;
alter table public.kb_object_revisions enable row level security;

-- Members read; nothing writes directly. `is_kb_member` includes reviewers,
-- because reading a shared World is not an edit.
drop policy if exists kb_objects_member_read on public.kb_objects;
create policy kb_objects_member_read on public.kb_objects
  for select to authenticated
  using ((select private.is_kb_member(kb_id)));

drop policy if exists kb_object_revisions_member_read
  on public.kb_object_revisions;
create policy kb_object_revisions_member_read on public.kb_object_revisions
  for select to authenticated
  using ((select private.is_kb_member(kb_id)));

revoke all on table public.kb_objects from anon, authenticated;
revoke all on table public.kb_object_revisions from anon, authenticated;
grant select on table public.kb_objects to authenticated;
grant select on table public.kb_object_revisions to authenticated;

-- Publishes one object revision. Creates the object on first publish and
-- updates it afterwards; `p_expected_current_revision` is the revision this
-- device last observed, and a mismatch is a conflict rather than an overwrite.
--
-- Returns a JSON object so the conflict path can answer with a PostgREST
-- error body (`code: 40001`) exactly as `publish_document_change` does; a
-- `returns uuid` function would discard that body.
--
-- The publish gate is keyed on a uuid, which is a document id for documents;
-- object ids spend the same per-caller budget without changing its shape.
create or replace function public.publish_object(
  p_kb_id uuid,
  p_object_id uuid,
  p_kind text,
  p_path text,
  p_title text,
  p_content jsonb,
  p_content_hash text,
  p_expected_current_revision uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_object public.kb_objects;
  v_revision_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  -- Before any query that costs something.
  perform private.publish_gate_assert(p_object_id, v_uid);

  if not private.can_edit_kb(p_kb_id) then
    raise exception 'edit permission required' using errcode = '42501';
  end if;
  if p_content is null
     or p_content_hash is null
     or nullif(btrim(p_kind), '') is null
     or nullif(btrim(p_path), '') is null
     or p_content ->> 'id' is distinct from p_object_id::text then
    raise exception 'invalid object content' using errcode = '22023';
  end if;

  -- A path is a location, not an identity: two live objects may not share one.
  if exists (
    select 1
      from public.kb_objects o
     where o.kb_id = p_kb_id
       and o.path = p_path
       and o.id <> p_object_id
       and o.deleted_at is null
  ) then
    return private.publish_conflict(p_object_id, v_uid);
  end if;

  select * into v_object
    from public.kb_objects
   where id = p_object_id
   for update;

  if not found then
    if p_expected_current_revision is not null then
      return private.publish_conflict(p_object_id, v_uid);
    end if;
    insert into public.kb_objects (id, kb_id, kind, path, title)
    values (p_object_id, p_kb_id, p_kind, p_path, p_title)
    returning * into v_object;
  else
    if v_object.kb_id <> p_kb_id then
      raise exception 'object belongs to another knowledge base'
        using errcode = '22023';
    end if;
    if v_object.current_revision_id is distinct from
        p_expected_current_revision then
      return private.publish_conflict(p_object_id, v_uid);
    end if;
    update public.kb_objects
       set kind = p_kind,
           path = p_path,
           title = p_title,
           deleted_at = null,
           updated_at = now()
     where id = p_object_id;
  end if;

  -- Past this point the call is going to land, so the caller is healthy.
  perform private.publish_gate_clear(p_object_id, v_uid);

  insert into public.kb_object_revisions (
    kb_id, object_id, parent_revision_id, content, content_hash, author_id
  )
  values (
    p_kb_id,
    p_object_id,
    v_object.current_revision_id,
    p_content,
    p_content_hash,
    v_uid
  )
  returning id into v_revision_id;

  update public.kb_objects
     set current_revision_id = v_revision_id,
         updated_at = now()
   where id = p_object_id;

  return jsonb_build_object('revision_id', v_revision_id);
end;
$$;

revoke all on function public.publish_object(
  uuid, uuid, text, text, text, jsonb, text, uuid
) from anon, public;
grant execute on function public.publish_object(
  uuid, uuid, text, text, text, jsonb, text, uuid
) to authenticated;

-- The wake-up. Identifiers only: a peer that sees this reads the durable rows
-- itself, and a forged payload could not drive a sync from nothing.
create or replace function private.notify_object_published()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'object_id', new.id,
      'kind', new.kind,
      'path', new.path,
      'revision_id', new.current_revision_id,
      'deleted', new.deleted_at is not null
    ),
    'object_published',
    'kb:' || new.kb_id::text,
    true
  );
  return new;
end;
$$;

drop trigger if exists kb_objects_notify_published on public.kb_objects;
create trigger kb_objects_notify_published
  after update of current_revision_id, deleted_at
  on public.kb_objects
  for each row
  when (
    old.current_revision_id is distinct from new.current_revision_id
    or old.deleted_at is distinct from new.deleted_at
  )
  execute function private.notify_object_published();
