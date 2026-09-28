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

## Map / GIS Pages (Leaflet + Livewire)

Maps are where Livewire's DOM diffing and a JS singleton library collide. Read
`references/gis-map-pitfalls.md` before adding or refactoring any map page.

Standing rules:

- **One map instance, owned by one shared component.** A page that embeds a map
  child component must receive that instance through a documented contract
  (`Livewire.on(...)` events or a single exported accessor), never by polling
  for a global. If you inherit a `window.map` + `setInterval`-until-ready
  pattern, count the defensive workarounds already in the file — a
  `setTimeout(invalidateSize)`, a container-`_leaflet_id` re-init branch, and a
  loop that manually `delete`s stale globals are each a bug that already
  shipped. Add no more.
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