-- Publish conflict circuit breaker.
--
-- On 2026-08-25 a shipped client entered an unbounded retry loop against
-- `publish_document_change`: it republished the same stale
-- `p_expected_current_revision`, took the optimistic-lock rejection, and
-- immediately republished the identical payload. Over five hours that produced
-- 5.57M `40001` failures at a peak of ~970/second, saturating the shared-CPU
-- instance and outrunning the log pipeline. No amount of client-side care
-- prevents this class of bug from recurring, so the database now refuses to
-- participate.
--
-- A conflict that repeats is never going to stop repeating on its own: the
-- caller is replaying a revision the canonical document has already moved past,
-- and nothing about retrying changes that. So consecutive conflicts on the same
-- (caller, document) pair earn an escalating cool-off, and calls made during
-- the cool-off are rejected before any query runs.
--
-- Recording a strike requires the transaction to commit, which a `raise` would
-- roll back. The conflict is therefore signalled by returning a PostgREST error
-- body with `response.status` 409 rather than by raising. The body keeps
-- `code = '40001'`, so `SharingController._isOptimisticMove` still recognises it
-- and its merge-and-retry-once path is unchanged.

create table if not exists private.publish_gate (
  user_id uuid not null,
  -- The all-zero UUID is a caller-wide block covering every document.
  document_id uuid not null,
  strikes integer not null default 0,
  window_started_at timestamptz not null default now(),
  last_strike_at timestamptz not null default now(),
  blocked_until timestamptz,
  reason text,
  primary key (user_id, document_id)
);

comment on table private.publish_gate is
  'Per-caller publish conflict budget. Written only on the conflict path and '
  'cleared on every successful publish, so a healthy client never touches it.';

alter table private.publish_gate enable row level security;
-- No policies: reachable only through the security-definer functions below.
revoke all on table private.publish_gate from anon, authenticated;

-- Tunables, kept together so the shape of the breaker is readable in one place.
--   * Fewer than 8 conflicts in a minute is ordinary contention between two
--     people editing the same document. It is not throttled at all.
--   * Past that the caller is looping. Cool-off doubles per strike from 1s,
--     reaching the 5 minute ceiling by ~17 consecutive conflicts, which caps a
--     runaway client at 12 requests/hour instead of 970 per second.
create or replace function private.publish_gate_backoff(p_strikes integer)
returns interval
language sql
immutable
set search_path = ''
as $$
  select case
    when p_strikes < 8 then null::interval
    else least(
      interval '5 minutes',
      make_interval(secs => (2 ^ least(p_strikes - 8, 8))::double precision)
    )
  end;
$$;

-- Cheap entry gate: one primary-key lookup per publish attempt.
-- `PT429` is PostgREST's convention for "respond with HTTP 429", which keeps
-- the rejection distinguishable from an optimistic-lock conflict client-side.
create or replace function private.publish_gate_assert(p_document_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocked_until timestamptz;
  v_reason text;
begin
  select g.blocked_until, g.reason
    into v_blocked_until, v_reason
    from private.publish_gate g
   where g.user_id = p_user_id
     and g.document_id in (p_document_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and g.blocked_until > now()
   order by g.blocked_until desc
   limit 1;

  if v_blocked_until is not null then
    raise exception 'too many failed publishes; retry after %',
      to_char(v_blocked_until at time zone 'UTC', 'HH24:MI:SS "UTC"')
      using errcode = 'PT429',
            hint = coalesce(
              v_reason,
              'Refresh the Knowledge Base before publishing again.'
            );
  end if;
end;
$$;

-- Records one conflict and returns the cool-off now in force, if any.
-- Must be called on a path that goes on to commit, or the strike is lost.
create or replace function private.publish_gate_strike(p_document_id uuid, p_user_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_strikes integer;
  v_blocked_until timestamptz;
begin
  insert into private.publish_gate as g (
    user_id, document_id, strikes, window_started_at, last_strike_at
  )
  values (p_user_id, p_document_id, 1, now(), now())
  on conflict (user_id, document_id) do update
    -- A quiet minute forgives the streak; anything faster keeps counting.
    set strikes = case
          when g.last_strike_at < now() - interval '1 minute' then 1
          else g.strikes + 1
        end,
        window_started_at = case
          when g.last_strike_at < now() - interval '1 minute' then now()
          else g.window_started_at
        end,
        last_strike_at = now()
  returning g.strikes into v_strikes;

  v_blocked_until := now() + private.publish_gate_backoff(v_strikes);

  if v_blocked_until is not null then
    update private.publish_gate
       set blocked_until = v_blocked_until
     where user_id = p_user_id and document_id = p_document_id;
  end if;

  return v_blocked_until;
end;
$$;

-- A publish that lands proves the caller is healthy again.
create or replace function private.publish_gate_clear(p_document_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from private.publish_gate
   where user_id = p_user_id
     and document_id = p_document_id
     and blocked_until is null;
end;
$$;

-- Shapes the conflict as a PostgREST error body instead of raising, so the
-- strike recorded alongside it survives. `code` stays '40001' for clients.
create or replace function private.publish_conflict(p_document_id uuid, p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_blocked_until timestamptz;
begin
  v_blocked_until := private.publish_gate_strike(p_document_id, p_user_id);
  perform set_config('response.status', '409', true);
  return jsonb_build_object(
    'code', '40001',
    'message', 'document moved on; refresh before publishing',
    'details', case
      when v_blocked_until is null then null
      else 'Repeated conflicts on this document are rate limited until '
           || to_char(v_blocked_until at time zone 'UTC', 'HH24:MI:SS "UTC"')
    end,
    'hint', 'Refresh the canonical revision before publishing again. '
            'Republishing the same expected revision cannot succeed.'
  );
end;
$$;

