-- Disconnect a local Knowledge Base from its Supabase mirror.
--
-- The Knowledge Base folder is not represented here and cannot be touched by
-- this function. Deleting the remote root cascades through memberships,
-- documents, revisions and change sets according to their existing foreign
-- keys, leaving the caller free to share the same local kb_id again later.
--
-- This is an RPC rather than a direct Data API delete so an owner can also
-- recover a partially-created share: that state has a knowledge_bases row but
-- no membership row, so the normal SELECT policy deliberately cannot see it.
create or replace function public.delete_shared_knowledge_base(p_kb_id uuid)
returns boolean
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

  delete from public.knowledge_bases
   where id = p_kb_id
     and owner_id = v_uid;

  if found then
    return true;
  end if;

  if exists (
    select 1 from public.knowledge_bases where id = p_kb_id
  ) then
    raise exception 'only the owner can delete the shared knowledge base'
      using errcode = '42501';
  end if;

  -- Missing is already disconnected, so retrying is a successful no-op.
  return false;
end;
$$;

comment on function public.delete_shared_knowledge_base(uuid) is
  'Deletes only the caller-owned Supabase mirror of a Knowledge Base.';

revoke execute on function public.delete_shared_knowledge_base(uuid)
  from public, anon;
grant execute on function public.delete_shared_knowledge_base(uuid)
  to authenticated;
