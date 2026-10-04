---
name: hermes-plugin-management
description: "Install, enable, and verify Hermes plugins."
version: 1.0.0
author: curator
license: MIT
metadata:
  hermes:
    tags: [hermes, plugins, install, enable, verify, update, skills]
---

# Hermes Plugin Management

Native Hermes plugins and portable Agent Plugins v1 packages are installed and
verified from the CLI. This skill carries the command surface and the
verification order. The bundled `hermes-agent` skill is the routing hub for
Hermes features but has no plugins entry in its routing table — do not guess
flags at it.

## When to Use

- The user asks whether a plugin is installed, asks to install/enable/remove
  one, or asks why an enabled plugin has no effect.
- Before reporting any plugin as installed, updated, or working — the
  verification order below is what makes that claim true.
- When a plugin exposes skills or tools and you need to know how to invoke them.

Not for plugin *authoring* or hook development — read the adapter itself for
that.

## The command is plural

`hermes plugins <subcommand>`. `hermes plugin list` fails with "not a `hermes`
command" plus a suggestion — that is a wasted call. The bare `hermes plugins`
opens the interactive toggle and dies with "Interactive mode requires a
terminal." in any non-pty call, so always pass a subcommand.

## Verify before claiming installed

A name under `plugins.enabled` in `config.yaml` proves nothing: a removed or
never-cloned plugin leaves the entry behind and then loads as a silent no-op.

```bash
hermes plugins list --plain                  # parseable, unlike the rich table
hermes plugins list --plain --no-bundled     # the user's own plugins only
test -d "${HERMES_HOME:-$HOME/.hermes}/plugins/<name>"
```

Report installed only when `list --plain` shows the row AND the directory
exists. Read the `Source` column: `user` = git clone, `bundled` = ships with
Hermes, `catalog:official@<sha>` = pinned catalog entry.

## Install from a Git URL

```bash
hermes plugins install https://github.com/owner/repo --no-enable
hermes plugins install owner/repo --enable          # shorthand form
```

`hermes plugins search <name>` returning nothing does NOT mean the plugin
cannot be installed — it only means it is absent from the curated catalog.
Catalog membership and installability are separate gates.

## Expect the community-source block, then override deliberately

Any non-catalog source prints "custom (unreviewed) source" and runs the
security scan. A CAUTION verdict ends in `Decision: BLOCKED` and installs
nothing. Read the findings, then re-run with `--force`:

```bash
hermes plugins install <url> --no-enable --force
```

The scan pattern-matches repository text including docs. Sort the findings
before reporting them: hits inside `README`/`INSTALL.md`/design docs (`rm -rf
~/...`, `npm install` from a git URL, dummy tokens in example code) are not
executable plugin behaviour. Say which findings are in code that actually runs
versus in prose, and never `--force` a repo whose executing part you have not
read.

`--no-enable` / `--enable` answer the enable prompt non-interactively;
`--yes-deps` answers the Python dependency consent. A "Skipped Node deps" line
means the plugin declares `package.json` Node deps that were not fetched — retry
without `--no-deps`, or state plainly that the deps are missing.

## Enable, then confirm registration

```bash
hermes plugins enable <name>
hermes plugins doctor <name>
```

`enable` prints the manifest name and the counts of registered tools/hooks.
`doctor` is the real runtime-contract check: it resolves the directory, parses
the manifest, imports the module, and reports `N tool(s), M hook(s)`. An adapter
that throws at import time silently disables the whole plugin, so `doctor` is
the only place that surfaces it.

## Effect timing differs by registration kind

Hooks reload in the running gateway at enable time ("Gateway reloaded
plugins"). Anything injected into the model context — a `pre_llm_call`
bootstrap, a skill registration — takes effect on the NEXT session, not this
one. Say "takes effect next session" whenever the mechanism injects context.

## A plugin directory is a git clone

Installed plugins keep provenance: `hermes plugins update <name>` pulls newer
commits and `hermes plugins check-updates` reports drift. `hermes skills check`
covers hub-installed skills only — it will never mention a plugin.

## Learn what a plugin registers from its adapter

Read `<plugin>/.hermes-plugin/plugin.yaml` and `.hermes-plugin/__init__.py` to
see the actual registration calls, the skills tree layout, and the namespacing
rules before guessing how to invoke anything — see
`references/plugin-adapter-contract.md`.

Plugin-provided skills appear in `skills_list` under the `plugin` category
with a `plugin:skill` qualified name. Always invoke them qualified; the bare
name can resolve to an unrelated skill of the same name.

## Config is not edited by hand

`plugins.enabled` is maintained by `hermes plugins enable/disable`. Use those
subcommands — a hand-edited `config.yaml` can corrupt the live gateway.