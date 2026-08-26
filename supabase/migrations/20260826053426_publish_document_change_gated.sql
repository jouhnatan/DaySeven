-- Republished from 20260822203229_protected_document_publishing.sql with the
-- gate wired in. Everything between the gate calls is unchanged.
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

  -- Before any query that costs something.
  perform private.publish_gate_assert(p_document_id, v_uid);

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
      return private.publish_conflict(p_document_id, v_uid);
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
      return private.publish_conflict(p_document_id, v_uid);
    end if;
    v_direct := v_doc.protection_class is null
      or v_rank >= private.publish_role_rank(v_doc.minimum_publish_role);
  end if;

  -- Past this point the call is going to land, so the caller is healthy.
  perform private.publish_gate_clear(p_document_id, v_uid);

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

-- `publish_document_directly` reads `id` out of the result. A conflict body has
-- no `id`, so it must keep raising for that caller rather than returning null.
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
  if v_result ->> 'code' = '40001' then
    raise exception 'document moved on; refresh before publishing'
      using errcode = '40001';
  end if;
  return (v_result ->> 'id')::uuid;
end;
$$;
