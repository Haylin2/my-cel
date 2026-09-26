---
name: git-workflow
description: "Git pitfalls: nested repos, staging, identity."
version: 1.0.0
author: Sydney
license: MIT
metadata:
  hermes:
    tags: [git, workflow, pitfalls, staging, nested-repos, commit]
    category: software-development
---

# Git Workflow

Pitfalls and procedures for everyday git operations that fall outside standard
`gh` CLI workflows (for gh-specific flows see the `github` skill).

## Standing Rules

- Always check `git status` and `git remote -v` before staging or pushing.
- Configure per-repo identity before first commit if global config is absent.
- Never assume a branch name — read it from `git branch --show-current`.
- When a CI job commits to the same branch you are on, fetch and compare before
  concluding your push is stale, and never force-push over the job's commits.
- For GitHub Actions workflow YAML itself (step order, per-step `cd`, local
  verification), see the `github-actions-workflows` skill.

## Pitfalls

### Nested `.git` directories when copying content

When `cp -r` (or similar) a directory that contains its own `.git` into another repo,
`git add` detects the nested `.git` and stages only a submodule reference (mode 160000),
not the actual files. Clones of the outer repo will not contain the copied content.

**Fix — remove nested `.git` before staging:**

```bash
cp -r /source/dir target/inside/repo
rm -rf target/inside/repo/.git
git add target/inside/repo/
```

If already staged as submodule:

```bash
git rm -r --cached target/inside/repo/
rm -rf target/inside/repo/.git
git add target/inside/repo/
git commit -m "Add dir contents (fix nested repo)"
```

### Unintended file changes in feature commits

When committing feature work, run `git diff --stat` before staging to catch
unintended modifications to config/meta files (e.g. `AGENTS.md`, `.hermes.md`)
that were modified by tooling or agents during the session but are not part of
the feature.

**Prevention:** `git add -p` or selective `git add <paths>` instead of
`git add -A`. Review `git diff --staged --stat` before committing.

**Fix — restore from upstream before amend:**

```bash
git show upstream/beta:AGENTS.md > AGENTS.md
git add AGENTS.md
git commit --amend --no-edit
```

### Missing git identity on fresh clones

New clones may lack both global and per-repo `user.name`/`user.email`.
Commits fail with `empty ident name`.

**Fix — set per-repo config before first commit:**

```bash
git config user.email "user@users.noreply.github.com"
git config user.name "username"
```

Detect from `gh auth status` or set manually.

Mid-rebase this failure can surface as a *different* message — `git rebase
--continue` complaining about "staged changes in your working tree" — because
rebase is mid-commit and cannot open an editor to ask for an identity. Read the
real cause from `git status` (it prints the rebase progress and the pending
commit) instead of staging things to satisfy the message.

### `git rebase --continue` wedged on its own commit

A rebase that pauses while replaying your own commit can refuse to continue
repeatedly even with the conflict resolved and identity configured — the todo
list still lists the commit, `HEAD` never moves, and the message does not
change. Continuing to poke it wastes the session.

**Fix — abort and replay:**

```bash
cp <the-file-you-edited> /tmp/saved          # keep your version
git rebase --abort
git fetch origin
git reset --hard origin/<branch>
git cherry-pick <sha1> <sha2> ...
diff /tmp/saved <the-file-you-edited>         # prove the replay is intact
```

Cherry-picking onto the freshly fetched remote head keeps the other party's
commits and lands yours in the same order, without the rebase state machine.

### Rehearse index-altering snippets on a copy, not the checkout

Any snippet that changes the real index (`git rm --cached`, `git add`, staging
for a commit) mutates live git state. Running it to "see what happens" leaves
staged changes behind, and a later `git reset` can hide the real effect (a
deleted file becomes tracked-again-but-absent: `git status` looks almost clean
and the deletion is invisible to the next agent).

**Fix — run it against an exported tree first:**

```bash
git archive HEAD | tar -x -C /tmp/rehearsal
# run the snippet inside /tmp/rehearsal, then inspect git status there
```

Only then run it for real, and re-check `git status` in the real repo afterwards.

## Synchronizing a repository with a fork

Use this when a repository has a working branch and a canonical integration branch, but remote names and branch names must be discovered rather than assumed.

1. **Discover before changing anything.** Read `git remote -v`, `git branch --show-current`, and `git status --short --branch`. Classify each remote and the base branch from the repository's instructions and fetched refs; do not infer meanings from names such as `origin` or `upstream`.

2. **Fetch both sides before comparing.** Use the discovered remote and branch variables:

   ```bash
   git fetch --prune "$fork_remote"
   git fetch --prune "$upstream_remote"
   git rev-list --left-right --count "$fork_remote/$base_branch...$upstream_remote/$base_branch"
   ```

   A nonzero left side means the fork integration branch has commits absent upstream. Never force-update it; stop and reconcile explicitly.

3. **Fast-forward the fork only when ancestry proves it is safe.** Check, then push the canonical base ref to the fork without changing remotes:

   ```bash
   git merge-base --is-ancestor "$fork_remote/$base_branch" "$upstream_remote/$base_branch"
   git push "$fork_remote" "$upstream_remote/$base_branch:refs/heads/$base_branch"
   git fetch --prune "$fork_remote"
   ```

   The ancestor check prevents overwriting fork-only work; a non-fast-forward result requires a human-reviewed reconciliation.

4. **Integrate the updated fork base into the current branch without switching branches.** Merge it, preserving local work:

   ```bash
   git merge --no-edit "$fork_remote/$base_branch"
   ```

   Verify the updated base is reachable from `HEAD` before pushing.

5. **Push and verify the exact current branch.** Do not use a generic `git push` or push normal work to the integration branch. Before pushing, fetch the remote and compare the exact current-branch ref; a branch may display a tracking label for the integration branch while its own remote ref has separate history.

   ```bash
   working_branch=$(git branch --show-current)
   git fetch --prune "$fork_remote"
   git rev-list --left-right --count "HEAD...$fork_remote/$working_branch"
   git push "$fork_remote" "HEAD:refs/heads/$working_branch"
   git ls-remote "$fork_remote" "refs/heads/$base_branch" "refs/heads/$working_branch"
   git status --short --branch
   ```

   If the remote current branch has commits absent locally, stop before force-pushing. Merge that remote ref into the fixed working branch, review the merge, rerun verification, and then push. This preserves remote work while ensuring the push is fast-forward-safe.

   Completion requires the working tree to be clean, the current branch to contain the synchronized base, and the remote ref to match the expected commit.

### Pitfalls

- **Do not trust a misleading upstream tracking label.** A branch can display `[origin/beta]` while the work belongs on another branch; inspect the actual ref and commit ancestry.
- **Do not force-push an integration branch.** A fast-forward-only push preserves fork-only commits; divergence is a review decision, not a command to overwrite.
- **Do not switch branches during synchronization.** Keep the working branch fixed; merge the fetched base into it so local commits and the integration history remain explicit.
- **Do not claim completion from a successful command alone.** Verify both remote refs and the local status before reporting synchronization complete.

## Verification

- `git status` shows no unexpected submodule entries.
- `git diff --cached --stat` shows actual file additions, not just mode changes.
- Commit and push succeed without warnings about embedded repos.
- For fork synchronization, the base branch is fast-forward-safe, the working branch contains it, and `git ls-remote` confirms the pushed ref.
