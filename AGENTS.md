# Working on DaySeven

Read `README.md` first — it describes the architecture, the document model,
and the release mechanism in full. This file covers only what an agent needs
to get right that the code does not enforce on its own.

## Shipping a change

DaySeven updates itself from a Supabase release feed. Two people run this app
and neither reinstalls by hand, so a change is not delivered when it is
merged — it is delivered when a release is published and their copies can see
it.

After a change is merged to `main` and is worth shipping:

1. **Bump `version:` in `pubspec.yaml`.** Always raise the build number, not
   just the patch — `1.3.2+7` to `1.3.3+8`. Two releases of the same version
   are told apart only by the build number, and a release that does not raise
   it will not be offered to anyone.
2. **Tag and push.** The tag must match the version name exactly, or CI fails
   the build on purpose:
   ```bash
   git tag v1.3.3 && git push origin v1.3.3
   ```
3. **Watch both workflows.** `gh run list` — *Build Windows release* and
   *Build macOS release* must both be green. A tag is the only thing that
   publishes; merging alone does nothing.
4. **Confirm the feed moved.** One row per platform should now be current at
   the new version:
   ```sql
   select platform, version, build_number, is_current
   from public.app_releases where is_current;
   ```

If only one workflow succeeds, the platforms are on different versions. Fix
the failure and release a **new** version rather than moving the tag: the tag
records what actually happened.

Do not bump the version on every commit. Bump it when you intend a release,
so that every version anyone runs corresponds to a build that exists.

## Things that break updating

- **`pubspec.yaml` `version:` is the single source of truth.** The storage
  paths, the `app_releases` row, the tag check, and what the running app
  reports about itself are all derived from it. Do not introduce a second
  place that states the version.
- **Do not reintroduce MSIX, App Installer, or code signing.** Windows ships
  a plain zip deliberately. MSIX required a signing certificate whose identity
  had to persist across every build forever, which is not worth it for two
  users. This was tried and removed.
- **Do not add a launch-time update check.** Updating happens when somebody
  chooses Menu → Run updates, and only then.
- **A failed check must not report "up to date."** `UpdateCheckFailed` exists
  to keep those distinct; the check runs because someone asked, and answering
  a question the app could not actually answer is a lie.
- **The install swap cannot be done by the process being replaced.** Both
  platforms write a detached script, hand off, and exit. Keep it that way.
- **`public.app_releases` is the only table `anon` may read.** It must stay
  readable signed-out — the person most in need of an update is the one whose
  old build cannot sign in. Nothing client-side may write it; publishing goes
  through `publish_release`, granted to `service_role` alone.

## Secrets

`SUPABASE_SERVICE_ROLE_KEY` is a GitHub repository secret used only by the
publish steps on tag builds. It bypasses every RLS policy. Never print it,
commit it, echo it in a workflow, or move it into a file that is tracked.
`/.ci/` is gitignored and holds nothing that belongs in the repository.

## Before you finish

```bash
flutter analyze
flutter test
./scripts/check_layers.sh   # needs ripgrep; it is silently vacuous without it
```

`check_layers.sh` enforces the import rules: `shared/` may not import `app/`
or `features/`, no feature may import another, and rendered `fontSize:` must
come from `uiTextStyle` or `editorTextStyle`.
