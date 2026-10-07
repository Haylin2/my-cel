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
`references/github-discussions.md` for the Discussions API and for the cheap
repo-state reads that settle a proposal question before you reply to it. See
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

## Reviewing Someone Else's Proposal

When the task is "reply to these open threads / discussions with your view" —
rather than "find the bugs yourself" — the value you add is entirely in what
you **verified** versus what you **asserted**. A thread full of opinions is
worth nothing; a thread where every claim carries a file:line, an index name, or
a live query result is worth acting on.

**Procedure:**

1. **Read every body you plan to respond to** before writing a word. Titles
   misstate scope routinely.
2. **Extract each falsifiable claim.** "31 PRs merged", "beta is in sync with
   main", "a status gate will keep beta stable", "the persons table has a phone
   field" — each is checkable, and each is a chance to be the person who catches
   the error.
3. **Verify the cheap mechanical claims in one batched script**, not one
   `gh`/SQL call per claim. A dozen single-purpose round trips cost a dozen
   context switches for facts that are all API reads.
4. **Separate what you found into: a correction, a confirmation, and an
   unknown.** A reply that only corrects reads as hostile; one that only agrees
   adds nothing. Confirmation is worth stating explicitly — "the rest of your
   pattern matches `UnitsExport` exactly" tells the author which half of their
   proposal is safe to build.
5. **Say which findings are certain and which are judgement.** "This column
   does not exist" is verifiable. "This will get slow" is a prediction. Mark the
   difference or the prediction inherits the credibility of the fact.
6. **Offer to do the mechanical part** rather than asking to be assigned it.
   Naming the exact next action you could take is more useful than a generic
   offer to help.

**Corrections must be about the work, not the writer.** "The count is 22 with
base=beta, not 31" — never "your summary is wrong." The author's number was
probably right for a different filter, and saying so is both kinder and more
accurate.

**Verify before replying, even when the thread is urgent.** Three replies in
this session found factual errors in work that had already been merged. The
cost of one extra `gh api` call is nothing next to publishing a correction
that is itself wrong.

When the user waives approval for a multi-thread sweep, that waiver covers
*posting*, never *verifying*. Draft, check, post, then report each URL — and
write each reply to its own file so one mangled draft does not block the rest.

**Draft text must be re-read before it goes out.** Long generated bodies
occasionally come back with corrupted characters and truncated sentences, and
the corruption reads as fluent until you look closely. Scanning the rendered
file catches it in seconds; posting it does not. When a draft looks mangled,
rewrite it whole rather than patching around the damaged spans — a partially
repaired draft is harder to review than a fresh one.

**On Telegram, verify long output the same way.** A length figure is not proof
that a body posted intact. A short structural read-back (title, category, body
size, comment count) is the check.

See `references/github-discussions.md` for the Discussion API mechanics, and the
`laravel-livewire` skill's `references/aggregate-query-pitfalls.md` for the
query-level verification probes.

## Reviewing a Third-Party Audit Issue

A sibling of the Discussions workflow above: someone else (often an
auto-generated contributor) filed an **issue** claiming a defect, with an
"Audited read-only at `<sha>` on branch `<x>`" footer. Your job is to verify,
then publish your own view with reasoning as a comment — not to fix it. Your
authority comes entirely from what you checked, so the value is in the
corrections and the missed risks, not in agreeing.

1. **Dump the body to a file and read it whole.** Titles routinely misstate
   scope; the footer is a claim, not evidence.
2. **Check the issue's own provenance before trusting any of it.** Does the cited
   commit exist, and does the cited branch exist on *either* remote (your fork
   and the canonical upstream)? A fabricated attribution means verify the rest
   harder.
3. **Audit against current HEAD, not the cited sha.** `git fetch` the base and
   pin the review to a commit you name, or the line numbers you quote will be
   the issue's stale ones.
4. **Read the repo's authoritative instruction file first.** It pins decisions
   (policies, env templates, install docs) that an audit issue may contradict,
   and those contradictions are often the real finding.
5. **Batch the mechanical checks into one labelled script** — cited `file:line`
   pairs, "appears in no template" greps, scheduler/job inventories, dependency
   lists. Then dispatch subagents for the deep framework-level verification and
   re-check their highest-severity claims yourself.
6. **Split every claim three ways: repo-verifiable code fact / environment fact
   (usually NOT verifiable from a repo) / product decision (not the repo's
   business).** Say which is which in the comment.
7. **Comment structure that works:** verdict → what reproduced (with measured
   output) → corrections with `file:line` → what the issue missed → whether it
   is closable by a PR at all → label suggestion → what you did NOT verify.

**Always suggest a label.** Read the label list before recommending one, and
route infra-decision findings to a human-owner label rather than a ready-to-
implement one — an issue no PR can close left unlabeled gets nobody.

## Reviewing a Batch of Fresh Issues

Audits arrive in bursts and the ask is "the new ones, no comment and no label".
List, filter, then fan out — one reviewer per issue, all in a single
`delegate_task` call, because each issue's verification is independent and each
reviewer's context would otherwise be diluted by the others.

Screen the batch mechanically before dispatching anything:

```bash
gh issue list --repo owner/repo --state open --json number,title,comments,labels,createdAt
```

Issues carrying comments or labels have already been triaged; skip them unless
asked. Fetch each remaining body to its own file so a reviewer reads the claim
whole and the batch survives a context loss:

```bash
gh issue view N --repo owner/repo --json body --jq .body > "$SCRATCH/issue-N.md"
```

Give each reviewer the issues file path, the pinned commit, the instruction-file
path, and — critically — **the specific things you want disproven, not merely
checked**. "Verify the claim" invites agreement; "prove whether this scope array
is reachable for a user with permission P and no unit row" forces the reviewer
to find the case that voids the finding. Tell reviewers to report in the issue's
own language and to cite `file:line` for every number.

Reviewers work in the background. Draft nothing until their reports arrive — a
correction built on an unverified report is the failure this whole workflow
exists to prevent. When the user waives approval for posting a batch, that
waiver covers *posting*, never *verifying*, and it does not extend to applying
labels unless they asked for that too.

**Review the report, not just its conclusion.** Every batch this far produced
findings that were correct in substance and wrong in at least one cited
location or count. Re-open the cited lines yourself and re-derive the headline
numbers before they reach a comment; a correction that is itself wrong costs
more than silence.

See `references/third-party-issue-review.md` for the claim-traps (fabricated
branch attribution, stale compose variants, "destructive" that archives first,
absence greps that pick up untracked env files, cited ranges that do not contain
what they are claimed to contain, source-grep absence claims that a framework
template fills in at render time, "runs twice" claims that a memoizing
attribute disproves) and the split recipe.

## Writing an Execution Plan From a Debugged Bug

A distinct class from an audit-driven plan: the root cause is already **verified**
by a working repro, so the plan's job is to transfer that confidence to an
executor who was not present. The user asking "write the full plan first, then we
start" wants the reasoning auditable, not more debugging.

**Follow the repo's own existing plan files.** `ls plans/` first — match the
house format (header block with commit stamp, quoted context, phase table,
per-phase done-criteria). A plan that invents its own structure is harder to
review than one that looks like its neighbours.

**Carry evidence, not conclusions.** Quote the measured reproduction ratio, the
console trace that named the loser, and the identity check that confirmed it.
"The map is racy" is unfalsifiable; "0/6 via menu navigation vs 783 on direct
load, `DESTROY` logged before `INIT`" is a fact the executor can re-check.

**Verify every `file:line` in the plan before committing it.** Batch the checks
into one script with labelled output. Off-by-one line numbers in a plan send the
executor to the wrong line and cost more than the batch costs to produce. If a
claim fails, fix it in the file rather than hoping nobody looks.

**Separate the mechanism spike from the code spike.** A `console.log` injected to
read an execution order is instrumentation and must be reverted; the reading is
what belongs in the plan. State the result as a reusable fact, never ship the
temporary edit.

**Phase the test before the fix.** A refactor plan whose regression spec lands in
the same phase as the implementation cannot prove the spec has teeth. Make
"it must fail against current code, or STOP and report" an explicit done-criterion.

**Write the escape-hatch table.** Multi-file refactors fail in ways the happy path
never anticipated. Give the executor named STOP conditions (this test went green,
so the repro was wrong; this out-of-scope file turns out to be affected; this
baseline gained an entry) so it reports instead of improvising.

**Name the exclusions and their reason.** "6 files, 2 untouched because they own
their own map and are pinned by E2E assertions" is reviewable. Quietly widening
scope is how a plan loses the reader's trust.

**Verify plan claims about the build, not just the code.** Confirm the baseline is
green before the first phase, and confirm any build step the plan introduces
still passes — a broken build discovered mid-execution invalidates the phases
after it.

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
