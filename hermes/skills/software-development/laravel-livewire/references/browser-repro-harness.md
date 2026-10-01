# Driving a live Laravel/Livewire app from the browser tool

Concrete recipe for reproducing and verifying Livewire UI bugs with `browser_exec`.
Read with `references/gis-map-pitfalls.md` (diagnosis path) — this file is the
harness that feeds it.

## Authenticate a Livewire-controlled form

`fill_input` cannot set a `wire:model` input — Livewire replaces the value on the
next update and the field reads empty. Go through the native setter so Livewire
observes a real input event:

```js
(() => {
  const set = (el, val) => {
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement : HTMLInputElement;
    Object.getOwnPropertyDescriptor(proto.prototype, 'value').set.call(el, val);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change',  { bubbles: true }));
  };
  set(document.getElementById('n_code'), '4411015056');
  set(document.getElementById('password'), '12345678');
})()
```

Submit by finding the button **by text** and clicking it — `form.submit()` skips
Livewire's own handler entirely:

```js
Array.from(document.querySelectorAll('button'))
  .find(b => b.innerText.includes('ورود')).click()
```

Confirm the result by asserting `location.pathname`, not by assuming.

## Sessions expire mid-investigation — re-auth and detect it cheaply

A long debugging stretch loses the session. The symptom is subtle and
misleading: the next `js("document.querySelector('a[href=...]').click()")` dies
with `Cannot read properties of null`, which reads like a broken selector or a
missing menu link rather than an auth redirect.

Check the pathname **first** whenever a selector comes back null before spending
time on the selector:

```python
print("url:", js("location.pathname"))
print("links:", js("document.querySelectorAll('a').length"))
```

`/login` with a full-body render means the session lapsed — re-run the login
block above and continue; it is a two-step recovery, not a new investigation.
Belt-and-braces: re-authenticate at the start of any task whose session may have
gone cold between your own tool calls.

### Where to find a login when nothing is handed to you

Field selectors are guesswork; seeded credentials are in the repo. Look them up
rather than inventing them, and never type a password you were not given:

```bash
grep -rn "Hash::make\|bcrypt(" database/seeders/
grep -E "^TEST_(PASSWORD|N_CODE)" .env.e2e.example
```

Then confirm the shape of the form before filling it — an id-based selector that
misses tells you the field is named something else:

```js
print(js("Array.from(document.querySelectorAll('input')).map(i=>({name:i.name,type:i.type,id:i.id}))"))
```

## Assertions that discriminate

Read state, not screenshots. For a map, the tuple that separates the failure
modes is: layer object present (`typeof window.markersLayer`), layer contents
(`…getLayers().length`), and DOM-rendered output
(`document.querySelectorAll('#map .leaflet-marker-icon').length`). Expect `-1`
for absent, not `0` — `0` reads as "rendered nothing" and hides "never ran".

## Trigger SPA navigation like a user

`goto_url` is a full reload and will mask every SPA-only defect. Click the real
link so `wire:navigate` engages:

```js
document.querySelector('a[href="/maps/point"]').click()
```

Then poll to a timeout instead of a fixed sleep — an SPA hop finishes in well
under a second, so a flat 5 s wait only proves you could afford to be patient:

```python
for t in range(0, 17, 2):
    time.sleep(2)
    print(js("location.pathname"), js("typeof window.markersLayer"))
```

Poll past any in-page readiness ceiling (a 10 s timeout needs ~16 s of polling)
so "waited too long" is never mistaken for "will never happen".

## Instrument without changing the outcome

Install the console hook **after** `wait_for_load`, or the navigation under test
wipes it and you record zero lines for a run that logged plenty. Append a marker
line before the triggering click so the two phases separate in one buffer.

Any instrumentation heavy enough to reorder work — `Object.defineProperty` traps
on the globals themselves — invalidates a race measurement. See the pitfall in
`references/gis-map-pitfalls.md`.

Prefer **source-level** instrumentation over in-page hooks when you need the true
ordering: a `console.log` line at each boundary in the view survives the
navigation and cannot perturb the page. In-page `console` wrappers must be
reinstalled after every load, and an `Object.defineProperty` trap is disqualifying
because it changes the queue it is measuring. Note that harness helpers may be
discoverable via `dir()` yet not callable from injected code — confirm a helper
exists by using it once before building a loop around it.

### Log discipline when you do edit source

Tag every temporary line with a unique prefix (`[DEBUG-maprace]`) so cleanup is
one `git diff` — and revert instrumentation the moment the reading is taken.
An in-page hook installed *before* `wait_for_load` is wiped by the navigation
under test and reports zero lines for a run that logged plenty; install after.
When the hook does not survive, the fallback that works is a temporary `console.log`
in the view itself.

## Report the rate, not one run

A single passing attempt proves nothing about an ordering bug, and a single
failing attempt proves nothing about a slow network. Loop 5+ times over every
entry path and publish the ratio — it is also what tells the user whether the
symptom they noticed is reliably reproducible or intermittent, which changes the
urgency of the fix.

After a fix, re-run the previously failing hops **and** the path that already
worked. A readiness-gate fix that satisfies an identity check can break the
direct-load case it was meant to protect.