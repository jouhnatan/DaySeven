-- Decline an invitation: deletes the caller's own pending membership row.
create or replace function public.decline_kb_invitation(p_kb_id uuid)
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

  delete from public.kb_members
   where kb_id = p_kb_id and user_id = v_uid and accepted_at is null;

  if not found then
    raise exception 'no pending invitation for this knowledge base' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.decline_kb_invitation(uuid) from public, anon;
grant execute on function public.decline_kb_invitation(uuid) to authenticated;
