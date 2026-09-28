# Domain recon techniques

Recon greps for direction audits, plus the output discipline that keeps a wide
sweep readable. These found the highest-leverage facts in every direction audit
run so far.

## Proving the feature does not exist yet

Grep the concept name in BOTH the English and the local-language form, across
code and seed data. In a Persian-language codebase a concept like "disease"
misses if you only grep `disease` — the real hits are `بیماری`. Do the same for
any other concept whose name appears in the domain but not in the code.

```bash
grep -rniE "disease|بیماری|<local term>" --include=*.php --include=*.blade.php \
  app database resources routes references 2>/dev/null | head -20
```

A handful of incidental hits (a unit name, a job title in seeder data) is the
normal result and is itself a finding: it proves there is no schema to extend.

## Proving dead endpoints

An API route with zero callers is a strong direction finding. Count callers
across views, JS, and tests:

```bash
grep -rn "<endpoint-name>" --include=*.blade.php --include=*.js --include=*.ts resources tests | head
```

Zero lines means the endpoint is unreachable from the product. Report it with
the route file:line AND the empty grep, so the maintainer can re-check.

## Proving a column or index is unused

Migrations accumulate spatial/geometry columns and indexes that no application
query ever uses. The inverse grep is the proof:

1. Find the index or column in its migration (it exists, with a GiST/unique
   flavour that signals intent).
2. Grep application code for the column name and for the spatial functions the
   index is meant to accelerate (`ST_Intersects`, `ST_Within`, `ST_MakeEnvelope`).
3. If every spatial filter is a plain `whereBetween` on two scalar columns and
   the spatial function never appears, the index is inert.

Say plainly whether the unused index is a missed opportunity or a non-issue for
the CURRENT workload — do not recommend building spatial queries just because a
spatial index happens to exist. A new feature is what would make it load-bearing.

**Confirm the index is empty before recommending it.** A geometry column whose
backfill ran in the migration before the data existed stays NULL forever, so its
GiST index has zero entries and any plan built on it returns nothing. A grep
proves the code does not use it; only a live count proves whether the index has
anything in it. The two facts point opposite ways from the intuition that "there
is an unused spatial index, so use it".

## Live schema checks turn a structural claim into a number

Structural greps establish shape. Row counts, index lists, and EXPLAIN plans
establish magnitude — and magnitude is what decides whether a finding is real.
Use the project's read-only DB tool (Boost's `database_query`, `psql`, or
equivalent) for SELECT/EXPLAIN only. Highest-value queries for a data-path audit:

```sql
-- population, non-nullness, and feature coverage in one round trip
SELECT (SELECT count(*) FROM t) AS total,
       (SELECT count(*) FROM t WHERE geom IS NOT NULL) AS geom_populated,
       (SELECT count(*) FROM t WHERE fk IS NOT NULL) AS has_fk;

SELECT tablename, indexname, indexdef FROM pg_indexes
WHERE tablename IN ('a','b') ORDER BY tablename, indexname;

EXPLAIN ANALYZE SELECT ...;   -- cite the real plan node + execution time
```

Three things this catches that greps cannot: a missing index on an FK column
(PostgreSQL does not index FK columns for you, so a `belongsTo` filter has no
index unless a migration added one), a spatial column that is 100% NULL, and a
query whose "optimisation" is a regression (an indexed-but-empty path loses to
the plain scan).

**Name the driver/extension version and check function availability before
relying on a postgis function.** Some `ST_*` functions referenced in current docs
do not exist in the installed release — verify against `pg_proc` or
`postgis_version()` and say so plainly rather than assuming the docs match the
deployment.

## Quantify cache-key cardinality before proposing a cache shape

A cache key with an unbounded dimension (a viewport bbox, a zoom level, a raw
search string) multiplies silently. Do the arithmetic out loud in the report:
distinct keys per user per day, times users, times payload size, times TTL. The
decisive metric is usually the **hit rate**, not the key count — a bbox key is
mostly write-once-never-read garbage that occupies the store for the full TTL,
while a domain-keyed cache is re-read on every page load.

State the key shape the FEATURE needs, not the one the code has. A map that
shades whole polygons is a very different access pattern from one that re-queries
on every pan, and inheriting the existing bbox key for a choropleth is a
straightforward 100x mistake.

## Proving a documented feature is absent from the code

Docs drift. When AGENTS.md or a reference doc names a table, model, route, or
command, prove it exists before any recommendation rests on it:

```bash
grep -rln '<table_name>' database/ app/          # no migration or model
grep -n  '<table_name>' AGENTS.md references/    # but docs describe it
```

A documented table with no migration is doc drift — report it as its own small
finding. Building a plan on the assumption that a documented subsystem exists is
how an audit goes wrong in a way the maintainer cannot see.

## Proving a library is loaded twice

Check the shared layout, then check whether any single page loads it again
itself (CDN `<script>` in a `@push`/`@script` block). Two copies of a global
singleton library break identity: instances created against copy A are invisible
to code holding a reference from copy B.

## Never cat a generated-data file

Seeder data files and fixture arrays can hold hundreds of kilobytes of
coordinates in a single line. `cat`/`head` on one floods the context and the
tool's output capture (a single wide command produced 120k chars and wrote a
side log).

```bash
wc -c database/seeders/SomeSeeder.php     # bytes
wc -l database/seeders/SomeSeeder.php     # lines
```

Report sizes and counts. When a specific region of the file is needed, read it
with `read_file` using `offset`/`limit`, or `sed -n '<start>,<end>p'`.

## Output discipline for wide sweeps

- Cap every recursive grep: `| head -N`. Uncapped `grep -r` over `app database
  resources routes` will fill the output window and truncate the interesting
  middle.
- Prefer several medium calls over one giant call: file listings + line counts
  first, then open only the files worth reading.
- Do not chain many unrelated greps into one command whose output you then have
  to attribute. Two or three commands max, each with a small `head`.
- A `wc -l` over candidate files is the cheapest way to rank a directory for
  attention. Open the biggest ones first; they hold the duplication.
