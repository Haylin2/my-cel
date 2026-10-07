# Third-Party Audit Issue Review

Verifying a defect report you did not write, before replying publicly. The
failure mode is not missing a bug — it is repeating a wrong premise, or
building a severity argument on an operation that turns out to be recoverable.

## Attribution in the footer is not evidence

Issue bodies commonly close with "audited read-only at `<sha>` (branch
`<x>`); no file was changed." Treat both halves as unverified input. The branch
name in particular is frequently invented — the author audited whatever branch
was checked out locally and the name never had to survive a remote lookup.

Check both remotes before accepting it:

```bash
git ls-remote --heads origin            # your fork
gh api repos/<owner>/<repo>/branches --jq '.[].name'   # canonical upstream
```

A commit can be real and the branch still nonexistent. When it is, say so in
one line — it establishes that the rest of the provenance needs independent
checking.

## Cite the compose/deploy variant the docs reference, not the one that exists

Repos accumulate deployment variants for stacks they do not ship. A claim whose
evidence is a compose file that no doc ever links to is a claim about a fiction.

```bash
# what do the docs actually point at?
grep -rn "docker-compose" install-guid.md README.md references/ AGENTS.md
# what does the cited file actually define?
grep -n "volumes:" -A3 docker-compose-<cited>.yml
```

If the cited file defines a service the app never uses (no matching driver in
`config/database.php`, no matching client in `composer.json`), the evidence line
proves nothing about the running system.

## "Destructive" is not the same as "unreversible"

Before writing a data-loss severity argument, read what the cited operation
actually does. Archive-then-delete commands copy rows into an archive table
*before* the delete, so the scary-looking operation is recoverable and the
failure mode is duplicate keys, not loss.

Then find the sibling that really is irreversible — usually a job dispatched
from a UI with a shorter retention default and **no** archive step. That path is
what the backup argument belongs on, and the issue almost never cites it.

## Open every cited line before you quote it

Bulk audit issues cite line ranges in bulk, and a meaningful share of them point
at code that is not the thing being claimed. A range described as "the sibling
query with the same pattern" may turn out to be `search`/`orderBy` lines with no
pattern at all.

Before a cited range enters your comment, read it. Where a cited range does not
contain what the issue says it contains, say so explicitly ("that range is
`userUnitId`/`search`/`orderBy`; there is no `when()` or `empty()` in it") — the
author needs to drop the claim, not silently keep a dead reference.

## Reproduce the mechanism; do not reason about it

When an issue claims a *mechanism* (a header poisons the URL root, an icon button
emits no accessible name, a scope array is empty), read the vendor source to
understand it, then **actually run it**. Reproduction almost always surfaces a
worse impact than the author claimed, and that delta is the most valuable thing
you can add:

- Booting the real kernel and issuing a request with the spoofed headers showed
  the *redirect target* was poisoned — not just the persisted link, which is
  what the issue argued.
- `Blade::render()` on the real `bootstrap/app.php` plus a real browser
  accessibility tree showed the inner SVG's `aria-hidden` and that a
  `responsive` button's label is `display:none`, i.e. outside the accessibility
  tree entirely, not merely visually hidden.

Cheap reproductions per domain: `php artisan tinker` with `DB::listen()` for
query claims; a throwaway Feature test that asserts a status code for reachability
claims; `Blade::render()` for markup claims; `at()` + `flushState()` for
framework-state claims.

## "0 occurrences" in source is not "0 in the product"

Absence greps over source miss markup that a framework template generates at
render time. `aria-current` was zero in every view file yet present in the
rendered HTML, because the paginator's own blade template emits it — as it also
emits a `<nav role="navigation">` landmark. A landmark claimed absent was present
for the same reason.

So for every absence claim, ask what the *template* adds. Report it as "zero in
source, generated at render" rather than accepting or rejecting the number.

## Re-measure per request, not per method

A single measurement of the method in isolation hides the cost that matters. A
Livewire page that runs a method once inline in the blade and again from a
script block was measured at 1× when measured as a method call; measuring each
HTTP request separately showed the real per-interaction cost was roughly 1.5×
the figure the author gave for the whole page view.

Measure each request separately and report a table. Also check the total against
the author's own figure — under-claiming hides the urgency, and the correction
is as valuable as the confirmation.

## Check for memoization before believing a "runs twice" claim

Before accepting that a method or computed value executes twice, look for a
memoizing attribute on it. A method marked with a computed attribute is cached
for the request by the framework's computed-property base class, so the author's
"same thing runs on every re-render" claim is false for that page and collapses
the proposed "treat all four pages as one change" grouping.

This is a per-page property, not a codebase-wide one: check the attribute on
*each* page the issue grouped together.

## Run the repo's own sweep and classify every hit

When the project's instruction file ships a mandatory sweep command for a defect
family, run it and report **all** hits classified, not just the ones the issue
named. The unreported hits are what tell the maintainer whether this is one live
leak or a systemic one — a seven-hit sweep where six are correct fail-closed
patterns and one is live changes the severity and the fix from a refactor to a
one-line edit.

Classify each hit as real leak / load-bearing early-return / false positive, and
name the sites the issue missed that you verified as *healthy* so the author does
not re-audit them.

## Verify a proposed central-override layer actually resolves

Audit issues often propose one override layer (a wrapper component, a base class,
a shared partial) instead of N local edits. Before accepting it, check whether
that layer can override anything in this stack.

For Blade component tags, resolution consults the registered alias map **before**
the anonymous-component path, so a view file placed in the component view
directory for a tag that already has a class alias is silently ignored. Prove it
by rendering a deliberately conflicting file and reporting what the tag resolved
to. CSS behaves the opposite way — it cascades, so the same override reasoning
that holds for a stylesheet does not transfer to a component tag, and an issue
that justifies the layer by "the project already overrides in CSS" has reasoned
across two different mechanisms.

## Split a bulk issue by risk class, not only by actionability

An issue that bundles a mechanical count with a product decision should be split
on both axes. The mechanical part is urgent; the product part needs an owner.
Beyond that, a count-based finding goes stale as soon as any unrelated change
touches the files — and a sibling issue already open on one of those files will
move the number under you. Say that, and propose the split with a suggested
issue per part and its risk class.

## Absence claims need a git-scoped grep

A claim of the form "this setting is in no env template" must be checked
against what **ships**, not the working tree:

```bash
git grep -n "SETTING_NAME" -- '.env*'        # tracked templates only
git ls-files | grep -i 'env'                 # which templates are even committed
```

A bare `grep -r` over the tree picks up a local untracked `.env` (real secrets,
machine-specific values) and can miss a committed template — either way the
verdict is about your box, not the repo.

## Repo-internal contradiction beats your own prior

An issue whose central premise is environmental ("the only copy lives on this
host's volume") is settled or collapsed by the repo's own committed templates,
not by argument. Point at the committed env template that names a managed
database, or at the install doc that names a local socket — whichever the repo
actually ships. If it supports both topologies and declares neither as
canonical, say the premise is unproven *and* that the finding still stands on
its verifiable part.

## Splitting an un-actionable issue

Findings that mix a code gap with an infra decision should be split in the
reply, because an issue no PR can close gets left open forever:

| Part | Example | Route |
|---|---|---|
| Closable by a PR | missing scheduled job, missing doc section, coverage gap | ready-to-implement label |
| Not closable by a PR | RPO/RTO targets, off-host destination, encryption, retention, drill ownership, key custody | human-owner / needs-triage label |

When naming the closable part, name the pattern to follow and the test that
pins the surface — a scheduler-inventory test or a route-permission parity test
will fail CI the moment the entry is added, and the executor needs to hear that
from you.

## Language and register

Match the issue's language (repo issues may be Persian). Lead with the verdict
so the author knows whether to act. Corrections are about the work, never the
writer: "the key is `user->id`, not the request IP" — not "your analysis is
wrong". When a proposed fix step is technically mandatory rather than optional,
say why with the measured output, because an optional-sounding step is the one
that gets skipped.

## Posting

Draft each body to its own file first, so a retry re-sends identical text, and
re-read it before sending — generated long bodies come back with mangled
characters, and the damage reads as fluent until inspected.

Then post one comment per issue, as one API call each. Mechanics that matter:

- The body must be sent as a **JSON object with a `body` key**, not as raw
  markdown. Passing a markdown file straight to `--input` returns
  `400 Problems parsing JSON`.
- Drive the per-issue calls from a small script that shells out once per issue
  and reports each URL, rather than one shell command looping over issues. A
  confirmation gate applies to the whole command, so a single gate timeout
  silently drops every draft in the batch.
- If an issue-comment MCP tool exists, try it, but fall back to the CLI on an
  auth error — the comment tool and the issue-list tool can have different auth
  state in the same session.
- After posting, verify structurally on the platform you posted to: a length
  figure is not proof that a long body rendered intact.