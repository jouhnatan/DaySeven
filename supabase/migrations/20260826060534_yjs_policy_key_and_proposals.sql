-- Phase 7: authorization for the CRDT path.
--
-- The client checks its own policy before sending and again on receive, but a
-- client checking its own permissions is advisory. This is the enforcement:
-- the server decides, from kb_members and documents, without consulting
-- policy.json at all.

-- The trust root for policy.json's signature. Written only by an owner, read
-- by any member, so tampering with the file is detectable and tampering with
-- the key needs the owner's account.
alter table public.knowledge_bases
  add column if not exists policy_public_key bytea;

comment on column public.knowledge_bases.policy_public_key is
  'Ed25519 public key that metadata/yjs/policy.json must verify against.';

create or replace function private.set_policy_public_key(
  p_kb_id uuid,
  p_public_key bytea
)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if (select auth.uid()) is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  -- Deliberately owner-and-co-owner, matching who may sign a policy.
  if not private.can_manage_kb(p_kb_id) then
    raise exception 'only an owner or co-owner can set the policy key'
      using errcode = '42501';
  end if;
  if p_public_key is null or octet_length(p_public_key) <> 32 then
    raise exception 'an Ed25519 public key is 32 bytes' using errcode = '22023';
  end if;
  update public.knowledge_bases set policy_public_key = p_public_key
   where id = p_kb_id;
end;
$fn$;

create or replace function public.set_policy_public_key(
  p_kb_id uuid,
  p_public_key bytea
)
returns void language sql security invoker set search_path = '' as $fn$
  select private.set_policy_public_key(p_kb_id, p_public_key);
$fn$;

-- A change to a protected file that its author may not publish directly.
-- Carries opaque Yjs bytes: the server gates and records, it cannot merge.
create table if not exists public.yjs_proposals (
  id uuid primary key default gen_random_uuid(),
  kb_id uuid not null references public.knowledge_bases(id) on delete cascade,
  file_id uuid not null,
  author_id uuid not null references auth.users(id) on delete cascade,
  update_bytes bytea not null,
  byte_size integer not null generated always as (octet_length(update_bytes)) stored,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  review_note text
);

create index if not exists yjs_proposals_kb_pending_idx
  on public.yjs_proposals (kb_id, status, created_at);

alter table public.yjs_proposals enable row level security;

drop policy if exists yjs_proposals_member_read on public.yjs_proposals;
create policy yjs_proposals_member_read on public.yjs_proposals
  for select to authenticated
  using ((select private.is_kb_member(kb_id)));

revoke all on table public.yjs_proposals from anon, authenticated;
grant select on table public.yjs_proposals to authenticated;
