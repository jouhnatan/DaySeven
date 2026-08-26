-- CRDT collaboration, phase 5: durability and transport.
--
-- Yjs updates ride Supabase Realtime Broadcast on `crdt:<kbId>` for liveness,
-- and land in Postgres so a peer that was offline can catch up. Realtime is
-- fire-and-forget and keeps no history; these tables are the history. Neither
-- is sufficient alone, and the client must treat the database as the truth and
-- the broadcast as an optimisation.
--
-- This runs *alongside* the existing documents/revisions sync, which stays
-- authoritative until CRDT sync is proven end to end. Nothing here changes a
-- single existing code path.
--
-- The write rate is the thing to get right. The outage that started this work
-- was per-keystroke traffic through PostgREST, so the client debounces 2-5s
-- before pushing and `yjs_push_update` refuses a caller that ignores that.

-- ----------------------------------------------------------------- Tables --

-- An append-only log of Yjs updates. Order is `id`, which is also the cursor a
-- catching-up peer remembers. Updates are opaque bytes to Postgres: the CRDT
-- semantics live in yrs, and the database deliberately knows nothing about
-- them beyond who appended them and when.
create table if not exists public.yjs_updates (
  id bigint generated always as identity primary key,
  kb_id uuid not null references public.knowledge_bases(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  update_bytes bytea not null,
  byte_size integer not null generated always as (octet_length(update_bytes)) stored,
  created_at timestamptz not null default now()
);

-- The only access pattern: "everything for this KB after cursor N, in order".
create index if not exists yjs_updates_kb_cursor_idx
  on public.yjs_updates (kb_id, id);

-- Folds the log down to one document state so catch-up is O(1) rather than
-- O(every edit ever made). `through_update_id` is the high-water mark the
-- snapshot already contains; updates at or below it are redundant and get
-- deleted by `yjs_compact`.
create table if not exists public.yjs_snapshots (
  kb_id uuid primary key references public.knowledge_bases(id) on delete cascade,
  snapshot_bytes bytea not null,
  state_vector bytea not null,
  through_update_id bigint not null,
  byte_size integer not null generated always as (octet_length(snapshot_bytes)) stored,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

comment on table public.yjs_updates is
  'Append-only Yjs update log. Durability for the crdt:<kbId> broadcast topic.';
comment on table public.yjs_snapshots is
  'Folded Yjs document state per Knowledge Base, so catch-up does not replay the whole log.';

-- -------------------------------------------------------------------- RLS --

alter table public.yjs_updates enable row level security;
alter table public.yjs_snapshots enable row level security;

-- Reading is for members. Writing goes through the RPCs below and nowhere
-- else: a direct insert would bypass the size and rate limits, which are the
-- only things standing between this table and the outage it was designed
-- against. There is deliberately no insert/update/delete policy.
create policy yjs_updates_member_read on public.yjs_updates
  for select to authenticated
  using ((select private.is_kb_member(kb_id)));

create policy yjs_snapshots_member_read on public.yjs_snapshots
  for select to authenticated
  using ((select private.is_kb_member(kb_id)));

revoke all on table public.yjs_updates from anon, authenticated;
revoke all on table public.yjs_snapshots from anon, authenticated;
grant select on table public.yjs_updates to authenticated;
grant select on table public.yjs_snapshots to authenticated;

-- ------------------------------------------------------------- Guardrails --

-- A single update larger than this is not a keystroke, it is a whole document
-- being resent. 1 MB is generous for a Yjs delta and small enough that a bug
-- cannot fill the free tier before anybody notices.
create or replace function private.yjs_max_update_bytes()
returns integer language sql immutable set search_path = '' as $fn$
  select 1048576;
$fn$;

-- The client debounces 2-5s. This is the floor that makes that non-optional:
-- 20 updates in 10 seconds is already four times the intended rate, and
-- anything past it is a loop rather than a person.
create or replace function private.yjs_rate_ok(p_kb_id uuid, p_author uuid)
returns boolean language sql stable security definer set search_path = '' as $fn$
  select count(*) < 20
    from public.yjs_updates u
   where u.kb_id = p_kb_id
     and u.author_id = p_author
     and u.created_at > now() - interval '10 seconds';
$fn$;

