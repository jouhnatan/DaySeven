-- Create (or repair) a Knowledge Base mirror and its owner membership in one
-- transaction. The former client-side two-insert sequence could leave an
-- orphaned knowledge_bases row because the bootstrap membership policy could
-- not see that row through knowledge_bases RLS until membership already
-- existed.
create or replace function public.share_knowledge_base(
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

  -- The conflict branch repairs an interrupted share only when the same user
  -- owns the existing row. A colliding id owned by anyone else returns no row
  -- and is rejected below, so this RPC cannot be used to take over a KB.
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

comment on function public.share_knowledge_base(uuid, text) is
  'Atomically creates or repairs a caller-owned Knowledge Base mirror and owner membership.';

revoke execute on function public.share_knowledge_base(uuid, text)
  from public, anon, authenticated;
grant execute on function public.share_knowledge_base(uuid, text)
  to authenticated;

-- Owner memberships are now bootstrapped only by the atomic RPC above. Direct
-- membership inserts remain available to existing owners, without the former
-- circular RLS branch that queried an as-yet-invisible Knowledge Base row.
drop policy if exists kb_members_insert_owner on public.kb_members;
create policy kb_members_insert_owner on public.kb_members
  for insert to authenticated
  with check ((select private.is_kb_owner(kb_id)));
