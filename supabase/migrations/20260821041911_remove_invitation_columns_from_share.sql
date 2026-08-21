-- Owner membership creation has no reason to read or write invitation
-- metadata. Keeping this RPC limited to the stable membership columns makes it
-- compatible with both the older invited_email schema and the live
-- invited_username schema while the broader migration history is reconciled.
create or replace function private.share_knowledge_base(
  p_kb_id uuid,
  p_name text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_name text := btrim(p_name);
  v_owner_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  if p_kb_id is null then
    raise exception 'knowledge base id is required' using errcode = '22023';
  end if;

  if v_name is null or char_length(v_name) not between 1 and 200 then
    raise exception 'knowledge base name must be between 1 and 200 characters'
      using errcode = '22023';
  end if;

  insert into public.knowledge_bases as existing_kb (id, name, owner_id)
  values (p_kb_id, v_name, v_uid)
  on conflict (id) do update
    set name = excluded.name
    where existing_kb.owner_id = excluded.owner_id
  returning owner_id into v_owner_id;

  if v_owner_id is null then
    raise exception 'knowledge base id belongs to another owner'
      using errcode = '42501';
  end if;

  insert into public.kb_members as existing_member (
    kb_id,
    user_id,
    role,
    accepted_at
  )
  values (p_kb_id, v_uid, 'owner', now())
  on conflict (kb_id, user_id) do update
    set role = 'owner',
        accepted_at = coalesce(existing_member.accepted_at, excluded.accepted_at);

  return true;
end;
$$;

comment on function private.share_knowledge_base(uuid, text) is
  'Privileged implementation for atomically creating or repairing a Knowledge Base share without depending on invitation metadata.';
