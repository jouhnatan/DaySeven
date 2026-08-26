-- CRDT collaboration, phase 5. Continues 20260826054316_yjs_durability_tables.sql.

-- ------------------------------------------------------------------- RPCs --

-- Appends one Yjs update and returns its cursor.
--
-- Requires an editing role: the same rank test `publish_document_change` uses,
-- so CRDT sync cannot become a way around the reviewed-edit permissions.
-- Protected-document gating is phase 7 and is deliberately not attempted here;
-- until it lands, a Knowledge Base with protected documents should not enable
-- CRDT sync.
create or replace function private.yjs_push_update(p_kb_id uuid, p_update bytea)
returns bigint
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_id bigint;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if coalesce(private.kb_member_role_rank(p_kb_id), 0) = 0 then
    raise exception 'edit permission required' using errcode = '42501';
  end if;
  -- A Yjs v1 update carrying nothing encodes as two zero bytes, not as an
  -- empty buffer, so an `octet_length = 0` test never fires for it. A client
  -- that skipped its own content check would append a two-byte row on every
  -- debounce tick forever: slow, silent write amplification of exactly the
  -- kind that caused the outage this architecture replaces.
  if p_update is null or octet_length(p_update) <= 2 then
    raise exception 'update carries no content' using errcode = '22023';
  end if;
  if octet_length(p_update) > private.yjs_max_update_bytes() then
    raise exception 'update is % bytes; the limit is %',
      octet_length(p_update), private.yjs_max_update_bytes()
      using errcode = '22023';
  end if;
  if not private.yjs_rate_ok(p_kb_id, v_uid) then
    raise exception 'too many updates; debounce before pushing again'
      using errcode = 'PT429',
            hint = 'Yjs updates are meant to be batched over 2-5 seconds.';
  end if;

  insert into public.yjs_updates (kb_id, author_id, update_bytes)
  values (p_kb_id, v_uid, p_update)
  returning id into v_id;

  return v_id;
end;
$fn$;

create or replace function public.yjs_push_update(p_kb_id uuid, p_update bytea)
returns bigint language sql security invoker set search_path = '' as $fn$
  select private.yjs_push_update(p_kb_id, p_update);
$fn$;

-- Everything this caller is missing, in one round trip.
--
-- `p_since` is the caller's cursor. When it is null, or older than the
-- snapshot's high-water mark, the snapshot comes too and the caller should
-- apply it before the updates. Yjs updates are idempotent and commutative, so
-- an overlap between snapshot and updates is harmless — which is why the
-- boundary is allowed to be approximate rather than transactional.
create or replace function private.yjs_pull(p_kb_id uuid, p_since bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_snapshot public.yjs_snapshots;
  v_send_snapshot boolean;
  v_updates jsonb;
  v_cursor bigint;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.is_kb_member(p_kb_id) then
    raise exception 'not a member of this knowledge base' using errcode = '42501';
  end if;

  select * into v_snapshot from public.yjs_snapshots where kb_id = p_kb_id;

  v_send_snapshot := v_snapshot.kb_id is not null
    and (p_since is null or p_since < v_snapshot.through_update_id);

  -- Read from the snapshot boundary when we are sending one, so nothing
  -- between the caller's cursor and the snapshot is skipped.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', u.id,
             'author_id', u.author_id,
             'update', encode(u.update_bytes, 'base64')
           ) order by u.id
         ), '[]'::jsonb),
         max(u.id)
    into v_updates, v_cursor
    from public.yjs_updates u
   where u.kb_id = p_kb_id
     and u.id > coalesce(
       case when v_send_snapshot then v_snapshot.through_update_id else p_since end,
       0
     );

  return jsonb_build_object(
    'snapshot', case
      when v_send_snapshot then encode(v_snapshot.snapshot_bytes, 'base64')
      else null
    end,
    'snapshot_through', case
      when v_send_snapshot then v_snapshot.through_update_id
      else null
    end,
    'updates', v_updates,
    'cursor', greatest(
      coalesce(v_cursor, 0),
      case when v_send_snapshot then v_snapshot.through_update_id else coalesce(p_since, 0) end
    )
  );
end;
$fn$;

create or replace function public.yjs_pull(p_kb_id uuid, p_since bigint default null)
returns jsonb language sql security invoker set search_path = '' as $fn$
  select private.yjs_pull(p_kb_id, p_since);
$fn$;

-- Folds the log into a snapshot and drops what the snapshot now contains.
--
-- The caller supplies the folded state because only the client has yrs; the
-- database cannot compute a Yjs merge. That means a caller could in principle
-- write a snapshot that loses edits, so this is restricted to owners and
-- co-owners, and it refuses to move the high-water mark backwards.
create or replace function private.yjs_compact(
  p_kb_id uuid,
  p_snapshot bytea,
  p_state_vector bytea,
  p_through bigint
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_uid uuid := (select auth.uid());
  v_existing bigint;
  v_deleted bigint;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if not private.can_manage_kb(p_kb_id) then
    raise exception 'only an owner or co-owner can compact CRDT history'
      using errcode = '42501';
  end if;
  if p_snapshot is null or octet_length(p_snapshot) = 0
     or p_state_vector is null or octet_length(p_state_vector) = 0 then
    raise exception 'a snapshot and state vector are required' using errcode = '22023';
  end if;

  -- Refuse to fold in updates that do not exist yet: the high-water mark must
  -- describe rows the log actually has.
  if p_through > coalesce(
       (select max(id) from public.yjs_updates where kb_id = p_kb_id), 0) then
    raise exception 'snapshot claims updates beyond the end of the log'
      using errcode = '22023';
  end if;

  select through_update_id into v_existing
    from public.yjs_snapshots where kb_id = p_kb_id for update;

  if v_existing is not null and p_through < v_existing then
    raise exception 'a newer snapshot already covers update %', v_existing
      using errcode = '40001';
  end if;

  insert into public.yjs_snapshots (
    kb_id, snapshot_bytes, state_vector, through_update_id, updated_at, updated_by
  )
  values (p_kb_id, p_snapshot, p_state_vector, p_through, now(), v_uid)
  on conflict (kb_id) do update
    set snapshot_bytes = excluded.snapshot_bytes,
        state_vector = excluded.state_vector,
        through_update_id = excluded.through_update_id,
        updated_at = excluded.updated_at,
        updated_by = excluded.updated_by;

  with gone as (
    delete from public.yjs_updates
     where kb_id = p_kb_id and id <= p_through
    returning 1
  )
  select count(*) into v_deleted from gone;

  return v_deleted;
end;
$fn$;

create or replace function public.yjs_compact(
  p_kb_id uuid,
  p_snapshot bytea,
  p_state_vector bytea,
  p_through bigint
)
returns bigint language sql security invoker set search_path = '' as $fn$
  select private.yjs_compact(p_kb_id, p_snapshot, p_state_vector, p_through);
$fn$;

revoke all on function public.yjs_push_update(uuid, bytea) from anon, public;
revoke all on function public.yjs_pull(uuid, bigint) from anon, public;
revoke all on function public.yjs_compact(uuid, bytea, bytea, bigint) from anon, public;
grant execute on function public.yjs_push_update(uuid, bytea) to authenticated;
grant execute on function public.yjs_pull(uuid, bigint) to authenticated;
grant execute on function public.yjs_compact(uuid, bytea, bytea, bigint) to authenticated;
