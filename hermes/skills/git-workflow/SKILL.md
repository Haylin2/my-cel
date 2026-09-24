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
