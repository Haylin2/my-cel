---
name: laravel-livewire
description: "Laravel 13 + Livewire 4 conventions, pitfalls, testing."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [laravel, livewire, php, pest, testing]
    category: software-development
---

# Laravel 13 + Livewire 4 Development

## When to Use

Use this skill when writing PHP/Laravel code, Livewire components, Pest tests,
API Resource transformers, or E2E tests for a Laravel 13 + Livewire 4 project.

Standing conventions and pitfalls for Laravel/Livewire projects. Applies to
PHP code changes, test writing, and API resource transformers.

## Always-On Rules

1. **Run Pint before commit.** `vendor/bin/pint --dirty` is enforced in CI.
2. **Clear config+route cache before running tests.** Stale `routes-v7.php`
   causes Livewire endpoint-hash mismatch — tests silently return 404 on
   `->set()`/`->call()`.
3. **Use `assertDatabaseHas` with all relevant fields.** Don't just assert on
   `title` — include `user_id`, `unit_id`, or any field the code was supposed
   to set. Partial assertions miss bugs.
4. **Test Resource transformers directly.** Don't rely solely on controller
   tests to cover API response shape — instantiate the Resource class and
   call `toArray(new Request())` to assert exact field contracts.
5. **E2E tests go in `tests/e2e/<feature>/`** with `.spec.ts` extension.
   Import from `../shared/fixtures` for `login`, `waitForLivewire`, etc.
6. **Regenerate PHPStan baseline after fixing errors.** When you fix errors
   that exist in `phpstan-baseline.neon`, the old entries become unmatched
   and PHPStan reports new errors. Run `vendor/bin/phpstan analyse
   --generate-baseline` after every fix round, then verify with
   `composer phpstan`.
7. **Never hand-interpolate a scope id list into raw SQL.** A permission-derived
   id list can be empty, and `implode(',', $ids)` then yields `IN ()` — a
   PostgreSQL syntax error, so the page 500s instead of showing zeroes. Eloquent
   `whereIn` compiles empty arrays to `0 = 1` and is safe; hand-built `IN (...)`
   is not. See `references/aggregate-query-pitfalls.md` Rule 1.

## Pitfalls

- **`whenLoaded` returns `MissingValue`, not `null`.** When calling
  `toArray()` directly on a JsonResource (not through `toResponse()`),
  `whenLoaded('relation')` returns a `MissingValue` object. Tests must
  check `instanceof` or use `array_key_exists` — `assertNull()` fails.
- **Factory defaults ≠ nullable columns.** A migration with
  `->default('o-bell')` on a NOT NULL column means the factory must NOT
  pass `null` for that field. Use the default value, not `null`.
- **Faker `passthrough()` requires an argument.** Use
  `fake()->optional(0.6)->words(3)` or another generator for optional
  JSON fields — `passthrough()` needs a value parameter.
- **Carbon `toISOString()` ≠ ATOM format.** `toISOString()` returns
  `.000000Z` suffix; ATOM uses timezone offset. Use `strtotime()` for
  flexible ISO 8601 validation in tests.
- **UUID primary key models + HasFactory.** Models with manual UUID
  generation in `boot()` (via `Str::uuid()`) work with `HasFactory`.
  Don't add `HasUuids` trait — it would conflict with the manual boot
  logic.
- **PHPStan `auth()->id()` vs `Auth::id()` in Livewire blade components.**
  PHPStan types `auth()` as `Illuminate\Contracts\Auth\Factory` which
  lacks `id()`. In anonymous-class Livewire blade components (single-file
  components with `return new class extends Component`), add
  `use Illuminate\Support\Facades\Auth;` and call `Auth::id()` instead.
  `auth()->user()` works fine (returns User|null), but `auth()->id()`
  does not.
- **PHPStan generic type for HasFactory.** PHPStan level 6+ requires the
  generic type annotation on `use HasFactory`. Write
  `/** @use HasFactory<\Database\Factories\YourFactory> */` immediately
  above the `use HasFactory;` statement. Without it, PHPStan reports
  `missingType.generics`.
- **PHPStan `@property-read` on JsonResource.** When a Resource class
  accesses `$this->some_field` (magic proxied from the underlying model),
  PHPStan reports `property.notFound`. Fix: add `@property-read` PHPDoc
  annotations for every accessed field, then access via
  `$model = $this->resource;` with a `@var Model $model` cast. Match
  the pattern used by other Resources in the project (see
  `NotificationResource.php` for the reference implementation).
- **`updateOrCreate` overwrites ownership on edit.** When using
  `Model::updateOrCreate(['id' => $editingId], [...])` and one field
  (e.g. `user_id`, `created_by`) should only be set on create — not on
  update — do NOT include it in the attributes array. The update path
  would overwrite the original value. Instead, omit the field from
  `updateOrCreate`, then conditionally set it after:
  ```php
  $model = Model::updateOrCreate(['id' => $editingId], [...]);
  if (! $editingId) {
      $model->update(['user_id' => Auth::id()]);
  }
  ```

## Dashboards & Report Endpoints

Before changing any stat card, chart, or report aggregation, read
`references/aggregate-query-pitfalls.md`. Standing rules:

- **A "last N days" chart needs a date predicate before the group-by.**
  `orderBy('day')->limit(N)` after a `groupBy` returns the N *oldest* groups —
  it looks right until the table outgrows the window. Filter on the date column
  so the query can use its index.
- **Empty buckets are gaps, not zeros.** `groupBy(date(col))` only returns days
  that have rows, so a day with no activity renders as a missing bar. Fill the
  window with `generate_series` + `LEFT JOIN`, or read a daily rollup the
  scheduler maintains — and say which, because a rollup always lags by its own
  generation interval.
- **Verify index coverage instead of assuming it.** An `AVG(CASE WHEN ...)` over
  a column with no index is invisible at dev row counts and a full scan in
  production. Query `pg_indexes` for the column before calling a query fast.
- **One scan per stat card.** Three `->count()` calls for total/open/closed is
  three scans; `COUNT(*) FILTER (WHERE ...)` (Postgres) or `SUM(CASE WHEN ...)`
  (portable, also works on the SQLite test driver) is one.
- **Prove query behaviour by running it.** Read the PHP, then run the real SQL
  against the dev database with `EXPLAIN (ANALYZE, BUFFERS)` and check
  `information_schema.columns` for columns you assumed exist. A conclusion
  drawn from reading code is a guess; a conclusion drawn from the returned rows
  is evidence.
- **Keep the UI chart and the report API on the same window.** Two definitions
  of one metric means nobody can tell which number is right when they disagree.
- **A window helper must keep the range, not just its width.** A factory that
  stores only `$days` and recomputes "now minus N" in the accessor cannot honour
  an explicit from/to range — it silently charts the most recent N days instead,
  so a user who picks last month sees this month. Store the bounds and return
  them. Covered in `references/aggregate-query-pitfalls.md` Rule 7.

## Map / GIS Pages (Leaflet + Livewire)

Maps are where Livewire's DOM diffing and a JS singleton library collide. Read
`references/gis-map-pitfalls.md` before adding or refactoring any map page, and
`references/browser-repro-harness.md` before reproducing a map bug in the
browser (Livewire form auth, SPA-navigation triggers, discriminating assertions).

Standing rules:

- **One map instance, owned by one shared component.** A page that embeds a map
  child component must receive that instance through a documented contract
  (`Livewire.on(...)` events or a single exported accessor), never by polling
  for a global. If you inherit a `window.map` + `setInterval`-until-ready
  pattern, count the defensive workarounds already in the file — a
  `setTimeout(invalidateSize)`, a container-`_leaflet_id` re-init branch, and a
  loop that manually `delete`s stale globals are each a bug that already
  shipped. Add no more.
- **Any "ready" gate on a global must also assert container identity.**
  `if (window.map && …)` passes against the *previous* page's instance, whose
  container is already detached — so the page binds layers to a map that is
  about to be replaced and renders nothing, with no error. Require
  `window.map.getContainer() === document.getElementById('map') &&
  document.body.contains(el)`. Existence is not readiness.
- **"Works on direct load, dead from the menu" is a global-singleton bug, not a
  data bug.** Reproduce both entry paths before reading any query code; a page
  whose output is correct standalone and empty after SPA navigation has an
  ordering or ownership defect, and the PHP side is exonerated.
- **`@script` runs once per component *instance*, not per render.** Two
  components that both `@script` against the same global run in mount order, so
  whichever resolves first wins and the loser binds to a stale object. Order is
  not guaranteed by nesting depth — verify it from a trace, never assume.
  See `references/gis-map-pitfalls.md`.
- **An identity guard mitigates a global-singleton bug; only explicit ownership
  resolves it.** Fixing every readiness gate still leaves pages racing over
  `window`. Moving the instance into an owner with a real lifecycle (`init()`
  builds, `destroy()` releases) removes the race instead of detecting it. Before
  designing that, **spike the lifecycle hook** — inject `x-data` with `init`/
  `destroy` console logs and click through one SPA hop to confirm teardown
  actually fires and in which order. That ordering is the design's foundation, and
  a few minutes of checking beats a wrong multi-file refactor.
  See `references/spa-lifecycle-refactor.md`.
- **Grep both `window.<global>` and `L.map(` before scoping a map refactor.** The
  first finds pages consuming the shared instance; the second finds pages owning
  their own, which never had the bug. A page whose globals are read by an E2E
  spec is a public contract — leave it, and name the exclusion in the plan so the
  scope is reviewable.
- **A green E2E suite proves nothing about an SPA-navigation bug if every spec
  uses `page.goto()`.** `goto` is a full reload, which is the entry path that
  works. Add a spec that clicks a real `wire:navigate` link and asserts rendered
  output, or the regression returns unnoticed.
- **A global JS library loads exactly once, from the shared layout.** If a page
  also pulls it from a CDN, two copies exist and `instanceof`/identity checks
  and cross-module references silently break. Check the layout before adding a
  `<script>` to a page.
- **Every CDN origin must be in the CSP before you leave report-only mode.**
  `connect-src 'self'` plus a CDN-loaded library or tile host is a page that
  works today and breaks on enforcement. Grep the CSP middleware for the origins
  the map actually needs.
- **A per-page-load Sanctum token minted into a JS variable is a pattern, not
  a convenience.** It churns rows in `personal_access_tokens`, widens the blast
  radius of whatever ability it grants, and lands the plaintext in script scope
  on every navigation. Mint one long-lived token, or proxy the data through
  session-authenticated Livewire instead of a Bearer fetch.
- **Bbox-driven refetch needs a sequence guard or AbortController.** Firing a
  request on every map `moveend` without cancellation lets an earlier, slower
  response land after a later one and repaint stale data. Debouncing is not
  enough — it only reduces the count, not the race.
- **Unscoped `ST_*` in an accessor is an N+1 waiting to happen.** An accessor
  that runs raw SQL to compute GeoJSON is fine only if every caller eager-loads
  the underlying attribute; check loop callers before trusting it.

## Merge Conflicts in Auto-Generated Files

When a PR has merge conflicts with `upstream/beta` in auto-generated files
(like `phpstan-baseline.neon`), do NOT manually merge the conflict markers.
These files are machine-generated — manual merge produces invalid output.

**Procedure:**
1. `git fetch upstream beta && git merge upstream/beta`
2. For the conflicted auto-generated file: `git checkout --theirs <file>`
   (take upstream's version as starting point)
3. `git add <file>`
4. Regenerate from scratch: `vendor/bin/phpstan analyse --no-progress --generate-baseline`
5. Verify: `composer phpstan`
6. `git add <file> && git commit --no-edit`
7. `git push origin <branch>`

**Never** edit phpstan-baseline.neon by hand to resolve conflicts.
The regenerate step produces the correct baseline for the current code state.

## Testing Patterns

See `references/testing-pitfalls.md` for the full decision table on
assertion patterns, factory creation, and E2E test structure.

## Reviewing Someone Else's Commits

When asked to review a range of commits you did not write (a batch on another
branch, a discussion thread, "what do you think about the last day of work"),
read `references/reviewing-others-commits.md` first.

Standing rules:

- **Run their suite on their commit before claiming a test gap.** Green tests
  that never exercise a path are the finding; a red suite is a different one.
- **Tests that only use inputs adjacent to `now` cannot catch a hardcoded
  "now".** Assert at least one case that is far in the past, or the assertion
  passes for the wrong reason.
- **Never verify in the user's working tree.** Use a detached worktree; copy
  `vendor/` (a symlink re-resolves the `App\` namespace to the original repo
  and silently ignores your edits) and `public/build` (a missing manifest fails
  every layout-rendering test and mimics a regression).
- **Verify each claim you publish by executing it, and correct disproved ones
  in the open.** A retracted finding belongs in the review as a correction, not
  a silent deletion.