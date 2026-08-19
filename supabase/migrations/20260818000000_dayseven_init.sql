-- DaySeven initial schema.
--
-- Model: a Knowledge Base is a folder on each member's disk. Postgres holds the
-- canonical revision history so that reviewed collaboration (change_sets ->
-- three-way merge -> new revision) has a shared base to merge against.
--
-- kb_id is denormalised onto documents, revisions and change_sets so that every
-- RLS policy is a single indexed membership lookup rather than a join chain.

create schema if not exists private;

-- ---------------------------------------------------------------- profiles --

create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 64),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- --------------------------------------------------------- knowledge bases --

create table public.knowledge_bases (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(name) between 1 and 200),
  owner_id   uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default now()
);

create index knowledge_bases_owner_id_idx on public.knowledge_bases (owner_id);

create table public.kb_members (
  kb_id         uuid not null references public.knowledge_bases (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  role          text not null default 'editor' check (role in ('owner', 'editor')),
  invited_email text,
  invited_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now(),
  accepted_at   timestamptz,
  primary key (kb_id, user_id)
);

create index kb_members_user_id_idx on public.kb_members (user_id);
create index kb_members_invited_by_idx on public.kb_members (invited_by);

-- --------------------------------------------------- documents & revisions --

create table public.documents (
  id                  uuid primary key default gen_random_uuid(),
  kb_id               uuid not null references public.knowledge_bases (id) on delete cascade,
  path                text not null check (char_length(path) between 1 and 1024),
  title               text not null default '',
  current_revision_id uuid,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (kb_id, path)
);

create index documents_kb_id_idx on public.documents (kb_id);

-- Append-only. No update or delete policy is ever granted on this table.
create table public.revisions (
  id                 uuid primary key default gen_random_uuid(),
  kb_id              uuid not null references public.knowledge_bases (id) on delete cascade,
  document_id        uuid not null references public.documents (id) on delete cascade,
  parent_revision_id uuid references public.revisions (id) on delete set null,
  content            jsonb not null,
  content_hash       text not null,
  author_id          uuid not null references auth.users (id) on delete restrict,
  created_at         timestamptz not null default now()
);

create index revisions_document_id_created_at_idx
  on public.revisions (document_id, created_at desc);
create index revisions_kb_id_idx on public.revisions (kb_id);
create index revisions_parent_revision_id_idx on public.revisions (parent_revision_id);
create index revisions_author_id_idx on public.revisions (author_id);

alter table public.documents
  add constraint documents_current_revision_id_fkey
  foreign key (current_revision_id) references public.revisions (id) on delete set null;

create index documents_current_revision_id_idx on public.documents (current_revision_id);

-- ------------------------------------------------------------ change sets --

create table public.change_sets (
  id                   uuid primary key default gen_random_uuid(),
  kb_id                uuid not null references public.knowledge_bases (id) on delete cascade,
  document_id          uuid not null references public.documents (id) on delete cascade,
  base_revision_id     uuid not null references public.revisions (id) on delete restrict,
  -- Full proposed block document as structured JSON. Never a binary payload.
  content              jsonb not null,
  author_id            uuid not null references auth.users (id) on delete restrict,
  status               text not null default 'pending'
                         check (status in ('pending', 'approved', 'rejected')),
  resulting_revision_id uuid references public.revisions (id) on delete set null,
  created_at           timestamptz not null default now(),
  resolved_at          timestamptz,
  resolved_by          uuid references auth.users (id) on delete set null,
  -- A resolved proposal must record who resolved it and when; a pending one must not.
  constraint change_sets_resolution_consistent check (
    (status = 'pending'  and resolved_at is null and resolved_by is null and resulting_revision_id is null)
    or (status = 'rejected' and resolved_at is not null and resolved_by is not null and resulting_revision_id is null)
    or (status = 'approved' and resolved_at is not null and resolved_by is not null and resulting_revision_id is not null)
  )
);

create index change_sets_document_id_status_idx on public.change_sets (document_id, status);
create index change_sets_kb_id_idx on public.change_sets (kb_id);
create index change_sets_base_revision_id_idx on public.change_sets (base_revision_id);
create index change_sets_author_id_idx on public.change_sets (author_id);
create index change_sets_resulting_revision_id_idx on public.change_sets (resulting_revision_id);
create index change_sets_resolved_by_idx on public.change_sets (resolved_by);

-- Only one pending proposal per document at a time: the review UI shows exactly
-- one diff, and the three-way merge has one unambiguous base.
create unique index change_sets_one_pending_per_document_idx
  on public.change_sets (document_id) where status = 'pending';

-- --------------------------------------------------------- RLS helpers ----

create or replace function private.is_kb_member(p_kb_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.kb_members m
    where m.kb_id = p_kb_id
      and m.user_id = (select auth.uid())
      and m.accepted_at is not null
  );
$$;

create or replace function private.is_kb_owner(p_kb_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.kb_members m
    where m.kb_id = p_kb_id
      and m.user_id = (select auth.uid())
      and m.role = 'owner'
      and m.accepted_at is not null
  );
$$;

revoke execute on function private.is_kb_member(uuid) from public, anon, authenticated;
revoke execute on function private.is_kb_owner(uuid) from public, anon, authenticated;

-- -------------------------------------------------------------- policies --

alter table public.profiles        enable row level security;
alter table public.knowledge_bases enable row level security;
alter table public.kb_members      enable row level security;
alter table public.documents       enable row level security;
alter table public.revisions       enable row level security;
alter table public.change_sets     enable row level security;

-- profiles: readable by anyone sharing a KB with you, so proposals can display
-- the author's custom display name.
create policy profiles_select_self_or_covisible on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1
      from public.kb_members mine
      join public.kb_members theirs on theirs.kb_id = mine.kb_id
      where mine.user_id = (select auth.uid())
        and theirs.user_id = public.profiles.id
    )
  );

create policy profiles_insert_self on public.profiles
  for insert to authenticated with check (id = (select auth.uid()));

create policy profiles_update_self on public.profiles
  for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- knowledge bases
create policy knowledge_bases_select_member on public.knowledge_bases
  for select to authenticated using ((select private.is_kb_member(id)));

create policy knowledge_bases_insert_owner on public.knowledge_bases
  for insert to authenticated with check (owner_id = (select auth.uid()));

create policy knowledge_bases_update_owner on public.knowledge_bases
  for update to authenticated
  using ((select private.is_kb_owner(id))) with check ((select private.is_kb_owner(id)));

create policy knowledge_bases_delete_owner on public.knowledge_bases
  for delete to authenticated using (owner_id = (select auth.uid()));

-- membership: you can see rows for KBs you belong to, plus your own pending
-- invitations (which you cannot yet see via is_kb_member, since accepted_at is null).
create policy kb_members_select_visible on public.kb_members
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_kb_member(kb_id)));

create policy kb_members_insert_owner on public.kb_members
  for insert to authenticated
  with check (
    (select private.is_kb_owner(kb_id))
    -- bootstrap: the KB creator inserts their own owner row
    or exists (
      select 1 from public.knowledge_bases k
      where k.id = kb_id and k.owner_id = (select auth.uid())
    )
  );

-- Accepting an invitation is the one self-update a member may make.
create policy kb_members_update_self_or_owner on public.kb_members
  for update to authenticated
  using (user_id = (select auth.uid()) or (select private.is_kb_owner(kb_id)))
  with check (user_id = (select auth.uid()) or (select private.is_kb_owner(kb_id)));

create policy kb_members_delete_owner on public.kb_members
  for delete to authenticated using ((select private.is_kb_owner(kb_id)));

-- documents
create policy documents_select_member on public.documents
  for select to authenticated using ((select private.is_kb_member(kb_id)));

create policy documents_insert_member on public.documents
  for insert to authenticated with check ((select private.is_kb_member(kb_id)));

create policy documents_update_member on public.documents
  for update to authenticated
  using ((select private.is_kb_member(kb_id))) with check ((select private.is_kb_member(kb_id)));

create policy documents_delete_owner on public.documents
  for delete to authenticated using ((select private.is_kb_owner(kb_id)));

-- revisions: insert + select only. No update, no delete: the history is append-only.
create policy revisions_select_member on public.revisions
  for select to authenticated using ((select private.is_kb_member(kb_id)));

create policy revisions_insert_member on public.revisions
  for insert to authenticated
  with check ((select private.is_kb_member(kb_id)) and author_id = (select auth.uid()));

-- change sets: members read all proposals in the KB and create their own.
-- Resolution happens through the approve/reject RPCs, so no update policy exists.
create policy change_sets_select_member on public.change_sets
  for select to authenticated using ((select private.is_kb_member(kb_id)));

create policy change_sets_insert_author on public.change_sets
  for insert to authenticated
  with check (
    (select private.is_kb_member(kb_id))
    and author_id = (select auth.uid())
    and status = 'pending'
  );

-- The author may withdraw their own untouched proposal.
create policy change_sets_delete_author on public.change_sets
  for delete to authenticated
  using (author_id = (select auth.uid()) and status = 'pending');
