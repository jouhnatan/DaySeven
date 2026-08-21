-- Keep the RLS-bypassing implementation outside the Data API's exposed
-- schemas. The public function below is only an authenticated invoker wrapper.
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
    invited_email,
    invited_by,
    accepted_at
  )
  values (p_kb_id, v_uid, 'owner', null, null, now())
  on conflict (kb_id, user_id) do update
    set role = 'owner',
        invited_email = null,
        invited_by = null,
        accepted_at = coalesce(existing_member.accepted_at, excluded.accepted_at);

  return true;
end;
$$;

comment on function private.share_knowledge_base(uuid, text) is
  'Privileged implementation for atomically creating or repairing a Knowledge Base share.';

revoke execute on function private.share_knowledge_base(uuid, text)
  from public, anon, authenticated;
grant execute on function private.share_knowledge_base(uuid, text)
  to authenticated;

create or replace function public.share_knowledge_base(
  p_kb_id uuid,
  p_name text
)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  select private.share_knowledge_base(p_kb_id, p_name);
$$;

comment on function public.share_knowledge_base(uuid, text) is
  'Authenticated API wrapper for atomically creating or repairing a Knowledge Base share.';

revoke execute on function public.share_knowledge_base(uuid, text)
  from public, anon, authenticated;
grant execute on function public.share_knowledge_base(uuid, text)
  to authenticated;
