-- Complete DaySeven's reviewed collaboration model.
--
-- This migration deliberately repairs the checked-in baseline as well as the
-- live schema: the latter already has username invitation support that is not
-- represented in the earlier migration history.

-- -------------------------------------------------------------- profiles --

alter table public.profiles add column if not exists username text;

update public.profiles p
   set username = 'user_' || substr(p.id::text, 1, 8)
  from auth.users u
 where u.id = p.id
   and p.username is null;

alter table public.profiles alter column username set not null;
alter table public.profiles drop constraint if exists profiles_username_check;
alter table public.profiles add constraint profiles_username_check check (
  username = lower(username)
  and username ~ '^[a-z0-9_-]{3,32}$'
);
create unique index if not exists profiles_username_key
  on public.profiles (username);

create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_requested_username text := lower(coalesce(
    new.raw_user_meta_data ->> 'username', ''
  ));
  v_username text := case
    when v_requested_username ~ '^[a-z0-9_-]{3,32}$'
      then v_requested_username
    else 'user_' || substr(new.id::text, 1, 8)
  end;
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    v_username,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      v_username,
      'Someone'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- ------------------------------------------------------------- membership --

-- An earlier deployed-only iteration exposed a two-argument invitation RPC.
-- Remove it so every caller must declare the intended role.
drop function if exists public.invite_kb_member_by_username(uuid, text);
drop function if exists private.invite_kb_member_by_username(uuid, text);

alter table public.kb_members drop constraint if exists kb_members_role_check;
alter table public.kb_members add constraint kb_members_role_check
  check (role in ('owner', 'co_owner', 'editor', 'reviewer'));

create or replace function private.has_kb_role(
  p_kb_id uuid,
  p_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
      from public.kb_members m
     where m.kb_id = p_kb_id
       and m.user_id = (select auth.uid())
       and m.accepted_at is not null
       and m.role = any (p_roles)
  );
$$;

create or replace function private.is_kb_member(p_kb_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_kb_role(
    p_kb_id,
    array['owner', 'co_owner', 'editor', 'reviewer']::text[]
  );
$$;

create or replace function private.is_kb_owner(p_kb_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_kb_role(p_kb_id, array['owner']::text[]);
$$;

create or replace function private.can_manage_kb(p_kb_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_kb_role(p_kb_id, array['owner', 'co_owner']::text[]);
$$;

create or replace function private.can_edit_kb(p_kb_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_kb_role(p_kb_id, array['owner', 'co_owner', 'editor']::text[]);
$$;

create or replace function private.can_review_kb(p_kb_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.has_kb_role(p_kb_id, array['owner', 'co_owner', 'reviewer']::text[]);
$$;

create or replace function private.invite_kb_member_by_username(
  p_kb_id uuid,
  p_username text,
  p_role text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
  v_target uuid;
  v_role text := lower(btrim(p_role));
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select role into v_caller_role
    from public.kb_members
   where kb_id = p_kb_id and user_id = v_uid and accepted_at is not null;

  if v_caller_role not in ('owner', 'co_owner') then
    raise exception 'only an owner or co-owner can invite collaborators'
      using errcode = '42501';
  end if;
  if v_role not in ('co_owner', 'editor', 'reviewer') then
    raise exception 'invalid collaboration role' using errcode = '22023';
  end if;
  if v_role = 'co_owner' and v_caller_role <> 'owner' then
    raise exception 'only the owner can create a co-owner'
      using errcode = '42501';
  end if;

  select id into v_target
    from public.profiles
   where username = lower(btrim(p_username));
  if v_target is null then
    raise exception 'no account has that username' using errcode = 'P0002';
  end if;
  if v_target = v_uid then
    raise exception 'you are already a collaborator' using errcode = '22023';
  end if;

  insert into public.kb_members (kb_id, user_id, role, invited_by, accepted_at)
  values (p_kb_id, v_target, v_role, v_uid, null)
  on conflict (kb_id, user_id) do update
    set role = excluded.role,
        invited_by = excluded.invited_by
  where public.kb_members.role <> 'owner';

  return v_target;
end;
$$;

create or replace function private.set_kb_member_role(
  p_kb_id uuid,
  p_user_id uuid,
  p_role text
)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
  v_target_role text;
  v_role text := lower(btrim(p_role));
begin
  select role into v_caller_role from public.kb_members
   where kb_id = p_kb_id and user_id = v_uid and accepted_at is not null;
  select role into v_target_role from public.kb_members
   where kb_id = p_kb_id and user_id = p_user_id;

  if v_target_role is null then
    raise exception 'collaborator not found' using errcode = 'P0002';
  end if;
  if v_target_role = 'owner' then
    raise exception 'the owner cannot be changed' using errcode = '42501';
  end if;
  if v_role not in ('co_owner', 'editor', 'reviewer') then
    raise exception 'invalid collaboration role' using errcode = '22023';
  end if;
  if v_caller_role = 'owner' then
    null;
  elsif v_caller_role = 'co_owner'
        and v_target_role in ('editor', 'reviewer')
        and v_role in ('editor', 'reviewer') then
    null;
  else
    raise exception 'not allowed to manage that collaborator'
      using errcode = '42501';
  end if;

  update public.kb_members set role = v_role
   where kb_id = p_kb_id and user_id = p_user_id;
end;
$$;

create or replace function private.remove_kb_member(
  p_kb_id uuid,
  p_user_id uuid
)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_caller_role text;
  v_target_role text;
begin
  select role into v_caller_role from public.kb_members
   where kb_id = p_kb_id and user_id = v_uid and accepted_at is not null;
  select role into v_target_role from public.kb_members
   where kb_id = p_kb_id and user_id = p_user_id;

  if v_target_role is null then return; end if;
  if v_target_role = 'owner' then
    raise exception 'the owner cannot be removed' using errcode = '42501';
  end if;
  if not (
    v_caller_role = 'owner'
    or (v_caller_role = 'co_owner' and v_target_role in ('editor', 'reviewer'))
  ) then
    raise exception 'not allowed to remove that collaborator'
      using errcode = '42501';
  end if;

  delete from public.kb_members
   where kb_id = p_kb_id and user_id = p_user_id;
end;
$$;

-- Public functions are invoker wrappers; the RLS-bypassing code remains in a
-- non-exposed schema and performs its own caller checks.
create or replace function public.invite_kb_member_by_username(
  p_kb_id uuid, p_username text, p_role text default 'editor'
)
returns uuid language sql security invoker set search_path = '' as $$
  select private.invite_kb_member_by_username(p_kb_id, p_username, p_role);
$$;
create or replace function public.set_kb_member_role(
  p_kb_id uuid, p_user_id uuid, p_role text
)
returns void language sql security invoker set search_path = '' as $$
  select private.set_kb_member_role(p_kb_id, p_user_id, p_role);
$$;
create or replace function public.remove_kb_member(p_kb_id uuid, p_user_id uuid)
returns void language sql security invoker set search_path = '' as $$
  select private.remove_kb_member(p_kb_id, p_user_id);
$$;

-- Pending invitees may read the KB name needed by the invitation inbox.
drop policy if exists knowledge_bases_select_member on public.knowledge_bases;
create policy knowledge_bases_select_member on public.knowledge_bases
  for select to authenticated using (
    exists (
      select 1 from public.kb_members m
       where m.kb_id = id and m.user_id = (select auth.uid())
    )
  );

-- Membership changes are RPC-only. Members can see the roster of an accepted
-- KB, and invitees can see their own pending row.
drop policy if exists kb_members_insert_owner on public.kb_members;
drop policy if exists kb_members_update_self_or_owner on public.kb_members;
drop policy if exists kb_members_delete_owner on public.kb_members;

-- -------------------------------------------------------------- proposals --

alter table public.documents add column if not exists deleted_at timestamptz;
alter table public.documents drop constraint if exists documents_kb_id_path_key;
create unique index if not exists documents_active_kb_path_key
  on public.documents (kb_id, path)
  where deleted_at is null;

alter table public.change_sets add column if not exists operation text
  not null default 'update';
alter table public.change_sets add column if not exists target_document_id uuid;
alter table public.change_sets add column if not exists proposed_path text;
alter table public.change_sets add column if not exists updated_at timestamptz
  not null default now();
alter table public.change_sets add column if not exists review_note text;

update public.change_sets
   set target_document_id = document_id,
       operation = 'update',
       updated_at = created_at
 where target_document_id is null;

alter table public.change_sets alter column target_document_id set not null;
alter table public.change_sets alter column document_id drop not null;
alter table public.change_sets alter column base_revision_id drop not null;
alter table public.change_sets alter column content drop not null;
alter table public.change_sets drop constraint if exists change_sets_operation_check;
alter table public.change_sets add constraint change_sets_operation_check
  check (operation in ('create', 'update', 'delete'));
alter table public.change_sets drop constraint if exists change_sets_payload_check;
alter table public.change_sets add constraint change_sets_payload_check check (
  (operation = 'create' and document_id is null and base_revision_id is null
    and content is not null and proposed_path is not null)
  or (operation = 'update' and document_id is not null
    and base_revision_id is not null and content is not null)
  or (operation = 'delete' and document_id is not null
    and base_revision_id is not null and content is null)
);

alter table public.change_sets drop constraint if exists change_sets_status_check;
alter table public.change_sets add constraint change_sets_status_check
  check (status in ('pending', 'approved', 'rejected', 'withdrawn', 'superseded'));
alter table public.change_sets drop constraint if exists change_sets_resolution_consistent;
alter table public.change_sets add constraint change_sets_resolution_consistent check (
  (status = 'pending' and resolved_at is null and resolved_by is null
    and resulting_revision_id is null)
  or (status = 'approved' and resolved_at is not null and resolved_by is not null)
  or (status in ('rejected', 'withdrawn', 'superseded')
    and resolved_at is not null and resulting_revision_id is null)
);

drop index if exists public.change_sets_one_pending_per_document_idx;
create unique index change_sets_one_pending_per_author_document_idx
  on public.change_sets (kb_id, author_id, target_document_id)
  where status = 'pending';
create index change_sets_pending_kb_updated_idx
  on public.change_sets (kb_id, updated_at desc)
  where status = 'pending';

-- Announce both the first proposal and subsequent edits to the same pending
-- proposal. The payload is only a wake-up signal; clients fetch content under
-- RLS after receiving it.
create or replace function private.notify_change_set_created()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'pending' then
    perform realtime.send(
      jsonb_build_object(
        'change_set_id', new.id,
        'document_id', new.target_document_id,
        'author_display_name', (
          select p.display_name from public.profiles p where p.id = new.author_id
        )
      ),
      'proposal_created',
      'kb:' || new.kb_id::text,
      true
    );
  end if;
  return new;
end;
$$;

drop trigger if exists change_sets_notify_created on public.change_sets;
create trigger change_sets_notify_created
  after insert or update of content, proposed_path, base_revision_id, operation
  on public.change_sets
  for each row execute function private.notify_change_set_created();

create or replace function private.submit_change_set(
  p_kb_id uuid,
  p_document_id uuid,
  p_target_document_id uuid,
  p_base_revision_id uuid,
  p_operation text,
  p_proposed_path text,
  p_content jsonb
)
returns public.change_sets
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_result public.change_sets;
begin
  if not private.has_kb_role(p_kb_id, array['editor']::text[]) then
    raise exception 'only an editor can submit a proposal'
      using errcode = '42501';
  end if;

  if p_operation not in ('create', 'update', 'delete') then
    raise exception 'invalid proposal operation' using errcode = '22023';
  end if;
  if p_target_document_id is null then
    raise exception 'target document is required' using errcode = '22023';
  end if;
  if p_operation = 'create' then
    if p_document_id is not null or p_base_revision_id is not null
       or p_content is null or nullif(btrim(p_proposed_path), '') is null
       or p_content ->> 'id' is distinct from p_target_document_id::text then
      raise exception 'invalid create proposal' using errcode = '22023';
    end if;
    if exists (
      select 1 from public.documents d where d.id = p_target_document_id
    ) then
      raise exception 'target document already exists' using errcode = '23505';
    end if;
  else
    if p_document_id is null or p_target_document_id <> p_document_id then
      raise exception 'invalid document target' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.documents d
       where d.id = p_document_id and d.kb_id = p_kb_id and d.deleted_at is null
    ) then
      raise exception 'document is not in this knowledge base' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.revisions r
       where r.id = p_base_revision_id
         and r.document_id = p_document_id and r.kb_id = p_kb_id
    ) then
      raise exception 'invalid base revision' using errcode = '22023';
    end if;
    if p_operation = 'update' and (
      p_content is null
      or p_content ->> 'id' is distinct from p_document_id::text
    ) then
      raise exception 'invalid update content' using errcode = '22023';
    end if;
    if p_operation = 'delete' and p_content is not null then
      raise exception 'delete proposals cannot contain content' using errcode = '22023';
    end if;
  end if;

  insert into public.change_sets as cs (
    kb_id, document_id, target_document_id, base_revision_id, operation,
    proposed_path, content, author_id, status
  ) values (
    p_kb_id, p_document_id, p_target_document_id, p_base_revision_id,
    p_operation, p_proposed_path, p_content, v_uid, 'pending'
  )
  on conflict (kb_id, author_id, target_document_id)
    where status = 'pending'
  do update set
    document_id = excluded.document_id,
    base_revision_id = excluded.base_revision_id,
    operation = excluded.operation,
    proposed_path = excluded.proposed_path,
    content = excluded.content,
    updated_at = now()
  returning cs.* into v_result;
  return v_result;
end;
$$;

create or replace function public.submit_change_set(
  p_kb_id uuid,
  p_document_id uuid,
  p_target_document_id uuid,
  p_base_revision_id uuid,
  p_operation text,
  p_proposed_path text,
  p_content jsonb
)
returns public.change_sets language sql security invoker set search_path = '' as $$
  select private.submit_change_set(
    p_kb_id, p_document_id, p_target_document_id, p_base_revision_id,
    p_operation, p_proposed_path, p_content
  );
$$;

-- Reviewers see the queue; Editors see only their own proposals.
drop policy if exists change_sets_select_member on public.change_sets;
create policy change_sets_select_role on public.change_sets
  for select to authenticated using (
    author_id = (select auth.uid())
    or (select private.can_review_kb(kb_id))
  );
drop policy if exists change_sets_insert_author on public.change_sets;
drop policy if exists change_sets_delete_author on public.change_sets;

-- Canonical table writes are owner/co-owner only. Editors write proposals;
-- Reviewers are read-only except for the resolution RPCs.
drop policy if exists documents_insert_member on public.documents;
drop policy if exists documents_update_member on public.documents;
create policy documents_insert_manager on public.documents
  for insert to authenticated with check ((select private.can_manage_kb(kb_id)));
create policy documents_update_manager on public.documents
  for update to authenticated
  using ((select private.can_manage_kb(kb_id)))
  with check ((select private.can_manage_kb(kb_id)));

drop policy if exists revisions_insert_member on public.revisions;
create policy revisions_insert_manager on public.revisions
  for insert to authenticated with check (
    (select private.can_manage_kb(kb_id))
    and author_id = (select auth.uid())
  );

-- Existing resolution functions retain their signatures for old clients, but
-- now require a review-capable role. New overloads add review notes.
drop function if exists public.reject_change_set(uuid);
drop function if exists public.approve_change_set(uuid, jsonb, text, uuid);

create or replace function private.reject_change_set(
  p_change_set_id uuid,
  p_review_note text default null
)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_cs public.change_sets;
begin
  select * into v_cs from public.change_sets
   where id = p_change_set_id for update;
  if not found then
    raise exception 'change set not found' using errcode = 'P0002';
  end if;
  if v_cs.status <> 'pending' then
    raise exception 'change set is already %', v_cs.status using errcode = '22023';
  end if;
  if not private.can_review_kb(v_cs.kb_id) then
    raise exception 'review permission required' using errcode = '42501';
  end if;
  if v_cs.author_id = v_uid then
    raise exception 'you cannot reject your own proposal' using errcode = '42501';
  end if;
  update public.change_sets
     set status = 'rejected', resolved_at = now(), resolved_by = v_uid,
         review_note = nullif(btrim(p_review_note), '')
   where id = p_change_set_id;
end;
$$;

-- Harden legacy approve/reject implementations to treat co-owners and
-- reviewers as reviewers. The merge payload remains client-computed and is
-- protected by the existing optimistic current-revision check.
create or replace function private.approve_change_set(
  p_change_set_id uuid,
  p_merged_content jsonb,
  p_content_hash text,
  p_expected_current_revision uuid,
  p_review_note text default null
)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_cs public.change_sets;
  v_doc public.documents;
  v_new_revision uuid;
begin
  select * into v_cs from public.change_sets
   where id = p_change_set_id for update;
  if not found then
    raise exception 'change set not found' using errcode = 'P0002';
  end if;
  if v_cs.status <> 'pending' then
    raise exception 'change set is already %', v_cs.status using errcode = '22023';
  end if;
  if not private.can_review_kb(v_cs.kb_id) then
    raise exception 'review permission required' using errcode = '42501';
  end if;
  if v_cs.author_id = v_uid then
    raise exception 'you cannot approve your own proposal' using errcode = '42501';
  end if;
  if p_merged_content ->> 'id' is distinct from v_cs.target_document_id::text then
    raise exception 'merged document identity changed' using errcode = '22023';
  end if;

  if v_cs.operation = 'create' then
    insert into public.documents (id, kb_id, path, title)
    values (
      v_cs.target_document_id,
      v_cs.kb_id,
      v_cs.proposed_path,
      coalesce(p_merged_content ->> 'title', '')
    )
    returning * into v_doc;
  else
    select * into v_doc from public.documents
     where id = v_cs.document_id and kb_id = v_cs.kb_id for update;
    if not found then
      raise exception 'document not found' using errcode = 'P0002';
    end if;
    if v_doc.current_revision_id is distinct from p_expected_current_revision then
      raise exception 'document moved on; recompute the merge' using errcode = '40001';
    end if;
  end if;

  if v_cs.operation = 'delete' then
    update public.documents set deleted_at = now(), updated_at = now()
     where id = v_doc.id;
    update public.change_sets
       set status = 'approved', resolved_at = now(), resolved_by = v_uid,
           review_note = nullif(btrim(p_review_note), '')
     where id = p_change_set_id;
    return null;
  end if;

  insert into public.revisions (
    kb_id, document_id, parent_revision_id, content, content_hash, author_id
  ) values (
    v_cs.kb_id, v_doc.id, v_doc.current_revision_id,
    p_merged_content, p_content_hash, v_uid
  ) returning id into v_new_revision;

  update public.documents
     set current_revision_id = v_new_revision,
         path = coalesce(v_cs.proposed_path, path),
         title = coalesce(p_merged_content ->> 'title', title),
         updated_at = now()
   where id = v_doc.id;

  update public.change_sets
     set status = 'approved', resulting_revision_id = v_new_revision,
         resolved_at = now(), resolved_by = v_uid,
         review_note = nullif(btrim(p_review_note), '')
   where id = p_change_set_id;
  return v_new_revision;
end;
$$;

create or replace function public.reject_change_set(
  p_change_set_id uuid,
  p_review_note text default null
)
returns void language sql security invoker set search_path = '' as $$
  select private.reject_change_set(p_change_set_id, p_review_note);
$$;

create or replace function public.approve_change_set(
  p_change_set_id uuid,
  p_merged_content jsonb,
  p_content_hash text,
  p_expected_current_revision uuid,
  p_review_note text default null
)
returns uuid language sql security invoker set search_path = '' as $$
  select private.approve_change_set(
    p_change_set_id, p_merged_content, p_content_hash,
    p_expected_current_revision, p_review_note
  );
$$;

-- ------------------------------------------------------------ privileges --

grant usage on schema private to authenticated;
grant execute on function private.has_kb_role(uuid, text[]) to authenticated;
grant execute on function private.can_manage_kb(uuid) to authenticated;
grant execute on function private.can_edit_kb(uuid) to authenticated;
grant execute on function private.can_review_kb(uuid) to authenticated;
grant execute on function private.invite_kb_member_by_username(uuid, text, text) to authenticated;
grant execute on function private.set_kb_member_role(uuid, uuid, text) to authenticated;
grant execute on function private.remove_kb_member(uuid, uuid) to authenticated;
grant execute on function private.submit_change_set(uuid, uuid, uuid, uuid, text, text, jsonb) to authenticated;
grant execute on function private.reject_change_set(uuid, text) to authenticated;
grant execute on function private.approve_change_set(uuid, jsonb, text, uuid, text) to authenticated;

revoke execute on function public.invite_kb_member_by_username(uuid, text, text) from public, anon;
revoke execute on function public.set_kb_member_role(uuid, uuid, text) from public, anon;
revoke execute on function public.remove_kb_member(uuid, uuid) from public, anon;
revoke execute on function public.submit_change_set(uuid, uuid, uuid, uuid, text, text, jsonb) from public, anon;
revoke execute on function public.reject_change_set(uuid, text) from public, anon;
revoke execute on function public.approve_change_set(uuid, jsonb, text, uuid, text) from public, anon;

grant execute on function public.invite_kb_member_by_username(uuid, text, text) to authenticated;
grant execute on function public.set_kb_member_role(uuid, uuid, text) to authenticated;
grant execute on function public.remove_kb_member(uuid, uuid) to authenticated;
grant execute on function public.submit_change_set(uuid, uuid, uuid, uuid, text, text, jsonb) to authenticated;
grant execute on function public.reject_change_set(uuid, text) to authenticated;
grant execute on function public.approve_change_set(uuid, jsonb, text, uuid, text) to authenticated;

revoke execute on function private.has_kb_role(uuid, text[]) from public, anon;
revoke execute on function private.can_manage_kb(uuid) from public, anon;
revoke execute on function private.can_edit_kb(uuid) from public, anon;
revoke execute on function private.can_review_kb(uuid) from public, anon;
revoke execute on function private.reject_change_set(uuid, text) from public, anon;
revoke execute on function private.approve_change_set(uuid, jsonb, text, uuid, text) from public, anon;
