# Maintaining the `reolink-cli` Skill

For future editors. Covers what the skill's invariants are, why the
structure looks the way it does, and what to run when you change it.

## Invariants (don't break these silently)

1. **SKILL.md stays under ~250 lines.** It loads into context on every
   skill invocation. Big tables (command reference signatures, intent
   disambiguation, error recovery, side-effects, gotchas) are load-
   bearing; verbose prose is not. If you're adding a table column or a
   flag description that is only useful when the agent drills into a
   specific command, put it in `references/<topic>.md` instead.
2. **Every command mentioned in SKILL.md must exist in the CLI.** CI
   enforces this via `scripts/check-skill-drift.sh`. A skill that
   advertises a removed command is worse than a skill that stays quiet
   about one (see the 5-stub-path incident that motivated the check).
3. **Credential-safety rule is non-negotiable.** The "never pass
   `--password PLAIN`" rule is cited by three places in the skill
   (credential-safety numbered step, Users section caveat, intent table
   entry). If you change wording in one, update the other two.
4. **Intent disambiguation belongs in SKILL.md**, not in a reference
   file. Benchmark eval-4 routinely finishes in 1 tool call precisely
   because the intent table doesn't require opening a second file.
5. **Gateway requirement must be stated up front.** Reason: without it,
   a fresh agent hits `Connection refused` on every control command.
   Don't move this to "Troubleshooting" — it's setup, not failure.

## Why the structure looks like this

- **199-line SKILL.md, 9 topic files under `references/`:** started from
  a 321-line SKILL.md + 552-line monolithic `command-recipes.md`.
  The monolith forced every task — even a simple `ptz move` — to drag
  16k tokens of recipe into context. Topic-splitting cuts that to
  ~1k tokens per task. Benchmark eval-2 load dropped from 2 files to 1.
- **`references/index.md` is rarely read in practice.** The routing
  table in SKILL.md itself is usually enough. index.md is a safety net
  for agents that didn't load SKILL.md first; don't let it grow.
- **`references/troubleshooting.md` holds both intent-map (full
  verbose) AND decision trees.** Rationale: an agent that hits an
  unfamiliar error *or* an ambiguous user phrasing both route to the
  same file. Keep the two sections clearly separated with the same
  H2-level headings.
- **No `references/command-recipes.md` — it was removed.** If you're
  tempted to add one back for cross-topic examples, first ask whether
  the example actually spans topics. End-to-end examples live in
  `docs/api-v30.md` (gateway HTTP) or `docs/cli-reference.md` (CLI).

## What to run when you change something

### Any skill edit

```bash
cargo build --bin reolink-cli
./scripts/check-skill-drift.sh
```

This fails if SKILL.md references a command the CLI doesn't have.

### Adding/removing a CLI command surface

1. Update the CLI code + its `--help` text.
2. Update `SKILL.md` Command Reference signature line.
3. If the command has non-obvious flags or needs an example, add to
   the matching `references/<topic>.md`.
4. Update the intent table if a user might reach this command via a
   loose phrasing ("the night lights", "what people does it see", …).
5. Re-run `check-skill-drift.sh`.
6. Consider adding a benchmark eval under
   `plugins/reolink-cli/skills/reolink-cli-workspace/iteration-N/`
   (see below).

### Running the benchmark

Pattern used in iter-5 … iter-7:

1. Start gateway: `reolink-cli gateway start --addr 127.0.0.1:9000 &`
2. For each eval:
   - Dispatch a subagent with the eval's prompt verbatim + reference
     paths to the skill + 5 assertions.
   - Self-score (agent returns a JSON with pass-per-assertion).
3. Aggregate into `iteration-N/benchmark.json` and `.md`. Reuse the
   `without_skill` baseline from iter-4 (stable — underlying CLI
   paths rarely change).
4. Compare on: pass rate, mean time (seconds), mean tokens, average
   files loaded from skill.

Subagent cost per eval: ~25k tokens, ~30s wall-clock.

### Adding a new eval

Create `iteration-N/eval-M/eval_metadata.json`:

```json
{
  "eval_id": M,
  "eval_name": "kebab-case-name",
  "prompt": "<the user request verbatim, Chinese or English>",
  "assertions": [
    {"text": "snake_case_id", "description": "What literally satisfies this in the run log"},
    ... five total
  ]
}
```

Five assertions per eval (precedent). Keep them strictly mechanical —
the self-scoring agent cannot evaluate intent, only "did this string
appear / did this ordered pattern occur".

## Red flags when editing

- **Adding a long paragraph to SKILL.md** — ask whether it can be a
  table row. If not, whether it belongs in a reference file.
- **Duplicating content between SKILL.md and a reference** — pick one
  canonical home and point to it from the other. Duplicates drift.
- **"I'll just mention this command in prose"** — it won't be matched
  by the drift check regex. Either use backtick syntax (`command …`)
  or skip.
- **Removing a gotcha because "agents should figure it out"** — every
  entry in the Gotchas table was added because an agent literally
  didn't figure it out. Leave them.

## Contact

Skill author sessions are stored under
`.claude/projects/.../memory/` — check `project_v30_authority.md` and
the reference-repo pointers for context on V20/V30 authority.
