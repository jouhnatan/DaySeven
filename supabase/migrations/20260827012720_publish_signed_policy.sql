-- Distributing the signed policy, so that a member who cannot sign can still
-- start collaboration.
--
-- `set_policy_public_key` published the key that `policy.json` must verify
-- against, but nothing ever published `policy.json` itself. It lives under
-- `metadata/`, which is excluded from sharing and is not part of the CRDT
-- document, so it never left the machine that signed it. Every other member
-- therefore saw a published key, no file, and "the signed policy file is
-- missing" — a state they had no way to leave, because republishing is an
-- owner action that only ever wrote to the owner's own disk.
--
-- The document is stored here as opaque signed text. The server is transport,
-- not an authority: clients verify the Ed25519 signature and the embedded
-- kb_id before believing a byte of it, exactly as they already do for a copy
-- read off disk. A row here that somebody tampered with fails verification the
-- same way a tampered file does.

alter table public.knowledge_bases
  add column if not exists policy_document text;

comment on column public.knowledge_bases.policy_document is
  'The signed metadata/yjs/policy.json, verified by clients against '
  'policy_public_key. Storage and transport only; never trusted unverified.';

-- Key and document move together. Publishing a key without the document it
-- verifies is the exact divergence that stranded every non-signing member.
create or replace function private.publish_policy(
  p_kb_id uuid,
  p_public_key bytea,
  p_document text
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
  -- Owner-and-co-owner, matching who may sign a policy.
  if not private.can_manage_kb(p_kb_id) then
    raise exception 'only an owner or co-owner can publish a policy'
      using errcode = '42501';
  end if;
  if p_public_key is null or octet_length(p_public_key) <> 32 then
    raise exception 'an Ed25519 public key is 32 bytes' using errcode = '22023';
  end if;
  if p_document is null or length(p_document) = 0 then
    raise exception 'a signed policy document is required'
      using errcode = '22023';
  end if;
  -- A policy is identifiers and roles for one Knowledge Base. Anything this
  -- large is not that, and is not worth handing to every member on open.
  if octet_length(convert_to(p_document, 'UTF8')) > 1048576 then
    raise exception 'the signed policy document is too large'
      using errcode = '22023';
  end if;

  update public.knowledge_bases
     set policy_public_key = p_public_key,
         policy_document = p_document
   where id = p_kb_id;
end;
$fn$;

create or replace function public.publish_policy(
  p_kb_id uuid,
  p_public_key bytea,
  p_document text
)
returns void language sql security invoker set search_path = '' as $fn$
  select private.publish_policy(p_kb_id, p_public_key, p_document);
$fn$;

-- The key-only path stays, for any client that has not updated yet, but it
-- now clears the document it would otherwise invalidate. A document signed by
-- the previous key cannot verify under a new one, and leaving it in place
-- would tell every member their policy had been tampered with.
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
  if not private.can_manage_kb(p_kb_id) then
    raise exception 'only an owner or co-owner can set the policy key'
      using errcode = '42501';
  end if;
  if p_public_key is null or octet_length(p_public_key) <> 32 then
    raise exception 'an Ed25519 public key is 32 bytes' using errcode = '22023';
  end if;
  update public.knowledge_bases
     set policy_public_key = p_public_key,
         policy_document = null
   where id = p_kb_id;
end;
$fn$;

revoke all on function public.publish_policy(uuid, bytea, text) from anon, public;
grant execute on function public.publish_policy(uuid, bytea, text) to authenticated;
