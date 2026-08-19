-- Resolution RPCs, Realtime notification, Storage bucket, housekeeping triggers.

-- ------------------------------------------------------------ housekeeping --

create or replace function private.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function private.touch_updated_at();

create trigger documents_touch_updated_at
  before update on public.documents
  for each row execute function private.touch_updated_at();

-- A profile row exists for every user from the moment they sign up. The display
-- name defaults to the local part of their email until they choose their own.
create or replace function private.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'display_name', ''),
      split_part(new.email, '@', 1),
      'Someone'
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- ------------------------------------------------------------------- RPCs --

-- Approve: write the client-computed three-way merge as a new revision and
-- resolve the proposal, in one transaction so the two cannot diverge.
--
-- p_expected_current_revision is an optimistic lock: if the document moved on
-- while the reviewer had the diff open, the merge was computed against a stale
-- local revision and must be recomputed.
create or replace function public.approve_change_set(
  p_change_set_id uuid,
  p_merged_content jsonb,
  p_content_hash text,
  p_expected_current_revision uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_cs public.change_sets;
  v_doc public.documents;
  v_new_revision uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_cs from public.change_sets where id = p_change_set_id for update;
  if not found then
    raise exception 'change set not found' using errcode = 'P0002';
  end if;
  if v_cs.status <> 'pending' then
    raise exception 'change set is already %', v_cs.status using errcode = '22023';
  end if;
  if v_cs.author_id = v_uid then
    raise exception 'you cannot approve your own proposal' using errcode = '42501';
  end if;
  if not private.is_kb_member(v_cs.kb_id) then
    raise exception 'not a member of this knowledge base' using errcode = '42501';
  end if;

  select * into v_doc from public.documents where id = v_cs.document_id for update;
  if v_doc.current_revision_id is distinct from p_expected_current_revision then
    raise exception 'document moved on; recompute the merge' using errcode = '40001';
  end if;

  insert into public.revisions (kb_id, document_id, parent_revision_id, content, content_hash, author_id)
  values (v_cs.kb_id, v_cs.document_id, v_doc.current_revision_id, p_merged_content, p_content_hash, v_uid)
  returning id into v_new_revision;

  update public.documents
     set current_revision_id = v_new_revision, updated_at = now()
   where id = v_cs.document_id;

  update public.change_sets
     set status = 'approved',
         resulting_revision_id = v_new_revision,
         resolved_at = now(),
         resolved_by = v_uid
   where id = p_change_set_id;

  return v_new_revision;
end;
$$;

-- Reject: status only. No revision is written and no document row is touched,
-- which is what guarantees the reviewer's file is left byte-identical.
create or replace function public.reject_change_set(p_change_set_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_cs public.change_sets;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;

  select * into v_cs from public.change_sets where id = p_change_set_id for update;
  if not found then
    raise exception 'change set not found' using errcode = 'P0002';
  end if;
  if v_cs.status <> 'pending' then
    raise exception 'change set is already %', v_cs.status using errcode = '22023';
  end if;
  if v_cs.author_id = v_uid then
    raise exception 'you cannot reject your own proposal' using errcode = '42501';
  end if;
  if not private.is_kb_member(v_cs.kb_id) then
    raise exception 'not a member of this knowledge base' using errcode = '42501';
  end if;

  update public.change_sets
     set status = 'rejected', resolved_at = now(), resolved_by = v_uid
   where id = p_change_set_id;
end;
$$;

-- Accept an invitation: the invited user claims their pending membership row.
create or replace function public.accept_kb_invitation(p_kb_id uuid)
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

  update public.kb_members
     set accepted_at = coalesce(accepted_at, now())
   where kb_id = p_kb_id and user_id = v_uid;

  if not found then
    raise exception 'no invitation for this knowledge base' using errcode = 'P0002';
  end if;
end;
$$;

revoke execute on function public.approve_change_set(uuid, jsonb, text, uuid) from public, anon;
revoke execute on function public.reject_change_set(uuid) from public, anon;
revoke execute on function public.accept_kb_invitation(uuid) from public, anon;
grant execute on function public.approve_change_set(uuid, jsonb, text, uuid) to authenticated;
grant execute on function public.reject_change_set(uuid) to authenticated;
grant execute on function public.accept_kb_invitation(uuid) to authenticated;

-- --------------------------------------------------------------- Realtime --

-- Notification only: the payload carries identifiers and the author's display
-- name, never document content. The client fetches the change set over REST
-- when the reviewer actually opens the diff.
create or replace function private.notify_change_set_created()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'change_set_id',       new.id,
      'document_id',         new.document_id,
      'author_display_name', (select p.display_name from public.profiles p where p.id = new.author_id)
    ),
    'proposal_created',
    'kb:' || new.kb_id::text,
    true  -- private channel
  );
  return new;
end;
$$;

create trigger change_sets_notify_created
  after insert on public.change_sets
  for each row execute function private.notify_change_set_created();

-- Private channel authorisation: only accepted members of kb:<uuid> may listen.
create policy kb_members_read_realtime_messages on realtime.messages
  for select to authenticated
  using (
    realtime.topic() like 'kb:%'
    and (select private.is_kb_member(substring(realtime.topic() from 4)::uuid))
  );

-- ---------------------------------------------------------------- Storage --

-- Images that a proposal references. A solo user's images never leave their disk;
-- upload happens lazily, only for assets a change set actually needs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'kb-assets', 'kb-assets', false, 26214400,
  array['image/png', 'image/jpeg', 'image/gif', 'image/webp', 'image/tiff']
)
on conflict (id) do nothing;

-- Object path convention: {kb_id}/{asset_id}
create policy kb_assets_select_member on storage.objects
  for select to authenticated
  using (
    bucket_id = 'kb-assets'
    and (select private.is_kb_member((storage.foldername(name))[1]::uuid))
  );

create policy kb_assets_insert_member on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'kb-assets'
    and (select private.is_kb_member((storage.foldername(name))[1]::uuid))
  );

create policy kb_assets_delete_owner on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'kb-assets'
    and (select private.is_kb_owner((storage.foldername(name))[1]::uuid))
  );
