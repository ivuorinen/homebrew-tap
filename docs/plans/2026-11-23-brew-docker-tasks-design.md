# Design: run brew tasks in a fresh Homebrew container

Date: 2026-11-23
Status: DRAFT — awaiting approval

## Intent

Every mise task that needs brew runs in a fresh `ghcr.io/homebrew/brew:latest`
container. The host does not need brew, and every run starts clean, so a
formula that fails to install is caught locally instead of by users.

## Goals

- `lint`, `lint-fix`, `tap-test` and `tap-install` run brew in Docker.
- Each one first checks that Docker is installed and the daemon answers, and
  exits 1 with a message that says which of the two is missing.
- `tap-install` installs and tests every formula in `Formula/` from scratch.

## Non-goals

- The pre-commit `brew-style` hook keeps its host-brew/RuboCop fallback.
- `.rubocop_homebrew.yml`, `lint-update-config` and the `rubocop` gem stay;
  after this change they serve only that hook. Removing them is a separate
  change.
- CI is unchanged; it calls none of these tasks.
- No per-formula selection for `tap-install`.

## Anti-goals

- Falling back to a host brew or plain RuboCop when Docker is unavailable.
  The clean environment is the point; a fallback hides installation issues.
- Any task other than `lint-fix` writing to the repo.
- Leaving containers behind.

## Approaches

- **A, chosen:** one shared helper holds the Docker check and the container
  setup; each task passes it the brew command to run. `tap-install` loops
  `brew install` + `brew test` over every formula. Measured: 26/26 installed
  and passed `brew test` in 167 s, including the brew update.
- **B:** same helper, but `tap-install` uses Homebrew's
  `brew test-bot --only-formulae`, which adds online audit, linkage and a
  bottle build. Measured: 78 s for two formulae (about 10+ min for 26), and
  its bottle step writes to `Formula/`, so it cannot use a read-only mount.
  Not chosen: too slow for a local task.
- **Inline per task:** dropped. It copies the image, environment and setup
  into four files that must then agree.

mise has no first-class "run this task in a container" feature, so the helper
is a plain `docker run` wrapper.

## Decided how

**Helper:** `.mise/brew-in-docker`, an executable bash script outside
`.mise/tasks/` so mise does not list it as a task. Tasks call it by path from
the project root.

1. `command -v docker`, else: `❌ docker not found: install Docker to run this
   task`.
2. `docker info >/dev/null 2>&1`, else: `❌ Docker is not running, or this user
   cannot reach the daemon`.
3. `docker run --rm --pull=always` with:
   - `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_NO_ANALYTICS=1`,
     `HOMEBREW_DEVELOPER=1`, `HOMEBREW_NO_ENV_HINTS=1`;
   - the repo bind-mounted at
     `/home/linuxbrew/.linuxbrew/Homebrew/Library/Taps/ivuorinen/homebrew-tap`,
     read-only unless the caller asks for a writable mount (only `lint-fix`
     does).
4. Inside the container, before the task's command:
   - `git config --global --add safe.directory "*"`;
   - update brew to `origin/main` (`git fetch origin main` +
     `git checkout -f origin/main` in `$(brew --repo)`), because the image's
     brew lags by days and new cops land on main;
   - `brew trust --tap ivuorinen/tap`.

**Tasks:**

| Task | Command in the container | Mount |
|---|---|---|
| `lint` | `brew style ivuorinen/tap` | ro |
| `lint-fix` | `brew style --fix ivuorinen/tap` | rw |
| `tap-test` | `brew test-bot --only-tap-syntax --tap=ivuorinen/tap` | ro |
| `tap-install` | `brew install` then `brew test` for each formula in `Formula/` | ro |

- `tap-test` drops `depends=["tap-install"]`; each task is its own container.
- `tap-install` runs every formula even after a failure, prints each failure
  with the tail of its log, and exits non-zero if any failed.
- Descriptions change from "needs brew" to "needs Docker"; `lint` no longer
  says "no brew needed".
- `lint-update-config`'s closing hint ("Run 'mise run lint'…") points at
  `bundle exec rubocop` instead, since `lint` no longer reads that file.
- README lines 130–131 describe the new `tap-test` and `tap-install`.

**Known limit:** the container runs as uid 1000 (`linuxbrew`). On a Linux host
whose user is not uid 1000, files `lint-fix` rewrites end up owned by uid
1000. The current host is uid 1000; this is not handled.

## Left to the builder

- The helper's exact argument interface (mount flag, how a multi-command
  snippet such as the `tap-install` loop is passed).
- Whether to add `-t` when stdout is a terminal, for colored output.
- Verification: run all four tasks; run one with `docker` absent from `PATH`
  and one with `DOCKER_HOST` pointing at a dead socket, and confirm each prints
  its message and exits 1.
