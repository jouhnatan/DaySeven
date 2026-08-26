-- Phase 7, continued. Submitting and resolving protected-file proposals.

-- Any editing role may propose anything; that is the point of proposing.
-- Rate and size limits mirror yjs_push_update, because a proposal is the same
-- kind of write with a different destination.
create or replace function private.yjs_submit_proposal(
  p_kb_id uuid,
  p_file_id uuid,
  p_update bytea
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if coalesce(private.kb_member_role_rank(p_kb_id), 0) = 0 then
    raise exception 'edit permission required' using errcode = '42501';
  end if;
  if p_update is null or octet_length(p_update) <= 2 then
    raise exception 'proposal carries no content' using errcode = '22023';
  end if;
  if octet_length(p_update) > private.yjs_max_update_bytes() then
    raise exception 'proposal is % bytes; the limit is %',
      octet_length(p_update), private.yjs_max_update_bytes()
      using errcode = '22023';
  end if;
  if (select count(*) from public.yjs_proposals p
       where p.kb_id = p_kb_id and p.author_id = v_uid
         and p.created_at > now() - interval '1 minute') >= 30 then
    raise exception 'too many proposals; slow down'
      using errcode = 'PT429';
  end if;

  -- One pending proposal per author per file. A client that resends its
  -- working copy on every debounce would otherwise build a queue nobody can
  -- review, which is the review-side version of the write amplification the
  -- update log is already guarded against.
  update public.yjs_proposals
     set status = 'withdrawn', resolved_at = now(), resolved_by = v_uid,
         review_note = 'Superseded by a newer proposal'
   where kb_id = p_kb_id and file_id = p_file_id
     and author_id = v_uid and status = 'pending';

  insert into public.yjs_proposals (kb_id, file_id, author_id, update_bytes)
  values (p_kb_id, p_file_id, v_uid, p_update)
  returning id into v_id;

  return v_id;
end;
$fn$;

create or replace function public.yjs_submit_proposal(
  p_kb_id uuid, p_file_id uuid, p_update bytea
)
returns uuid language sql security invoker set search_path = '' as $fn$
  select private.yjs_submit_proposal(p_kb_id, p_file_id, p_update);
$fn$;

-- Approving or rejecting one.
--
-- The reviewer must outrank the file's protection, judged against
-- `documents.minimum_publish_role` — the server's own mirror of the policy,
-- not the signed file, which the server never reads. A file with no row in
-- `documents` has no protection recorded, so any editing role may resolve it;
-- that is the same answer `publish_document_change` gives for an unprotected
-- document.
--
-- Approval does not apply anything. The server cannot merge Yjs. It records
-- the decision and returns the bytes, and the approving client applies them
-- and pushes the result through yjs_push_update like any other edit. Ordering
-- is therefore enforced here and merging stays where the CRDT is.
create or replace function private.yjs_resolve_proposal(
  p_proposal_id uuid,
  p_approve boolean,
  p_review_note text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_proposal public.yjs_proposals;
  v_rank integer;
  v_required text;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_proposal from public.yjs_proposals
   where id = p_proposal_id for update;
  if not found then
    raise exception 'no such proposal' using errcode = '22023';
  end if;
  if v_proposal.status <> 'pending' then
    raise exception 'proposal was already %', v_proposal.status
      using errcode = '40001';
  end if;

  v_rank := coalesce(private.kb_member_role_rank(v_proposal.kb_id), 0);
  if v_rank = 0 then
    raise exception 'edit permission required' using errcode = '42501';
  end if;

  select d.minimum_publish_role into v_required
    from public.documents d
   where d.id = v_proposal.file_id and d.kb_id = v_proposal.kb_id;

  if v_required is not null
     and v_rank < private.publish_role_rank(v_required) then
    raise exception 'this protected file requires % to review', v_required
      using errcode = '42501';
  end if;

  -- Reviewing your own proposal defeats the purpose of proposing. Rejecting
  -- it is still allowed: that is how an author withdraws.
  if v_proposal.author_id = v_uid and p_approve then
    raise exception 'a proposal cannot be approved by its author'
      using errcode = '42501';
  end if;

  update public.yjs_proposals
     set status = case when p_approve then 'approved' else 'rejected' end,
         resolved_at = now(), resolved_by = v_uid,
         review_note = nullif(btrim(coalesce(p_review_note, '')), '')
   where id = p_proposal_id;

  return jsonb_build_object(
    'id', v_proposal.id,
    'kb_id', v_proposal.kb_id,
    'file_id', v_proposal.file_id,
    'author_id', v_proposal.author_id,
    'status', case when p_approve then 'approved' else 'rejected' end,
    'update', case when p_approve
      then encode(v_proposal.update_bytes, 'base64') else null end
  );
end;
$fn$;

create or replace function public.yjs_resolve_proposal(
  p_proposal_id uuid,
  p_approve boolean,
  p_review_note text default null
)
returns jsonb language sql security invoker set search_path = '' as $fn$
  select private.yjs_resolve_proposal(p_proposal_id, p_approve, p_review_note);
$fn$;

-- Pending proposals for a Knowledge Base, without their payloads: a review
-- queue is a list of decisions to make, not a bulk download of every pending
-- edit.
create or replace function private.yjs_pending_proposals(p_kb_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if not private.is_kb_member(p_kb_id) then
    raise exception 'not a member of this knowledge base' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id,
      'file_id', p.file_id,
      'author_id', p.author_id,
      'byte_size', p.byte_size,
      'created_at', p.created_at
    ) order by p.created_at)
    from public.yjs_proposals p
   where p.kb_id = p_kb_id and p.status = 'pending'
  ), '[]'::jsonb);
end;
$fn$;

create or replace function public.yjs_pending_proposals(p_kb_id uuid)
returns jsonb language sql security invoker set search_path = '' as $fn$
  select private.yjs_pending_proposals(p_kb_id);
$fn$;

revoke all on function public.set_policy_public_key(uuid, bytea) from anon, public;
revoke all on function public.yjs_submit_proposal(uuid, uuid, bytea) from anon, public;
revoke all on function public.yjs_resolve_proposal(uuid, boolean, text) from anon, public;
revoke all on function public.yjs_pending_proposals(uuid) from anon, public;
grant execute on function public.set_policy_public_key(uuid, bytea) to authenticated;
grant execute on function public.yjs_submit_proposal(uuid, uuid, bytea) to authenticated;
grant execute on function public.yjs_resolve_proposal(uuid, boolean, text) to authenticated;
grant execute on function public.yjs_pending_proposals(uuid) to authenticated;
