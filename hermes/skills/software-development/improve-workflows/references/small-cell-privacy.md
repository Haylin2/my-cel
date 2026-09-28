# Small-cell privacy for aggregate-on-a-map features

Direction-audit notes for when a choropleth, heat layer, or colour-scaled polygon
map will carry health case counts. The threshold itself is a domain decision; the
STRUCTURE of the problem is not, and getting the structure wrong is what leaks.

## The shape of the risk

A raw count attributed to a named small facility is a count of identified people.
"Health house" catchments are village-scale, so a single-digit count at that level
is directly identifying. Three amplifiers compound it:

1. **Repeated layers** — the same facility is exposed once per metric, so a
   cross-layer subtraction re-derives values any single layer's suppression hid.
2. **Colour is a channel** — a choropleth ramp with buckets `0 / 1-9 / 10+`
   publishes the threshold K in the UI, which makes the suppression reversible
   by combining the visible buckets with any known total. A distinct fill for
   "zero" plus a ramp step for the suppressed band is three buckets where one was
   intended.
3. **Cached suppression is cross-user leakage** — if suppression is applied
   *after* the cache read, a value suppressed for one scope is served to another.
   Apply it INSIDE the cached closure, keyed on scope.

## Rules

- Suppress a non-zero band (`1 <= n < K`), never render it as `0`. Zero is
  safe and must stay visually distinct — collapsing it destroys information and
  creates a false "no disease here" signal.
- Derived values follow their numerator: rates, percentages, per-capita figures
  computed from a suppressed count are suppressed too.
- Secondary suppression is mandatory when any total, grand total, or
  unrestricted "all cases" layer is published — otherwise the total minus the
  visible components back-solves every suppressed cell.
- Deliver suppression as a **flag + null count** in the payload
  (`{count: null, suppressed: true}`), never as a formatted string. A
  pre-formatted string is trivially re-derived by any client-side aggregate.
- Row-level org scoping answers "may this user see unit X", never "is count N at
  unit X safe to publish". The two requirements are orthogonal; scoping is not a
  small-cell control.

## Interaction with existing rendering

The choropleth fill function and the popup/legend renderer must both branch on
the suppressed flag. When the feature lands on an existing map, check whether
the renderer escapes all interpolations — a popup builder that escapes names but
emits numeric fields raw will leak the count through a field nobody reviewed.

## Must be decided by the domain owner

These are not derivable from code, and an audit should list them as open
questions rather than pick a value:

- The threshold K itself (and whether it is absolute or denominator-based).
- Whether a rate per 1,000/100,000 is publishable at the finest level at all.
- Which metrics are legally notifiable — a reporting duty can override
  suppression, so suppression is not uniformly applicable.
- Whether zero may be shown.
- Whether a wide-scope user sees all layers at once, and whether all layers may
  be simultaneously visible to one user (this is a permissions decision, not a
  rendering one).
- Whether the map is internal-only or ever published externally — different
  threshold regimes apply.

Published agency guidance is worth citing instead of asserting a number: the
thresholds in circulation (1-9 in several US state health-department small-number
protocols, NCHS rules, ONS domain-specific thresholds) carry the caveat that there
is no scientific basis for any particular value. Cite the guideline, name it as a
working value, and leave the choice to the owner.
