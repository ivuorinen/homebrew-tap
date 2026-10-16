# Tap conventions

- Never edit `Formula/**` by hand; change `scripts/sync_formulae.rb` or `formula-sources.json` and run `make sync`.
- Never reopen Ruby core classes (`class String`, …); `brew style` fails the tap with Lint/DuplicateMethods.
- In `scripts/`, use stdlib only: no `exclude?`/`blank?` (they exist only inside brew); swap the predicate instead.
- A change to a stage's output format (formula file, `formulae.json`) updates its producer, its consumer and `scripts/test_sync_formulae.rb` together.
- The sonar secret-scan hook in `.claude/settings.json` scans files only on `Read`; content reached through Grep, Bash or MCP tools is not scanned.
