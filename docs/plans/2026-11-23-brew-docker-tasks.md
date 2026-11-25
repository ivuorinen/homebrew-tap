# Brew Tasks in Docker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `lint`, `lint-fix`, `tap-test` and `tap-install` run brew in a fresh
`ghcr.io/homebrew/brew:latest` container after checking that Docker is usable.

**Architecture:** One executable helper, `.mise/brew-in-docker`, checks Docker,
starts the container with the repo mounted as the tap, brings brew up to
`origin/main`, and runs the command it was given. The four mise file tasks call
it with their brew command.

**Tech Stack:** bash, Docker, mise file tasks, Homebrew (inside the container).

**Spec:** `docs/plans/2026-11-23-brew-docker-tasks-design.md`

## Global Constraints

- Image: `ghcr.io/homebrew/brew:latest`. Not Docker Hub `homebrew/brew` (stale
  since 2025-11-03).
- Docker check messages, verbatim, to stderr, exit 1:
  - `❌ docker not found: install Docker to run this task`
  - `❌ Docker is not running, or this user cannot reach the daemon`
- No fallback to a host brew or to RuboCop when Docker is unavailable.
- Only `lint-fix` mounts the repo writable; every other run mounts it read-only.
- Task files keep the house style: `#!/usr/bin/env bash`, a
  `#MISE description="…"` header, `set -euo pipefail`, an emoji `echo` line
  before the work.
- `shellcheck` (on PATH) reports nothing for every new or changed shell file.
- Never edit the repo's `Formula/**`. Tests that need a broken formula edit a
  scratch copy only.
- Out of scope, do not touch: `.pre-commit-config.yaml`, `.rubocop.yml`,
  `.rubocop_homebrew.yml`, `Gemfile*`, `.github/**`.
- The working tree already holds seven unrelated uncommitted
  `scripts/*.rb` changes. Do not modify or stage them.
- No `git commit` without the user's explicit instruction. When committing:
  stage explicit paths only, check `git status --short` first, no `--no-verify`,
  no attribution trailers.
- `S` below means a scratch directory outside the repo, such as
  `S=$(mktemp -d)`. Commands run from the repo root unless a step says
  otherwise.

## Review Focus

1. Running a task from a subdirectory (`cd scripts && mise run lint`): the repo
   root is mounted, not `$PWD`. Test: Task 1, Step 4 (subdirectory case).
2. A repo path containing a space: the mount still works. Test: Task 1, Step 4
   (space case).
3. Ctrl+C mid-run: the container stops and is removed; nothing is left
   running. Test: Task 1, Step 4 (SIGINT case).
4. One formula fails to install: the others still run, the failure is listed
   with its log tail, and the task exits 1. Test: Task 3, Step 5.
5. Read-only tasks leave the repo untouched; `lint-fix` leaves files owned by
   the host user. Test: Task 2, Step 5.

---

### Task 1: The `brew-in-docker` helper

**Files:**
- Create: `.mise/brew-in-docker` (mode 0755)

**Interfaces:**
- Produces: `.mise/brew-in-docker [--writable] <command> [args...]`
  - Runs `<command> [args...]` in the container after setup; its exit status
    is the helper's exit status. Stdout and stderr pass through.
  - `--writable` (must be the first argument) mounts the repo read-write.
  - Docker check failure: the message from Global Constraints, exit 1.
  - No command: a one-line usage message to stderr, exit 2.
  - Inside the container the tap is at
    `/home/linuxbrew/.linuxbrew/Homebrew/Library/Taps/ivuorinen/homebrew-tap`
    (= `$(brew --repo ivuorinen/tap)`).

- [ ] **Step 1: Run the checks before the helper exists**

Run: `.mise/brew-in-docker brew --version; echo "exit=$?"`
Expected: `No such file or directory`, `exit=127`.

- [ ] **Step 2: Implement `.mise/brew-in-docker`**

- Repo root: the helper's parent directory, resolved from the helper's own
  path (`cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd`), never `$PWD`.
- Checks, in order: a command was given (else usage, exit 2), then
  `command -v docker`, then `docker info >/dev/null 2>&1`.
- Print `🐳 Running in ghcr.io/homebrew/brew:latest...` before `docker run`.
- The last line is `exec docker run …`. Without `exec`, bash holds a SIGINT
  sent to the helper until `docker` exits, and the container keeps running.
- `docker run` arguments:
  - `--rm --init --pull=always`; add `-it` only when stdin and stdout are both
    terminals.
  - `-e` for `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_ANALYTICS=1`,
    `HOMEBREW_DEVELOPER=1`, `HOMEBREW_NO_ENV_HINTS=1`.
  - `--mount type=bind,src=<root>,dst=<tap dir>`, with `,readonly` appended
    unless `--writable`. Use `--mount`, not `-v`: `-v` silently creates a
    missing source directory.
  - Then the image and `bash -c "$setup" bash "$@"`, so the command's
    arguments reach the container as an argument list. Never splice them into
    the script string.
- `$setup` is exactly:

```bash
set -euo pipefail
git config --global --add safe.directory "*"
repo=$(brew --repo)
git -C "$repo" fetch -q origin main
git -C "$repo" checkout -q -f origin/main
brew trust --tap ivuorinen/tap >/dev/null
exec "$@"
```

- [ ] **Step 3: Run the basic checks**

Run each command and compare with its expected result:

| Command | Expected |
|---|---|
| `.mise/brew-in-docker brew --version; echo "exit=$?"` | `Homebrew 7.…`, `exit=0` |
| `.mise/brew-in-docker bash -c 'git -C "$(brew --repo)" rev-parse HEAD origin/main'` | two identical hashes |
| `.mise/brew-in-docker touch /home/linuxbrew/.linuxbrew/Homebrew/Library/Taps/ivuorinen/homebrew-tap/.probe; echo "exit=$?"` | `Read-only file system`, non-zero exit |
| `.mise/brew-in-docker --writable bash -c 't=$(brew --repo ivuorinen/tap); touch "$t/.probe" && rm "$t/.probe"'; echo "exit=$?"; test ! -e .probe && echo clean` | `exit=0`, `clean` |
| `.mise/brew-in-docker; echo "exit=$?"` | usage line, `exit=2` |
| `mkdir -p "$S/nodocker" && ln -sf "$(command -v bash)" "$(command -v dirname)" "$S/nodocker/" && PATH="$S/nodocker" .mise/brew-in-docker true; echo "exit=$?"` | `❌ docker not found: install Docker to run this task`, `exit=1` |
| `DOCKER_HOST=unix:///nonexistent.sock .mise/brew-in-docker true; echo "exit=$?"` | `❌ Docker is not running, or this user cannot reach the daemon`, `exit=1` |
| `shellcheck .mise/brew-in-docker` | no output |

Then check that mise does not list the helper as a task:

```bash
mise tasks ls | awk '{print $1}' | rg -cx brew-in-docker
```

Expected: no output (`rg -c` prints nothing when there are no matches).

- [ ] **Step 4: Run the Review Focus checks**

| Case | Command | Expected |
|---|---|---|
| subdirectory | `cd scripts && ../.mise/brew-in-docker bash -c 'ls "$(brew --repo ivuorinen/tap)/Formula"'` | `a g p` (one per line) |
| space | `ln -sfn "$PWD" "$S/tap with space" && "$S/tap with space/.mise/brew-in-docker" bash -c 'ls "$(brew --repo ivuorinen/tap)/Formula"'` | `a g p` |
| SIGINT | `timeout -s INT 30 .mise/brew-in-docker sleep 300; echo "exit=$?"; sleep 3; docker ps -q --filter ancestor=ghcr.io/homebrew/brew:latest` | non-zero exit, then no container IDs |

- [ ] **Step 5: No commit**

Commit only on the user's instruction. Path for that commit:
`.mise/brew-in-docker`.

---

### Task 2: `lint`, `lint-fix` and `tap-test` in Docker

**Files:**
- Modify: `.mise/tasks/lint`
- Modify: `.mise/tasks/lint-fix`
- Modify: `.mise/tasks/tap-test`
- Modify: `.mise/tasks/lint-update-config` (closing `echo` only)
- Modify: `README.md` (the `tap-test` line, currently line 130)

**Interfaces:**
- Consumes: `.mise/brew-in-docker [--writable] <command> [args...]` (Task 1).
  mise runs file tasks with the project root as cwd, so tasks call it as
  `.mise/brew-in-docker`.

- [ ] **Step 1: Make a scratch copy with two offenses**

`vendor/` is 190 MB of gems (`BUNDLE_PATH`), so link it instead of copying it:

```bash
rm -rf "$S/lint-copy" && rsync -a --exclude /vendor ./ "$S/lint-copy/" && ln -s "$PWD/vendor" "$S/lint-copy/vendor"
printf '%s\n' 'puts "#{ARGV[0] || "none"}"' "X_PROBE = 'a'" >> "$S/lint-copy/scripts/sync_formulae.rb"
```

The first line is a `Homebrew/SimpleInterpolation` offense, which only
`brew style` knows. The second is an auto-correctable `Style/StringLiterals`
offense.

- [ ] **Step 2: Show that the current tasks miss or fail**

```bash
(cd "$S/lint-copy" && bash .mise/tasks/lint) > "$S/lint-old.log" 2>&1; rg -c 'Homebrew/SimpleInterpolation' "$S/lint-old.log"
mise run tap-test; echo "exit=$?"
```

Expected: no count printed (plain RuboCop cannot see the cop), then
`tap-test` fails because there is no `brew` on the host.

- [ ] **Step 3: Rewrite the three tasks and the hint**

Each task body becomes its echo line plus one helper call:

| Task | `#MISE description` | echo | helper call |
|---|---|---|---|
| `lint` | `Lint with brew style in a fresh Homebrew container, as CI does (needs Docker)` | `🔍 Linting with brew style...` | `.mise/brew-in-docker brew style ivuorinen/tap` |
| `lint-fix` | `Auto-correct brew style offenses in a fresh Homebrew container (needs Docker)` | `🔧 Auto-correcting brew style offenses...` | `.mise/brew-in-docker --writable brew style --fix ivuorinen/tap` |
| `tap-test` | `Audit this tap's formulae in a fresh Homebrew container, as CI does (needs Docker)` | `🍺 Auditing tap...` | `.mise/brew-in-docker brew test-bot --only-tap-syntax --tap=ivuorinen/tap` |

- Delete `#MISE depends=["tap-install"]` from `tap-test`.
- In `lint-update-config`, the closing echo becomes
  `echo "✅ Updated. Run 'bundle exec rubocop' to check for new offenses."`
- In `README.md`, the `tap-test` line becomes (keep the comment column):
  `mise run tap-test               # Audit the tap as CI does (brew test-bot, in Docker)`

- [ ] **Step 4: Run the tasks**

```bash
cp -a .mise "$S/lint-copy/"
```

| Command | Expected |
|---|---|
| `(cd "$S/lint-copy" && bash .mise/tasks/lint); echo "exit=$?"` | output names `Homebrew/SimpleInterpolation`, `exit=1` |
| `(cd "$S/lint-copy" && bash .mise/tasks/lint-fix); rg -n "X_PROBE = \"a\"" "$S/lint-copy/scripts/sync_formulae.rb"` | one match: the quote was auto-corrected |
| `mise run lint; echo "exit=$?"` | `no offenses detected`, `exit=0` |
| `mise run tap-test > "$S/tap-test.log" 2>&1; echo "exit=$?"` | `exit=0`; the log ends with `All steps passed!` |
| `rg -c 'Installing tap locally' "$S/tap-test.log"` | no output: `tap-install` no longer runs first |
| `shellcheck .mise/tasks/lint .mise/tasks/lint-fix .mise/tasks/tap-test .mise/tasks/lint-update-config` | no output |

- [ ] **Step 5: Check that the repo is untouched and ownership is right**

```bash
git status --short > "$S/before.txt"
mise run lint && mise run tap-test && mise run lint-fix
git status --short | diff "$S/before.txt" - && echo unchanged
fd -H -I --owner "!$(id -un)" . | rg -v '^\.git/' ; echo "foreign-owned listed above (expect none)"
```

Expected: `unchanged`, and no paths before the final line.

- [ ] **Step 6: No commit**

Commit only on the user's instruction. Paths for that commit:
`.mise/tasks/lint .mise/tasks/lint-fix .mise/tasks/tap-test .mise/tasks/lint-update-config README.md`.

---

### Task 3: `tap-install` as a fresh install of every formula

**Files:**
- Modify: `.mise/tasks/tap-install`
- Modify: `README.md` (the `tap-install` line, currently line 131)

**Interfaces:**
- Consumes: `.mise/brew-in-docker <command> [args...]` (Task 1).

- [ ] **Step 1: Make a scratch copy with one formula whose checksum is wrong**

```bash
rm -rf "$S/install-copy" && rsync -a --exclude /vendor ./ "$S/install-copy/"
sed -i "s/03b0577b41923d152f36df23460ffe171e1d7095f6e5929004c006999cadddaf/$(printf '0%.0s' $(seq 64))/" "$S/install-copy/Formula/a/a.rb"
rg -c '0{64}' "$S/install-copy/Formula/a/a.rb"
```

Expected: `1`. That sha is `a`'s linux/amd64 asset; the host is x86_64.

- [ ] **Step 2: Show that the current task fails**

Run: `mise run tap-install; echo "exit=$?"`
Expected: fails, no `brew` on the host.

- [ ] **Step 3: Rewrite `.mise/tasks/tap-install`**

- `#MISE description="Install and test every formula in a fresh Homebrew container (needs Docker)"`
- echo: `🍺 Installing and testing every formula...`
- One call: `.mise/brew-in-docker bash -c '<loop>'`. Single-quote the loop so
  the host shell expands nothing.
- The loop, inside the container:
  - Formula names: the basenames without `.rb` of
    `$(brew --repo ivuorinen/tap)/Formula/*/*.rb`, sorted.
  - For each name: `brew install --formula "ivuorinen/tap/<name>"`, and if
    that succeeds `brew test "ivuorinen/tap/<name>"`. Each step's output goes
    to a log file, not the terminal.
  - Per name, print exactly one of:
    - `✅ <name>`
    - `❌ <name> (install failed)`
    - `❌ <name> (test failed)`
  - After a failure line, print the last 20 lines of that step's log,
    indented two spaces.
  - Keep going after a failure.
  - At the end print `<passed>/<total> formulae installed and tested`. Exit 1
    if any failed, otherwise 0.
- In `README.md`, the `tap-install` line becomes (keep the comment column):
  `mise run tap-install            # Install and test every formula from scratch (in Docker)`

- [ ] **Step 4: Run it on the real tap**

Run: `mise run tap-install; echo "exit=$?"`
Expected: 26 `✅` lines, `26/26 formulae installed and tested`, `exit=0`
(about 3 minutes).

- [ ] **Step 5: Run it on the broken copy**

```bash
cp -a .mise "$S/install-copy/"
(cd "$S/install-copy" && bash .mise/tasks/tap-install); echo "exit=$?"
```

Expected: `❌ a (install failed)` followed by an indented log tail containing
brew's checksum `mismatch` error, 25 `✅` lines, `25/26 formulae installed and tested`,
`exit=1`.

- [ ] **Step 6: Lint**

Run: `shellcheck .mise/tasks/tap-install`
Expected: no output.

- [ ] **Step 7: No commit**

Commit only on the user's instruction. Paths for that commit:
`.mise/tasks/tap-install README.md`.
