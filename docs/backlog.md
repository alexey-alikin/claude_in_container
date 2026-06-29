# Backlog

Items considered and deferred. Each entry captures the threat, the options
weighed, and the tradeoffs — so when we come back to it we don't re-do the
analysis from scratch.

---

## Write-protection hooks for credentials and `CLAUDE.md`

**Status:** deferred. Two `PreToolUse` hooks are validated and running in the
maintainer's personal `claude_home/`. Decision needed on how (or whether) to
ship them to other users of this repo.

**Threats addressed**
1. Credentials (GitHub PATs, AWS keys, Anthropic/OpenAI keys, PEM private keys,
   Slack/Google/Stripe tokens) accidentally written into any file by Claude and
   then committed to git.
2. Prompt-injection causing writes to `CLAUDE.md`. `CLAUDE.md` is loaded
   automatically every session, so a malicious instruction landed there
   reactivates in every future session until removed.

**The hooks themselves**
- Two short Python scripts (~30 lines each, stdlib only — `python3` is already
  in the image).
- Hook `type: command` — no LLM, no token cost, ~10 ms per Write/Edit call.
- `scan-secrets.sh`: regex-matches a fixed list of credential shapes against
  the content being written. Patterns are precise (specific prefixes and
  length-bounded character classes), not entropy heuristics, to keep
  false-positive rate near zero.
- `guard-claude-md.sh`: blocks any `Write`/`Edit`/`MultiEdit` where the
  basename is `CLAUDE.md`. Memory files (`.claude/projects/*/memory/`) are
  intentionally NOT gated — they're frequent and don't reach git.

### Option 1: opt-in examples (lowest friction to ship)
Add `hooks/scan-secrets.sh`, `hooks/guard-claude-md.sh`, and a short
`hooks/README.md` to the repo. The README walks users through copying the
scripts into `claude_home/.claude/hooks/` and merging a hook entry into their
`claude_home/.claude/settings.json`.

- **Pros:** zero behavior change for existing users. Easy to iterate — edit
  the example, users update on their own schedule.
- **Cons:** discoverability is poor; most users won't install unless something
  prompts them. Drift over time as users diverge from the shipped example.

### Option 2: `claude_home/` seed (middle ground)
Add `claude_home/.claude/hooks/*.sh` and `claude_home/.claude/settings.json`
to the existing seed template that the repo already ships
(`claude_home/.claude/CLAUDE.md` and `.gitconfig` follow the same pattern).
Fresh installs get the hooks active by default; the files are bind-mounted, so
pattern updates are live next session with no image rebuild.

- **Pros:** active by default for new users. Matches the existing
  seed pattern — no new schema surface. Pattern updates don't require a
  rebuild.
- **Cons:** existing users already have a populated `claude_home/`; the seed
  doesn't reach them unless `claude.sh` is taught to backfill missing files
  (which has its own merge-conflict edge cases for `settings.json`). Hooks
  live in a writable bind mount, so a prompt-injected session can edit
  `settings.json` to disable them — protection is default-on but
  bypassable from inside the sandbox.

### Option 3: bake scripts into the Docker image (Flavor A)
Copy hook scripts into the image at e.g. `/usr/local/share/claude-hooks/` via
the Dockerfile. Reference them via absolute paths from a `settings.json` that
either ships in the seed (combine with Option 2) or is injected by `claude.sh`
on first run.

- **Pros:** scripts are tamper-resistant (read-only rootfs). Single
  versioned source of truth for the script contents.
- **Cons:** activation still lives in the writable `settings.json` in
  `claude_home/`, so a prompt-injected session can disable the hook by
  removing the entry. **Default-on but bypassable — worst of both worlds.**
  Pattern updates require an image rebuild.

### Option 4: managed-settings.json (Flavor B — most robust)
Ship the hook scripts AND a `/etc/claude-code/managed-settings.json` in the
image (read-only) with `allowManagedHooksOnly: true`. Claude Code treats
managed settings as policy: they override user/project/local and cannot be
disabled from `claude_home/`.

- **Pros:** prompt-injection can neither tamper with the scripts (read-only
  rootfs) nor with their activation (managed settings ignore user settings
  for hooks). Actually closes the loophole. Aligns with Claude Code's
  enterprise-policy intent.
- **Cons:** behavior change on rebuild — anyone pulling the new image gets
  blocking hooks they didn't opt into. Mitigation: clear release-notes
  call-out plus a documented opt-out (e.g. a Dockerfile build arg, or a
  separate "lite" image target, that skips installing
  `managed-settings.json`). Pattern updates require an image rebuild. New
  schema surface (`managed-settings.json`) to maintain.

### Recommendation when revisiting
- If the goal is "available to anyone who wants it" → **Option 1**.
- If the goal is "default-on for new users, low friction" → **Option 2**.
- If the goal is "actually closes the prompt-injection bypass" → **Option 4**.
- **Option 3 is not recommended in isolation** — it's default-on but
  bypassable, which is strictly worse than Option 2 (same bypassability,
  more rebuild friction).

A reasonable phased path: ship **Option 1** now (cheap, low risk), see if
users adopt it; if uptake is low but threats matter, escalate to **Option 4**
in a tagged release with prominent CHANGELOG notes.
