# Aggregate & Report Query Pitfalls

Dashboards, report endpoints, and stat cards are where a query that looked
correct at 50 rows becomes a production incident. Every rule here is a
correctness bug first and a performance concern second.

## Rule 1 — an empty scope list in hand-built SQL is a 500, not an empty result

Any scope derived from permissions can legitimately come back empty: a user with
no units, no unit in session, or a filtered-down id list. `implode(',', $ids)`
on `[]` produces the empty string, so the query becomes `WHERE unit_id IN ()`,
which is a **syntax error** in PostgreSQL — the page 500s instead of rendering
zeroes.

Eloquent's `whereIn` is safe: an empty array compiles to `0 = 1`. Hand-built
`IN (...)` is not. When you interpolate an id list, branch on emptiness:

```php
->when($ids === [], fn ($q) => $q->whereRaw('1 = 0'))
->when($ids !== [], fn ($q) => $q->whereIn('unit_id', $ids))
```

**Verify it, don't reason about it.** A scope-empty test must exist alongside the
feature, or the guard is one refactor from regressing.

## Rule 2 — `ORDER BY` before `LIMIT` returns the OLDEST groups

```php
->selectRaw('date(created_at) as day, count(*) as count')
->groupBy('day')
->orderBy('day')
->limit(30)   // 30 OLDEST days, not 30 most recent
```

A chart labelled "last 30 days" silently renders the oldest 30 days present.
It looks plausible on a young table and becomes wrong the moment history
outgrows the window. Prefer a date predicate **before** the group-by so the
query can use the date index:

```php
->where('created_at', '>=', now()->subDays(30))
->groupBy('day')
```

If the table genuinely has no date column, `orderByDesc('day')` + reverse in
PHP is correct but still reads the whole table — pair it with a real window.

## Rule 3 — unbounded date bucketing scales forever

A `groupBy(date(col))` with no predicate on `col` scans the entire table on
every request and its result grows with project age. Give it an explicit window
or read from a rollup table that a scheduled job maintains.

## Rule 4 — empty buckets are gaps, not zeros

Date group-by returns only days that have at least one row. A column chart then
renders a **gap** where a zero belongs, and the trend line skips days
silently. Two fixes:

- `generate_series` over the window, `LEFT JOIN` the aggregate onto it
- read from a daily rollup table a scheduler already populates

State which one you chose and why in the PR — a rollup is faster but always
lags by its own generation interval, so "today" is never in it.

## Rule 5 — conditional aggregation on an unindexed column is a future full scan

```php
AVG(CASE WHEN status = 'completed' AND completed_at IS NOT NULL
    THEN EXTRACT(EPOCH FROM (completed_at - created_at)) / 86400 END)
```

Index coverage is the difference between an index scan and reading the whole
table. At dev row counts the query is instant either way, so this is invisible
until production. **Check the index, don't assume:**

```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'tickets' AND indexdef ILIKE '%completed_at%';
```

When the aggregate runs over the same column set on every dashboard load,
consider a partial index (`WHERE status = 'completed'`) or a rollup.

## Rule 6 — a single scan for a stat card, not one query per number

Three `->count()` calls for total/open/closed is three scans. One scan with
`COUNT(*) FILTER (WHERE ...)` (PostgreSQL) or `SUM(CASE WHEN ...)` (portable,
works on the SQLite test driver) returns the same numbers. Same rule for
per-day and per-unit breakdowns in one report endpoint — and keep the UI chart
and the report API on the *same* window, or you have two definitions of one
metric and no way to tell which is right.

## Rule 7 — a window helper that keeps only the WIDTH cannot honour a RANGE

The trap appears when a series/window factory is built for "the last N days"
and a page later needs a user-picked from/to range:

```php
public static function between(Carbon $from, Carbon $to): self
{
    $days = $from->diffInDays($to) + 1;
    return new self($days);          // only the width survives
}

public function window(): array
{
    $to = now()->startOfDay();       // always re-anchored to today
    return [$to->copy()->subDays($this->days - 1)->toDateString(), $to->toDateString()];
}
```

`between()` now returns exactly the same series as `lastDays($days)`. Every
row inside the range the user picked is charted as zero, and the chart renders
a full window of zeros — a plausible-looking empty report, not an error. The
dashboard path (last N days) stays correct, which is why this survives review:
only the date-picker pages break.

Keep the bounds:

```php
private readonly ?array $explicitBounds;   // array{0: Carbon, 1: Carbon}|null

public static function between(Carbon $from, Carbon $to): self
{
    $fromDay = $from->copy()->startOfDay();
    $toDay   = $to->copy()->startOfDay();

    return new self(max(1, (int) $fromDay->diffInDays($toDay) + 1), [$fromDay, $toDay]);
}

public function window(): array
{
    if ($this->explicitBounds !== null) {
        return [$this->explicitBounds[0]->toDateString(), $this->explicitBounds[1]->toDateString()];
    }

    $to = now()->startOfDay();

    return [$to->copy()->subDays($this->days - 1)->toDateString(), $to->toDateString()];
}
```

**Prove it with a range in the past.** Assert the returned bounds, then assert
that a row placed inside the chosen range is non-zero in the output — the
bounds assertion alone still passes for a helper that returns the right dates
but joins against the wrong window. Existing tests that only pick ranges ending
at (or one day past) `now()` cannot distinguish the two implementations; that is
the entire blind spot.

## Procedure — check a claim about a query before you assert it

Never conclude a query is fast, correct, or wrong from reading its PHP. Run it.

```bash
# Does the column exist at all? (catches proposed export columns that don't)
psql -h 127.0.0.1 -U USER -d DB -c "
SELECT column_name FROM information_schema.columns
WHERE table_name='x' ORDER BY ordinal_position;"

# Is it indexed?
psql -h 127.0.0.1 -U USER -d DB -c "
SELECT indexname FROM pg_indexes WHERE tablename='x';"

# What does the query actually return?
psql -h 127.0.0.1 -U USER -d DB -c "<the real query>"

# What is the plan?
psql -h 127.0.0.1 -U USER -d DB -c "EXPLAIN (ANALYZE, BUFFERS) <the real query>;"
```

Take the password from the project's own env file rather than prompting:

```bash
export PGPASSWORD=$(grep -m1 '^DB_PASSWORD=' .env.testing | cut -d= -f2-)
```

Note the **test** database in `phpunit.xml` may not exist yet — the dev
database is the one to probe. Confirm which one answered before trusting a
row count as evidence.

## Cache versioning convention

Stat blocks are cached under `namespace:v{version}:{scopeHash}` so a version
bump invalidates every scope at once. Read the version through the project's
invalidation service rather than reaching for the raw key, and remember the
version is part of the key: bumping it orphans the old entries until their TTL
expires. A namespace added to a new cache key must also be registered for
periodic pruning, or stale versions accumulate.
