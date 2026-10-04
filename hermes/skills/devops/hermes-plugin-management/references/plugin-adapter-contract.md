# Reading a plugin adapter to learn what it registers

A plugin's real behaviour is in its adapter, not its README. Read it before
documenting or invoking anything the plugin exposes.

## Files

- `<plugin>/.hermes-plugin/plugin.yaml` — `name`, `version`, `description`,
  `author`, `provides_hooks` (event names). This is what `plugins list` and
  `plugins doctor` report.
- `<plugin>/.hermes-plugin/__init__.py` — exposes `register(ctx)`. This is the
  only code Hermes executes from the plugin.
- Git-clone layout puts `.hermes-plugin/` and `skills/` as siblings, so the
  plugin resolves `../skills`; a flattened install puts `skills/` next to the
  module. Adapters commonly try both and raise loudly if neither matches — a
  bootstrap that silently skips is how a broken install looks healthy.

## `ctx` calls worth knowing

- `ctx.register_skill(name, path)` — `path` MUST be a `pathlib.Path`. A bare
  string raises `AttributeError` inside the loader, which disables the entire
  plugin without a traceback in normal output. Each registered skill needs a
  `<name>/SKILL.md` under the skills tree.
- `ctx.register_tool(...)` — contributes to the deferred tool catalog.
- `ctx.register_hook(event, fn)` — event names come from `provides_hooks`.

## Hook return contracts

- `pre_llm_call` returning `{"context": ...}` is the documented injection path:
  the text is appended to the user message (typically only on the first turn,
  guarded by an `is_first_turn` flag).
- Return values from `on_session_start` are ignored, and `ctx.inject_message`
  refuses from that hook. A bootstrap written there appears to work and never
  fires.

## Verifying after reading

1. `hermes plugins doctor <name>` — manifest parse + import + registration
   counts. Non-zero counts here should match what the adapter registers.
2. `skills_list` — plugin skills show under the `plugin` category as
   `plugin:skill`. If a skill the adapter registers is absent, the plugin did
   not load; fix that before assuming the skill is missing upstream.
3. Fallback invocation when the namespaced lookup returns not-found: read
   `<plugin>/skills/<skill>/SKILL.md` directly.

## Example shape

A workflow-skills plugin registers every `<skills>/<name>/SKILL.md` with the
native loader and injects one `pre_llm_call` bootstrap on the first turn that
tells the model the skills are already available and names the directory. The
bootstrap carries the skills directory path, so a failed registration still has
a documented read-the-file fallback.