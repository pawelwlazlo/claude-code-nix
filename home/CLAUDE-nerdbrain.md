# Global guidance: nerdbrain second brain

## Scope and language
- Applies to ALL Claude Code sessions on this machine.
- Becomes a no-op when the SessionStart hook signals CWD is inside
  ~/obsidian/nerdbrain (the vault has its own CLAUDE.md with different rules).
- Entity pages (`5-wiki/entities/projects/<slug>.md`) are English-only
  regardless of conversation language — rationale: tokenization efficiency.
- Index entries and log entries follow the vault language (currently PL).

## How project context reaches you
The SessionStart hook (~/.claude/hooks/nerdbrain-load.sh) resolves a project
slug from `.nerdbrain-slug` (override) → git remote → basename, then injects
either:
  (a) the entity page from 5-wiki/entities/projects/<slug>.md, or
  (b) a stub saying no page exists yet.

Injected metadata includes: `slug`, `tier` (rest|rest-http|cli|file|none),
and `OBSIDIAN_API_KEY` presence notice.

If a page was injected: treat it as authoritative. Do NOT re-derive stack,
build commands, or conventions by reading the codebase — use the page.

If a stub was injected: build understanding during the session and create
an entity page when a write trigger fires (see below).

## Linear integration

For any Linear read/write, invoke the `linear-cli` skill (from the
`pawelwlazlo/linear-skills` plugin marketplace) — it has the full command
reference. Do NOT use a Linear MCP (the local MCP was removed; it bloated
context).

When the entity page frontmatter contains `linear.team` or `linear.project`,
prefer querying Linear for active work over re-asking the user. When recording
decisions, link to Linear issue IDs (e.g. "2026-05-05 — chose JWT over
sessions (LIN-123)").

### Issue workflow

When given a Linear issue ID:

1. Fetch the issue and read its full content.
2. **No implementation comment** → enter planning mode: draft a plan, run a QA
   session with the user to clarify details.
3. **Implementation comment exists** → review the plan; run QA only if
   ambiguities remain.

A plan must contain: **Objective**, **Scope**, **Technical Approach**,
**Implementation Steps**, **Acceptance Criteria**, **Risks**, **Dependencies**.

Post the finalized plan as a Linear comment before starting implementation.
After each working session, post a short summary comment (decisions, progress,
open questions) to preserve context for future sessions.

### Completion summary (mandatory)

After every working session — including continuations and partial sessions —
post a comment to the Linear issue. Must include:
- what was changed,
- scope completed,
- current status,
- validation / test results,
- what remains next.

Must not be skipped. The comment must be self-contained enough to resume
from Linear history alone without losing execution context.

### Branch policy

1. **On main/master**: before committing any changes, create an issue branch
   by fetching the branch name from Linear.
2. **On a different issue branch**: ask the user to choose:
   a. Create target branch from the current branch?
   b. Create target branch from main/master?
   c. Leave branch as-is?

## Obsidian integration

For any Obsidian vault read/write (including the wiki at `~/obsidian/nerdbrain`),
invoke the `obsidian-cli` skill — it has the full command reference and quirks.
When authoring or editing note content with Obsidian-specific syntax (wikilinks,
embeds, callouts, frontmatter properties), also invoke the `obsidian-markdown`
skill. For Bases (Obsidian's database views), use the `obsidian-bases` skill.

Do NOT use any Obsidian MCP and do NOT call the Local REST API directly
(`curl https://127.0.0.1:27124`) — both bloat context and add auth ceremony.
The `tier` value the SessionStart hook injects is informational only; the
preference order is fixed: `obsidian` CLI first, filesystem (`Read`/`Edit`/
`Write` on the vault path) as fallback.

Vault root: `~/obsidian/nerdbrain/`. Obsidian reloads from disk automatically,
so direct filesystem writes are safe. After writes, check for
`*sync-conflict*` siblings and warn the user if any appeared.

## Write protocol — WHEN

Write proactively when ANY of these fire:

1. You inferred build / test / run / deploy commands not yet on the page.
2. You found a project-specific convention not obvious from code.
3. The user mentioned a gotcha or non-obvious bug cause.
4. A decision was made in-session worth preserving.
5. You found a non-trivial setup quirk that would slow a future session.

DO NOT write:
- Facts trivially re-derivable from code (project layout, public API surface).
- One-off context irrelevant next session.
- Duplicates — re-read the relevant section before writing; edit rather
  than append if new info contradicts existing content.

## Write protocol — HOW

Section update modes:
- **Edit (rewrite):** Purpose, Stack, Commands, Conventions, References.
- **Append (chronological):** Gotchas, Decisions.
- **Edit + flag staleness:** Active context (flag when updated > 14 days ago).

Always bump frontmatter `updated: YYYY-MM-DD` on every write.

### Commands

The patterns below are the canonical shape for wiki entity-page writes.
For the broader CLI surface, see the `obsidian-cli` skill.

```
# Read (rare; the hook usually pre-loads the page)
obsidian read vault=nerdbrain path=5-wiki/entities/projects/<slug>.md

# Append (chronological, end-of-file)
obsidian append vault=nerdbrain \
                path=5-wiki/entities/projects/<slug>.md \
                content="$CONTENT"

# Create a new file
obsidian create vault=nerdbrain \
                path=5-wiki/entities/projects/<slug>.md \
                content="$CONTENT"
```

**Drop to filesystem when:**
- Content has newlines / multi-line markdown (CLI's `content=` value gets
  awkward to escape — use `Write` on the absolute path instead).
- You need a section-aware edit (CLI cannot insert under a specific heading
  — `Read` then `Edit` the file directly).

**If the vault directory itself is missing** (`tier=none`): wiki is
unreachable this session. Do not attempt writes. Mention briefly if the
user asks something the wiki would have answered.

## Index and log maintenance

**New entity page created:**
1. Append to `~/obsidian/nerdbrain/5-wiki/index.md` under `## Projekty`:
   `- [[<slug>]] — <one-line description>` (description in vault language, PL)
2. Append to `~/obsidian/nerdbrain/5-wiki/log.md`:
   `## [YYYY-MM-DD] entity | <slug> (new project page)`

**Entity page updated:**
Append to log only:
`## [YYYY-MM-DD] entity | <slug> (<short note>)`

## Creating a new page

Use the template below. Fill what you know with confidence; leave sections
empty rather than guessing. Initialize `local-paths` with the current
`host:$PWD` pair. Set `slug:` and `remote:` from the hook-injected values.

```markdown
---
type: entity
subtype: project
tags: [project]
created: YYYY-MM-DD
updated: YYYY-MM-DD
slug: <slug>
remote: <git-remote-url-or-empty>
local-paths:
  - {host: <hostname>, path: <absolute-path>}
linear:
  team: <team-key>
  project: <uuid>
related: []
---

# <slug>

## Purpose
One to three sentences: what it is, who it serves, what problem it solves.

## Stack
- Language: ...
- Framework: ...
- DB / infra: ...
- Key libraries: ...

## Commands
- Build: `...`
- Test: `...`
- Run dev: `...`
- Deploy: `...`

## Conventions
Project-specific patterns not obvious from code.

## Gotchas
Foot-guns, surprising behavior, "looks like X but isn't".

## Decisions
- `YYYY-MM-DD` — decision + reason (+ Linear/issue link if applicable)

## Active context
What is happening now, deadlines, freeze windows, who to ask.
Flag staleness when updated > 14 days ago.

## References
- Issue tracker (Linear / Jira / GitLab): ...
- Slack / Teams channel: ...
- Runbook / dashboard: ...
```

## Boundary cases
- Hook signals vault unreachable → wiki disabled this session, work normally.
- Hook flags sync conflicts → do NOT write to the affected page; tell the user.
- Two repos map to same slug → use `.nerdbrain-slug` in one to differentiate.
- Active context > 14 days old → treat as possibly stale; verify with user.
- Working inside ~/obsidian/nerdbrain → this CLAUDE.md is inactive.
