-- Make reviewed submission the normal collaborative path for Editors and
-- Co-Owners. The existing per-author/document partial unique index continues
-- to make this an upsert into one pending proposal per collaborator.

create or replace function private.submit_change_set(
  p_kb_id uuid,
  p_document_id uuid,
  p_target_document_id uuid,
  p_base_revision_id uuid,
  p_operation text,
  p_proposed_path text,
  p_content jsonb
)
returns public.change_sets
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_result public.change_sets;
begin
  if not private.has_kb_role(
    p_kb_id,
    array['editor', 'co_owner']::text[]
  ) then
    raise exception 'only an editor or co-owner can submit a proposal'
      using errcode = '42501';
  end if;

  if p_operation not in ('create', 'update', 'delete') then
    raise exception 'invalid proposal operation' using errcode = '22023';
  end if;
  if p_target_document_id is null then
    raise exception 'target document is required' using errcode = '22023';
  end if;

  if p_operation = 'create' then
    if p_document_id is not null
       or p_base_revision_id is not null
       or p_content is null
       or nullif(btrim(p_proposed_path), '') is null
       or p_content ->> 'id' is distinct from p_target_document_id::text then
      raise exception 'invalid create proposal' using errcode = '22023';
    end if;
    if exists (
      select 1
        from public.documents d
       where d.id = p_target_document_id
    ) then
      raise exception 'target document already exists' using errcode = '23505';
    end if;
  else
    if p_document_id is null or p_target_document_id <> p_document_id then
      raise exception 'invalid document target' using errcode = '22023';
    end if;
    if not exists (
      select 1
        from public.documents d
       where d.id = p_document_id
         and d.kb_id = p_kb_id
         and d.deleted_at is null
    ) then
      raise exception 'document is not in this knowledge base'
        using errcode = '22023';
    end if;
    if not exists (
      select 1
        from public.revisions r
       where r.id = p_base_revision_id
         and r.document_id = p_document_id
         and r.kb_id = p_kb_id
    ) then
      raise exception 'invalid base revision' using errcode = '22023';
    end if;
    if p_operation = 'update' and (
      p_content is null
      or p_content ->> 'id' is distinct from p_document_id::text
    ) then
      raise exception 'invalid update content' using errcode = '22023';
    end if;
    if p_operation = 'delete' and p_content is not null then
      raise exception 'delete proposals cannot contain content'
        using errcode = '22023';
    end if;
  end if;

  insert into public.change_sets as cs (
    kb_id,
    document_id,
    target_document_id,
    base_revision_id,
    operation,
    proposed_path,
    content,
    author_id,
    status
  ) values (
    p_kb_id,
    p_document_id,
    p_target_document_id,
    p_base_revision_id,
    p_operation,
    p_proposed_path,
    p_content,
    v_uid,
    'pending'
  )
  on conflict (kb_id, author_id, target_document_id)
    where status = 'pending'
  do update set
    document_id = excluded.document_id,
    base_revision_id = excluded.base_revision_id,
    operation = excluded.operation,
    proposed_path = excluded.proposed_path,
    content = excluded.content,
    updated_at = now()
  returning cs.* into v_result;

  return v_result;
end;
$$;

-- Explicit direct publishing supersedes the caller's own reviewed draft. This
-- is status-only: no canonical document or revision is touched here.
create or replace function private.withdraw_pending_change_set(
  p_kb_id uuid,
  p_target_document_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.can_manage_kb(p_kb_id) then
    raise exception 'only an owner or co-owner can publish directly'
      using errcode = '42501';
  end if;

  update public.change_sets
     set status = 'withdrawn',
         resolved_at = now(),
         resolved_by = v_uid,
         review_note = 'Superseded by direct publish'
   where kb_id = p_kb_id
     and target_document_id = p_target_document_id
     and author_id = v_uid
     and status = 'pending';
end;
$$;

create or replace function public.withdraw_pending_change_set(
  p_kb_id uuid,
  p_target_document_id uuid
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.withdraw_pending_change_set(p_kb_id, p_target_document_id);
$$;

grant execute on function private.withdraw_pending_change_set(uuid, uuid)
  to authenticated;
revoke execute on function private.withdraw_pending_change_set(uuid, uuid)
  from public, anon;

revoke execute on function public.withdraw_pending_change_set(uuid, uuid)
  from public, anon;
grant execute on function public.withdraw_pending_change_set(uuid, uuid)
  to authenticated;

-- Direct publishing is an explicit manager action. Keep its revision insert
-- and canonical pointer update in one short transaction, guarded by the same
-- optimistic current-revision comparison used by proposal approval.
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
  v_uid uuid := (select auth.uid());
  v_doc public.documents;
  v_revision_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.can_manage_kb(p_kb_id) then
    raise exception 'only an owner or co-owner can publish directly'
      using errcode = '42501';
  end if;
  if p_content ->> 'id' is distinct from p_document_id::text
     or nullif(btrim(p_relative_path), '') is null then
    raise exception 'invalid direct publish payload' using errcode = '22023';
  end if;

  select * into v_doc
    from public.documents
   where id = p_document_id
   for update;

  if found then
    if v_doc.kb_id <> p_kb_id or v_doc.deleted_at is not null then
      raise exception 'document is not active in this knowledge base'
        using errcode = '22023';
    end if;
    if v_doc.current_revision_id is distinct from p_expected_current_revision then
      raise exception 'document moved on; sync before publishing directly'
        using errcode = '40001';
    end if;
  else
    if p_expected_current_revision is not null then
      raise exception 'document moved on; sync before publishing directly'
        using errcode = '40001';
    end if;
    insert into public.documents (id, kb_id, path, title)
    values (
      p_document_id,
      p_kb_id,
      p_relative_path,
      coalesce(p_content ->> 'title', '')
    )
    returning * into v_doc;
  end if;

  insert into public.revisions (
    kb_id,
    document_id,
    parent_revision_id,
    content,
    content_hash,
    author_id
  ) values (
    p_kb_id,
    p_document_id,
    v_doc.current_revision_id,
    p_content,
    p_content_hash,
    v_uid
  )
  returning id into v_revision_id;

  update public.documents
     set current_revision_id = v_revision_id,
         path = p_relative_path,
         title = coalesce(p_content ->> 'title', ''),
         updated_at = now()
   where id = p_document_id;

  return v_revision_id;
end;
$$;

create or replace function public.publish_document_directly(
  p_kb_id uuid,
  p_document_id uuid,
  p_relative_path text,
  p_content jsonb,
  p_content_hash text,
  p_expected_current_revision uuid
)
returns uuid
language sql
security invoker
set search_path = ''
as $$
  select private.publish_document_directly(
    p_kb_id,
    p_document_id,
    p_relative_path,
    p_content,
    p_content_hash,
    p_expected_current_revision
  );
$$;

grant execute on function private.publish_document_directly(
  uuid, uuid, text, jsonb, text, uuid
) to authenticated;
revoke execute on function private.publish_document_directly(
  uuid, uuid, text, jsonb, text, uuid
) from public, anon;

revoke execute on function public.publish_document_directly(
  uuid, uuid, text, jsonb, text, uuid
) from public, anon;
grant execute on function public.publish_document_directly(
  uuid, uuid, text, jsonb, text, uuid
) to authenticated;

-- Wake every open client when a pending proposal is edited or resolved. The
-- payload remains metadata-only; REST under change_sets RLS is authoritative.
create or replace function private.notify_change_set_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'change_set_id', new.id,
      'document_id', new.target_document_id,
      'status', new.status,
      'author_username', (
        select p.username
          from public.profiles p
         where p.id = new.author_id
      )
    ),
    'proposal_created',
    'kb:' || new.kb_id::text,
    true
  );
  return new;
end;
$$;

drop trigger if exists change_sets_notify_created on public.change_sets;
create trigger change_sets_notify_created
  after insert or update of
    content,
    proposed_path,
    base_revision_id,
    operation,
    status
  on public.change_sets
  for each row execute function private.notify_change_set_created();
