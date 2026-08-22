-- The application release feed.
--
-- DaySeven ships as a sideloaded Windows MSIX and a macOS app bundle, neither
-- of which has a store behind it to hand out new versions. This table is that
-- store: CI writes one row per published build, and installed copies read it to
-- learn whether they are out of date.
--
-- Windows does not read this table. It polls the `.appinstaller` manifest in
-- the `releases` bucket, which is the operating system's own update mechanism.
-- The row still exists for Windows so the app can show what it would be
-- updating to, and so a release is described in one place for both platforms.

create table public.app_releases (
  id              uuid primary key default gen_random_uuid(),

  platform        text not null check (platform in ('windows', 'macos')),
  channel         text not null default 'stable'
                    check (channel in ('stable', 'beta')),

  -- Both halves of the pubspec `version: X.Y.Z+B`. Comparing the two together
  -- is what makes a build-number-only release detectable.
  version         text not null check (version ~ '^\d+\.\d+\.\d+$'),
  build_number    integer not null check (build_number >= 0),

  -- What the updater downloads: the .msix on Windows, the .zip on macOS.
  download_url    text not null,
  -- What a person opens by hand: the .appinstaller on Windows, the .dmg on
  -- macOS. Windows cannot update from `download_url` alone, so this is the
  -- link the app offers when App Installer polling is unavailable.
  install_url     text,

  sha256          text not null check (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes      bigint not null check (size_bytes > 0),
  release_notes   text,

  -- Optional floor. A client older than this should be told the update is not
  -- optional; leaving it null makes every update advisory.
  minimum_version text check (minimum_version ~ '^\d+\.\d+\.\d+$'),

  is_current      boolean not null default true,
  published_at    timestamptz not null default now(),

  unique (platform, channel, version, build_number)
);

-- One live release per platform and channel. Publishing is "clear the flag,
-- then set it", and this index is what makes that race-proof.
create unique index app_releases_current_idx
  on public.app_releases (platform, channel)
  where is_current;

alter table public.app_releases enable row level security;

-- The one table in this schema that `anon` may read.
--
-- Everywhere else anonymous access is revoked outright, because every other row
-- belongs to somebody. A release does not: it is the public fact of which build
-- is current. It has to be readable signed-out, because the person most in need
-- of an update is the one whose old build cannot sign in.
create policy app_releases_select_public
  on public.app_releases
  for select
  to anon, authenticated
  using (true);

-- No insert, update or delete policy exists, so no client can write here
-- whatever privileges it holds. CI publishes through the RPC below, which runs
-- as the table owner.
grant select on public.app_releases to anon, authenticated;

create or replace function private.publish_release(
  p_platform        text,
  p_version         text,
  p_build_number    integer,
  p_download_url    text,
  p_install_url     text,
  p_sha256          text,
  p_size_bytes      bigint,
  p_release_notes   text default null,
  p_minimum_version text default null,
  p_channel         text default 'stable'
) returns public.app_releases
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_release public.app_releases;
begin
  -- Clearing first keeps the partial unique index satisfied at every moment,
  -- and the whole function is one transaction, so there is never a window in
  -- which a platform has no current release.
  update public.app_releases
     set is_current = false
   where platform = p_platform
     and channel = p_channel
     and is_current;

  insert into public.app_releases (
    platform, channel, version, build_number, download_url, install_url,
    sha256, size_bytes, release_notes, minimum_version, is_current
  ) values (
    p_platform, p_channel, p_version, p_build_number, p_download_url,
    p_install_url, p_sha256, p_size_bytes, p_release_notes, p_minimum_version,
    true
  )
  on conflict (platform, channel, version, build_number) do update
     set download_url    = excluded.download_url,
         install_url     = excluded.install_url,
         sha256          = excluded.sha256,
         size_bytes      = excluded.size_bytes,
         release_notes   = excluded.release_notes,
         minimum_version = excluded.minimum_version,
         is_current      = true,
         published_at    = now()
  returning * into v_release;

  return v_release;
end;
$$;

create or replace function public.publish_release(
  p_platform        text,
  p_version         text,
  p_build_number    integer,
  p_download_url    text,
  p_install_url     text,
  p_sha256          text,
  p_size_bytes      bigint,
  p_release_notes   text default null,
  p_minimum_version text default null,
  p_channel         text default 'stable'
) returns public.app_releases
language sql
security definer
set search_path = ''
as $$
  select private.publish_release(
    p_platform, p_version, p_build_number, p_download_url, p_install_url,
    p_sha256, p_size_bytes, p_release_notes, p_minimum_version, p_channel
  );
$$;

-- Publishing belongs to CI and to nobody else. `service_role` bypasses RLS by
-- design, so the guard that matters is this one: no client-facing role can
-- reach the function at all.
revoke execute on function private.publish_release(
  text, text, integer, text, text, text, bigint, text, text, text
) from public, anon, authenticated;

revoke execute on function public.publish_release(
  text, text, integer, text, text, text, bigint, text, text, text
) from public, anon, authenticated;

grant execute on function public.publish_release(
  text, text, integer, text, text, text, bigint, text, text, text
) to service_role;

-- The bucket the installers live in.
--
-- Public, unlike `kb-assets`, and it has to be: on Windows the client fetching
-- the update is the operating system's App Installer, which requests a plain
-- URL and cannot attach an `apikey` header. Nothing here belongs to a user —
-- these are the same build artifacts anyone is invited to download and run.
--
-- No mime allowlist: .msix, .appinstaller, .zip, .dmg and .cer between them
-- have no stable set of content types worth enumerating.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('releases', 'releases', true, 524288000, null)
on conflict (id) do update
  set public = true,
      file_size_limit = 524288000,
      allowed_mime_types = null;

-- No object policies. Reads go through the bucket's public route, which does
-- not consult RLS, and the only writer is CI holding the service role key.
