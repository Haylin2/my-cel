# Reviewing a batch of someone else's commits

The task: "what do you think about the commits from the last N hours?" — read a
commit range on a branch you did not write, judge it, and publish a verdict
(discussion comment, issue comment, review). You are an advisor here: the
deliverable is a defensible opinion, not a merged fix.

Read every commit's diff, not its message. Commit messages in a good batch are
accurate, but the diff is what you are reviewing.

## 1 — Establish the range from the remote, never from memory

Your working branch may be days behind the range you are asked about. Resolve
the tip explicitly and confirm it is an ancestor of what you think it is:

```bash
git fetch https://github.com/OWNER/REPO beta
git rev-parse --short FETCH_HEAD
git merge-base --is-ancestor <sha> FETCH_HEAD && echo YES || echo NO
```

`git log --oneline <base>..<tip>` gives the commits. Count merges separately
from real work (`git rev-list --count --no-merges <base>..<tip>`) — the merge
count inflates the apparent size of the batch.

## 2 — A change entering through two PRs is one change, not two

The same commit object can reach the tip twice via different PRs. Diff the two
before counting it as separate work:

```bash
git diff <sha-a> <sha-b> -- path/to/file   # empty output = identical change
git show <sha> | git patch-id --stable     # same patch-id = same diff
```

A PR that re-imports an earlier PR's work is a review observation, not a bug —
say it as "this batch's commit count is inflated", never as duplicated effort.

## 3 — Run the suite before claiming a test gap

You cannot claim "the tests miss this path" until you know the tests are green
on the tip. A red suite and an uncovered path are different findings.

Then read what the existing tests actually assert. A test that only ever picks
ranges, values, or inputs **adjacent to the current moment** cannot distinguish
"honours the input" from "always assumes now" — that is the blind spot, and it
is where a real bug hides while the whole batch reads as well-tested.

## 4 — Verify every claim you intend to publish, by running it

A review is only as good as its evidence. Three claim classes are *always*
wrong when reasoned and *usually* fine when executed — run them:

| Claim class | Execute |
|---|---|
| "this library call does X" | a 5-line PHP script booting the framework |
| "this date/label is invalid" | walk the real values through the library |
| "this table grows by N rows" | compute it; do not eyeball the interval |

Then re-run everything that ran red *after* your fix, and confirm the
pre-existing tests still pass — otherwise you have traded their bug for yours.

**A published claim you later disprove is a correction, not a footnote.** State
it plainly in the comment ("my earlier suspicion was wrong, verified here is
why") rather than quietly deleting it; the reader already reasoned along with
you.

## 5 — Check prior reviewers' concerns instead of inheriting them

A thread may already contain a review. Its concerns are hypotheses. For each
one, decide whether it survives contact with the code — e.g. "deleting these
plan files loses the decision history" is false if each deleted plan has a
closed issue carrying the same content. Say explicitly which prior concerns you
checked and cleared; that is more useful than restating them.

## 6 — Run the suite against their commit in a throwaway worktree

Never checkout someone else's commit in the user's working tree. Use a detached
worktree so the user's branch, staged changes, and untracked files are
untouched:

```bash
git worktree add /tmp/wt-<name> <sha>
cp -a .env /tmp/wt-<name>/.env
```

**`vendor/` must be copied, never symlinked.** Composer's generated
`autoload_psr4.php` computes `$baseDir = dirname($vendorDir)`, so a symlinked
`vendor` still resolves the `App\` namespace to the ORIGINAL repo — your edits
in the worktree are silently ignored and you "verify" unmodified code:

```bash
cp -a vendor /tmp/wt-<name>/vendor
cd /tmp/wt-<name> && php artisan package:discover
```

**Copy `public/build` too**, or every test that renders a layout fails with
"Vite manifest not found" — a worktree artifact that looks exactly like a
regression. When a suite fails only in a worktree, check for a missing build
asset before believing the failure.

Clean up with `git worktree remove /tmp/wt-<name> --force` and confirm the
user's `git status` is unchanged.

## 7 — Publish long comments through a payload file

Discussion and review comments routinely exceed shell-argument limits and are
full of backticks and quotes. Build the JSON body in a file, then:

```bash
gh api graphql -f query='
query { repository(owner:"OWNER", name:"REPO") { discussion(number:N) { id } } }' \
  --jq '.data.repository.discussion.id'
```

Resolve the **global node ID** (looks like `D_kwDO...`, not the number) and
pass it to `addDiscussionComment` via `gh api graphql --input payload.json`.

Never construct a discussion/review comment id by hand from the number — a
guessed node id fails or, worse, targets the wrong thread.

Then verify the post landed with a fresh read (author, length, url) before
telling the user it is published. Posting is a side effect: report the URL you
read back, not the one you intended to write.
