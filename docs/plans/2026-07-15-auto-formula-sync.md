# Plan: Pull-based formula sync from GitHub release binaries

Date: 2026-07-15
Status: DRAFT — awaiting approval to implement

## Goal

Invert the update model: instead of each tool's repo pushing formula updates
into this tap, the tap **pulls** the latest release from a tracked list of GitHub
repos on a schedule, parses the release's **prebuilt binary assets**, and
regenerates the formulae itself. Seed the list with `ivuorinen/a`,
`ivuorinen/gh-action-readme`, `ivuorinen/gh-history`, `ivuorinen/gh-calver`.

## Scope & constraints

**Touches (new files):**
- `formula-sources.json` — the tracked-repo list (config).
- `scripts/sync_formulae.rb` — generator (Ruby stdlib + `gh` CLI, no new gems).
- `scripts/test_sync_formulae.rb` — offline unit check for the pure functions.
- `.github/actions/ci/action.yml` — composite action holding the tap-validation
  steps, reused by both `ci.yml` and the sync workflow.
- `.github/workflows/sync-formulae.yml` — scheduled workflow that regenerates
  formulae, validates them in-job via the composite action, then opens a PR.
- `Formula/a/a.rb`, `Formula/g/gh-action-readme.rb`, `Formula/g/gh-history.rb`,
  `Formula/g/gh-calver.rb` — generated on first run.

**Touches (edited):**
- `.github/workflows/ci.yml` — replace the inline setup + test-bot steps with a
  call to the new composite action (keep the matrix, permissions, concurrency,
  the real-formulae gate, and the bottle-artifact upload at the job level).
- `Makefile` — add a `sync` target.
- `README.md` — document the config and the pull model.

**Must not change:** the docs site generator (`parse_formulas.rb`,
`build_site.rb`), `pages-build.yml`, the theme, or the two `example-*.rb`
formulae (CI explicitly special-cases them).

**Decision A — ship prebuilt binaries, parse release assets.** Per the user's
requirement, formulae download the platform binary from the release rather than
building from Go source. The four repos ship assets three different ways, so the
generator needs a **fuzzy platform-matcher** (one matcher, not four per-repo
maps — see the review lens):
- `a`: goreleaser tarballs `a_1.0.0_darwin_amd64.tar.gz` (lowercase os,
  `amd64`/`arm64`), plus raw binaries and `.deb/.rpm/.apk/.sbom.json`.
- `gh-action-readme`: goreleaser tarballs `gh-action-readme_Darwin_x86_64.tar.gz`
  (capitalised os, `x86_64`/`arm64`).
- `gh-history`, `gh-calver`: **raw un-archived binaries**
  `gh-calver_darwin-amd64` (no extension).

**Decision B — sha256 comes from the GitHub API `digest`, no downloads.**
Verified: `gh api repos/OWNER/REPO/releases/latest` returns
`assets[].digest = "sha256:…"` for every asset on all four repos. The generator
reads name + digest + `browser_download_url` from the API and emits the formula
directly — it downloads zero bytes of release payload, so there are no temp
files, no extraction, no cleanup.

**Decision C — target macOS + Linux, arm64 + x86_64 only.** Skip
windows/freebsd/386 assets (Homebrew platforms are macOS + Linux).

## Tasks

1. **Config file `formula-sources.json`** — array of objects, one per repo:
   `[{"repo":"ivuorinen/a"}, {"repo":"ivuorinen/gh-action-readme"}, …]`.
   Optional per-object override keys `desc`, `license`, `bin`, `test` for the
   calibration cases below. Array-of-objects so overrides can be added later
   without a format change.
   — verify: `ruby -rjson -e 'JSON.parse(File.read("formula-sources.json"))'` exits 0.

2. **Generator `scripts/sync_formulae.rb`** — pure, testable helpers plus a thin
   `gh`-calling driver:
   - `class_name(name)` — `gh-action-readme` → `GhActionReadme`, `a` → `A`; must
     round-trip through the docs parser's `convert_class_name_to_formula_name`.
   - `sanitize_desc(str)` — strip a leading `A/An/The`, strip a trailing `.`,
     collapse whitespace, truncate at a word boundary to ≤ 80 chars. Overridable
     by config `desc`.
   - `match_asset(assets, os, arch)` — the fuzzy matcher. OS from
     `/darwin|macos/i` (matches `darwin` and `Darwin`) vs `/linux/i`; arch from
     `/arm64|aarch64/i` vs `/amd64|x86_64|x64/i`. Exclude
     `.sbom.json .deb .rpm .apk .sig .pem .txt .bundle .zip .exe` and
     windows/freebsd/386/i386. Among the remaining candidates for a platform,
     prefer the `.tar.gz` archive; else take the raw binary. Returns
     `{name, url, sha256, archive?}` or `nil` (platform absent).
   - `formula_body(meta)` — inline heredoc template emitting: `desc`, `homepage`,
     an **explicit `version`** (required — raw-binary URLs carry no version for
     the docs parser to derive), `license` (omitted when unknown),
     `on_macos`/`on_linux` → `on_arm`/`on_intel` blocks each with `url` +
     `sha256`, a `def install` (`bin.install "<bin>"` for archives;
     `bin.install "<asset>" => "<bin>"` per-platform for raw binaries), and a
     `test do` running `#{bin}/<bin> --help` (overridable by config `test`).
     `<bin>` defaults to the repo name (override via config `bin`).
   - Driver: for each source run `gh api repos/OWNER/REPO/releases/latest` (tag +
     assets with name/digest/url) and `gh api repos/OWNER/REPO` (description,
     `license.spdx_id`, homepage); build `meta`; write
     `Formula/<first-letter>/<name>.rb` **only if the rendered content differs**.
   — verify: `make sync` locally produces 4 formulae; `brew style Formula/**/*.rb`
     and `brew audit --formula` on each pass or remaining warnings are recorded.

3. **Offline unit check `scripts/test_sync_formulae.rb`** — `assert`-based, no
   network, feeding recorded asset lists from the 4 seed repos:
   - `class_name` round-trip incl. `a`→`A`→`a`.
   - `sanitize_desc`: the 130-char `gh-action-readme` desc truncates ≤ 80 and
     drops the leading article.
   - `match_asset` on all four fixtures: `a` and `gh-action-readme` pick the
     `.tar.gz` (despite opposite casing) and never pick `.sbom.json`/`.deb`;
     `gh-history`/`gh-calver` pick the raw `*-<arch>` binary; `386`/`windows`
     never selected; digest → bare 64-hex sha256.
   — verify: `ruby scripts/test_sync_formulae.rb` exits 0.

4. **Composite action `.github/actions/ci/action.yml`** — extract the reusable
   tap-validation sequence from `ci.yml`: setup-ruby, setup-homebrew, cache gems,
   install-bundler-gems, `make setup`, and `brew test-bot`
   (`--only-cleanup-before`, `--only-setup`, `--only-tap-syntax`, and
   `--only-formulae` gated on a `run-formulae` input). Pinned action SHAs move
   into the composite. **The HOMEBREW_* env is set on the composite's own run
   steps** — composite actions do not inherit the caller workflow's `env:`.
   — verify: `ci.yml` still runs green on a PR (same steps, now via `uses:`);
     `actionlint` clean.

5. **Edit `.github/workflows/ci.yml`** — replace the inline setup/test-bot steps
   with `uses: ./.github/actions/ci`, preserving the matrix and the conditional
   `run-formulae` input from the existing real-formulae check.
   — verify: CI workflow diff is a straight extraction — no behaviour change.

6. **Workflow `.github/workflows/sync-formulae.yml`** — `on: schedule` (daily
   cron) + `workflow_dispatch`; `concurrency: group: sync-formulae,
   cancel-in-progress: false`; least-privilege `permissions` (contents: write,
   pull-requests: write). Steps: checkout, setup-ruby, `ruby
   scripts/sync_formulae.rb` (auth via `GH_TOKEN: ${{ github.token }}`), **then
   `uses: ./.github/actions/ci` to validate the freshly generated formulae in the
   same job** (ubuntu-24.04), then open/update a single PR via
   `peter-evans/create-pull-request` **pinned to a commit SHA** with a body
   listing the version bumps. No PAT: validation is in-job before the PR opens;
   if validation fails the run fails and no PR is opened.
   — verify: `workflow_dispatch` generates the 4 formulae, the composite action
     validates them green, and a PR opens whose diff is exactly those formulae; a
     deliberately broken formula fails the run and opens no PR.

7. **`Makefile` `sync` target** — `ruby scripts/sync_formulae.rb`, so it runs
   locally the same way CI runs it (requires `gh` — present in the runner and
   locally).
   — verify: `make sync` regenerates formulae with no diff on a second run
     (idempotence).

8. **`README.md`** — document `formula-sources.json`, `make sync`, and the pull
   model.
   — verify: README references the new files; no stale claims.

## Adversarial hardening

- **complexity**: The one abstraction — the fuzzy `match_asset` — is justified by
  a real, verified three-way divergence in asset naming; it replaces four
  hand-maintained per-repo maps with one matcher. Everything else is cut: no
  asset downloads (API `digest` gives sha256), no temp-file handling, no ERB
  (inline heredoc), no YAML gem (stdlib `json`), no second update mechanism (one
  idempotent regenerate-and-diff does create + update + metadata refresh),
  no PAT, no per-repo config unless a repo actually needs an override.
- **review** (edge cases in tasks 2/3): opposite OS casing (`darwin` vs
  `Darwin`) and arch spelling (`amd64` vs `x86_64`) both handled by the regex
  matcher. Both an archive and a raw binary exist for the same platform on `a` →
  prefer `.tar.gz`. Sidecar files (`.sbom.json`, `.deb`, `.rpm`, `.apk`, `.sig`,
  `.pem`, checksums `.txt`, `.bundle`) and out-of-scope platforms
  (windows/freebsd/386) are excluded so they can never be mis-selected. A repo
  missing a platform → that `on_*` block is simply omitted, formula still valid.
  A repo with **no release** → skipped with a logged warning, no broken formula.
  `gh-action-readme`'s 130-char desc → truncated ≤ 80. Single-letter `a` → class
  `A` round-trips. Explicit `version` is always emitted because raw-binary URLs
  contain no version string.
- **security**: (a) Workflow least-privilege, **opens a PR, never pushes main**;
  generated formulae are **validated in-job before the PR opens**, so the default
  `GITHUB_TOKEN` "PRs don't trigger CI" limitation is moot and no PAT is
  introduced (credential surface stays at zero). (b) The `sha256` pinned in each
  formula is GitHub's own published asset `digest`, read over the authenticated
  API — the same trust boundary as `brew install`, and every future user
  download is verified against it. (c) All third-party actions pinned to commit
  SHAs. (d) `gh` auth via `GH_TOKEN`/`github.token`; the token is never written
  into a formula or PR body.
- **errors / leaks**: No downloads → no file handles/temp dirs to leak. Any `gh`
  API failure for a repo → that repo is skipped with a warning and its existing
  formula is left untouched (never overwritten with partial data); the run exits
  non-zero if any source failed, so CI surfaces it. A malformed/missing `digest`
  or no matched asset for every platform → skip that repo, don't emit a
  binary-less formula.
- **migrations**: No datastore. The `.rb` files are the mutated state; rollback =
  revert the sync PR/commit. Each install pins `sha256`, so a revert cannot
  silently repoint an existing install.
- **concurrency**: Workflow `concurrency` group prevents two scheduled runs from
  racing; `create-pull-request` updates the existing branch/PR in place.
- **contract**: Two consumers of the generated `.rb`. (1) Homebrew: must load,
  `brew style` clean, `brew audit --formula` acceptable, and `brew test-bot
  --only-formulae` install+test green (in-job + CI). (2) Docs parser
  `parse_formulas.rb`: regexes desc/homepage/url/sha256/license, derives name
  from class and version from the **explicit `version` stanza** — which is why
  the generator must always emit `version` (raw-binary URLs have none). Verified
  compatible; no parser change.
- **arch**: Fits the existing `scripts/*.rb` + `Makefile` + `.github/workflows`
  structure; no new language or dependency (`gh` is already present in the runner
  and locally). The composite action deduplicates the validation steps so `ci.yml`
  and the sync workflow can't drift. Gotcha handled: composite steps set
  HOMEBREW_* env themselves (caller `env:` is not inherited).
- **perf**: Pure `gh api` metadata per repo (2 calls × 4 repos), no payload
  downloads; daily schedule. Optimization: read the existing formula's `version`
  first and skip a repo entirely when the upstream tag is unchanged.
- **tests**: Task 3 is a real offline check of the branching logic (matcher,
  sanitizer, name round-trip) against recorded fixtures, not a tautology; the
  install/test correctness of each formula is verified by `brew test-bot`.
- **config / observability**: `formula-sources.json` is the single source of
  truth and is documented; the workflow logs per-repo old→new version and the PR
  body lists the bumps.
- **privacy / a11y / i18n**: not applicable — no personal data, no UI change, no
  localized strings.

## Rollback / abort

- Bad sync PR: close it / don't merge — nothing reaches `main`.
- Bad formula already merged: `git revert` the sync commit; installs pin
  `sha256`, so no user install is silently altered.
- Kill switch: delete/rename `sync-formulae.yml` or empty `formula-sources.json`.

## Open questions & accepted risks

- **Binary name inside the archive.** `bin.install "<repo>"` assumes goreleaser
  names the binary after the repo (true for `a`, `gh-action-readme`). If a repo
  differs, set `bin` in `formula-sources.json`. `brew test-bot` catches a wrong
  name. Accepted (calibration knob).
- **Pre-merge validation runs ubuntu-only.** The sync job validates on
  `ubuntu-24.04`; the full `ubuntu + macos-14` matrix runs in `ci.yml` on merge.
  Since binaries are prebuilt (no compile), the main pre-merge risk is a bad
  URL/sha or a failing `test do`, both caught on ubuntu. Accepted.
- **Missing licenses.** `gh-history` and `gh-calver` have no license on GitHub,
  so their formulae omit `license` and `brew audit` may warn. Accepted; real fix
  is adding a LICENSE to those repos. Routes to: the source repos.
- **Auto-desc quality.** `sanitize_desc` is best-effort truncation; where it
  reads badly, set a `desc` override in the config (calibration knob). Accepted.
- **`test do` command.** Defaults to `--help`; the two `gh` extensions may behave
  differently as standalone binaries. `brew test-bot` will flag any that fail;
  those get a `test` override. Accepted.
