# Working on DaySeven

Read `README.md` first — it describes the architecture, the document model,
and the release mechanism in full. This file covers only what an agent needs
to get right that the code does not enforce on its own.

## Committing

**Commit every change.** When a piece of work is finished and the checks below
pass, commit it without being asked. Do not leave finished work sitting in the
working tree waiting for permission, and do not batch several unrelated changes
into one commit — one commit per change, with a message that says what it does
and why.

"Finished" means `flutter analyze`, `flutter test` and `./scripts/check_layers.sh`
all pass. A commit that does not build is worse than no commit.

A commit on its own does not bump the version and does not tag. That is the
release step, and it is not optional either: committing is the first half of
finishing a change, and **Shipping a change** below is the second.

## Shipping a change

DaySeven updates itself from a Supabase release feed. Two people run this app
and neither reinstalls by hand, so a change is not delivered when it is
merged — it is delivered when a release is published and their copies can see
it.

Every completed application change is worth shipping by default. Unless the
user explicitly says not to release it, do not stop after committing or
pushing `main`: publish a build that the running app can discover in App
settings.

Work done on a branch is not exempt, and neither is work that went through a
pull request. Merging the PR is not the end of the task: green CI on a PR
builds the app, it does not publish it, so carry on through the steps below in
the same task rather than handing back a merged branch nobody can install.

After a change is merged to `main`:

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

Do not bump the version on intermediate commits. Bump it once for the completed
change, then finish the tag, workflows, and feed verification in the same task
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
- **Do not add a launch-time update check.** The check runs when somebody opens
  Menu → Settings, and the install when they press Run updates. Nothing
  updates on its own.
- **The interface follows one design system, written out in
  `docs/design-system.md`.** Read it before changing how anything looks. The
  short version: colour comes from `shared/ui/theme.dart` and nowhere else,
  sizes come from `uiTextStyle`/`editorTextStyle`, cards are flat and only
  menus and dialogs carry a shadow, and fern is spent at most twice per view —
  on where you are, and on the action that commits. `check_layers.sh` fails the
  build on a colour literal in `lib/`.
- **Do not add a dark theme.** There is one palette and it is light. This is a
  rule of the system rather than an omission, and the native title bar is
  driven from the colour `app.dart` hands the window chrome — sending a dark
  one is what would turn the Windows caption dark.
- **Settings live in one place.** Settings owns every settings region
  behind a left-hand rail, including the Knowledge Base's sharing and
  collaborators. It cannot import them: features do not import each other, so
  the composition root in `app/shell/shell.dart` passes the Knowledge Base
  panel in and the gear beside the tree calls back up to open it. Add a new
  region by extending `AppSettingsSection`, and inject its body the same way
  if it belongs to a feature.
- **Settings is no longer special.** It used to carry a second design
  system of its own — a separate palette, three private typefaces and a film
  grain. That existed because the app theme was not something a settings
  surface wanted to look like, which is no longer true. Do not reintroduce it.
- **A failed check must not report "up to date."** `UpdateCheckFailed` exists
  to keep those distinct; the check runs because someone asked, and answering
  a question the app could not actually answer is a lie.
- **The install swap cannot be done by the process being replaced.** Both
  platforms write a detached script, hand off, and exit. Keep it that way.
- **Clients may never gain `insert` on the `kb:%` Realtime topic.** That topic
  is the notification bus, and everything on it is written by a database
  trigger. A client able to insert there could forge a `document_published` or
  `proposal_created` event and drive a collaborator's sync from nothing. Live
  presence is the one thing clients send, which is exactly why it has its own
  topic, `presence:<kbId>`, and why the `insert` policy is scoped to that
  prefix alone. If you add another client-sent Realtime message, give it its
  own topic too rather than widening this one.
- **Presence must stay ephemeral and best-effort.** It writes no table, creates
  no revision, and touches no ledger; its failures are swallowed into a health
  value rather than surfaced. It is chrome. If it ever becomes something the
  reviewed-edit path depends on, that is a bug.
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
