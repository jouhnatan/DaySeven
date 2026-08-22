-- Explicit publishing with per-document protection.
--
-- Local autosave remains device-local. An authenticated Editor, Co-Owner, or
-- Owner calls publish_document_change when they explicitly press Publish (or
-- Propose). The server locks the document and decides in the same transaction
-- whether to append one canonical revision or upsert that author's pending
-- change set. Clients therefore cannot bypass protection with a stale UI.

alter table public.documents
  add column if not exists protection_class text,
  add column if not exists minimum_publish_role text;

alter table public.documents
  drop constraint if exists documents_protection_consistent;
alter table public.documents
  add constraint documents_protection_consistent check (
    (protection_class is null and minimum_publish_role is null)
    or (
      protection_class = 'protected'
      and minimum_publish_role in ('editor', 'co_owner', 'owner')
    )
  );

create or replace function private.kb_member_role_rank(p_kb_id uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select case m.role
    when 'editor' then 1
    when 'co_owner' then 2
    when 'owner' then 3
    else 0
  end
    from public.kb_members m
   where m.kb_id = p_kb_id
     and m.user_id = (select auth.uid())
     and m.accepted_at is not null;
$$;

create or replace function private.publish_role_rank(p_role text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case p_role
    when 'editor' then 1
    when 'co_owner' then 2
    when 'owner' then 3
    else 0
  end;
$$;

create or replace function private.can_publish_document(
  p_kb_id uuid,
  p_document_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select private.kb_member_role_rank(p_kb_id) > 0
       and (
         d.protection_class is null
         or private.kb_member_role_rank(p_kb_id)
              >= private.publish_role_rank(d.minimum_publish_role)
       )
      from public.documents d
     where d.id = p_document_id
       and d.kb_id = p_kb_id
  ), false);
$$;

create or replace function private.set_document_protection(
  p_kb_id uuid,
  p_document_id uuid,
  p_protection_class text,
  p_minimum_publish_role text
)
returns public.documents
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_rank integer;
  v_doc public.documents;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  v_rank := private.kb_member_role_rank(p_kb_id);
  if coalesce(v_rank, 0) = 0 then
    raise exception 'edit permission required' using errcode = '42501';
  end if;

  select * into v_doc
    from public.documents
   where id = p_document_id
     and kb_id = p_kb_id
     and deleted_at is null
   for update;
  if not found then
    raise exception 'document not found' using errcode = 'P0002';
  end if;

  -- Changing or removing an existing lock requires meeting its current bar.
  if v_doc.protection_class is not null
     and v_rank < private.publish_role_rank(v_doc.minimum_publish_role) then
    raise exception 'the current protection level is above your role'
      using errcode = '42501';
  end if;

  if p_protection_class is null and p_minimum_publish_role is null then
    update public.documents
       set protection_class = null,
           minimum_publish_role = null,
           updated_at = now()
     where id = p_document_id
    returning * into v_doc;
    return v_doc;
  end if;

  if p_protection_class is distinct from 'protected'
     or private.publish_role_rank(p_minimum_publish_role) = 0 then
    raise exception 'invalid protection policy' using errcode = '22023';
  end if;
  if private.publish_role_rank(p_minimum_publish_role) > v_rank then
    raise exception 'you cannot set protection above your own role'
      using errcode = '42501';
  end if;

  update public.documents
     set protection_class = p_protection_class,
         minimum_publish_role = p_minimum_publish_role,
         updated_at = now()
   where id = p_document_id
  returning * into v_doc;
  return v_doc;
end;
$$;

create or replace function public.set_document_protection(
  p_kb_id uuid,
  p_document_id uuid,
  p_protection_class text,
  p_minimum_publish_role text
)
returns public.documents
language sql
security invoker
set search_path = ''
as $$
  select private.set_document_protection(
    p_kb_id,
    p_document_id,
    p_protection_class,
    p_minimum_publish_role
  );
$$;

create or replace function private.publish_document_change(
  p_kb_id uuid,
  p_document_id uuid,
  p_operation text,
  p_relative_path text,
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
  v_rank integer;
  v_doc public.documents;
  v_revision_id uuid;
  v_change_set public.change_sets;
  v_direct boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  v_rank := private.kb_member_role_rank(p_kb_id);
  if coalesce(v_rank, 0) = 0 then
    raise exception 'edit permission required' using errcode = '42501';
  end if;
  if p_operation not in ('create', 'update', 'delete') then
    raise exception 'invalid publish operation' using errcode = '22023';
  end if;
  if nullif(btrim(p_relative_path), '') is null then
    raise exception 'a document path is required' using errcode = '22023';
  end if;
  if p_operation <> 'delete' and (
    p_content is null
    or p_content_hash is null
    or p_content ->> 'id' is distinct from p_document_id::text
  ) then
    raise exception 'invalid document content' using errcode = '22023';
  end if;
  if p_operation = 'delete' and (p_content is not null or p_content_hash is not null) then
    raise exception 'delete cannot contain document content' using errcode = '22023';
  end if;

  select * into v_doc
    from public.documents
   where id = p_document_id
   for update;

  if p_operation = 'create' then
    if found or p_expected_current_revision is not null then
      raise exception 'document moved on; refresh before publishing'
        using errcode = '40001';
    end if;
    -- A new document has no protection policy yet, so all editing roles may
    -- explicitly publish it. It can be protected after its first revision.
    insert into public.documents (id, kb_id, path, title)
    values (
      p_document_id,
      p_kb_id,
      p_relative_path,
      coalesce(p_content ->> 'title', '')
    )
    returning * into v_doc;
    v_direct := true;
  else
    if not found or v_doc.kb_id <> p_kb_id or v_doc.deleted_at is not null then
      raise exception 'document is not active in this knowledge base'
        using errcode = '22023';
    end if;
    if v_doc.current_revision_id is distinct from p_expected_current_revision then
      raise exception 'document moved on; refresh before publishing'
        using errcode = '40001';
    end if;
    v_direct := v_doc.protection_class is null
      or v_rank >= private.publish_role_rank(v_doc.minimum_publish_role);
  end if;

  if not v_direct then
    if p_operation = 'update' then
      v_change_set := private.submit_change_set(
        p_kb_id,
        p_document_id,
        p_document_id,
        v_doc.current_revision_id,
        'update',
        case when p_relative_path is distinct from v_doc.path
          then p_relative_path else null end,
        p_content
      );
    else
      v_change_set := private.submit_change_set(
        p_kb_id,
        p_document_id,
        p_document_id,
        v_doc.current_revision_id,
        'delete',
        p_relative_path,
        null
      );
    end if;
    return jsonb_build_object('outcome', 'proposed', 'id', v_change_set.id);
  end if;

  if p_operation = 'delete' then
    update public.documents
       set deleted_at = now(), updated_at = now()
     where id = p_document_id;
    update public.change_sets
       set status = 'withdrawn', resolved_at = now(), resolved_by = v_uid,
           review_note = 'Superseded by direct publish'
     where kb_id = p_kb_id
       and target_document_id = p_document_id
       and author_id = v_uid
       and status = 'pending';
    return jsonb_build_object('outcome', 'published', 'id', p_document_id);
  end if;

  insert into public.revisions (
    kb_id, document_id, parent_revision_id, content, content_hash, author_id
  ) values (
    p_kb_id, p_document_id, v_doc.current_revision_id,
    p_content, p_content_hash, v_uid
  )
  returning id into v_revision_id;

  update public.documents
     set current_revision_id = v_revision_id,
         path = p_relative_path,
         title = coalesce(p_content ->> 'title', ''),
         updated_at = now()
   where id = p_document_id;

  -- A successful direct publish only supersedes this publisher's draft.
  -- Proposals from other collaborators remain independently reviewable.
  update public.change_sets
     set status = 'withdrawn', resolved_at = now(), resolved_by = v_uid,
         review_note = 'Superseded by direct publish'
   where kb_id = p_kb_id
     and target_document_id = p_document_id
     and author_id = v_uid
     and status = 'pending';

  return jsonb_build_object('outcome', 'published', 'id', v_revision_id);
end;
$$;

create or replace function public.publish_document_change(
  p_kb_id uuid,
  p_document_id uuid,
  p_operation text,
  p_relative_path text,
  p_content jsonb,
  p_content_hash text,
  p_expected_current_revision uuid
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.publish_document_change(
    p_kb_id,
    p_document_id,
    p_operation,
    p_relative_path,
    p_content,
    p_content_hash,
    p_expected_current_revision
  );
$$;

-- Keep the old manager-only RPC safe for older clients. It now delegates to
-- the protection-aware transaction and refuses to turn a supposed direct
-- publish into a proposal.
create or replace function private.publish_document_directly(
  p_kb_id uuid,
  p_document_id uuid,
  p_relative_path text,
  p_content jsonb,
  p_content_hash text,
  p_expected_current_revision uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not private.can_manage_kb(p_kb_id) then
    raise exception 'only an owner or co-owner can publish directly'
      using errcode = '42501';
  end if;
  if exists (
    select 1 from public.documents d
     where d.id = p_document_id
       and d.kb_id = p_kb_id
       and not private.can_publish_document(p_kb_id, p_document_id)
  ) then
    raise exception 'this protected document requires review for your role'
      using errcode = '42501';
  end if;
  v_result := private.publish_document_change(
    p_kb_id,
    p_document_id,
    case when p_expected_current_revision is null then 'create' else 'update' end,
    p_relative_path,
    p_content,
    p_content_hash,
    p_expected_current_revision
  );
  return (v_result ->> 'id')::uuid;
end;
$$;

-- Older table-write clients may continue to publish unprotected Manager
-- changes, but cannot move a protected canonical pointer below its threshold.
drop policy if exists documents_update_manager on public.documents;
create policy documents_update_protection_aware on public.documents
  for update to authenticated
  using ((select private.can_publish_document(kb_id, id)))
  with check ((select private.can_publish_document(kb_id, id)));

-- Protection columns are RPC-only, preventing a raw table update/insert from
-- changing the policy without comparing the caller's rank to the old policy.
revoke update on table public.documents from authenticated;
grant update (path, title, current_revision_id, deleted_at, updated_at)
  on table public.documents to authenticated;
revoke insert on table public.documents from authenticated;
grant insert (id, kb_id, path, title, current_revision_id, created_at, updated_at, deleted_at)
  on table public.documents to authenticated;

create or replace function private.notify_document_published()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'document_id', new.id,
      'revision_id', new.current_revision_id,
      'deleted', new.deleted_at is not null
    ),
    'document_published',
    'kb:' || new.kb_id::text,
    true
  );
  return new;
end;
$$;

create or replace function private.notify_document_protection_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'document_id', new.id,
      'protection_class', new.protection_class,
      'minimum_publish_role', new.minimum_publish_role
    ),
    'document_protection_changed',
    'kb:' || new.kb_id::text,
    true
  );
  return new;
end;
$$;

drop trigger if exists documents_notify_published on public.documents;
create trigger documents_notify_published
  after update of current_revision_id, deleted_at
  on public.documents
  for each row
  when (
    old.current_revision_id is distinct from new.current_revision_id
    or old.deleted_at is distinct from new.deleted_at
  )
  execute function private.notify_document_published();

drop trigger if exists documents_notify_protection_changed on public.documents;
create trigger documents_notify_protection_changed
  after update of protection_class, minimum_publish_role
  on public.documents
  for each row
  when (
    old.protection_class is distinct from new.protection_class
    or old.minimum_publish_role is distinct from new.minimum_publish_role
  )
  execute function private.notify_document_protection_changed();

grant execute on function private.kb_member_role_rank(uuid) to authenticated;
grant execute on function private.publish_role_rank(text) to authenticated;
grant execute on function private.can_publish_document(uuid, uuid) to authenticated;
grant execute on function private.set_document_protection(uuid, uuid, text, text)
  to authenticated;
grant execute on function private.publish_document_change(
  uuid, uuid, text, text, jsonb, text, uuid
) to authenticated;

revoke execute on function private.kb_member_role_rank(uuid) from public, anon;
revoke execute on function private.publish_role_rank(text) from public, anon;
revoke execute on function private.can_publish_document(uuid, uuid) from public, anon;
revoke execute on function private.set_document_protection(uuid, uuid, text, text)
  from public, anon;
revoke execute on function private.publish_document_change(
  uuid, uuid, text, text, jsonb, text, uuid
) from public, anon;

revoke execute on function public.set_document_protection(uuid, uuid, text, text)
  from public, anon;
grant execute on function public.set_document_protection(uuid, uuid, text, text)
  to authenticated;
revoke execute on function public.publish_document_change(
  uuid, uuid, text, text, jsonb, text, uuid
) from public, anon;
grant execute on function public.publish_document_change(
  uuid, uuid, text, text, jsonb, text, uuid
) to authenticated;
