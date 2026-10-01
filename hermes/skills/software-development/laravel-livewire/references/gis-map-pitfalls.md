# Map / GIS pitfalls (Leaflet + Livewire)

Depth for the standing rules in SKILL.md. Every item names the failure mode, not
just the rule.

## Global instance + poll-for-ready

The common inherited shape:

```js
function waitForMap(cb, tries = 0) {
    if (window.map) return cb();
    if (tries > 100) return;
    setTimeout(() => waitForMap(cb, tries + 1), 50);
}
```

Why it breaks:

- **SPA navigation** — a navigable app reuses the shell. The next page's
  `@script` runs while the previous map instance is still on `window`, so the
  poll succeeds against a map whose container has already been replaced.
- **Two map pages in one session** — both write `window.map`; the second
  silently orphans the first, and the first page's listeners now drive the
  wrong instance.
- **Slow tile server** — the poll is gated on map construction, which is fast,
  so this specific symptom is rare, but any sibling readiness check
  (`typeof map.getSize === 'function'`) that never resolves fails silently.
  Always log on the give-up branch, or the failure is invisible.

Symptom-free fix: a map child component owns the instance, exposes it once, and
parents react to an explicit ready event.

### Minimal safe gate

Verified fix for the third case below (global exists, container stale) — keep the
poll, make its condition identity-based:

```js
function waitForMap(callback) {
    var tries = 0;
    function check() {
        var el = document.getElementById('map');
        if (window.map && typeof window.map.getSize === 'function' &&
            window.map.getContainer() === el && document.body.contains(el)) {
            callback();
        } else if (++tries > 50) {
            console.error('Map not ready within 10s');   // never omit this
        } else {
            setTimeout(check, 200);
        }
    }
    check();
}
```

`document.body.contains(el)` matters as much as the equality test: it rejects a
container that matches by id but is orphaned. Keep the give-up log — a readiness
gate that fails silently is indistinguishable from a bug that never fires.

## Diagnosing "works direct, dead from the menu"

This is the diagnostic path for the SPA case above. The failure is a **mount
order race**, and reading the PHP will not reveal it.

1. **Reproduce both entry paths separately**, then measure the rate. Navigate
   from every sibling page that also embeds the map child, not just from a
   neutral page — a non-map origin may pass while every map→map hop fails. A
   single run proves nothing; report the fail ratio over 5+ attempts, because
   instrumenting can turn a deterministic failure green by shifting timings.
2. **Tag the outgoing instance before navigating** so stale versus fresh is
   decidable afterwards: `window.__oldMap = window.map;
   window.__oldContainer = window.map.getContainer();`
3. **Hook `console` AFTER the initial page load**, never before — a hook
   installed pre-load is wiped by the navigation you are trying to observe.
4. **Log at four boundaries**, which names the loser deterministically:
   gate registered → gate resolved → consumer callback entered → producer
   constructed the instance. Read the emitted order; do not infer it from
   template nesting.
5. **Confirm with identity, not presence**:
   `window.map.getContainer() === document.getElementById('map')`,
   `document.body.contains(window.__oldContainer)`,
   `window.__oldMap === window.map`.
6. **Fix, then re-run every hop plus a direct load** — the direct-load case is
   the regression guard, since the naive fix can break the path that used to
   work.

Pitfall: trapping the globals themselves with
`Object.defineProperty(window, 'markersLayer', {get,set})` to record assignment
order looks like the cleanest trace and **perturbs the race it is measuring** —
it turned a 100%-failing reproduction green. Prefer `console.log` at the four
boundaries, which is cheap enough not to reorder the queue. If a trap is
unavoidable, treat a green result as inconclusive, not as a fix.

The bug generalises across every page reusing the helper — fix all of them in
one pass or the next hop reintroduces it. A correct surface-level patch is still
worth landing first, but report the sibling count and the deeper architectural
fix (per-page Alpine store or scoped state object) rather than presenting the
guard as the resolution.

## Manual global teardown

The tell that teardown is being hand-rolled:

```js
['markersLayer', 'linesLayer', 'geojsonLayers', 'countyLayers'].forEach(function (name) {
    if (window[name]) { try { window[name].remove?.(); } catch (e) {} delete window[name]; }
});
```

Every name added to that list is a layer type that leaked on the previous page.
The list is a symptom inventory. Prefer a scoped container object per page
(`window.__mapState = { layers: new Map(), dispose() {...} }`) so teardown is one
call and misses are impossible.

## Layout race

Leaflet captures container dimensions at construction. If the page is still
settling (SPA nav, web-font swap, a panel animating open), it locks in a small
size and renders half-width. The standard fix is `invalidateSize()` after the
frame settles — but if the codebase has a bare `setTimeout(..., 100)`, that is
the shape to replace, not copy: hook the actual settle signal (ResizeObserver on
the container, or the end of the opening transition) and register the listener
so it can be removed with the component.

## Double library load

Check the shared layout first:

```bash
grep -rn "<library>" resources/views/components/layouts/ resources/views/livewire/
```

Two copies of Leaflet means `L.map(...)` from the CDN copy and `L.map(...)`
from the vendored copy are different constructors, layer registries do not
merge, and plugins attached to one copy are invisible to the other. Also a CSP
liability: `connect-src 'self'` with an unlisted CDN works only while the policy
is report-only.

## Uncancelled viewport refetch

```js
map.on('moveend', () => { clearTimeout(t); t = setTimeout(load, 300); });
```

Debounce throttles, it does not order. Request A starts, then B starts, B
returns first, A returns last and wins. For data whose content changes under
the viewport (hardware counts, live status), that is a visibly wrong map with no
error anywhere. Either `AbortController` per request, or a monotonically
increasing id compared before applying the response.

## Spatial work

- Plain `whereBetween('lat', …)` / `whereBetween('lng', …)` on a composite
  B-tree index is fine and often cheaper than a spatial predicate for a bbox
  viewport. Reach for `ST_*` when you need containment (which polygon contains
  this point), distance, or joins across geometry types — not reflexively because
  a geometry column exists.
- A geometry column plus a GiST index that no query references is inert. Before
  recommending spatial queries, confirm the new feature actually needs them.
- GeoJSON emitted at full precision is a payload problem, not a correctness one.
  Simplify server-side per zoom band when the polygon set is large, and measure
  the serialized size before claiming it is fine.
- Raw `ST_AsGeoJSON` in a model accessor runs once per model. Any loop that
  reads it without eager loading is an N+1; check the caller, not the accessor.
