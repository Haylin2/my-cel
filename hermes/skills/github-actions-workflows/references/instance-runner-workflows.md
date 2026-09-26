# The state-repo + app-repo runner pattern

A long-lived self-hosted runner bootstrapped by a scheduled workflow, split
across two repos:

- **state repo** (e.g. a per-server "my-<name>" repo) — holds
  `.github/workflows/<name>.yml`, plus `hermes/` (config, memories, skills,
  cron) and `9router/` state. The workflow RESTORES these into the runner home
  at boot and PUSHES them back on shutdown, so this repo has a self-committing
  CI job.
- **app repo** (e.g. the h-dashboard fork) — the actual project, cloned or reset
  to a per-server branch at boot, built, and served.

## Consequences for editing the workflow

- The workflow's own directory (`$GITHUB_WORKSPACE`) is the state repo, NOT the
  app. Any install or artisan command must `cd` into the app path first.
- The workflow's own YAML is tracked in the state repo, so editing it is a
  normal commit+push to that branch — but a boot cycle's sync step may push
  before you do. Fetch and compare, reconcile, never force-push.
- Anything the restored `~/.hermes/config.yaml` references (a CLI on PATH, a
  `cwd` directory, an MCP command) must be installed **before** the step that
  restores that config and starts the gateway. The restored config's absolute
  paths are the contract — match them exactly (an npm global prefix under
  `~/.npm-global/bin` versus a symlink into `/usr/local/bin` are different
  paths), or the tool resolves in an interactive shell but not in the MCP
  process.
- Tools that need a project index (code knowledge graphs, doc indexes) must run
  against the app repo after its dependencies are installed and before the
  process that serves the index starts.
- Persist PATH/credentials for later steps by appending to `~/.bashrc`,
  `~/.profile` and `/etc/environment`; an `export` in one step does not survive
  into the next.

## Adding a CLI the agent's config will reference

Order matters and the config is the spec: read the config the workflow restores
to learn the exact expected path, install the CLI to that path (plus a symlink
for interactive use), then index the project, then boot the consumer. Verify by
rehearsing the install and index commands locally and by reading the restored
config's `command:`/`args:` — not by assuming the default install location.

## Verification recipe for this shape

1. `scripts/verify-workflow.sh .github/workflows/<name>.yml`
2. Rehearse any destructive snippet (index removal, file cleanup) against a
   throwaway copy: `git archive HEAD | tar -x -C <tmp>` then run the snippet
   there. Never rehearse it against the live checkout.
3. After push, confirm on the remote ref, not the local file:
   `git show origin/<branch>:.github/workflows/<name>.yml | grep <marker>`.
