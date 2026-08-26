-- Enforces zero-retention policy past n-1 releases.
--
-- Keeps only the 2 most recent builds (current release n and rollback release n-1)
-- per platform and channel. Older releases are automatically pruned from
-- public.app_releases and storage.objects in the releases bucket upon publishing.

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
  v_pruned_versions text[];
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

  -- Zero-retention policy past n-1: Keep only the 2 most recent builds
  -- (current release n and previous release n-1) for this platform and channel;
  -- prune everything older from app_releases and storage.objects.
  select array_agg(version) into v_pruned_versions
  from (
    select version
    from public.app_releases
    where platform = p_platform
      and channel = p_channel
    order by build_number desc
    offset 2
  ) old_versions;

  if v_pruned_versions is not null and array_length(v_pruned_versions, 1) > 0 then
    -- Delete pruned versions from app_releases
    delete from public.app_releases
    where platform = p_platform
      and channel = p_channel
      and version = any(v_pruned_versions);

    -- Allow delete on storage.objects for this transaction
    perform pg_catalog.set_config('storage.allow_delete_query', 'true', true);

    -- Delete corresponding artifacts from storage.objects
    delete from storage.objects
    where bucket_id = 'releases'
      and split_part(name, '/', 1) = p_platform
      and split_part(name, '/', 2) = any(v_pruned_versions);
  end if;

  return v_release;
end;
$$;
