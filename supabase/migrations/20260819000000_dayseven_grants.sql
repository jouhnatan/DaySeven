-- Privileges.
--
-- Row Level Security decides which rows a signed-in user may touch, but it
-- never grants access on its own: without a table privilege every request fails
-- with "permission denied" before a policy is consulted. This project does not
-- grant DML to `authenticated` by default, so the grants are made explicitly.
--
-- Each grant mirrors the policies already in place, so nothing here widens what
-- a user can do. Where a table has no policy for an operation, no privilege is
-- granted either: revisions are append-only, and change sets are resolved
-- through approve/reject rather than by being updated.

grant select, insert, update on public.profiles to authenticated;

grant select, insert, update, delete on public.knowledge_bases to authenticated;
grant select, insert, update, delete on public.kb_members to authenticated;
grant select, insert, update, delete on public.documents to authenticated;

-- Append-only: the history is never rewritten.
grant select, insert on public.revisions to authenticated;

-- Created and withdrawn by their author; approved or rejected only through the
-- RPCs, which run as their owner.
grant select, insert, delete on public.change_sets to authenticated;

-- Anonymous users have no business in any of it.
revoke all on public.profiles, public.knowledge_bases, public.kb_members,
  public.documents, public.revisions, public.change_sets from anon;

-- A policy expression is evaluated as the role running the query, so the
-- membership helpers the policies call must be executable by `authenticated`.
-- Keeping them off the API does not depend on revoking that: `private` is not
-- an exposed schema, so nothing in it is reachable over PostgREST.
grant usage on schema private to authenticated;

grant execute on function private.is_kb_member(uuid) to authenticated;
grant execute on function private.is_kb_owner(uuid) to authenticated;

revoke all on schema private from anon;
revoke execute on function private.is_kb_member(uuid) from anon, public;
revoke execute on function private.is_kb_owner(uuid) from anon, public;
