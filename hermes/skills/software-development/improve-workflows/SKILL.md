---
name: improve-workflows
version: 1.0.0
author: Hermes Agent (session-derived)
license: MIT
description: "Audit plan-writing and issue registration workflows."
---

# Improve Workflows

Operational patterns discovered during real improve skill executions. Supplements the improve skill (shadcn) with Hermes-specific tooling workflows.

## Issue Registration (`--issues`)

When the improve skill's `--issues` modifier publishes plans as GitHub issues:

### Procedure

1. Determine `owner/repo` from `git remote -v` — never assume from AGENTS.md or memory. The canonical upstream and the server's fork may use different owner names.
2. Check if issues are enabled: `gh issue list --repo owner/repo`. If "disabled", try the fork remote.
3. Verify labels exist: `gh label list --repo owner/repo`. Create missing ones first or omit.
4. Create: `gh issue create --repo owner/repo --title '...' --body '...' [--label '...']`
5. Record the issue URL in the plan file and tracker.

### Pitfalls

- **GitHub MCP auth failure → switch to `gh` CLI immediately.** Do not retry MCP. The MCP server requires `GITHUB_PERSONAL_ACCESS_TOKEN` env var; `gh` uses stored credentials. One retry wastes time; the fallback is instant.
- **Wrong repo name.** AGENTS.md may reference a canonical name that differs from the actual git remote. `git remote -v` is authoritative. If the primary repo has issues disabled, try the fork remote.
- **Missing labels.** `--label 'improve-audit'` fails if the label doesn't exist. Either create it first (`gh label create improve-audit --repo owner/repo`) or omit labels entirely.
- **Bulk issue registration (10+ plans).** Use `cronjob_manage` with `schedule: 'every 5m'` and `repeat: N` instead of creating all issues in one turn. Track progress in `plans/tracker.json` (JSON array with `done: boolean`, `plan_file`, `issue_url` fields per finding). Set `deliver` to the user's home channel for status updates.

## Subagent Audit Pattern

For the `standard` effort level (default), fan out with 4 parallel subagents:

1. **Correctness & Security** — input validation, auth/authz, SQL injection, XSS, race conditions
2. **Performance & Architecture** — N+1 queries, unbounded recursion, cache misuse, God classes
3. **Test Coverage & Quality** — untested critical paths, wrong annotations, DRY violations
4. **Tech Debt & DX** — baseline bloat, dead code, CI gaps, documentation

Each subagent prompt must include:
- Recon facts (languages, frameworks, key directories)
- Domain-specific risk hints from recon
- Decided tradeoffs from intent docs
- "Return findings only — no fixes, no file dumps"
- Hard Rules 4 and 6 from the improve skill (verbatim)

Subagent output schema per finding: `{id, category, finding, evidence, impact, effort, risk, confidence}`.

## Direction Audits (`improve next` / future feature)

When the maintainer asks what to BUILD NEXT rather than what is broken, do NOT
fan out by the nine bug categories. Fan out by DOMAIN, one consultant per
surface the feature would touch. Domain-scoped prompts produce far better
reports than category-scoped ones, because each consultant can reason about
one architecture end to end.

Typical four-way split for a new feature request in a Laravel app:
1. **Data model** — schema options for the new entities, indexes, migrations, time grain
2. **Backend data path** — controller/endpoint shape, query strategy, caching, payload size
3. **Frontend architecture** — existing page duplication, shared shell/component target, migration path
4. **Access control + privacy + testability** — permission/ability model, row scoping, disclosure risk, minimum test set

Do NOT write plans for a direction audit until the maintainer picks from the
presented options. Direction findings are options to weigh, not a ranked bug
table. `improve` already separates them; keep that separation in the write-up.

### Steer In-Flight Audits When the Maintainer Narrows Scope

A maintainer usually answers the first scope question *after* the fan-out is
already running. That is fine — the fan-out is background work and the
conversation continues. `delegate_task(action='steer', subagent_id=..., message=...)`
queues text onto that child's next tool result.

- **A steer aimed at a child that already finished is silently dropped** — the
  completion entry reports it as a `missed_steer`. When the maintainer's answer
  invalidates that child's recommendation, re-dispatch it rather than folding
  its now-stale analysis into the report.
- **Name what to DROP, not only what to add.** "No mobile, no importer" has to
  be an instruction to remove that design work; a child that already scoped it
  keeps designing it if you merely stop mentioning it.
- **Restate the consequence, not just the constraint.** "Rows are recorded at
  leaf units and rolled up the org tree" does not reach a child that planned a
  per-row store — say that the read path is an aggregate over descendants and
  that the existing recursive tree is the mechanism, not something to reinvent.
- `action='steer'` on a subagent that is no longer live errors out. Check
  `action='list'` for the live set before steering a batch.

See `references/domain-recon-techniques.md` for the recon greps that make these
audits cheap, the live-schema checks that turn a structural claim into a number,
and the output-truncation rule that keeps a wide sweep readable. See
`references/small-cell-privacy.md` when the feature shades polygons with health
case counts.

## Vetting Subagent Reports

Subagents over-report. Three failure classes to check:

1. **By-design behavior** reported as bug (e.g., "CSP unsafe-inline" when it's intentional)
2. **Mis-attributed evidence** — real finding, wrong file or line
3. **Duplicates** across subagents (same root cause, different symptoms)

Always open the cited code yourself before including a finding in the vetted table. Downgrade or reject accordingly.

**Verify a claim that changes a security or permissions decision yourself, every
time — do not delegate it.** A child asserting "this token is wildcard-scoped" is
a claim about the blast radius of a credential leak; it is cheap to confirm (read
the framework's `createToken` signature and check the default argument) and
expensive to get wrong. Same for anything that would become a new permission
string, a new ability, or a suppression threshold.

**Verify the cheap mechanical claims in a batch, not one at a time.** A dozen
single-purpose `grep`s each cost a round trip; grouping them into one script with
a labelled output per check costs one. Every finding you intend to keep gets a
verification pass, and a claim that fails it goes in the report marked as
unverified or is dropped.

**Report what the audit did not cover.** A direction audit that scoped itself to
four domains must say which categories it skipped, so the maintainer knows
whether a clean result means "clean" or "not looked at".

## Presenting a Direction Audit

Findings table first, then the architecture options as a separate section — the
maintainer weighs options, they do not rank them against bugs. Keep the two
visually distinct.

Every number in the report should be one you obtained, not one a child asserted:
row counts from a live query, index lists from `pg_indexes`, payload sizes from
`octet_length`, plan shapes from `EXPLAIN`. When a child's number cannot be
re-derived cheaply, either verify it or soften the claim.

Close the report by asking which findings become plans, offering a default
selection, and naming the dependency order. Then stop — do not write plans
nobody asked for.

## Plans Directory Structure

```
plans/
  tracker.json              ← queue for automated processing
  README.md                 ← index: priority order, dependency graph, status
  001-<slug>.md
  002-<slug>.md
```

Each plan file stamps the commit hash it was written against (`git rev-parse --short HEAD`).

The `tracker.json` schema:
```json
{
  "last_created": 0,
  "findings": [
    {
      "num": 1,
      "id": "SEC-001",
      "slug": "short-slug",
      "title": "Plan title",
      "category": "security",
      "effort": "M",
      "impact": "high",
      "done": false,
      "plan_file": "plans/001-short-slug.md",
      "issue_url": "https://github.com/.../issues/N"
    }
  ]
}
```
