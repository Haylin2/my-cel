# Replacing a global singleton with an explicit lifecycle

The architectural half of the map/GIS problem. `references/gis-map-pitfalls.md`
stops at the identity guard and says to report the deeper fix; this file is that
fix. Read it before designing anything that moves map ownership off a global.

## Verify the lifecycle hook exists before designing around it

A whole redesign can rest on one unverified claim: that Alpine runs `destroy()`
for a component SPA navigation removes. Prove it in the real page. Do not assume
it, and do not assume it fails.

```blade
<div wire:ignore>
    <div id="map" class="h-[80lvh] rounded"
         x-data="{ init(){ console.log('[SPIKE] INIT fired'); },
                   destroy(){ console.log('[SPIKE] DESTROY fired'); } }"></div>
</div>
```

Load an origin page, install the console hook **after** load, click through to the
target with `wire:navigate`, then read the emitted order.

That order is the entire basis of the design. Observed: `DESTROY` then `INIT` —
the old instance is told to tear down *before* the new one is constructed, so
`destroy()` can invalidate shared state and `init()` rebuild it with no window in
which two instances coexist. Had `destroy()` not fired, the store design below
would have been invalid and the correct answer would have been something else
entirely.

This is a few minutes of work that de-risks a multi-file refactor. Revert the
spike with `git checkout <file>` the moment you have the reading — a stray
`x-data` logging on every map load is noise in every later trace.

Confirm framework semantics from the shipped source, not from memory or docs:

```bash
grep -n "evaluateScripts\|onlyIfScriptHasntBeenRunAlreadyForThisComponent\|destroyTree\|onElRemoved" \
  vendor/livewire/livewire/dist/livewire.esm.js
```

A `WeakMap` keyed on the component instance for executed scripts is what makes
"once per instance" true; `onElRemoved(... destroyTree)` is what drives Alpine
teardown. Both answers are one grep away and settle arguments that docs leave
ambiguous.

## Enumerate consumers before designing the replacement

Run both greps — they answer different questions and you need each:

```bash
grep -rn "window\.map\|window\.markersLayer\|<livewire:maps.map" resources/views/
grep -rn "L\.map(" resources/views/livewire/
```

The first finds pages that **consume** the shared instance — the in-scope set.
The second finds pages that **own** one, and those usually never had the bug
because they were never coupled to the global.

Classify every hit:

- consumes the shared global → in scope
- owns its own `L.map` on its own container → already independent, leave alone
- exposes a global that a test asserts on → leave alone, and say why

That third class is the one that bites. A page whose `window._drawnItems` /
`window._mapGeojson` are read by a Playwright spec is a public contract whether
or not the name is tasteful; refactoring it breaks tests for no gain the bug
requires.

Name the exclusions in the plan. "6 files; 2 look related but own their own map
and are pinned by E2E assertions, so untouched" is a reviewable claim. Quietly
rewriting them is not.

## The replacement shape

One owner, explicit lifecycle, no ambient readiness:

```js
Alpine.store('map', {
    instance: null,
    container: null,

    use(el) {
        // reuse only when bound to this exact, connected container
        if (this.instance && this.container === el && document.body.contains(el)) {
            return this.instance;
        }
        this.release(el);
        this.instance = L.map(el).setView(/* … */);
        this.container = el;
        return this.instance;
    },

    release(el) {
        if (!this.instance) return;
        // only destroy the instance that owns THIS container
        if (!el || this.container === el) this.instance.remove();
        this.instance = null;
        this.container = null;
    },
})
```

Producer component: `init()` → `use(el)`, `destroy()` → `release(el)`.
Consumers call `use(el)` and attach to the returned instance instead of polling a
global for readiness.

**Why this is the resolution and not a mitigation.** `release()` runs on
teardown, so an instance whose container has been detached is *destroyed* rather
than merely not-selected. The race stops happening; it is not merely detected.
The identity check inside `use()` then covers only the direct-load and back-nav
cases, as belt-and-braces rather than as the primary defence.

Keep `window.map` assigned as a labelled temporary alias while other code still
reads it, then delete it once the last consumer converts. Two names for one thing
is acceptable only while it is explicitly transitional.

### Registering the store — hook the event, never call at module top level

The shape above is useless without knowing *when* `Alpine.store()` is legal. At
the top level of a bundled module it runs before Alpine exists and throws. Bind
to `alpine:init` instead, which is order-independent:

```js
import { registerMapStore } from './map-store';

document.addEventListener('alpine:init', () => {
  registerMapStore(window.Alpine);
});
```

Spike this too — a store read back as `Alpine.store('name')` from `page.evaluate`
proves registration landed *and* that consumers can reach it.

**Know how Alpine gets onto the page before reasoning about ordering.** Grep the
layout:

```bash
grep -rn "@livewireScripts\|@livewireStyles" resources/views/
```

No hits means Livewire auto-injects Alpine at the end of `<body>`, so it starts
*after* every head script and `alpine:init` is guaranteed to fire before the first
`x-data` initialises. If the project later adds an explicit `@livewireScripts` to
`<head>`, listening to the event still holds — which is the reason to prefer it
over a positional assumption.

Consumers reach the store as `window.Alpine.store('map')` from plain `@script`,
or `$store.map` from inside `x-data`.

## What must not change

This is a refactor of ownership, not of appearance. Establish the visual contract
before touching anything:

```bash
grep -rn "leaflet-\|clientWidth\|#map\|#unitMap" tests/e2e/
```

If the specs key on rendered DOM — `.leaflet-container`, `.leaflet-marker-icon`,
`svg path`, element width — then the contract survives the refactor untouched, and
that is what makes the change reviewable. If any spec reads the global's identity
directly, that read is a contract to preserve or change deliberately.

### Two test categories that break, and which one is legitimate

Not every failing assertion is a regression. Sort them before reacting:

- **Asserts rendered output** (marker counts, polygons, element width) → must
  still pass untouched. If it fails, the refactor changed behaviour. Stop.
- **Asserts an implementation string** (`assertStringContainsString('initMap')`,
  `assertSeeHtml('id="map"')`) → will fail when the mechanism is legitimately
  replaced. Update it to assert the *new* contract, and say in the plan which
  assertions change and why. Rewriting an assertion because its subject was
  removed is legitimate; weakening one that still describes required behaviour is
  not. Flag the distinction in the plan rather than discovering it mid-execution.

Enumerating the baseline count per file makes the blast radius reviewable before
you touch anything: `grep -c "resources/views/livewire/maps/point.blade.php"
phpstan-baseline.neon`. Treat those counts as *moving*: the baseline is
line-keyed, so editing a baselined file un-matches its entries and the counts
change. Regenerate and require `git diff phpstan-baseline.neon` to show **zero
additions** — an addition means a real new error got suppressed.

## The suite gap this class of bug lives in

An SPA-navigation defect is invisible to a suite whose specs all call
`page.goto()`. `goto` is a full reload — the one entry path that works. So the
coverage for the affected pages can be comprehensive and entirely green while the
bug reproduces 100% of the time through the UI.

After fixing, add a spec that navigates as a user does:

```ts
await page.goto('/origin');
await page.locator('a[href="/maps/point"]').click();
await expect(page.locator('.leaflet-marker-icon').first()).toBeVisible({ timeout: 15000 });
expect(await page.locator('.leaflet-marker-icon').count()).toBeGreaterThan(0);
```

Check for this before believing any green run on a navigation bug.
`grep -rn "page.goto" tests/e2e/maps/` answering "everywhere" is the tell.

## Instrumentation hygiene

Adding a log line to a poll that counts attempts is an edit to the logic, not
just to the output. A counter that read `tries > 50` must still read `tries > 50`
afterwards — bumping it inside the condition changes when the give-up branch
fires and invalidates the very trace you added it for. When instrumenting, change
only the logging.