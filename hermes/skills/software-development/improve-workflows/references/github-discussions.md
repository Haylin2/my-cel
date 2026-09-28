# GitHub Discussions: Reading, Posting, Commenting

Discussions are the third publishing surface next to issues and PRs. The REST
API does not cover them at all, and the porcelain has a JSON-output problem, so
route reads through GraphQL.

## Preflight

```bash
gh auth status                                    # once per session
gh api graphql -F query=@/path/to/q.graphql        # every read below
```

**Always put the GraphQL query in a file and pass it with `-F query=@file`.**
Passing the query inline with `-f query='...'` mangles it — `gh` treats the
string as the variable *value*, not the document, and you get
`Expected NAME, actual: STRING` or a parse error at `[1, 2]`. This bit every
time it was tried; the file form is the one that works.

## Confirm discussions are on, and get the category

```graphql
query {
  repository(owner: "OWNER", name: "REPO") {
    hasDiscussionsEnabled
    discussionCategories(first: 25) { nodes { id name slug isAnswerable } }
  }
}
```

`hasDiscussionsEnabled: false` means the whole surface is closed — do not try to
create anything. The `id` is needed to write a discussion via GraphQL; the
`slug` or `name` is what the porcelain `create` flag takes.

## List recent discussions with authors and comment counts

```graphql
query {
  repository(owner: "OWNER", name: "REPO") {
    discussions(first: 50, orderBy: { field: UPDATED_AT, direction: DESC }) {
      nodes {
        number title url createdAt answerChosenAt
        author { login }
        category { name slug }
        comments { totalCount }
      }
    }
  }
}
```

Order by `UPDATED_AT`, not `CREATED_AT`, when the task is "what is active right
now" — a long-lived thread with fresh replies is active, and created-order buries
it. `answerChosenAt` distinguishes a question already answered from one still
open, which is usually the deciding fact for whether a reply is welcome.

`gh discussion list --json` is not the tool for this: its JSON output is
malformed (`expected an object but got: array`). Use the GraphQL query above.

## Read the bodies you are about to respond to

Listing titles is not enough to write a substantive reply. One more query with
`body` on both the discussion and its `comments` nodes, then filter to the
numbers you care about. Comment threads carry the decisions — a proposal that
looks open in the title is often already settled three comments down.

## Create a discussion

```bash
gh discussion create -R OWNER/REPO \
  --category "Ideas" \
  --title "Short descriptive title" \
  --body-file /abs/path/body.md
```

`--category` takes the category **name or slug**, not the node id. Write the
body to a file rather than inlining it: long bodies with backticks, backslashes
and `$` are a quoting minefield in a shell argument, and a file is re-editable
before it goes out.

## Comment on a discussion

```bash
gh discussion comment NUMBER -R OWNER/REPO --body-file /abs/path/comment.md
```

One file per comment, written and reviewed separately. Never batch several
comments into one drafted file — a mangled draft in one reply does not block the
other three, but a combined writeup can leave all of them unsent.

## Verify what you posted

The create/comment commands return a URL. Confirm the write landed rather than
trusting the exit code:

```bash
gh discussion view NUMBER -R OWNER/REPO --json title,url,category,body
```

Comment counts are the cheap round trip for a multi-comment run — one pass over
the numbers you posted to, checking each count went up.

## Repo-state claims you can settle before replying

A surprising number of replies to proposals are settled by three cheap API
reads. Run them rather than speculating:

```bash
# Is a CI status gate real, or decorative?
gh api repos/O/R/branches/beta/protection          # 404 = no protection at all

# What branches actually exist on the canonical repo?
gh api repos/O/R/branches --jq '.[].name'

# Are two branches really in sync?
gh api repos/O/R/compare/main...beta \
  --jq '"ahead=\(.ahead_by) behind=\(.behind_by) status=\(.status)"'
# status: "diverged" is the finding — "identical" only shows when ahead=behind=0

# Does a numbered post exist as a PR, as an issue, or as neither?
gh pr view N -R O/R --json number,state,mergedAt,baseRefName
gh issue view N -R O/R --json number,state,closedAt
```

Issue and PR numbers share one namespace, so a post that is an issue 404s as a
PR and vice versa — check both before concluding a reference is wrong. And a
PR that is `MERGED` is not `CLOSED`: `gh pr view --json state` distinguishes
them, and collapsing the two turns "already shipped" into "already closed",
which reads as "rejected".

**Counting merged work over a date window:** filter on the base branch too. A
window count that mixes bases is the number someone else got wrong, so state
both the window and the base filter whenever you quote a count.

## The blank-scope and dead-query trap

A "no rows match" query is not a harmless null — it is a syntax error that
aborts the whole statement:

```sql
SELECT count(*) FROM t WHERE id IN ();   -- ERROR: syntax error at or near ")"
```

This is the single most common cause of a dashboard that renders fine with data
and 500s in production. Any `IN (...)` built by joining an id list at runtime —
rather than by a query builder, which turns an empty list into a false predicate —
must be guarded. The failure is invisible during development precisely because
dev datasets always produce a non-empty list.

## Token scopes for Discussions

Discussion reads and writes need the `read:discussion` (or `repo`) scope. When
`gh` is authenticated but a discussion read 404s or returns
`Could not resolve to a Discussion`, check the granted scopes before assuming
the content is gone:

```bash
gh auth status      # prints the scopes on the active token
```

A token without the discussion scope makes the Discussions tab look empty rather
than erroring, which reads as "nobody has posted yet" instead of "you cannot
read this".
