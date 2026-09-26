---
name: github-actions-workflows
description: "Use when editing GitHub Actions workflow YAML."
version: 1.0.0
author: Sydney
license: MIT
metadata:
  hermes:
    tags: [github-actions, ci, workflow, yaml, runner, bootstrap]
    category: software-development
---

# GitHub Actions Workflow Editing

Editing a workflow file that is not in the same repo as the project it builds
(the state-repo pattern: one repo holds the YAML plus restored state, another
holds the app). `references/instance-runner-workflows.md` describes that shape.

## When to Use

- Editing any `.github/workflows/*.yml` — adding, reordering, renumbering or
  removing steps, or adding an install that later steps depend on.
- A workflow that bootstraps a machine from a scheduled/self-hosted run and
  restores state from a repo into the runner home.
- A workflow that operates on a project checked out from a *second* repo.

Not for reading CI results (use the `github` skill's CI reference) or for
repo/branch/PR management.

## Procedure

1. **Locate the file and its owning repo before editing.** The workflow usually
   lives in a different repo than the code it operates on. `git remote -v` in
   the workflow's directory tells you which repo you are about to change.

2. **Read the whole file, then map step order.** List every step name in order
   (`grep -n '^      - name:'`). Steps are sequential and each one establishes a
   guarantee the next depends on.

3. **Place a new step by guarantee, not by name or intuition.** An install that
   a later step's config file points at must run *before* that step. A restored
   config (a committed `config.yaml`, a manifest) is read late in the run, so
   anything its `command:`/`args:` reference needs must exist by then. Put
   index/build steps after the source they read is in place and before the
   process that consumes the index boots.

4. **`cd` to the project in every step that touches one.** A `run:` block starts
   in the checked-out repo's workspace, which is frequently NOT the app. A bare
   `composer require`, `npm install`, `php artisan …` or `npx` then installs into
   the wrong project and litters the wrong repo root. This is the most common
   defect in this pattern — see pitfalls.

5. **Keep numbering and quoting coherent.** Renumber a step when you insert one
   (or label it `10b.` and keep the sequence readable). Any `echo` containing
   `$(command)` needs double quotes; single quotes print the literal `$(…)`.

6. **Verify locally before committing** — `scripts/verify-workflow.sh <file>`
   parses the YAML, then `bash -n` every `run:` block with `${{ }}` expressions
   replaced by placeholders. A workflow that only runs on a schedule is
   otherwise unverifiable until it is too late.

7. **Commit narrowly, then push.** `git add <file>` — never `-A` in a state repo
   where other steps write files. If the push is rejected because the workflow's
   own trailing sync step pushed first, reconcile as described below.

## Removing a file the user does not want

When the file is tracked in the base branch but unwanted on this instance, drop
it branch-locally without opening a PR against the base:

```bash
git rm -q --cached path/to/file
rm -f path/to/file
grep -qxF 'path/to/file' .git/info/exclude 2>/dev/null \
  || echo 'path/to/file' >> .git/info/exclude
```

`.git/info/exclude` is local and unshared, so the base branch keeps the file
while this branch's tree and `git status` stay clean. Then remove EVERY
write/creation of that file from the workflow — do not keep a "courtesy"
creation step, and do not keep a bare `rm -f` for a file you simply never
create.

Standing preference for h-dashboard: the repo's own `AGENTS.md` is the
authoritative instruction file. Do not have a workflow generate a second
instruction file into the project.

## Pitfalls

- **A step's cwd is the checked-out repo, not the app.** The runner resets the
  working directory to the workspace between steps, so a `cd` in one step does
  not carry into the next. Every `run:` needs its own `cd` when it acts on a
  second repo. Symptom: a stray `composer.json` / `vendor/` / `package.json` at
  the state repo's root, and the tool failing at runtime because the package was
  never added to the app.
- **A scheduled job commits to the branch you are working on.** A trailing sync
  step pushes to the same branch, so a push can be rejected minutes after you
  fetched. Re-fetch and compare before assuming your push is stale; never
  force-push over the job's commits.
- **The state repo may have no commit identity.** `git commit` and
  `git rebase --continue` both fail with `empty ident name`; mid-rebase that can
  surface as a "staged changes in your working tree" message that masks the real
  cause. Set `user.name` / `user.email` per repo before the first commit.
- **`git rebase --continue` can wedge on its own commit.** When a rebase pauses
  mid-commit, abort and replay instead of fighting it: save the file,
  `git rebase --abort`, `git reset --hard origin/<branch>`, then
  `git cherry-pick <sha1> <sha2> …`. Verify the replayed file against your saved
  copy with `diff`.
- **Single-quoted `echo` around a command substitution prints literally.**
  `echo '… $(cmd)'` outputs `$(cmd)`.
- **Editing a live checkout's index as a side effect is not free.** A rehearsal
  of an index-removal snippet changes real git state; a later `git reset` leaves
  the file deleted on disk but tracked again, which looks like a clean tree
  while hiding the change. Rehearse destructive snippets on a throwaway copy
  (`git archive HEAD | tar -x -C <tmp>`) instead of the live checkout.

## Verification

- `scripts/verify-workflow.sh <file>` reports a successful parse and no `bash -n`
  failures, and lists every step name in order.
- `git diff --stat` after the edit shows only the workflow file (and any
  intended `.gitignore` line).
- After push: `git rev-parse --short HEAD origin/<branch>` matches, and
  `git show origin/<branch>:<file> | grep <the new step>` proves the change
  reached the remote rather than only the local checkout.
