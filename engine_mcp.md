# engine_mcp: an API and MCP server for the engine (specification; implementation in progress)

**Progress log** (update after each phase):

- [x] Phase 0 - scaffolding (`packages/engine_api`, CI workflow, docs rows)
- [x] Phase 1 - registry core in `engine_core` (`engine_core_ops.dart`: Operation, Param/ParamValidator, results/errors, context/policy, registry+dispatcher, JSON Schema, path sandbox, `engine.*` operations); tests in `packages/engine_core/test/ops/`
- [x] Phase 2 - write safety (`safety.dart` SafetyPipeline: validation, locks, diff, preview + HMAC confirmation token, atomic write with rollback, undo journal `.studio/undo/`; `undo.list/undo/redo`). Token format `v1:<op>:<argsHash>:<beforeHash>:<expiry>:<hmac>` (base64url). Redo walks forward from the oldest undone entry.
- [~] Phase 3 - read operations in `engine_core`: `project.open/close/info/tree/search/validate/git_status`, `level.list/read/validate/diff/lock_status`, `schema.components/component/template/validate_component`, `idle.validate/simulate/format_number`, `release.plan` (+ declared `release.build`, requiresFlutter). Moved into core with shims left in `engine_studio`/`engine_cli`: `StudioProject`, project tree/search, git status, find/replace, `release_plan.dart`. CLI binding generated from the registry is done (`engine_cli/lib/src/ops_cli.dart`: `game_agent <group> <verb>`, `--json/--stdin/--args`, legacy verbs kept). Still to do in this phase: `level.lint`, `asset.*`, `project.symbols/problems`, `graph.*`.
- [~] Phase 4 - write operations: `level.create/add_entity/remove_entity/move_entity/set_field/set_layer/add_component/remove_component/paint_tile/fill_region` done (`level_write_ops.dart`, reuse the studio `EditCommand`s, validate the edited level, undoable). `prefab.list/read/save/place` and `level.import_tmx/export_tmx` done. Still to do: legacy `studio` commands as adapters with golden comparison.
- [~] Phase 6 - `engine_api` server: JSON-RPC core, MCP session (initialize, ping, tools/list with pagination, tools/call, resources + templates, prompts/list stub), stdio transport, `--project/--read-only/--allow/--deny/--underscore-tool-names`, and HTTP (`--http`: `POST /mcp`, REST `/v1/<group>/<verb>`, `GET /v1/engine/operations`, `/v1/openapi.json`, `/v1/health`, `POST /rpc` with batches and `rpc.discover`; bearer token in `.studio/api-token` 0600, constant-time compare, Host check against DNS rebinding, body limit, `X-Request-Id`, `--allow-remote` gate) done (`packages/engine_api/lib/src`). Request log (`.studio/api-requests.jsonl`, rotated, no args/results), result-size limit (`too_large`) and rate/concurrency limits (429 + `Retry-After`) are done. Prompts (`build_level`, `fix_validation_problems`, `balance_idle_game`, in code with a stale-operation test) are done. Still to do: `engine_api.yaml`, `Idempotency-Key`, CORS, SSE streaming, failed-auth delay, project:// resources.
- [x] Phase 7 (partial) - `engine_api/test/parity_test.dart`: every served operation is an MCP tool and a REST path, Flutter-only ones (`release.build`, `project.create`, `project.upgrade`) are declared but CLI-only; CLI parity is `engine_cli/test/ops_cli_test.dart`. `engine_api/test/e2e_test.dart` walks the whole agent workflow (open, create, edit, validate, world.build/step/query, destructive preview + confirmation, undo). Still to do: generated docs.


Status: **planning only.** Nothing here is built. Three rounds of decisions are recorded below; nothing is left open.

## Goal

A new package, `packages/engine_api`, that lets a person or an AI agent drive the engine without Dart code:

- **MCP server** (Model Context Protocol) so Claude and other agents can call the engine as tools and read it as resources.
- **HTTP/JSON API** over the same operations, for non-MCP clients and scripts.
- It must cover **every studio command, every engine function that makes sense to expose, and per-project functions**
  (a project = a game folder with `pubspec.yaml`, `assets/`, levels, graphs, prefabs).
- Each operation carries enough detail (description, typed parameters, examples, error codes) for a user or agent to use
  it without reading the source.

## The 1:1 rule (the architectural constraint)

> Anything in `engine_api` is a call into `engine_core` (or another engine package), and **the CLI has the same operation
> 1:1**. No operation exists only in the API; none exists only in the CLI.

Consequences for the design:

1. **One operation registry is the source of truth.** Each operation is declared once: name, summary, long description,
   input schema, output schema, errors, examples, whether it reads or writes, and a handler that calls `engine_core`.
2. **The CLI and the API are both generated from / bound to that registry.** A `game_agent <group> <op>` command exists
   for every operation, and the MCP tool and HTTP route for it exist too. Where does the registry live so the CLI can use
   it without depending on `engine_api`? Proposal: the registry and handlers live in **`engine_core`** (pure Dart, the
   `engine_core_ops.dart` entry, like `engine_core_idle.dart`); `engine_cli` binds them to commands and `engine_api` binds
   them to MCP/HTTP. (Keeps the package DAG one-way: `engine_core` -> everything else.)
3. **A parity test** enumerates the registry and fails if any operation lacks a CLI command, an MCP tool or an HTTP route,
   or if the CLI has an operation the registry does not know. Docs for the three surfaces are generated from the registry.

## Scope to cover (inventory to confirm)

Existing CLI today: `create`, `upgrade`, `lint`, `pack-assets`, `build-release`, `idle simulate`, `idle validate`, and
`studio` with `validate`, `import-tmx`, `export-tmx`, `export-levels`, `project-manifest`, `diff`, `merge`, `lock`,
`unlock`, `save-prefab`, `place-prefab`, `add-entity`, `remove-entity`, `set-field`, `move-entity`, `set-layer`,
`paint-tile`, `fill-region`.

To add (as operations, then CLI + API): level/graph CRUD and validation, component schema listing (`allComponentSchemas`),
world snapshot/patch (`WorldView`, `applyPatch`), content DSL (dialogue, AI graphs), idle (`simulate`, `validate`, state
inspection), strategy (turn state, orders), asset index and atlas queries, localisation catalogs, save codes, release
planning, project analysis (problems, symbols, search, git status), plugins list. Each needs an owner decision on whether it
is in v1 (see questions).

## Proposed steps (to be refined after the answers)

1. **Decide the surface and transport** (questions below), and the safety model for write operations.
2. **Inventory and classify** every CLI command, studio action and public engine entry point: read / write / destructive,
   project-scoped or pure, sync or long-running.
3. **Design the operation registry** in `engine_core` (`Operation`, `OperationParam`, `OperationResult`, error taxonomy),
   with JSON-Schema generation from the existing `FieldSchema`/component schemas so inputs are self-describing.
4. **Migrate the existing CLI commands onto the registry** (behaviour-preserving; the existing CLI tests are the
   regression suite), so the 1:1 rule starts true.
5. **Add the missing operations** group by group (levels, graphs, schemas, world, idle, strategy, assets, project, release),
   each with tests, CLI binding and docs.
6. **Create `packages/engine_api`**: MCP server (stdio first), HTTP server, project/session handling, auth, limits.
7. **Parity test + generated docs** (tool catalogue, HTTP reference, CLI reference from one source).
8. **End-to-end verification**: an MCP client script that lists tools and runs a real project workflow (create project,
   add entity, validate, simulate idle), run in CI.
9. **Release plumbing**: workflow, CHANGELOG, mkdocs nav, `docs/engine-releasing.md` entry, `release_consistency_test`.

## Decisions (answered by the owner)

| Topic | Decision |
|---|---|
| Registry location | **`engine_core`** (pure Dart `engine_core_ops.dart`); `engine_cli` and `engine_api` both bind to it. |
| Runtime | **Pure Dart**, compiled to a native executable; calls `engine_core` directly. |
| Transports | **All four:** MCP over stdio, MCP over streamable HTTP, REST/JSON, and JSON-RPC. One registry feeds all. |
| Projects | **One project root per server run** (`--project <dir>`), plus an explicit `project.open` / `project.switch` operation; every project operation is scoped to the open root. |
| Write safety | **Dry-run by default for destructive operations** (apply with `apply: true`), an **undo log** for writes, and a **`--read-only`** mode that disables all writes. |
| Auth | **Bearer token**, bound to **localhost by default**; remote binding needs an explicit flag. |
| Flutter-dependent operations | **Excluded from v1** (preview, run game, live world, profiling). Everything pure-Dart is covered. |
| v1 scope | **Everything in the inventory**, built in phases behind one release; released when the parity test is green. |
| "All engine functions" | **Curated operations over data**, not raw Dart calls. Closures/streams/live objects are excluded. Adding a public engine feature should add an operation (checklist in CONTRIBUTING). |
| CLI mirror | Every operation is **`game_agent <group> <op>`** with `--json` output and JSON input via flags or stdin. Existing commands keep working (as the friendly form of the same operations). |
| MCP self-description | **All four:** resources (schemas, project files, docs pages), prompts (guided workflows), rich tool descriptions (examples + error codes), and generated reference docs (MCP, REST/OpenAPI, CLI) from the registry. |
| Naming / versioning | **`group.verb`** dotted names (`level.add_entity`, `idle.simulate`) shared by MCP tools, REST paths and CLI groups; the registry has a semver, removed operations are deprecated for one release. |

### Second round (answered)

| Topic | Decision |
|---|---|
| Undo log | **Inside the project at `.studio/undo/`, keeping the last 100 writes**; each entry stores the before-state of the touched file. |
| Locks | **Respect the advisory `FileLock`:** a write to a locked level fails with a clear "locked by X" error. Explicit `level.lock` / `level.unlock` / forced takeover operations exist. |
| Dry-run preview | **The engine's `LevelDiff`** (added/removed/changed entities and fields) **plus a summary and a confirmation token** that must be echoed in the apply call, so a stale preview cannot be applied. |
| Observability and trust (all four) | `engine.health` + `engine.capabilities` (versions, enabled groups, read-only flag); a **JSON-lines request log with per-operation timing**; a **per-operation allow/deny list** in config; **rate and size limits** (request, result, calls per minute). |

### Third round (settled with the recommended defaults, as the owner asked not to be asked again)

| Topic | Decision |
|---|---|
| MCP prompts | Files under `packages/engine_api/prompts/*.md` (front matter: name, description, arguments); every prompt is executed by a test against a scratch project so it cannot rot. |
| REST routes | `POST /v1/<group>/<verb>` with the params as the JSON body; `GET /v1/engine/operations` lists the catalogue; OpenAPI served at `/v1/openapi.json`. |
| JSON-RPC | One endpoint (`POST /rpc`), method = the dotted operation name, params = the same object; batch requests allowed. |
| Token | Generated at start, printed once to stderr and written to `.studio/api-token` (mode 600) unless `--token` is given; `--rotate-token` makes a new one; stdio MCP needs no token (the parent process owns the pipe). |
| Config | `engine_api.yaml` in the project root (or `--config`); command-line flags win over the file; the file may set allow/deny lists, limits, bind address and read-only. |

## Inventory of what exists today (step 1 of the plan, to be re-verified against the code when the registry is built)

Every row becomes one operation (kind: R read, W write, D destructive; scope: P pure, J project). The `game_agent` command on
the left is what the friendly CLI form keeps being.

| Today's CLI | Operation | Kind | Scope | Notes |
|---|---|---|---|---|
| `create <name> --template --org --output-dir` | `project.create` | W | P | needs the Flutter SDK; shells out to `flutter create` (long-running, **excluded from v1 API**, stays CLI-only until a host exists; the registry marks it `requiresFlutter`) |
| `upgrade --ref` | `project.upgrade` | W | J | rewrites engine `ref:` in pubspec, runs pub; `requiresFlutter` |
| `lint <level> --render --playable` | `level.lint` | R | J | `--render` returns a PNG (base64 in API) |
| `pack-assets -i -o -m --padding --max-width --scales` | `asset.pack` | W | J | pure Dart (image package) |
| `build-release ...` | `release.build` | W | J | `requiresFlutter`; its plan part (`release_plan.dart`) is pure and becomes `release.plan` (R) |
| `idle simulate <game.json> --days --prestige-at` | `idle.simulate` | R | P | already a registry-shaped function (`simulateIdle`) |
| `idle validate <game.json>` | `idle.validate` | R | P | |
| `studio validate [project]` | `project.validate` | R | J | all levels against schemas; `--strict` |
| `studio import-tmx` / `export-tmx` | `level.import_tmx` / `level.export_tmx` | W | J | |
| `studio export-levels` | `level.export_canonical` | W | J | rewrites files canonically |
| `studio project-manifest` | `project.manifest` | W | J | |
| `studio diff a b` | `level.diff` | R | P | `--json`, `--exit-code` |
| `studio merge base ours theirs` | `level.merge` | D | J | writes over ours; conflict = error |
| `studio lock` / `unlock` | `level.lock` / `level.unlock` | W | J | advisory lock file |
| `studio save-prefab` / `place-prefab` | `prefab.save` / `prefab.place` | W | J | |
| `studio add-entity` | `level.add_entity` | W | J | `--name --component* --index` |
| `studio remove-entity` | `level.remove_entity` | D | J | |
| `studio move-entity` | `level.move_entity` | W | J | |
| `studio set-field` | `level.set_field` | W | J | `--entity --component --field --value` (JSON) |
| `studio set-layer` | `level.set_layer` | W | J | |
| `studio paint-tile` / `fill-region` | `level.paint_tile` / `level.fill_region` | W | J | |

Operations with no CLI form yet (to add, each with a CLI command): `project.open/info/tree/search/problems/symbols/git_status`,
`level.list/read/validate_text`, `graph.*`, `schema.components/fields/docs`, `world.snapshot/patch/validate`,
`idle.state/buy_plan/best_purchase`, `strategy.*`, `asset.index/atlas_regions`, `i18n.*`, `save.encode/decode/migrate`,
`engine.health/capabilities/operations`, `undo.list/undo/redo`.

**Consequence of the 1:1 rule for Flutter-dependent commands.** `create`, `upgrade` and `build-release` need the Flutter SDK and
long-running processes. They stay in the registry as operations flagged `requiresFlutter`, **implemented in `engine_cli`** (which
may run processes) and **not served by `engine_api` in v1**; the parity test knows this flag, so the rule reads: every operation has
a CLI command; every non-`requiresFlutter` operation also has MCP, REST and JSON-RPC bindings.

## Operation groups (draft, to be turned into the registry)

`project.*` (open, info, manifest, tree, search, problems, symbols, git status, pub get plan) - `level.*` (list, read, validate,
add/remove/move entity, set field/layer, paint/fill tiles, diff, merge, export, import/export TMX, lock/unlock) -
`prefab.*` - `graph.*` (list, read, validate, compile, add/remove node/edge) - `schema.*` (components, fields, docs) -
`world.*` (snapshot, patch, validate; headless, data only) - `idle.*` (validate, simulate, state, buy plan) -
`strategy.*` (rules data, turn state) - `asset.*` (index, atlas regions, pack) - `i18n.*` (catalogs, keys) -
`save.*` (encode/decode codes, migrate) - `release.*` (plan, build-release dry-run) - `engine.*` (version, capabilities,
operation catalogue) - `undo.*` (list, undo, redo).

## Steps (refined)

1. **Inventory + classification** of every CLI command, studio action and curated engine entry point: read / write /
   destructive, project-scoped or pure, sync or long-running (long-running are excluded in v1 with Flutter ops).
2. **Registry design in `engine_core`:** `Operation` (name, summary, description, params schema, result schema, errors,
   examples, `kind`: read|write|destructive, `scope`: pure|project), `OperationContext` (project root, read-only flag,
   undo log, clock), `OperationResult`/`OperationError` taxonomy, JSON-Schema generation from `FieldSchema`.
3. **Write-safety layer** (shared by every surface): dry-run result as a `LevelDiff` preview with a confirmation token,
   `apply` flag, undo log in `.studio/undo/` (last 100), read-only enforcement, advisory-lock handling (fail with "locked by X"),
   per-operation allow/deny list, size/rate limits, JSON-lines request log. Tested once, inherited by all operations.
4. **Move the existing CLI commands onto the registry** (behaviour-preserving; the existing ~130 CLI tests are the
   regression suite), adding `--json` and stdin input. 1:1 is true from here on.
5. **Add missing operations** group by group (each: tests, CLI binding, doc entry, example).
6. **`packages/engine_api`:** MCP server (stdio, streamable HTTP), REST + OpenAPI, JSON-RPC, bearer-token auth, localhost
   default, request limits, structured errors, resources, prompts, health/capabilities.
7. **Parity + docs:** a test enumerates the registry and fails if any operation lacks a CLI command, MCP tool, REST route or
   JSON-RPC method, or if a surface has something the registry lacks; generated references for all three surfaces.
8. **End-to-end:** a scripted MCP client (stdio and HTTP) runs a real workflow against a scratch project (create, add entity,
   dry-run then apply a destructive edit, validate, undo, idle simulate) in CI.
9. **Release plumbing:** workflow, CHANGELOG, mkdocs nav, `docs/engine-releasing.md`, `release_consistency_test`, CLAUDE.md
   package map (engine_api depends on engine_core only).

## Risks

- A large surface multiplies maintenance; the registry + parity test is the mitigation.
- Write operations through an agent can destroy a project; needs dry-run/undo/locks decided up front.
- Operations that need Flutter (rendering, preview, running a game) cannot live in pure-Dart `engine_core`; they would be
  exposed only where a Flutter-capable host exists (or excluded from v1).
- MCP spec evolves; pin the protocol version and isolate it behind an adapter.

---

# Implementation specification

Everything below is the build contract. It is written so that someone (or an agent) with no other context can implement the
package phase by phase. Names are final unless marked *(suggested)*. Where an existing engine type is reused it is named exactly.

## A. Packages, dependencies and files

Dependency direction stays one-way: `engine_schema` -> `engine_core` -> (`engine_cli`, `engine_api`). `engine_api` depends on
`engine_core` (and `engine_schema` transitively) and **not** on Flutter or `engine_cli`. `engine_cli` depends on `engine_core`.

### A.1 In `packages/engine_core/lib/` (the registry; pure Dart, web-safe except where noted)

```
engine_core_ops.dart                  # public entry: exports everything below
src/ops/operation.dart                # Operation, OperationKind, OperationScope, Example
src/ops/param.dart                    # Param, ParamType, ParamSchema -> JSON Schema
src/ops/result.dart                   # OpResult, OpError, ErrorCode
src/ops/context.dart                  # OpContext, ProjectRoot, Clock, UndoLog, Locks, Limits
src/ops/registry.dart                 # OperationRegistry, version, lookup, catalogue()
src/ops/json_schema.dart              # ParamSchema/FieldSchema -> JSON Schema (draft 2020-12) + OpenAPI components
src/ops/safety.dart                   # dry-run, confirmation token, apply pipeline, read-only, lock check
src/ops/undo_log.dart                 # .studio/undo/ journal (dart:io; excluded from web entry)
src/ops/paths.dart                    # safe project path resolution (no escape, no symlink escape)
src/ops/groups/project_ops.dart       # project.*
src/ops/groups/level_ops.dart         # level.*
src/ops/groups/prefab_ops.dart        # prefab.*
src/ops/groups/graph_ops.dart         # graph.*
src/ops/groups/schema_ops.dart        # schema.*
src/ops/groups/world_ops.dart         # world.*
src/ops/groups/idle_ops.dart          # idle.*
src/ops/groups/strategy_ops.dart      # strategy.*
src/ops/groups/asset_ops.dart         # asset.*
src/ops/groups/i18n_ops.dart          # i18n.*
src/ops/groups/save_ops.dart          # save.*
src/ops/groups/release_ops.dart       # release.* (plan only; build is requiresFlutter)
src/ops/groups/engine_ops.dart        # engine.* (health, capabilities, operations)
src/ops/groups/undo_ops.dart          # undo.*
src/ops/all_operations.dart           # `final allOperations = <Operation>[...]` + `buildRegistry()`
```

`engine_core_ops.dart` is a **separate entry** (like `engine_core_idle.dart`, `engine_core_io.dart`) so games that do not need it do
not import it. Operations that read or write files (`dart:io`) are in files imported only from `engine_core_ops.dart`; the main
`engine_core.dart` stays web-compilable. A guard test (`ops_web_safety_test.dart`) compiles nothing but checks that
`engine_core.dart` does not export any `src/ops/` file.

### A.2 In `packages/engine_cli/lib/src/`

```
ops_cli.dart                # builds Command<int> objects from the registry (A.2.1)
ops_cli_format.dart         # text rendering of results (tables, diffs, problems) per operation
legacy_commands.dart        # maps the existing command names/flags onto operations (kept working)
```

Existing files (`studio_edit_commands.dart`, `studio_diff_commands.dart`, `studio_asset_commands.dart`, `idle_command.dart`,
`lint_command.dart`, ...) are **reduced to thin legacy adapters** in phase 4 and then deleted file by file as their behaviour is
proven identical by their existing tests.

### A.3 New package `packages/engine_api/`

```
pubspec.yaml                          # name: engine_api; publish_to: none; version 0.1.0; deps: engine_core, args, shelf (see A.4)
README.md  CHANGELOG.md  LICENSE      # required by release_consistency_test
bin/engine_api.dart                   # executable: `engine_api serve ...`, `engine_api mcp-stdio`, `engine_api docs`
lib/engine_api.dart                   # public API (embedding): ApiServer, ApiConfig
lib/src/config.dart                   # ApiConfig + engine_api.yaml loader + flag overrides
lib/src/server.dart                   # starts transports, shares one OperationRegistry/OpContext factory
lib/src/transport/mcp_stdio.dart      # newline-delimited JSON-RPC over stdin/stdout
lib/src/transport/mcp_http.dart       # streamable HTTP MCP endpoint (/mcp)
lib/src/transport/rest.dart           # /v1/<group>/<verb>, /v1/engine/operations, /v1/openapi.json
lib/src/transport/jsonrpc.dart        # /rpc (single + batch)
lib/src/mcp/protocol.dart             # message types, protocol version negotiation, capability building
lib/src/mcp/tools.dart                # Operation -> MCP tool, call handling, result shaping
lib/src/mcp/resources.dart            # resource templates + readers
lib/src/mcp/prompts.dart              # prompt loader (prompts/*.md) + renderer
lib/src/auth.dart                     # bearer token create/store/check, constant-time compare
lib/src/limits.dart                   # size limits, rate limiter (token bucket per client)
lib/src/request_log.dart              # JSON-lines request log
lib/src/docs_gen.dart                 # MCP/REST/CLI reference generation from the registry
prompts/*.md                          # guided workflows (L.4)
test/                                 # see M
tool/gen_docs.dart                    # writes docs/reference/api/*.md, openapi.json
```

### A.4 Dependencies (offline-friendly)

pub.dev is unreachable in the build sandbox, so prefer packages already resolved in the monorepo: `args`, `path`, `yaml`,
`crypto` (already used for save codes), `image` (already in engine_cli). The HTTP server uses **`dart:io` `HttpServer` directly**
(no `shelf`) to avoid a new dependency; request routing is ~150 lines in `rest.dart`. SSE for streamable HTTP is written by hand
(`text/event-stream`). If `shelf` is later preferred, it is confined to `transport/`.

## B. Core types (exact shape)

```dart
enum OperationKind { read, write, destructive }
enum OperationScope { pure, project }        // pure: needs no project; project: needs an open project root

class Operation {
  const Operation({
    required this.name,                      // 'level.add_entity' (lowercase, [a-z_]+ '.' [a-z_]+)
    required this.summary,                   // <= 100 chars, imperative, shown in lists
    required this.description,               // markdown, what/when/why/side effects/pitfalls
    required this.params,                    // List<Param>
    required this.result,                    // ResultSpec (JSON schema of OpResult.data)
    required this.kind,
    required this.scope,
    required this.handler,                   // FutureOr<OpResult> Function(OpContext, Map<String, Object?> args)
    this.errors = const [],                  // ErrorCode values this operation can return, with a sentence each
    this.examples = const [],                // List<Example>(title, args, result) - executed by tests
    this.requiresFlutter = false,            // true: implemented in engine_cli, not served by engine_api (v1)
    this.since = '0.1.0',
    this.deprecated,                         // Deprecation(since, removeIn, replacement)
    this.cli,                                // CliHints: friendly aliases, positional params, legacy name
  });
}

class Param {
  const Param(this.name, this.type, {this.required = false, this.defaultValue,
      this.description = '', this.min, this.max, this.options, this.items,
      this.properties, this.positional = false, this.cliFlag, this.cliAbbr, this.secret = false});
}
enum ParamType { string, integer, number, boolean, enumeration, array, object, json, path }
```

- `path` params are project-relative strings validated by `paths.dart` (A: never absolute, never `..`, never through a symlink that
  leaves the project root). For `scope: pure` operations that take files (`level.diff a b`), `path` params are resolved against the
  process working directory only when the surface is the **CLI**; over MCP/REST they must be project-relative (or the content
  is passed inline as `json`). This rule is the main sandbox boundary.
- `json` is any JSON value (used for component field values, level content, patches).
- Every operation that writes has two extra implicit params added by the registry (not declared per operation): `apply: boolean`
  (default **false** for `destructive`, default **true** for `write`) and `confirmation: string` (required to apply a destructive
  operation, see E.2).
- `OpResult`: `{ ok: true, data: <json>, warnings: [string], diff?: LevelDiffJson, undoId?: string, durationMs: int }` or
  `{ ok: false, error: { code, message, details?, hint? } }`. Handlers return/throw `OpError`; the dispatcher converts to the envelope.

### B.1 ErrorCode taxonomy (stable strings; never reused)

| Code | Meaning | HTTP | JSON-RPC code | CLI exit |
|---|---|---|---|---|
| `invalid_params` | missing/typed wrong/out of range | 400 | -32602 | 64 |
| `unknown_operation` | name not in registry | 404 | -32601 | 64 |
| `not_found` | project/level/entity/prefab/graph missing | 404 | -32001 | 66 |
| `already_exists` | creating something that exists | 409 | -32002 | 73 |
| `validation_failed` | result would violate schemas (`details.problems[]`) | 422 | -32003 | 65 |
| `locked` | advisory lock held (`details.owner`, `details.since`) | 423 | -32004 | 75 |
| `read_only` | server/session is read-only | 403 | -32005 | 77 |
| `forbidden` | operation disabled by allow/deny list or auth | 403 | -32006 | 77 |
| `confirmation_required` | destructive op without a valid confirmation (`details.preview`) | 409 | -32007 | 78 |
| `confirmation_stale` | token no longer matches current state | 409 | -32008 | 78 |
| `conflict` | merge/diff conflict (`details.conflicts[]`) | 409 | -32009 | 1 |
| `unsupported` | `requiresFlutter` or feature not built | 501 | -32010 | 69 |
| `too_large` | request/result over limits | 413 | -32011 | 64 |
| `rate_limited` | over rate limit (`details.retryAfterMs`) | 429 | -32012 | 75 |
| `unauthorized` | missing/bad token | 401 | -32013 | 77 |
| `io_error` | filesystem failure | 500 | -32014 | 74 |
| `internal` | bug; message safe, details only in the request log | 500 | -32603 | 70 |

(JSON-RPC -32700 parse error and -32600 invalid request keep their standard meaning.) CLI exit numbers follow `sysexits.h` where
a match exists, and 0 is success; `conflict` is 1 to keep today's `studio merge` behaviour.

## C. Parameter schema -> JSON Schema

`json_schema.dart` is the single converter used by MCP (`inputSchema`), OpenAPI, CLI help and request validation. Mapping:

| `ParamType` / `FieldType` | JSON Schema |
|---|---|
| `string`, `path` | `{"type":"string"}` (path adds `"description"` "project-relative") |
| `integer` / `FieldType.int` | `{"type":"integer","minimum":..,"maximum":..}` |
| `number` / `FieldType.double` | `{"type":"number",...}` |
| `boolean` / `FieldType.bool` | `{"type":"boolean"}` |
| `enumeration` / `FieldType.enumeration` | `{"type":"string","enum":[...]}` |
| `FieldType.vector2` | `{"type":"array","items":{"type":"number"},"minItems":2,"maxItems":2}` |
| `array` / `FieldType.list` | `{"type":"array","items":<items>}` |
| `object` / `FieldType.object` | `{"type":"object","properties":..,"additionalProperties":true}` |
| `json` | `{}` (any) |

Component schemas (`allComponentSchemas`) are exposed as `schema.component` results **and** as JSON Schema fragments under
`engine://schemas/components/<name>` so a client can validate a component before calling `level.set_field`. `FieldSchema.required`
-> `required`; `optional` -> allow `null`; `defaultValue` -> `default`. BigNumber fields (idle) are `string` with pattern
`^-?[0-9]+(\.[0-9]+)?(e[+-]?[0-9]+)?$`.

Request validation happens **once, in the dispatcher**, before the handler runs; handlers receive already-coerced values. Unknown
params are rejected (`invalid_params`, listing the allowed names) so typos never silently do nothing. The CLI coerces flag
strings with the same schema (`"3"` -> 3 for `integer`; `--value` for a `json` param is parsed as JSON, falling back to a plain
string, exactly as `studio set-field` does today).

## D. Execution context and project handling

```dart
class OpContext {
  final ProjectRoot? project;        // null for pure operations / before project.open
  final bool readOnly;
  final Clock clock;                 // injected (tests, deterministic undo ids)
  final UndoLog? undo;               // null when project == null or readOnly
  final Locks locks;                 // wraps FileLock with this process's owner id ('engine_api@host:pid')
  final Limits limits;
  final String actor;                // 'cli' | 'mcp:<client name>' | 'rest:<token id>' | 'rpc'
  final void Function(String) log;   // request-scoped logger
}
```

- **Project model.** A server run has *at most one* current project (decision). `project.open {path}` sets it (path must be an
  existing folder with `pubspec.yaml`; the **only** operation that takes an absolute path, and only over stdio MCP/CLI or when
  `--allow-open <glob>` permits it over network transports). `project.switch` is an alias. With `--project <dir>` the project is
  open at startup and `project.open` is disabled unless `--allow-switch` is set. The CLI context always opens the project at
  `--project` or the current directory (found by walking up to `pubspec.yaml`).
- **Resolution.** `ProjectRoot.resolve(String relative)`: normalize, reject absolute/`..`/NUL, join to root, then
  `File.resolveSymbolicLinksSync` and require the result to stay inside the real root. Used for **every** path param.
- **Well-known folders** (constants in `ProjectRoot`): `assets/levels`, `assets/prefabs`, `assets/graphs` (graphs live in
  `graphs/` today; the constant reflects what `StudioProject.nextGraphPath` uses), `assets/ai`, `.studio/` (undo, token, logs,
  playtest). The constants are read from the existing `StudioProject` logic so API and studio agree.
- **Concurrency.** The dispatcher serializes **write** operations per project with an in-process mutex (a `Future` chain), so two
  agents cannot interleave a read-modify-write on one file. Reads run concurrently. Cross-process safety is the advisory lock (E.4).

## E. Write safety (shared by every surface)

Implemented once in `safety.dart`; operations declare `kind` and return a **proposed change set**, the pipeline does the rest.

### E.1 Change sets

A write/destructive handler does not write files itself. It returns `Proposal { List<FileChange> changes; Object? data; }` where
`FileChange` is `{ path, before: String?, after: String?  /* null = delete */ }`. The pipeline then:

1. validates every changed level/graph/prefab against the schemas (`LevelValidator.forSchemas(allComponentSchemas)`; same as the
   studio edit commands do today: "this would make X invalid") -> `validation_failed` with `details.problems`;
2. checks locks for each path (E.4) and `readOnly` (E.5);
3. computes the diff (levels: `diffLevels`; other files: unified text diff summary);
4. if `kind == destructive` and `apply != true`: returns `confirmation_required`-style **preview** (E.2) and writes nothing;
5. otherwise writes atomically (temp file + rename; reuse `AtomicSave` semantics) in a stable order, appends the undo entry
   **before** the rename of the first file (so a crash leaves a restorable record), and returns `{ data, diff, undoId }`.

`kind == write` operations apply immediately (`apply` defaults true) but still go through steps 1-3 and 5, and can be previewed
with `apply:false`.

### E.2 Dry-run preview and confirmation token

Preview result: `{ ok:true, data:{ preview:true, summary:"Removes entity 'guard' and 2 components", diff:{...}, confirmation:"<token>", expiresAt } }`.

`confirmation` = base64url( `v1.` + `<opName>.` + `<sha256 of canonical(args without apply/confirmation)>.` + `<sha256 of the
before-state of every touched file>.` + `<expiry unix seconds>` + `.` + HMAC-SHA256(serverSecret, all previous parts) ). The server
secret is generated at startup (random 32 bytes, memory only, so tokens die with the process). To apply: call the **same
operation with the same args plus `confirmation`** (and `apply:true` is implied by a valid token). Verification recomputes the
hashes against current files: a mismatch -> `confirmation_stale` (the project changed since the preview, show a new preview);
expired (default 5 minutes) -> `confirmation_stale`; wrong operation/args -> `invalid_params`. CLI: `--apply` runs preview+apply in
one call after printing the diff when `--yes` is given or stdin is a TTY and the user confirms; otherwise prints the preview and
exits 78.

### E.3 Undo log

- Location: `<project>/.studio/undo/`. One journal file per write: `NNNNNN-<utc>-<op>.json` with `{ id, op, args, actor, at,
  files: [{path, beforeSha256, afterSha256, beforeFile: "NNNNNN/…"?}] }` and a sibling folder holding the **before** content
  (`NNNNNN/<path with / replaced by %2F>`), so undo works without git. Created-only files store `before: null`.
- Retention: keep the **last 100** entries; pruning happens after each successful write, oldest first, never during an undo.
- `undo.list {limit}` (R), `undo.undo {id?}` (W, defaults to the newest not-yet-undone; refuses with `conflict` if a touched file's
  current hash differs from the entry's `afterSha256` unless `force:true`), `undo.redo {id?}` (W). An undo is itself journaled (so
  redo works) and counts toward the 100.
- `.studio/undo/` is created lazily; `project.manifest`/gitignore advice: the docs recommend ignoring `.studio/`.

### E.4 Locks

Before writing a path, the pipeline uses the existing `FileLock(path)` (`<path>.lock`, `staleAfter` 2 h): `inspect()`; if held by
another owner -> `locked` with owner and `acquiredAt`. The API never holds locks implicitly between calls (decision: respect, not
acquire). `level.lock {path, force?}` / `level.unlock {path, force?}` expose `acquire`/`release` for explicit takeover.

### E.5 Read-only and allow/deny

- `--read-only` (or `readOnly: true` in config, or `engine.set_read_only` is **not** an operation: it cannot be toggled remotely)
  makes every `write`/`destructive` operation return `read_only` before the handler's proposal is even computed.
- Allow/deny lists (config `operations.allow` / `operations.deny`, glob on names, e.g. `deny: ["release.*", "asset.pack"]`) are
  evaluated per call: deny wins; an operation not matching a non-empty allow list is `forbidden`. They also filter the catalogue
  (`tools/list`, `GET /v1/engine/operations`, OpenAPI) so a denied operation is invisible, not merely failing.

## F. CLI binding

`ops_cli.dart` builds, for each operation: `Command<int>` named `<verb>` under a group command named `<group>` (e.g.
`game_agent level add-entity`, verb underscores become hyphens). Rules:

1. **Flags from params:** each param becomes `--<name-with-hyphens>`; `required` -> validated after parse; `boolean` -> `--[no-]flag`;
   `enumeration` -> `allowed:`; `array` -> repeatable option; `positional: true` params are positional in declared order
   (`game_agent level diff <a> <b>`); `cliAbbr` gives `-x`.
2. **Input via stdin:** `--stdin` reads one JSON object from stdin and merges it under flags (flags win). `--args '<json>'` is the
   same inline. Params with `secret: true` are never echoed in help or logs.
3. **Output:** default human text rendered by `ops_cli_format.dart` per operation (falls back to pretty JSON); `--json` prints the
   exact `OpResult` envelope (stable, one object, newline-terminated) and sets the exit code from the table in B.1; `--quiet` prints
   nothing on success. Diagnostics go to stderr, data to stdout.
4. **Writes:** `--dry-run` (= `apply:false`), `--apply`, `--confirmation <token>`, `--yes` (non-interactive confirm), `--force` for
   lock/undo conflicts. `destructive` operations without `--apply`/`--yes` print the preview and exit 78.
5. **Project:** global `--project <dir>` (default: nearest ancestor with `pubspec.yaml`); `--read-only` global flag.
6. **Help:** generated from `summary`, `description` (first paragraph), param descriptions and the first example; `game_agent ops list`
   prints the catalogue (name, kind, scope, summary); `game_agent ops show <name>` prints everything including JSON Schema.
7. **Legacy compatibility:** `legacy_commands.dart` keeps today's commands working: `studio add-entity <file> --name ...` maps to
   `level.add_entity` (file positional becomes `path`); `lint`, `pack-assets`, `idle simulate`, etc. likewise. Legacy output text is
   preserved byte for byte where tests pin it; `--json` is new. Each legacy command is marked `deprecated: false` (they stay), they
   are simply aliases.
8. **`requiresFlutter` operations** (`project.create`, `project.upgrade`, `release.build`) are bound in `engine_cli` with their current
   process-running implementation and the same registry metadata; `engine_api` lists them in `engine.capabilities.unsupported` and
   returns `unsupported` if called.

## G. MCP server (engine_api)

### G.1 Protocol

- Spec: Model Context Protocol, JSON-RPC 2.0 messages. Protocol version is **pinned in one constant**
  (`mcpProtocolVersion = '2025-06-18'` *(suggested; confirm against the current spec at implementation time)*). `initialize` negotiates:
  if the client requests a version we do not know, reply with ours; clients may disconnect.
- Server capabilities in the `initialize` result: `tools: {listChanged: true}`, `resources: {subscribe: false, listChanged: true}`,
  `prompts: {listChanged: false}`, `logging: {}`. `serverInfo: {name: 'engine_api', version: <package version>}`;
  `instructions`: a short paragraph (how to open a project, dry-run/confirmation flow, read-only flag).
- Methods implemented: `initialize`, `notifications/initialized`, `ping`, `tools/list` (+ cursor pagination, page size 100),
  `tools/call`, `resources/list`, `resources/templates/list`, `resources/read`, `prompts/list`, `prompts/get`, `logging/setLevel`,
  `notifications/cancelled` (cancels an in-flight operation by request id where the handler checks a cancellation token),
  `notifications/tools/list_changed` (emitted after `project.open`/`project.switch` because project-scoped tools may differ; in
  practice the tool list is constant, so this is sent only if the allow/deny filter changes).
- Unknown methods -> JSON-RPC `-32601`. Notifications never get a response.

### G.2 Tools

One MCP tool per non-`requiresFlutter` operation. Mapping:

- `name`: the dotted operation name (`level.add_entity`). *(MCP allows `.` in tool names; if a client rejects dots, the server
  has `--tool-name-style underscore` which exposes `level_add_entity`; the registry name is unchanged.)*
- `description`: `summary` + blank line + `description` + a **"Kind"** line (`read` / `write` / `destructive - preview first`) + the
  examples rendered as short JSON blocks + the error codes with their meaning. This is the "enough detail for the agent" requirement.
- `inputSchema`: C converter output, including the implicit `apply` / `confirmation` params for write kinds, `additionalProperties: false`.
- `outputSchema` (if the negotiated version supports it): the operation's `result` spec wrapped in the `OpResult` envelope.
- `annotations`: `readOnlyHint` (kind == read), `destructiveHint` (kind == destructive), `idempotentHint` (declared per operation, true
  for set-style writes), `openWorldHint: false`, `title`.
- `tools/call` result: `content: [{type:"text", text:<pretty JSON of the envelope>}]` plus `structuredContent: <envelope>`; `isError:
  true` when `ok:false` (the envelope carries `error.code`). Large `data` over `limits.maxResultBytes` is truncated with
  `error: too_large` unless the operation is paginated (`limit`/`cursor` params, declared per operation).
- Binary results (rendered PNG from `level.lint --render`) use `content: [{type:"image", data: <base64>, mimeType:"image/png"}]`.

### G.3 Resources

Static list (`resources/list`) and templates (`resources/templates/list`), `resources/read` returns `contents: [{uri, mimeType,
text|blob}]`.

| URI | Content | MIME |
|---|---|---|
| `engine://operations` | the catalogue (name, kind, summary) | application/json |
| `engine://operations/{name}` | full operation spec incl. JSON Schema and examples | application/json |
| `engine://schemas/components` | list of component names | application/json |
| `engine://schemas/components/{name}` | JSON Schema + defaults for one component | application/json |
| `engine://docs/{page}` | a docs page from `docs/` (concepts, tutorials, reference), markdown | text/markdown |
| `engine://reference/errors` | the error taxonomy (B.1) | text/markdown |
| `project://info` | name, version, engine ref, counts (levels, prefabs, graphs, atlases) | application/json |
| `project://tree` | file tree (same filter as the studio tree) | application/json |
| `project://levels/{name}` | level JSON (project-relative `assets/levels/{name}.json`) | application/json |
| `project://prefabs/{name}` | prefab JSON | application/json |
| `project://graphs/{name}` | graph JSON | application/json |
| `project://file/{path}` | any text file inside the project (size-capped, binary refused) | text/plain or json |
| `project://problems` | current validation problems | application/json |
| `project://undo` | the undo journal summary | application/json |

Project URIs return `not_found` until a project is open. No resource ever resolves outside the project root (same `paths.dart`).

### G.4 Prompts

Defined by files in `prompts/` with front matter:

```markdown
---
name: build_level
description: Build a platformer level step by step and validate it.
arguments:
  - name: theme
    description: What the level is like
    required: false
---
You are editing the open project with the engine tools...
1. Call project.info ...
```

`prompts/get` renders `{{argument}}` placeholders and returns `messages: [{role:"user", content:{type:"text", text:...}}]`.
Initial prompt set (each has a test that **executes its steps** against a scratch project via the tool dispatcher): `build_level`,
`fix_validation_problems`, `balance_idle_game`, `add_enemy_ai_graph`, `localize_game`, `review_changes` (uses `level.diff` +
`undo.list`), `new_project_checklist`.

### G.5 Transports

**stdio:** UTF-8 newline-delimited JSON, one message per line, no embedded newlines; logs only to stderr. `engine_api mcp-stdio
--project <dir> [--read-only] [--config f]`. No token (parent owns the pipe).

**Streamable HTTP (`/mcp`):** `POST /mcp` with `Content-Type: application/json` and `Accept: application/json, text/event-stream`
carrying one JSON-RPC message or a batch; requests get either `application/json` (single response) or a `text/event-stream` (only
used when the operation emits progress); notifications/responses get `202 Accepted`. `GET /mcp` with `Accept: text/event-stream` opens
the server-to-client stream (server notifications such as list_changed, logging); `DELETE /mcp` ends a session. Session id: returned
in the `Mcp-Session-Id` header of the `initialize` response and required afterwards (`400` if missing, `404` if unknown).
`MCP-Protocol-Version` header checked. Always requires the bearer token and validates `Origin` against `config.allowedOrigins`
(default: none, so browsers cannot call it) to defeat DNS-rebinding.

## H. REST and JSON-RPC

### H.1 REST (`/v1`)

| Method + path | Purpose |
|---|---|
| `POST /v1/<group>/<verb>` | run an operation; body = params object (empty body = `{}`); response = the `OpResult` envelope |
| `GET /v1/engine/operations` | catalogue (filtered by allow/deny); `?group=level&kind=write` filters |
| `GET /v1/engine/operations/<group>.<verb>` | one operation spec with JSON Schema and examples |
| `GET /v1/openapi.json` | OpenAPI 3.1 document generated from the registry |
| `GET /v1/health` | `{status:"ok", version, uptimeMs}` - **no auth** (liveness only, no project data) |
| `GET /v1/project/<…>` | convenience GETs for the read operations that have no params beyond a path: `project/info`, `project/tree`, `level/list`, `schema/components` (documented as sugar for POST) |

- Status codes from B.1; `200` for `ok:true` including previews. Error body is the envelope with `ok:false`. `Content-Type:
  application/json; charset=utf-8`. Unknown path -> 404 `unknown_operation`; wrong method -> 405 with `Allow`.
- Headers: `Authorization: Bearer <token>` (required except `/v1/health`); `X-Request-Id` accepted/echoed (generated if absent);
  `Idempotency-Key` honoured for write operations for 10 minutes (same key+body returns the stored response; different body -> `409
  conflict`).
- CORS: off by default; `config.cors.origins` enables exact-origin allow with `Authorization` allowed.
- Limits (config defaults): request body 1 MiB, response 8 MiB (`too_large`), 120 requests/minute per token, 4 concurrent
  requests per token (`rate_limited` with `Retry-After`).

### H.2 JSON-RPC (`POST /rpc`)

Standard JSON-RPC 2.0. `method` = operation name, `params` = object (by-name only; by-position -> `-32602`). `result` = the `OpResult`
envelope's `data` plus `meta: {warnings, diff?, undoId?, durationMs}` on success; failures use `error: {code, message, data:{code:
<ErrorCode>, details, hint}}` with the JSON-RPC codes of B.1. Batches (array) are executed **in order**, each write holding the
project mutex; a batch is not transactional (documented), `engine.batch` is **not** provided in v1. Special methods:
`rpc.discover` returns the catalogue (OpenRPC-style JSON). Same auth/limits as REST.

## I. Authentication, configuration, logging

- **Token:** 32 random bytes, base64url (43 chars). On `serve` startup: if `--token` or `ENGINE_API_TOKEN` is given use it;
  otherwise read `.studio/api-token`; otherwise generate, write it there with file mode 0600 (best effort on Windows), and print
  `engine_api: bearer token written to <path>` to stderr (the token itself is **never** printed unless `--print-token`).
  `--rotate-token` replaces it. Comparison is constant-time (`crypto`-style XOR loop). Failed attempts are counted per remote
  address and cause a 1-second delay after 5 failures.
- **Binding:** `127.0.0.1` by default. `--bind 0.0.0.0` (or an address) is refused unless `--allow-remote` is also passed and a token
  is configured; startup prints a warning that TLS is not terminated here and recommends a reverse proxy (`wss://`-style advice).
- **Config file `engine_api.yaml`** (project root or `--config`); flags override file values; unknown keys are an error:

```yaml
project: .                       # path (default: the --project flag or cwd)
readOnly: false
bind: 127.0.0.1
port: 7421                       # REST + JSON-RPC + /mcp share one port; 0 = pick a free one and print it
transports: [stdio, http]        # stdio is chosen by the `mcp-stdio` subcommand, http by `serve`
allowOpen: []                    # globs of absolute paths project.open may open over network transports
allowedOrigins: []
operations:
  allow: []                      # empty = all
  deny: ["release.*"]
limits:
  maxRequestBytes: 1048576
  maxResultBytes: 8388608
  requestsPerMinute: 120
  concurrentPerToken: 4
undo:
  keep: 100
confirmation:
  ttlSeconds: 300
log:
  file: .studio/api-requests.jsonl
  level: info
```

- **Request log** (JSON lines, one per call, flushed): `{ts, requestId, transport, actor, op, kind, ok, code, durationMs, bytesIn,
  bytesOut, project, undoId}`. Args and results are **not** logged by default (`log.level: debug` adds args with `secret` params
  redacted). Rotated at 10 MiB, keep 5.
- **`engine.health`** `{status, version, registryVersion, uptimeMs, project: {open, name}, readOnly}`; **`engine.capabilities`**
  `{registryVersion, mcpProtocolVersion, transports, groups: {<group>: count}, unsupported: [{name, reason}], limits, allow/deny
  summary, flutter: false}`; **`engine.operations`** the catalogue.

## J. Operation specifications (v1, complete list)

Notation: params as `name:type!` (`!` required, default in `=`); result is the `data` field. `P` = project-scoped, `-` = pure.
Kinds: R/W/D. Each operation also appears with its CLI command (`game_agent <group> <verb>`, verb hyphenated) and has at least one
example. Handlers reuse the cited existing code; **no logic is re-implemented**, it is moved into `engine_core/src/ops/groups/` and the
old call sites call the same function.

### J.1 project.*

| Operation | K | S | Params | Result | Reuses |
|---|---|---|---|---|---|
| `project.open` | R | - | `path:path!` | `{name, root, engineRef, levels, prefabs, graphs}` | `StudioProject.open` |
| `project.close` | R | P | - | `{closed:true}` | - |
| `project.info` | R | P | - | `{name, root, version, engine:{ref, packages}, counts, flutterProject}` | `StudioProject`, pubspec parse (`yaml`) |
| `project.tree` | R | P | `filter:enum(all,code,levels,graphs,images,data,other)='all'`, `maxEntries:int=2000` | `[{path, isDirectory, kind, depth}]` | `listProjectTree`, `FileKind` (move to core) |
| `project.search` | R | P | `query:string!`, `limit:int=200` | `[{path, line, column, text}]` | `searchProject` (move to core) |
| `project.validate` | R | P | `strict:bool=false` | `{ok, levels:[{path, errors[], warnings[]}]}` | `StudioValidateCommand` core part |
| `project.problems` | R | P | `include:[string]=levels,graphs` | `[{path, severity, message, entity?, component?, field?}]` | `project_problems.dart` logic |
| `project.manifest` | W | P | - | `{path, content}` | `project-manifest` command logic |
| `project.symbols` | R | P | - | `{classes, atlasIds, entityNames}` | `ProjectSymbols` |
| `project.git_status` | R | P | - | `{available, changes:{path: M|A|D|R|?|!}}` | `readGitStatus` (process runner injected; `dart:io` only) |
| `project.pub_get` | W | P | - | `{exitCode, output}` | `runPubGet`; **`requiresFlutter`** |
| `project.create` | W | - | `name:string!`, `template:enum(default_game,strategy_game,idle_game)`, `org`, `outputDir` | `{path}` | CreateCommand; **`requiresFlutter`** |
| `project.upgrade` | W | P | `ref:string='main'` | `{changed:[...]}` | UpgradeCommand; **`requiresFlutter`** |

### J.2 level.* (levels are `assets/levels/*.json`; `path` is project-relative; `name` is the entity name)

| Operation | K | Params | Result | Reuses |
|---|---|---|---|---|
| `level.list` | R | - | `[{path, entities, hasTileMap, lockedBy?}]` | `LevelDocument.fromJson` |
| `level.read` | R | `path!`, `entity?:string`, `components?:[string]` | level JSON (or one entity / selected components) | `LevelDocument` |
| `level.validate` | R | `path?` or `json?` (inline level), `playable:bool=false` | `{ok, errors[], warnings[]}` | `LevelValidator.forSchemas`, playability heuristic (`lint --playable`) |
| `level.lint` | R | `path!`, `render:bool=false`, `playable:bool=false` | `{ok, message, png?:base64}` | `LintCommand` logic (needs `image`; stays pure Dart) |
| `level.create` | W | `path!`, `entities?:json` | `{path, entities}` | `LevelSaver`, `canonicalJson` |
| `level.add_entity` | W | `path!`, `name?`, `components?:[string]`, `index?:int`, `values?:object` | `{index, entity}` | `studio add-entity` |
| `level.remove_entity` | D | `path!`, `name!` | `{removed}` | `studio remove-entity` |
| `level.move_entity` | W | `path!`, `name!`, `x?:number`, `y?:number`, `index?:int` | `{entity}` | `studio move-entity` |
| `level.set_field` | W | `path!`, `entity!`, `component!`, `field!`, `value!:json` | `{before, after}` | `studio set-field` |
| `level.set_layer` | W | `path!`, `entity!`, `z!:int` | `{entity}` | `studio set-layer` |
| `level.add_component` | W | `path!`, `entity!`, `component!`, `values?:object` | `{component}` | `ComponentSchema.template` |
| `level.remove_component` | D | `path!`, `entity!`, `component!` | `{removed}` | new (small) |
| `level.paint_tile` | W | `path!`, `entity!`, `col!:int`, `row!:int`, `tileId!:int` | `{changed}` | `studio paint-tile` |
| `level.fill_region` | W | `path!`, `entity!`, `col!`, `row!`, `tileId!` | `{filled:int}` | `studio fill-region` |
| `level.diff` | R | `a!:path`, `b!:path` (or `aJson`/`bJson`) | `{added[], removed[], changed[], format}` | `diffLevels`, `LevelDiff.format/toJson` |
| `level.merge` | D | `base!`, `ours!`, `theirs!` | `{merged, conflicts[]}`; conflict -> `conflict` | `mergeLevels` |
| `level.import_tmx` | W | `tmx!:path`, `output?:path` | `{path, entities}` | `TmxImport` |
| `level.export_tmx` | W | `path!`, `output?:path` | `{path}` | TMX export |
| `level.export_canonical` | W | `paths?:[path]` | `{rewritten:[path]}` | `studio export-levels` |
| `level.lock` / `level.unlock` | W | `path!`, `force:bool=false` | `{owner, acquiredAt}` / `{released}` | `FileLock` |
| `level.lock_status` | R | `path!` | `{locked, owner?, since?}` | `FileLock.inspect` |

### J.3 prefab.*, graph.*, asset.*, i18n.*

| Operation | K | Params | Result | Reuses |
|---|---|---|---|---|
| `prefab.list` / `prefab.read` | R | `name!` | prefab JSON | `PrefabStore` |
| `prefab.save` | W | `path!`, `entity!`, `name!` | `{path}` | `studio save-prefab` |
| `prefab.place` | W | `path!`, `prefab!`, `x?`, `y?`, `name?` | `{entity}` | `studio place-prefab` |
| `graph.list` / `graph.read` | R | `path!` | graph JSON | `GraphDocument` |
| `graph.create` | W | `path!`, `type:enum(dialogue,behaviorTree,stateMachine)` | `{path}` | graph editor logic |
| `graph.add_node` / `graph.remove_node` | W / D | `path!`, `kind!`, `id?`, `params?` / `id!` | `{node}` | `GraphEditor` |
| `graph.connect` / `graph.disconnect` | W | `path!`, `from!`, `fromPort!`, `to!`, `toPort!` | `{edge}` | `GraphEditor` (port type check) |
| `graph.set_param` | W | `path!`, `node!`, `param!`, `value!:json` | `{before, after}` | `GraphEditor` + `FieldSchema` |
| `graph.validate` | R | `path!` | `{issues[]}` | `validateGraph` |
| `graph.compile` | R/W | `path!`, `output?:path` | engine JSON (or written path) | dialogue/BT/SM compilers |
| `graph.node_kinds` | R | `type!` | `[NodeKind JSON]` | `GraphType.registry` (+ plugin kinds when a host registers them) |
| `asset.index` | R | - | atlases, images, prefabs, regions | `AssetIndex.scan` |
| `asset.atlas_regions` | R | `atlas!` | `[{region, x, y, w, h}]` | `AssetIndex` |
| `asset.pack` | W | `input!:path`, `outputImage`, `outputManifest`, `padding=2`, `maxWidth=2048`, `scales='1.0'` | `{images, manifests, regions}` | `pack-assets` |
| `i18n.keys` | R | `locale?` | keys/missing/placeholder report | `LocalizationManager` |
| `i18n.set` | W | `locale!`, `key!`, `text!` | `{before, after}` | locale JSON files |

### J.4 schema.*, world.*, engine data

| Operation | K | S | Params | Result |
|---|---|---|---|---|
| `schema.components` | R | - | `group?:string` | `[{name, group, fieldCount}]` (`allComponentSchemas`) |
| `schema.component` | R | - | `name!` | fields, types, ranges, options, defaults, required, JSON Schema, template |
| `schema.validate_component` | R | - | `name!`, `value!:json` | `{ok, errors[]}` |
| `schema.template` | R | - | `name!` | default component JSON (`ComponentSchema.template`) |
| `world.build` | R | - | `level?:path` or `json`, `systems?:[string]` | `{worldId, entities}`: loads a level into a **headless, in-memory** `World` held in the session (max 4 worlds, 10 min idle TTL) |
| `world.step` | W* | - | `worldId!`, `seconds:number=1`, `ticks?:int` | `{tick, entities, events[]}` (*mutates only the in-memory world; kind `read` for safety purposes, never touches files) |
| `world.snapshot` | R | - | `worldId!`, `entities?:[int]` | `WorldSnapshot` JSON |
| `world.patch` | R* | - | `worldId!`, `patch!:json` | `{applied}` (`applyPatch`) |
| `world.query` | R | - | `worldId!`, `component!`, `where?` | entities with that component |
| `world.discard` | R | - | `worldId!` | `{discarded}` |

(`world.*` are the "all engine functions" most useful to an agent: a deterministic, headless sandbox using `engine_core` only. Systems
available by name: `movement`, `gravity`, `collision`, `tween`, `particles`, plus the idle/strategy installers; systems that need
Flutter or input are not listed. This keeps the Flutter exclusion intact.)

### J.5 idle.*, strategy.*, save.*, release.*, engine.*, undo.*

| Operation | K | Params | Result | Reuses |
|---|---|---|---|---|
| `idle.validate` | R | `path?` or `json?` | `{ok, problems[]}` | `validateIdleDefinition` |
| `idle.simulate` | R | `path?`/`json?`, `days=3`, `prestigeAt?`, `mainResource='coins'` | `{elapsedSeconds, purchases, stalled, stallReason?, milestones[], finalIncome}` (+ `text`) | `simulateIdle`, `describeSimulation` |
| `idle.state` | R | `path?`/`json?`, `afterSeconds=0` | wallet, income, owned, achievements after a simulated run | `loadIdleDefinition`, `computeIncome` |
| `idle.best_purchase` | R | `path?`/`json?`, `wallet?:object`, `owned?:object` | `{entity/id, isUpgrade, cost, gain, payback}` | `bestPurchase` |
| `idle.format_number` | R | `value!:string`, `style=suffix`, `decimals=2` | `{text}` | `formatBigNumber` |
| `strategy.rules` | R | - | turn/order/combat constants and component list | static description |
| `strategy.simulate_turns` | R | `level!`, `turns=1`, `ai?` | `{events[], winner?}` using `OrderSystem`, `TurnSystem`, `AITurnSystem` in a headless world | strategy core |
| `save.encode` | R | `save!:json` | `{code}` | `SaveCodec.export` |
| `save.decode` | R | `code!` | `{save}` or `validation_failed` (message from `SaveFormatException`) | `SaveCodec.import` |
| `save.migrate` | R | `save!:json`, `fromVersion?`, `toVersion` | migrated save | `SaveMigrator` (migrations registered by name by the host; v1 ships none) |
| `release.plan` | R | `android=true`, `ios=false`, `flavor?`, `target`, `buildName?`, `buildNumber?` | planned commands, signing checks | `release_plan.dart` |
| `release.build` | W | as plan | exit codes | **`requiresFlutter`** |
| `engine.health` / `engine.capabilities` / `engine.operations` | R | - | see I | registry |
| `engine.docs` | R | `page?:string` | list of docs pages or one page's markdown | files under `docs/` shipped with the package |
| `undo.list` / `undo.undo` / `undo.redo` | R / W / W | see E.3 | | `undo_log.dart` |

## K. Documentation generation

`engine_api docs` (and `tool/gen_docs.dart`) produces from the registry, deterministically (sorted by name):

- `docs/reference/operations.md` - one section per operation: summary, kind, scope, description, params table (type, required,
  default, constraints), result schema, errors, examples as **CLI**, **MCP tools/call**, **REST curl**, **JSON-RPC** snippets.
- `docs/reference/api/openapi.json` - OpenAPI 3.1 (`paths`: `/v1/<group>/<verb>`, shared `OpResult`/`OpError` components,
  `securitySchemes: bearer`, tags per group, `x-kind`, `x-cli`).
- `docs/reference/cli.md` - the operation-derived part is generated (marker comments `<!-- generated:ops -->`), hand-written
  sections (create/upgrade narrative) stay.
- `docs/reference/mcp.md` - tools table, resources, prompts, transport setup for Claude Desktop/Code (`claude mcp add`, JSON config
  snippet), troubleshooting.

Drift tests (like `component_docs_test.dart`): the generated files must equal the committed ones; failing prints the regenerate command.

## L. Testing specification

### L.1 Registry/unit (in `engine_core`)

- `operation_registry_test`: unique dotted names, valid pattern, every param typed, every example's `args` validate against the
  operation's own schema, every `errors` code exists in `ErrorCode`, `requiresFlutter` ops have no handler in core.
- `json_schema_test`: golden JSON Schema for each `ParamType`/`FieldType`; every component schema converts and a generated template
  validates against its own JSON Schema (property test over `allComponentSchemas`).
- `paths_test`: traversal (`../x`, absolute, NUL, `a/../../b`), symlink escape (create a symlink to a temp dir), case/dots/Windows
  separators, very long paths.
- `safety_test`: preview for destructive ops writes nothing; token verifies, becomes `confirmation_stale` after any touched file
  changes or TTL elapses (injected `Clock`), rejects a token from a different op/args; read-only blocks writes before proposals;
  lock held by another owner -> `locked` with owner; atomic write leaves the old file intact when the second file fails; undo
  journal written before the first rename; 100-entry pruning; undo then redo restores bytes; undo refuses on changed file unless
  `force`.
- One test file **per group** exercising every operation against a scratch project (copy of a fixture in `test/fixtures/project/`):
  happy path, each documented error code, `--dry-run` result, and (for writes) that the file content equals what the legacy CLI
  produced for the same inputs (golden comparison, proving the migration is behaviour-preserving).

### L.2 CLI (`engine_cli`)

- Existing ~130 tests untouched and green after phase 4 (legacy adapters).
- `ops_cli_test`: for **every** registered operation, `game_agent <group> <verb> --help` renders, a call with `--json` returns a valid
  envelope, required-param errors exit 64, destructive without `--apply` exits 78, `--stdin` merges. Generated from the registry so a
  new operation is covered automatically.

### L.3 API (`engine_api`)

- `mcp_protocol_test`: initialize/negotiation, tools/list pagination, tools/call success + `isError`, resources/templates/read,
  prompts/get rendering, ping, cancellation, unknown method, malformed JSON, batch handling over stdio and `/mcp`.
- `rest_test` / `jsonrpc_test`: status code and error mapping table B.1 (one assertion per code), auth missing/wrong/right,
  constant-time compare helper test, rate limit and size limit, `Idempotency-Key`, CORS off/on, `Origin` rejection on `/mcp`,
  `405`, `404`, OpenAPI document validity (structural) and that every path exists.
- `config_test`: file+flag precedence, unknown key error, remote bind refusal without `--allow-remote`.
- `request_log_test`: one line per call, no args by default, redaction of `secret` params at debug level, rotation.
- `docs_drift_test`: generated docs equal committed docs.
- **`parity_test` (the 1:1 rule)**: iterates `buildRegistry()`; asserts for each operation: has a CLI command name (or is in
  `legacyAliases`), and unless `requiresFlutter` also an MCP tool, a REST route, an OpenAPI path and a JSON-RPC method; asserts the
  reverse (no CLI group/verb, tool, route or method without an operation); asserts `requiresFlutter` ops are listed in
  `engine.capabilities.unsupported`; asserts allow/deny filtering hides an operation on **all** surfaces simultaneously.
- `e2e_test` (process level, runs in CI): start `engine_api mcp-stdio` as a subprocess with a scratch project; a small Dart MCP client
  performs: initialize -> tools/list (count == registry non-Flutter count) -> project.info -> level.create -> level.add_entity ->
  level.remove_entity (preview, then apply with the token) -> project.validate -> undo.undo -> idle.simulate on the sample game ->
  `world.build/step/snapshot`. Repeat the same script over HTTP (`/mcp`, `/rpc`, `/v1`) with the bearer token and assert identical
  `data` for the same operation across all four transports.

### L.4 Prompts

Each prompt file has a sibling `*.test.yaml` listing the tool calls its steps imply; the test renders the prompt, checks every tool
name it mentions exists in the registry and that the listed calls succeed against the fixture project.

## M. Build order, tasks and acceptance criteria

Each phase = one or more commits, pushed after the **package's tests and `analyze --fatal-infos` are green** (gate the commit on the
real "All tests passed" line, not on a pipe). Phases are sequential; within a phase, groups can be done in any order.

**Phase 0 - scaffolding (1 commit).** Create `packages/engine_api` (pubspec with `publish_to: none`, version 0.1.0, README/CHANGELOG/
LICENSE), `.github/workflows/engine_api.yml` (paths: engine_api, engine_core, engine_schema, engine_cli), CLAUDE.md package map
row, root README row, `docs.yml` API loop entry, mkdocs nav placeholder, `release_consistency_test` passes (it picks the package up
automatically: same version, `publish_to: none`, LICENSE/README/CHANGELOG). *Accept:* CI green with an empty `lib/engine_api.dart`.

**Phase 1 - registry core (2-3 commits).** `operation.dart`, `param.dart`, `result.dart`, `context.dart`, `registry.dart`,
`json_schema.dart`, `paths.dart`, error taxonomy, dispatcher (`registry.call(name, args, ctx)`: validate -> handler -> envelope ->
duration), `engine.*` operations as the first (trivial) operations. *Accept:* L.1 registry/json_schema/paths tests green; `engine.operations`
works through the dispatcher.

**Phase 2 - write safety (2 commits).** `safety.dart`, `undo_log.dart`, change sets, tokens, locks, read-only, allow/deny. Tested with a
**fake operation** that proposes file changes. *Accept:* `safety_test` complete (all cases in L.1).

**Phase 3 - move existing read operations (2 commits).** `project.validate`, `level.lint`, `level.diff`, `idle.validate`,
`idle.simulate`, `asset.pack`, `release.plan` etc. into groups; legacy commands call the registry. *Accept:* all old CLI tests green; the
new per-group tests green; `ops_cli` generates the commands for these.

**Phase 4 - move existing write operations (3 commits).** `level.add_entity ... fill_region`, `level.import/export_tmx`,
`level.export_canonical`, `level.lock/unlock`, `level.merge`, `prefab.save/place`, `project.manifest`. Handlers return Proposals;
legacy commands become adapters; golden comparisons prove identical files. *Accept:* old tests green; every legacy command has an
operation; legacy files reduced.

**Phase 5 - new operations (one commit per group).** `project.*` extras, `level.read/list/validate/create/add_component/remove_component`,
`graph.*`, `schema.*`, `i18n.*`, `save.*`, `strategy.*`, `idle.state/best_purchase/format_number`, `engine.docs`, `world.*`, `undo.*`.
Each with CLI binding (automatic), tests (L.1/L.2), doc examples. *Accept:* `parity_test` skeleton in core lists no operation without a CLI
command.

**Phase 6 - engine_api server (4 commits).** (a) config, auth, limits, request log; (b) MCP protocol + stdio + tools; (c) resources +
prompts; (d) HTTP: `/mcp`, REST, JSON-RPC, OpenAPI. *Accept:* L.3 tests green except e2e/parity/docs.

**Phase 7 - parity, docs, e2e (2 commits).** `parity_test`, `docs_drift_test`, generator, `e2e_test`, generated references committed,
`docs/reference/mcp.md` and a tutorial "Drive the engine from Claude" (executed by the e2e script). *Accept:* all engine_api tests green in CI.

**Phase 8 - release plumbing (1 commit).** CHANGELOG entries per phase, `docs/engine-releasing.md` mention, README badges row,
`engine_mcp.md` marked **Implemented** with a link to the generated reference, TODO.md entry closed.

## N. Operational details and edge cases

- **Determinism:** operations with randomness take an explicit `seed:int` (default 1) and use `DeterministicRandom`; the request log
  records it. `idle.simulate`, `world.step` and `strategy.simulate_turns` are reproducible from their args.
- **Time:** every handler gets time only from `OpContext.clock`; tests inject a fixed clock; the determinism guard test
  (`idle_determinism_test` style) is extended to `src/ops/` forbidding `DateTime.now()` outside `context.dart`.
- **Long-running operations:** none in v1 (Flutter exclusions). Every handler must finish within `limits.maxOperationSeconds` (default
  30); the dispatcher enforces it with a timeout (`internal` + `details.timeout`) and, for `world.step`, a cap on ticks per call (10,000).
- **Result size:** `level.read` of a huge level pages with `entityOffset/entityLimit`; `project.tree`, `project.search`, `undo.list` take
  `limit`. Streams are not used in v1.
- **Encoding:** all files UTF-8; levels written with `canonicalJson` (sorted keys, 2-space indent) exactly like the CLI does; CRLF in
  input is accepted and normalized to LF on write (documented).
- **Windows:** path separator normalization in `paths.dart`; lock file and token permission handling are best-effort; stdio MCP reads
  in binary-safe UTF-8.
- **Secrets:** no operation returns environment variables, signing keys or keystore passwords; `release.plan` redacts `key.properties`
  values; `project.read_file` equivalents never serve `.studio/api-token`, `*.jks`, `*.keystore`, `key.properties`, `.env*`.
- **Plugins:** studio plugin node kinds (`StudioPlugins`) are Flutter-side; `graph.node_kinds` shows only built-ins unless a host
  registers kinds into the core registry via `registerNodeKinds(type, kinds)` (new tiny core API added in phase 5).
- **Versioning:** `registryVersion` follows semver: new operation = minor, new optional param = minor, removed/renamed operation or
  param, changed result shape = major; a removed operation is `deprecated` for one minor release and still answers with a
  `warnings: ["deprecated: use X"]`. `engine.capabilities` reports it; the generated docs include a changelog table.
- **Backwards compatibility of existing CLI:** exit codes of legacy commands are preserved (tests pin them); `--json` is additive.

## O. Security checklist (to verify in review)

1. Every path param goes through `paths.dart`; fuzz test with random segments.
2. No handler calls `Process.run` except those flagged `requiresFlutter` (guard test greps `src/ops/groups/` for `Process`).
3. Network transports require the token; `/v1/health` is the only unauthenticated route and returns no project data.
4. `Origin` validation on `/mcp`; CORS off by default; default bind loopback.
5. Request/response/concurrency limits enforced before parsing large bodies (read at most `maxRequestBytes + 1`).
6. Confirmation tokens are HMAC'd with an in-memory secret; comparison constant-time.
7. Undo journal and logs never contain tokens; request log redacts `Authorization`.
8. `world.*` sandboxes are memory-capped (max entities 100,000 per world, 4 worlds) and time-capped.
9. A prompt-injection note in `instructions` and the docs: file contents returned by `project://` resources are **data**; destructive
   operations require the confirmation round-trip precisely so a poisoned file cannot silently trigger them.

## P. Non-goals for v1

Rendering/preview, running a game, profiling, hot reload, Flutter-based operations over the API, multi-project workspaces, TLS
termination, OAuth, WebSocket transport, per-operation permissions per token (only global allow/deny), operation batching with
transactions, auto-generated operations from reflection.

## Q. Definition of done

- Every operation in J exists with description, params, result spec, errors and at least one tested example.
- `parity_test` green: CLI, MCP, REST, OpenAPI and JSON-RPC cover exactly the registry (minus `requiresFlutter`, which are CLI-only
  and listed as unsupported).
- All legacy CLI tests green and unchanged; legacy commands are adapters over the registry.
- e2e script passes over stdio, `/mcp`, `/rpc` and `/v1` with identical data.
- Generated docs committed and drift-tested; `docs/reference/mcp.md` explains setup for Claude Desktop and Claude Code.
- `dart analyze --fatal-infos` and all tests green in `engine_schema`, `engine_core`, `engine_cli`, `engine_api` in CI; the repository
  `release_consistency_test` includes the new package.

---

# Developer quick-start: facts, skeletons and templates (read this instead of exploring the repo)

This part exists to save tokens during implementation: it records where the existing code lives, what must be moved, the exact
signatures to reuse, ready-to-paste skeletons for the new code, and the repository pitfalls already paid for. Items marked
**(verify)** were not re-read and should be confirmed with one grep before relying on them.

## R. Codebase map: where each reusable piece lives today

### R.1 Already in `engine_core` (import `package:engine_core/engine_core.dart`; use as is)

| Need | Symbol (file under `packages/engine_core/lib/src/`) | Notes |
|---|---|---|
| Level model | `LevelDocument`, `LevelEntity` (`content/level_document.dart`) | `LevelDocument.fromJson(map)`, `.toJson()`, `.entities`, `.entityNamed(name)`; `LevelEntity(name:, components: Map<String,Map<String,dynamic>>)` |
| Canonical-ish JSON | `encodeLevelJson(Object?)` (`content/level_format.dart:7`) | what the editor/saver writes |
| Level validation | `LevelValidator.forSchemas(allComponentSchemas).validate(doc)` -> `List<LevelIssue>`; `LevelIssue.severity` (`IssueSeverity.error/warning`) (`validation/level_validator.dart`) | used by every edit command today |
| Raw level check | `Level.validate(json)` -> `List<Map>` entities, throws `LevelLoadException` (`content/level.dart`) | used by `lint` |
| Edit commands | `AddEntityCommand(entity,{index})`, `RemoveEntityCommand(entity)`, `SetComponentFieldCommand({entity, component, field, value})`, `SetLayerCommand({...})`, `MoveEntityCommand({entity,x,y})`, `SetTileCommand({...})`, `FillRegionCommand({...})`, `InstantiatePrefabCommand(prefab,{x,y})`, `FlattenTileMapCommand(entity)` (`command/*.dart`); all implement `EditCommand.apply(LevelDocument)` / `revert` | the 1:1 operations call these exactly like `studio_edit_commands.dart` does |
| Diff / merge | `diffLevels(before, after)` -> `LevelDiff` (`added`, `removed`, `changed`, `isEmpty`, `format()`, `toJson()`), `mergeLevels(base, ours, theirs)` -> `LevelMerge` (`content/level_diff.dart:100,188`) | |
| Prefab | `Prefab`, `Prefab.fromEntities(name, entities)`, `toJson` (`content/prefab.dart`) | |
| Brushes | `BrushLibrary` (`content/brush.dart`) | |
| Locks | `FileLock(path)`, `.inspect()`, `.acquire(owner)` -> `LockResult(acquired, holder)`, `.release(owner,{force})`, `LockInfo(owner, acquiredAt)`, `lockOwner()` (`io/file_lock.dart`; **dart:io**) | |
| Atomic file save | `AtomicSave(path).write(map)/read()` (`io/atomic_save.dart`, exported via `engine_core_io.dart`) | JSON maps only; ops need a string variant (see S.4) |
| Save codes | `SaveCodec.export/import`, `SaveMigrator` (`content/save_codec.dart`) | |
| Idle | everything via `package:engine_core/engine_core_idle.dart` (`validateIdleDefinition`, `loadIdleDefinition`, `simulateIdle`, `describeSimulation`, `bestPurchase`, `computeIncome`, ...) | |
| Numbers | `BigNumber`, `formatBigNumber(value,{style,decimals,decimalSeparator,groupSeparator})` | |
| Schemas | `allComponentSchemas` (`Map<String, ComponentSchema>`), `ComponentSchema(name, fields)` `.template` (default JSON), `FieldSchema(name,type,{min,max,options,defaultValue,required,optional})`, `FieldType {int,double,bool,string,enumeration,vector2,list,object}` (package `engine_schema`, re-exported through core; **import `package:engine_schema/engine_schema.dart` explicitly** as the CLI does) | |
| World | `World(width:, height:)`, `registerCoreComponents(world)`, `WorldSnapshot.capture/.toJson/.fromJson/.restoreInto`, `world.applyPatch`, `world.toJson()`, `world.components.register`, `world.storeOf<T>()`, `world.step(dt)`, `world.events.on/emit/flush` | for `world.*` ops |
| Graphs | `Graph`, `GraphNode`, `GraphEdge`, `GraphType {dialogue, behaviorTree, stateMachine}` (`.registry`), `NodeKind`, `GraphPort`, `PortType`, `validateGraph(graph,{registry})`, `GraphIssue`, `compile*` (`graph/*.dart`) | |
| Turn/strategy | `OrderSystem`, `TurnSystem`, `startTurnBasedGame`, `submitOrder`, `HostSession` etc. (`turn/*`, `net/*`) | |
| Localization | `LocalizationManager` (`content/localization.dart`), `StringTable` | |
| Time/random | `DeterministicRandom(seed)` (`ecs/deterministic_random.dart`) | |
| Tmx | `TmxImport`, `tileMapToTmx` (check exact names with `grep -rn "tileMapToTmx\|class TmxImport" packages/engine_core/lib`) **(verify)** | used by `studio import-tmx/export-tmx` |

### R.2 Currently in `engine_studio` (Flutter package) but **pure Dart** -> must move to `engine_core` in phase 3/5

`engine_studio` depends on Flutter, so the CLI and `engine_api` cannot import it. These files have **no Flutter imports** and move
(git mv, then fix imports; the studio re-imports them from core; their tests move with them):

| From `packages/engine_studio/lib/src/` | To `packages/engine_core/lib/src/ops/project/` | Public symbols |
|---|---|---|
| `project/studio_project.dart` | `studio_project.dart` | `StudioProject.open(path)`, `.root`, `.levelPaths()`, `.graphPaths()`, `.codeFiles()`, `.nextGraphPath()`, `ProjectOpenException` (imports `../playtest/play_test.dart` only for a constant: replace with a literal) |
| `project/project_tree.dart` | `project_tree.dart` | `ProjectEntry(relativePath,isDirectory,depth,name)`, `listProjectTree(root)`, `FileKind`, `kindOf`, `visibleTree`, `filterFiles` |
| `project/project_search.dart` | `project_search.dart` | `ProjectMatch`, `searchProject(root, entries, query)` (imports `../code/find_replace.dart`: move that tiny pure file too) |
| `project/project_problems.dart` | `project_problems.dart` | `ProjectProblem`, `ProblemSource`, `collectProjectProblems(project)` (**depends on `graph/graph_editor.dart`**, which is Flutter-tainted via `dart:ui`: extract its pure `validate()` logic into core `graph/graph_validate.dart` first, see R.4) |
| `project/git_status.dart` | `git_status.dart` | `GitChange`, `parseGitStatus`, `readGitStatus`, `runGit`, `folderHasChanges` |
| `project/pub_get.dart` | (stays Flutter-agnostic) `pub_get.dart` | `runPubGet`, `PubGetResult` |
| `assets/asset_index.dart` | `asset_index.dart` | `AssetIndex.scan(root)`, `.atlases`, `.declaredRegions`, `.atlasById`, `AtlasInfo` (imports `../textures/atlas_catalog.dart`: **verify** it is pure, it showed a flutter match = 1, probably an image decode; if it uses `dart:ui`, split the catalog JSON part out) |
| `assets/asset_references.dart` | `asset_references.dart` | `checkAssetReferences(...)` -> `List<LevelIssue>` |
| `assets/project_stores.dart` | `project_stores.dart` | `PrefabStore(root).save/load/list`, `BrushStore` |
| `code/project_symbols.dart` | `project_symbols.dart` | `ProjectSymbols.scan(root)`, `.classes/.atlasIds/.entityNames`, `completionsFor` |
| `level/level_saver.dart` | `level_saver.dart` | `LevelSaver.save(path, doc)`, `.autosave(...)` (**verify** exact methods; the studio and the new undo-aware pipeline must share one writer) |
| `inspector/entity_inspector.dart` | `entity_inspector.dart` | `EntityInspector(editor).components()` uses `LevelEditor` (Flutter-tainted): move only `ParsedField parseFieldText(FieldSchema, String)` and `InspectedComponent` |
| `code/analysis.dart` | stays in studio | analyzer output parsing; `project.analyze` is **not** in v1 (needs the Dart SDK process) |

`engine_studio` keeps thin re-export shims (`export 'package:engine_core/engine_core_ops.dart' show ...`) so studio code and its ~450 tests
change as little as possible. **Rule:** a file moves only together with its tests, in the same commit, with `flutter test` green in
`engine_studio`.

### R.3 Currently inside `engine_cli` command classes -> extract into core ops

| CLI file | Private logic to extract | Becomes |
|---|---|---|
| `studio_command.dart:226` `canonicalJson(Object?)` | the canonical JSON writer used by every studio command | `core/ops/canonical_json.dart` (also fixes duplication with `encodeLevelJson`: **verify** whether they are byte-identical; if yes keep one) |
| `studio_command.dart` `StudioValidateCommand` | project-wide level validation incl. `--strict` | `project.validate` handler |
| `studio_command.dart` import-tmx / export-levels / project-manifest classes | TMX import, canonical rewrite, manifest build | `level.import_tmx`, `level.export_canonical`, `project.manifest` |
| `studio_edit_commands.dart` | helpers `loadLevelOrNull`, `validateAndWrite`, `entityNamedOrNull`, `parseFieldValue` and each command's `run()` body | the `level.*` edit handlers (they currently print and write directly; the new handlers **return a Proposal** instead of writing) |
| `studio_diff_commands.dart` | diff/merge/lock/unlock bodies (use `diffLevels`, `mergeLevels`, `FileLock`) | `level.diff`, `level.merge`, `level.lock/unlock` |
| `studio_asset_commands.dart` | `export-tmx`, `save-prefab`, `place-prefab` bodies | `level.export_tmx`, `prefab.save`, `prefab.place` |
| `lint_command.dart` | `_checkPlayable(entities)` (pure: move to core) and `_render(entities, path)` (PNG via `package:image`) | `level.lint`. **Decision:** core contains no image code. Rendering and decoding go through an `ImageCodec` interface injected in `OpContext` (`decode(bytes)`, `resize`, `encodePng`, and a `renderTileMap(...)` helper built on them); `engine_cli` and `engine_api` each supply the same small implementation over `package:image` (about 40 lines, in `image_codec.dart` of each package). Without a codec the render/pack parts return `unsupported`. |
| `pack_assets_command.dart` (~500 lines, private `_PackItem`, `_Rect`, `_PackedSheet`) | the whole packer (rect packing is pure; decode/resize/encode use `package:image`) | `asset.pack` in core, written against the same injected `ImageCodec` (the packing algorithm moves to core as is; only the pixel calls go through the interface). |
| `release_plan.dart` |
| `release.build` | W | as plan | exit codes | **`requiresFlutter`** |
| `engine.health` / `engine.capabilities` / `engine.operations` | R | - | see I | registry |
| `engine.docs` | R | `page?:string` | list of docs pages or one page's markdown | files under `docs/` shipped with the package |
| `undo.list` / `undo.undo` / `undo.redo` | R / W / W | see E.3 | | `undo_log.dart` |

## K. Documentation generation

`engine_api docs` (and `tool/gen_docs.dart`) produces from the registry, deterministically (sorted by name):

- `docs/reference/operations.md` - one section per operation: summary, kind, scope, description, params table (type, required,
  default, constraints), result schema, errors, examples as **CLI**, **MCP tools/call**, **REST curl**, **JSON-RPC** snippets.
- `docs/reference/api/openapi.json` - OpenAPI 3.1 (`paths`: `/v1/<group>/<verb>`, shared `OpResult`/`OpError` components,
  `securitySchemes: bearer`, tags per group, `x-kind`, `x-cli`).
- `docs/reference/cli.md` - the operation-derived part is generated (marker comments `<!-- generated:ops -->`), hand-written
  sections (create/upgrade narrative) stay.
- `docs/reference/mcp.md` - tools table, resources, prompts, transport setup for Claude Desktop/Code (`claude mcp add`, JSON config
  snippet), troubleshooting.

Drift tests (like `component_docs_test.dart`): the generated files must equal the committed ones; failing prints the regenerate command.

## L. Testing specification

### L.1 Registry/unit (in `engine_core`)

- `operation_registry_test`: unique dotted names, valid pattern, every param typed, every example's `args` validate against the
  operation's own schema, every `errors` code exists in `ErrorCode`, `requiresFlutter` ops have no handler in core.
- `json_schema_test`: golden JSON Schema for each `ParamType`/`FieldType`; every component schema converts and a generated template
  validates against its own JSON Schema (property test over `allComponentSchemas`).
- `paths_test`: traversal (`../x`, absolute, NUL, `a/../../b`), symlink escape (create a symlink to a temp dir), case/dots/Windows
  separators, very long paths.
- `safety_test`: preview for destructive ops writes nothing; token verifies, becomes `confirmation_stale` after any touched file
  changes or TTL elapses (injected `Clock`), rejects a token from a different op/args; read-only blocks writes before proposals;
  lock held by another owner -> `locked` with owner; atomic write leaves the old file intact when the second file fails; undo
  journal written before the first rename; 100-entry pruning; undo then redo restores bytes; undo refuses on changed file unless
  `force`.
- One test file **per group** exercising every operation against a scratch project (copy of a fixture in `test/fixtures/project/`):
  happy path, each documented error code, `--dry-run` result, and (for writes) that the file content equals what the legacy CLI
  produced for the same inputs (golden comparison, proving the migration is behaviour-preserving).

### L.2 CLI (`engine_cli`)

- Existing ~130 tests untouched and green after phase 4 (legacy adapters).
- `ops_cli_test`: for **every** registered operation, `game_agent <group> <verb> --help` renders, a call with `--json` returns a valid
  envelope, required-param errors exit 64, destructive without `--apply` exits 78, `--stdin` merges. Generated from the registry so a
  new operation is covered automatically.

### L.3 API (`engine_api`)

- `mcp_protocol_test`: initialize/negotiation, tools/list pagination, tools/call success + `isError`, resources/templates/read,
  prompts/get rendering, ping, cancellation, unknown method, malformed JSON, batch handling over stdio and `/mcp`.
- `rest_test` / `jsonrpc_test`: status code and error mapping table B.1 (one assertion per code), auth missing/wrong/right,
  constant-time compare helper test, rate limit and size limit, `Idempotency-Key`, CORS off/on, `Origin` rejection on `/mcp`,
  `405`, `404`, OpenAPI document validity (structural) and that every path exists.
- `config_test`: file+flag precedence, unknown key error, remote bind refusal without `--allow-remote`.
- `request_log_test`: one line per call, no args by default, redaction of `secret` params at debug level, rotation.
- `docs_drift_test`: generated docs equal committed docs.
- **`parity_test` (the 1:1 rule)**: iterates `buildRegistry()`; asserts for each operation: has a CLI command name (or is in
  `legacyAliases`), and unless `requiresFlutter` also an MCP tool, a REST route, an OpenAPI path and a JSON-RPC method; asserts the
  reverse (no CLI group/verb, tool, route or method without an operation); asserts `requiresFlutter` ops are listed in
  `engine.capabilities.unsupported`; asserts allow/deny filtering hides an operation on **all** surfaces simultaneously.
- `e2e_test` (process level, runs in CI): start `engine_api mcp-stdio` as a subprocess with a scratch project; a small Dart MCP client
  performs: initialize -> tools/list (count == registry non-Flutter count) -> project.info -> level.create -> level.add_entity ->
  level.remove_entity (preview, then apply with the token) -> project.validate -> undo.undo -> idle.simulate on the sample game ->
  `world.build/step/snapshot`. Repeat the same script over HTTP (`/mcp`, `/rpc`, `/v1`) with the bearer token and assert identical
  `data` for the same operation across all four transports.

### L.4 Prompts

Each prompt file has a sibling `*.test.yaml` listing the tool calls its steps imply; the test renders the prompt, checks every tool
name it mentions exists in the registry and that the listed calls succeed against the fixture project.

## M. Build order, tasks and acceptance criteria

Each phase = one or more commits, pushed after the **package's tests and `analyze --fatal-infos` are green** (gate the commit on the
real "All tests passed" line, not on a pipe). Phases are sequential; within a phase, groups can be done in any order.

**Phase 0 - scaffolding (1 commit).** Create `packages/engine_api` (pubspec with `publish_to: none`, version 0.1.0, README/CHANGELOG/
LICENSE), `.github/workflows/engine_api.yml` (paths: engine_api, engine_core, engine_schema, engine_cli), CLAUDE.md package map
row, root README row, `docs.yml` API loop entry, mkdocs nav placeholder, `release_consistency_test` passes (it picks the package up
automatically: same version, `publish_to: none`, LICENSE/README/CHANGELOG). *Accept:* CI green with an empty `lib/engine_api.dart`.

**Phase 1 - registry core (2-3 commits).** `operation.dart`, `param.dart`, `result.dart`, `context.dart`, `registry.dart`,
`json_schema.dart`, `paths.dart`, error taxonomy, dispatcher (`registry.call(name, args, ctx)`: validate -> handler -> envelope ->
duration), `engine.*` operations as the first (trivial) operations. *Accept:* L.1 registry/json_schema/paths tests green; `engine.operations`
works through the dispatcher.

**Phase 2 - write safety (2 commits).** `safety.dart`, `undo_log.dart`, change sets, tokens, locks, read-only, allow/deny. Tested with a
**fake operation** that proposes file changes. *Accept:* `safety_test` complete (all cases in L.1).

**Phase 3 - move existing read operations (2 commits).** `project.validate`, `level.lint`, `level.diff`, `idle.validate`,
`idle.simulate`, `asset.pack`, `release.plan` etc. into groups; legacy commands call the registry. *Accept:* all old CLI tests green; the
new per-group tests green; `ops_cli` generates the commands for these.

**Phase 4 - move existing write operations (3 commits).** `level.add_entity ... fill_region`, `level.import/export_tmx`,
`level.export_canonical`, `level.lock/unlock`, `level.merge`, `prefab.save/place`, `project.manifest`. Handlers return Proposals;
legacy commands become adapters; golden comparisons prove identical files. *Accept:* old tests green; every legacy command has an
operation; legacy files reduced.

**Phase 5 - new operations (one commit per group).** `project.*` extras, `level.read/list/validate/create/add_component/remove_component`,
`graph.*`, `schema.*`, `i18n.*`, `save.*`, `strategy.*`, `idle.state/best_purchase/format_number`, `engine.docs`, `world.*`, `undo.*`.
Each with CLI binding (automatic), tests (L.1/L.2), doc examples. *Accept:* `parity_test` skeleton in core lists no operation without a CLI
command.

**Phase 6 - engine_api server (4 commits).** (a) config, auth, limits, request log; (b) MCP protocol + stdio + tools; (c) resources +
prompts; (d) HTTP: `/mcp`, REST, JSON-RPC, OpenAPI. *Accept:* L.3 tests green except e2e/parity/docs.

**Phase 7 - parity, docs, e2e (2 commits).** `parity_test`, `docs_drift_test`, generator, `e2e_test`, generated references committed,
`docs/reference/mcp.md` and a tutorial "Drive the engine from Claude" (executed by the e2e script). *Accept:* all engine_api tests green in CI.

**Phase 8 - release plumbing (1 commit).** CHANGELOG entries per phase, `docs/engine-releasing.md` mention, README badges row,
`engine_mcp.md` marked **Implemented** with a link to the generated reference, TODO.md entry closed.

## N. Operational details and edge cases

- **Determinism:** operations with randomness take an explicit `seed:int` (default 1) and use `DeterministicRandom`; the request log
  records it. `idle.simulate`, `world.step` and `strategy.simulate_turns` are reproducible from their args.
- **Time:** every handler gets time only from `OpContext.clock`; tests inject a fixed clock; the determinism guard test
  (`idle_determinism_test` style) is extended to `src/ops/` forbidding `DateTime.now()` outside `context.dart`.
- **Long-running operations:** none in v1 (Flutter exclusions). Every handler must finish within `limits.maxOperationSeconds` (default
  30); the dispatcher enforces it with a timeout (`internal` + `details.timeout`) and, for `world.step`, a cap on ticks per call (10,000).
- **Result size:** `level.read` of a huge level pages with `entityOffset/entityLimit`; `project.tree`, `project.search`, `undo.list` take
  `limit`. Streams are not used in v1.
- **Encoding:** all files UTF-8; levels written with `canonicalJson` (sorted keys, 2-space indent) exactly like the CLI does; CRLF in
  input is accepted and normalized to LF on write (documented).
- **Windows:** path separator normalization in `paths.dart`; lock file and token permission handling are best-effort; stdio MCP reads
  in binary-safe UTF-8.
- **Secrets:** no operation returns environment variables, signing keys or keystore passwords; `release.plan` redacts `key.properties`
  values; `project.read_file` equivalents never serve `.studio/api-token`, `*.jks`, `*.keystore`, `key.properties`, `.env*`.
- **Plugins:** studio plugin node kinds (`StudioPlugins`) are Flutter-side; `graph.node_kinds` shows only built-ins unless a host
  registers kinds into the core registry via `registerNodeKinds(type, kinds)` (new tiny core API added in phase 5).
- **Versioning:** `registryVersion` follows semver: new operation = minor, new optional param = minor, removed/renamed operation or
  param, changed result shape = major; a removed operation is `deprecated` for one minor release and still answers with a
  `warnings: ["deprecated: use X"]`. `engine.capabilities` reports it; the generated docs include a changelog table.
- **Backwards compatibility of existing CLI:** exit codes of legacy commands are preserved (tests pin them); `--json` is additive.

## O. Security checklist (to verify in review)

1. Every path param goes through `paths.dart`; fuzz test with random segments.
2. No handler calls `Process.run` except those flagged `requiresFlutter` (guard test greps `src/ops/groups/` for `Process`).
3. Network transports require the token; `/v1/health` is the only unauthenticated route and returns no project data.
4. `Origin` validation on `/mcp`; CORS off by default; default bind loopback.
5. Request/response/concurrency limits enforced before parsing large bodies (read at most `maxRequestBytes + 1`).
6. Confirmation tokens are HMAC'd with an in-memory secret; comparison constant-time.
7. Undo journal and logs never contain tokens; request log redacts `Authorization`.
8. `world.*` sandboxes are memory-capped (max entities 100,000 per world, 4 worlds) and time-capped.
9. A prompt-injection note in `instructions` and the docs: file contents returned by `project://` resources are **data**; destructive
   operations require the confirmation round-trip precisely so a poisoned file cannot silently trigger them.

## P. Non-goals for v1

Rendering/preview, running a game, profiling, hot reload, Flutter-based operations over the API, multi-project workspaces, TLS
termination, OAuth, WebSocket transport, per-operation permissions per token (only global allow/deny), operation batching with
transactions, auto-generated operations from reflection.

## Q. Definition of done

- Every operation in J exists with description, params, result spec, errors and at least one tested example.
- `parity_test` green: CLI, MCP, REST, OpenAPI and JSON-RPC cover exactly the registry (minus `requiresFlutter`, which are CLI-only
  and listed as unsupported).
- All legacy CLI tests green and unchanged; legacy commands are adapters over the registry.
- e2e script passes over stdio, `/mcp`, `/rpc` and `/v1` with identical data.
- Generated docs committed and drift-tested; `docs/reference/mcp.md` explains setup for Claude Desktop and Claude Code.
- `dart analyze --fatal-infos` and all tests green in `engine_schema`, `engine_core`, `engine_cli`, `engine_api` in CI; the repository
  `release_consistency_test` includes the new package.

---

# Developer quick-start: facts, skeletons and templates (read this instead of exploring the repo)

This part exists to save tokens during implementation: it records where the existing code lives, what must be moved, the exact
signatures to reuse, ready-to-paste skeletons for the new code, and the repository pitfalls already paid for. Items marked
**(verify)** were not re-read and should be confirmed with one grep before relying on them.

## R. Codebase map: where each reusable piece lives today

### R.1 Already in `engine_core` (import `package:engine_core/engine_core.dart`; use as is)

| Need | Symbol (file under `packages/engine_core/lib/src/`) | Notes |
|---|---|---|
| Level model | `LevelDocument`, `LevelEntity` (`content/level_document.dart`) | `LevelDocument.fromJson(map)`, `.toJson()`, `.entities`, `.entityNamed(name)`; `LevelEntity(name:, components: Map<String,Map<String,dynamic>>)` |
| Canonical-ish JSON | `encodeLevelJson(Object?)` (`content/level_format.dart:7`) | what the editor/saver writes |
| Level validation | `LevelValidator.forSchemas(allComponentSchemas).validate(doc)` -> `List<LevelIssue>`; `LevelIssue.severity` (`IssueSeverity.error/warning`) (`validation/level_validator.dart`) | used by every edit command today |
| Raw level check | `Level.validate(json)` -> `List<Map>` entities, throws `LevelLoadException` (`content/level.dart`) | used by `lint` |
| Edit commands | `AddEntityCommand(entity,{index})`, `RemoveEntityCommand(entity)`, `SetComponentFieldCommand({entity, component, field, value})`, `SetLayerCommand({...})`, `MoveEntityCommand({entity,x,y})`, `SetTileCommand({...})`, `FillRegionCommand({...})`, `InstantiatePrefabCommand(prefab,{x,y})`, `FlattenTileMapCommand(entity)` (`command/*.dart`); all implement `EditCommand.apply(LevelDocument)` / `revert` | the 1:1 operations call these exactly like `studio_edit_commands.dart` does |
| Diff / merge | `diffLevels(before, after)` -> `LevelDiff` (`added`, `removed`, `changed`, `isEmpty`, `format()`, `toJson()`), `mergeLevels(base, ours, theirs)` -> `LevelMerge` (`content/level_diff.dart:100,188`) | |
| Prefab | `Prefab`, `Prefab.fromEntities(name, entities)`, `toJson` (`content/prefab.dart`) | |
| Brushes | `BrushLibrary` (`content/brush.dart`) | |
| Locks | `FileLock(path)`, `.inspect()`, `.acquire(owner)` -> `LockResult(acquired, holder)`, `.release(owner,{force})`, `LockInfo(owner, acquiredAt)`, `lockOwner()` (`io/file_lock.dart`; **dart:io**) | |
| Atomic file save | `AtomicSave(path).write(map)/read()` (`io/atomic_save.dart`, exported via `engine_core_io.dart`) | JSON maps only; ops need a string variant (see S.4) |
| Save codes | `SaveCodec.export/import`, `SaveMigrator` (`content/save_codec.dart`) | |
| Idle | everything via `package:engine_core/engine_core_idle.dart` (`validateIdleDefinition`, `loadIdleDefinition`, `simulateIdle`, `describeSimulation`, `bestPurchase`, `computeIncome`, ...) | |
| Numbers | `BigNumber`, `formatBigNumber(value,{style,decimals,decimalSeparator,groupSeparator})` | |
| Schemas | `allComponentSchemas` (`Map<String, ComponentSchema>`), `ComponentSchema(name, fields)` `.template` (default JSON), `FieldSchema(name,type,{min,max,options,defaultValue,required,optional})`, `FieldType {int,double,bool,string,enumeration,vector2,list,object}` (package `engine_schema`, re-exported through core; **import `package:engine_schema/engine_schema.dart` explicitly** as the CLI does) | |
| World | `World(width:, height:)`, `registerCoreComponents(world)`, `WorldSnapshot.capture/.toJson/.fromJson/.restoreInto`, `world.applyPatch`, `world.toJson()`, `world.components.register`, `world.storeOf<T>()`, `world.step(dt)`, `world.events.on/emit/flush` | for `world.*` ops |
| Graphs | `Graph`, `GraphNode`, `GraphEdge`, `GraphType {dialogue, behaviorTree, stateMachine}` (`.registry`), `NodeKind`, `GraphPort`, `PortType`, `validateGraph(graph,{registry})`, `GraphIssue`, `compile*` (`graph/*.dart`) | |
| Turn/strategy | `OrderSystem`, `TurnSystem`, `startTurnBasedGame`, `submitOrder`, `HostSession` etc. (`turn/*`, `net/*`) | |
| Localization | `LocalizationManager` (`content/localization.dart`), `StringTable` | |
| Time/random | `DeterministicRandom(seed)` (`ecs/deterministic_random.dart`) | |
| Tmx | `TmxImport`, `tileMapToTmx` (check exact names with `grep -rn "tileMapToTmx\|class TmxImport" packages/engine_core/lib`) **(verify)** | used by `studio import-tmx/export-tmx` |

### R.2 Currently in `engine_studio` (Flutter package) but **pure Dart** -> must move to `engine_core` in phase 3/5

`engine_studio` depends on Flutter, so the CLI and `engine_api` cannot import it. These files have **no Flutter imports** and move
(git mv, then fix imports; the studio re-imports them from core; their tests move with them):

| From `packages/engine_studio/lib/src/` | To `packages/engine_core/lib/src/ops/project/` | Public symbols |
|---|---|---|
| `project/studio_project.dart` | `studio_project.dart` | `StudioProject.open(path)`, `.root`, `.levelPaths()`, `.graphPaths()`, `.codeFiles()`, `.nextGraphPath()`, `ProjectOpenException` (imports `../playtest/play_test.dart` only for a constant: replace with a literal) |
| `project/project_tree.dart` | `project_tree.dart` | `ProjectEntry(relativePath,isDirectory,depth,name)`, `listProjectTree(root)`, `FileKind`, `kindOf`, `visibleTree`, `filterFiles` |
| `project/project_search.dart` | `project_search.dart` | `ProjectMatch`, `searchProject(root, entries, query)` (imports `../code/find_replace.dart`: move that tiny pure file too) |
| `project/project_problems.dart` | `project_problems.dart` | `ProjectProblem`, `ProblemSource`, `collectProjectProblems(project)` (**depends on `graph/graph_editor.dart`**, which is Flutter-tainted via `dart:ui`: extract its pure `validate()` logic into core `graph/graph_validate.dart` first, see R.4) |
| `project/git_status.dart` | `git_status.dart` | `GitChange`, `parseGitStatus`, `readGitStatus`, `runGit`, `folderHasChanges` |
| `project/pub_get.dart` | (stays Flutter-agnostic) `pub_get.dart` | `runPubGet`, `PubGetResult` |
| `assets/asset_index.dart` | `asset_index.dart` | `AssetIndex.scan(root)`, `.atlases`, `.declaredRegions`, `.atlasById`, `AtlasInfo` (imports `../textures/atlas_catalog.dart`: **verify** it is pure, it showed a flutter match = 1, probably an image decode; if it uses `dart:ui`, split the catalog JSON part out) |
| `assets/asset_references.dart` | `asset_references.dart` | `checkAssetReferences(...)` -> `List<LevelIssue>` |
| `assets/project_stores.dart` | `project_stores.dart` | `PrefabStore(root).save/load/list`, `BrushStore` |
| `code/project_symbols.dart` | `project_symbols.dart` | `ProjectSymbols.scan(root)`, `.classes/.atlasIds/.entityNames`, `completionsFor` |
| `level/level_saver.dart` | `level_saver.dart` | `LevelSaver.save(path, doc)`, `.autosave(...)` (**verify** exact methods; the studio and the new undo-aware pipeline must share one writer) |
| `inspector/entity_inspector.dart` | `entity_inspector.dart` | `EntityInspector(editor).components()` uses `LevelEditor` (Flutter-tainted): move only `ParsedField parseFieldText(FieldSchema, String)` and `InspectedComponent` |
| `code/analysis.dart` | stays in studio | analyzer output parsing; `project.analyze` is **not** in v1 (needs the Dart SDK process) |

`engine_studio` keeps thin re-export shims (`export 'package:engine_core/engine_core_ops.dart' show ...`) so studio code and its ~450 tests
change as little as possible. **Rule:** a file moves only together with its tests, in the same commit, with `flutter test` green in
`engine_studio`.

### R.3 Currently inside `engine_cli` command classes -> extract into core ops

| CLI file | Private logic to extract | Becomes |
|---|---|---|
| `studio_command.dart:226` `canonicalJson(Object?)` | the canonical JSON writer used by every studio command | `core/ops/canonical_json.dart` (also fixes duplication with `encodeLevelJson`: **verify** whether they are byte-identical; if yes keep one) |
| `studio_command.dart` `StudioValidateCommand` | project-wide level validation incl. `--strict` | `project.validate` handler |
| `studio_command.dart` import-tmx / export-levels / project-manifest classes | TMX import, canonical rewrite, manifest build | `level.import_tmx`, `level.export_canonical`, `project.manifest` |
| `studio_edit_commands.dart` | helpers `loadLevelOrNull`, `validateAndWrite`, `entityNamedOrNull`, `parseFieldValue` and each command's `run()` body | the `level.*` edit handlers (they currently print and write directly; the new handlers **return a Proposal** instead of writing) |
| `studio_diff_commands.dart` | diff/merge/lock/unlock bodies (use `diffLevels`, `mergeLevels`, `FileLock`) | `level.diff`, `level.merge`, `level.lock/unlock` |
| `studio_asset_commands.dart` | `export-tmx`, `save-prefab`, `place-prefab` bodies | `level.export_tmx`, `prefab.save`, `prefab.place` |
| `lint_command.dart` | `_checkPlayable(entities)` (pure: move to core) and `_render(entities, path)` (PNG via `package:image`) | `level.lint`. **Decision:** core contains no image code. Rendering and decoding go through an `ImageCodec` interface injected in `OpContext` (`decode(bytes)`, `resize`, `encodePng`, and a `renderTileMap(...)` helper built on them); `engine_cli` and `engine_api` each supply the same small implementation over `package:image` (about 40 lines, in `image_codec.dart` of each package). Without a codec the render/pack parts return `unsupported`. |
| `pack_assets_command.dart` (~500 lines, private `_PackItem`, `_Rect`, `_PackedSheet`) | the whole packer | `asset.pack`; **needs `package:image`** for decode/resize/encode: so `asset.pack` is the **one** operation implemented in `engine_cli` and `engine_api` via an injected `ImageCodec` interface in `OpContext` (`decode(bytes)`, `encodePng`, `resize`), with the implementation in a new tiny package-internal file `engine_api/lib/src/image_codec.dart` and `engine_cli/lib/src/image_codec.dart` (each wraps `package:image`). Registry-wise it stays a normal operation; if no codec is in the context it returns `unsupported`. |
| `release_plan.dart` | `planAndroid(...)`, `planIos(...)`, `ReleasePlan`, `automaticExportOptions` (already pure functions) | `release.plan` handler (move file to core as is; pure) |
| `idle_command.dart` | `SimulateCommand.run`, `ValidateIdleCommand.run` bodies | `idle.simulate`, `idle.validate` |
| `create_command.dart`, `upgrade_command.dart`, `build_release_command.dart`, `template.dart`, `process_utils.dart` | process-running code | stay in `engine_cli` as `requiresFlutter` handlers registered into the registry at CLI start-up |

### R.4 Studio graph code

`engine_studio/lib/src/graph/graph_editor.dart` mixes pure graph editing (add/remove node, connect with port-type check, params,
`validate()`, `compile()`) with `dart:ui` types (`Offset` positions). Extract a pure `GraphModel`/`GraphEditorCore` into
`engine_core/lib/src/graph/graph_edit.dart` using plain `double x, y` for positions; `GraphEditor` in the studio wraps it and converts to
`Offset`. The `graph.*` write operations call the core class. **(verify)** the exact method names with
`grep -n "^  [A-Za-z<>?]* [a-z][A-Za-z]*(" packages/engine_studio/lib/src/graph/graph_editor.dart` before writing the handlers.

## S. Code skeletons (paste, then fill)

### S.1 `packages/engine_core/lib/src/ops/operation.dart`

```dart
import 'dart:async';

import 'context.dart';
import 'param.dart';
import 'result.dart';

enum OperationKind { read, write, destructive }
enum OperationScope { pure, project }

typedef OpHandler = FutureOr<OpOutcome> Function(OpContext ctx, Map<String, Object?> args);

class Example {
  const Example(this.title, this.args, {this.expect});
  final String title;
  final Map<String, Object?> args;
  /// Subset of the result `data` the example must produce (checked by the registry test against the fixture project).
  final Map<String, Object?>? expect;
}

class Deprecation {
  const Deprecation({required this.since, required this.removeIn, this.replacement});
  final String since, removeIn;
  final String? replacement;
}

class CliHints {
  const CliHints({this.group, this.verb, this.legacy = const []});
  final String? group, verb;            // default: split the dotted name, underscores -> hyphens
  final List<String> legacy;            // e.g. ['studio add-entity'] (space-separated command path)
}

class Operation {
  const Operation({
    required this.name,
    required this.summary,
    required this.description,
    required this.kind,
    required this.scope,
    required this.handler,
    this.params = const [],
    this.result = const ResultSpec.any(),
    this.errors = const {},             // ErrorCode -> one-sentence meaning
    this.examples = const [],
    this.requiresFlutter = false,
    this.idempotent = false,
    this.since = '0.1.0',
    this.deprecated,
    this.cli = const CliHints(),
  });
  final String name, summary, description, since;
  final OperationKind kind;
  final OperationScope scope;
  final OpHandler handler;
  final List<Param> params;
  final ResultSpec result;
  final Map<ErrorCode, String> errors;
  final List<Example> examples;
  final bool requiresFlutter, idempotent;
  final Deprecation? deprecated;
  final CliHints cli;

  String get group => name.split('.').first;
  String get verb => name.split('.').last;
}
```

`OpOutcome` is what a handler returns: `OpOutcome.data(Object? data, {warnings})` for reads, or `OpOutcome.proposal(Proposal p, {data})`
for writes (E.1). Throw `OpError(code, message, {details, hint})` for failures.

### S.2 Dispatcher (the only place that validates, logs, times and enforces policy)

```dart
class OperationRegistry {
  OperationRegistry(Iterable<Operation> ops, {this.version = '0.1.0'})
      : _byName = {for (final o in ops) o.name: o};
  final String version;
  final Map<String, Operation> _byName;
  Iterable<Operation> get all => _byName.values;
  Operation? lookup(String name) => _byName[name];

  Future<OpResult> call(String name, Map<String, Object?> rawArgs, OpContext ctx) async {
    final sw = Stopwatch()..start();
    try {
      final op = _byName[name];
      if (op == null) throw OpError(ErrorCode.unknownOperation, 'No operation "$name".', hint: 'List them with engine.operations.');
      ctx.policy.check(op, ctx);                                   // allow/deny, read-only (kind != read), flutter flag
      final args = ParamValidator(op).coerce(rawArgs);            // types, ranges, unknown keys -> invalid_params
      if (op.scope == OperationScope.project && ctx.project == null) {
        throw OpError(ErrorCode.notFound, 'No project is open.', hint: 'Call project.open first.');
      }
      final outcome = await ctx.serialize(op, () async => op.handler(ctx, args)); // write ops under the project mutex
      final result = await ctx.safety.finish(op, args, outcome, ctx);             // preview/confirm/apply/undo (E.1-E.3)
      return result.withDuration(sw.elapsedMilliseconds);
    } on OpError catch (e) {
      return OpResult.failure(e, durationMs: sw.elapsedMilliseconds);
    } catch (e, st) {
      ctx.log('internal error in $name: $e\n$st');
      return OpResult.failure(OpError(ErrorCode.internal, 'Internal error.'), durationMs: sw.elapsedMilliseconds);
    }
  }
}
```

### S.3 Worked example: `level.add_entity` (the pattern every write op follows)

```dart
final levelAddEntity = Operation(
  name: 'level.add_entity',
  summary: 'Add an entity (optionally with components at their default values) to a level.',
  description: 'Adds one entity. Each name in `components` starts at the schema defaults (the same values the studio '
      'palette uses); `values` overrides fields per component. The result must still validate or nothing is written.',
  kind: OperationKind.write,
  scope: OperationScope.project,
  params: [
    Param('path', ParamType.path, required: true, positional: true, description: 'Level file, e.g. assets/levels/level1.json'),
    Param('name', ParamType.string, description: 'Entity name (unique names make later edits easier).'),
    Param('components', ParamType.array, items: Param.string(), cliFlag: 'component', description: 'Component names to add.'),
    Param('index', ParamType.integer, min: 0, description: 'Insert position; default end.'),
    Param('values', ParamType.object, description: 'Per-component field overrides: {"position": {"x": 3}}.'),
  ],
  errors: {
    ErrorCode.notFound: 'The level file does not exist.',
    ErrorCode.validationFailed: 'The level would become invalid (details.problems).',
    ErrorCode.locked: 'Someone holds the level lock (details.owner).',
  },
  examples: [
    Example('Add a coin', {'path': 'assets/levels/level1.json', 'name': 'coin_1', 'components': ['position'], 'values': {'position': {'x': 64, 'y': 32}}}),
  ],
  cli: CliHints(legacy: ['studio add-entity']),
  handler: (ctx, a) {
    final file = ctx.project!.resolve(a['path']! as String);        // sandboxed path
    final before = ctx.files.read(file);                              // String? (null = missing)
    if (before == null) throw OpError(ErrorCode.notFound, 'No level at ${a['path']}.');
    final doc = LevelDocument.fromJson(jsonDecode(before) as Map<String, dynamic>);
    final components = <String, Map<String, dynamic>>{};
    for (final c in (a['components'] as List?)?.cast<String>() ?? const []) {
      final schema = allComponentSchemas[c] ?? (throw OpError(ErrorCode.invalidParams, 'Unknown component "$c".'));
      components[c] = Map<String, dynamic>.of(schema.template);
    }
    ((a['values'] as Map?) ?? const {}).forEach((c, v) => components.putIfAbsent(c as String, () => {}).addAll((v as Map).cast()));
    final entity = LevelEntity(name: a['name'] as String?, components: components);
    AddEntityCommand(entity, index: a['index'] as int?).apply(doc);
    return OpOutcome.proposal(
      Proposal([FileChange(path: a['path']! as String, before: before, after: canonicalJson(doc.toJson()))]),
      data: {'index': doc.entities.indexOf(entity), 'entity': entity.name},
    );
  },
);
```

Every other write operation differs only in how it builds `after`. Reads return `OpOutcome.data(...)`.

### S.4 File access abstraction (makes core ops testable without disk)

```dart
abstract class ProjectFiles {            // implemented by DiskFiles (dart:io) and MemoryFiles (tests)
  String? read(String absolutePath);
  List<String> list(String absoluteDir, {bool recursive});
  bool exists(String absolutePath);
  void writeAtomic(String absolutePath, String content);   // temp file + rename
  void delete(String absolutePath);
}
```
`OpContext.files` is a `ProjectFiles`. `MemoryFiles` makes the per-operation tests fast and lets the web build of `engine_core` keep
compiling (the disk implementation lives in `ops/disk_files.dart`, imported only by `engine_core_ops.dart`; if `engine_core_ops.dart`
must also compile for web, put it behind a conditional import, but v1 targets the VM only).

### S.5 CLI binding core (`engine_cli/lib/src/ops_cli.dart`)

```dart
List<Command<int>> buildOpCommands(OperationRegistry registry, OpContext Function(ArgResults) makeCtx) {
  final groups = <String, _GroupCommand>{};
  for (final op in registry.all) {
    groups.putIfAbsent(op.group, () => _GroupCommand(op.group)).addSubcommand(_OpCommand(op, registry, makeCtx));
  }
  return groups.values.toList();
}

class _OpCommand extends Command<int> {
  _OpCommand(this.op, this.registry, this.makeCtx) {
    for (final p in op.params.where((p) => !p.positional)) { addParamOption(argParser, p); }   // flag per param (S.6)
    argParser..addFlag('json', negatable: false)..addFlag('dry-run', negatable: false)..addFlag('apply', negatable: false)
             ..addFlag('yes', negatable: false)..addOption('confirmation')..addFlag('stdin', negatable: false)..addOption('args');
  }
  @override String get name => op.cli.verb ?? op.verb.replaceAll('_', '-');
  @override String get description => op.summary;
  @override String get invocation => '${runner!.executableName} ${op.group} $name ${op.params.where((p) => p.positional).map((p) => '<${p.name}>').join(' ')}';
  @override Future<int> run() async {
    final args = await collectArgs(op, argResults!);                  // flags + positionals + --args + --stdin (flags win)
    final result = await registry.call(op.name, args, makeCtx(argResults!));
    return renderAndExit(op, result, json: argResults!['json'] as bool, yes: argResults!['yes'] as bool);
  }
}
```

`renderAndExit` prints text via `ops_cli_format.dart` (a `Map<String, String Function(OpResult)>` keyed by operation name; default pretty
JSON), maps `ErrorCode -> exit code` from B.1, and for a destructive preview prints the diff plus "run again with --apply" then exits 78.

### S.6 Param -> CLI option rules (`addParamOption`)

`boolean` -> `addFlag(name, negatable: true)`; `array` -> `addMultiOption(cliFlag ?? name)`; `enumeration` -> `addOption(name, allowed: options)`;
others -> `addOption(name, abbr: cliAbbr, defaultsTo: defaultValue?.toString(), help: description)`. Coercion back to typed values uses the
same `ParamValidator` as the API (`'3'` -> 3; `json` params go through `parseFieldValue`).

### S.7 MCP dispatch core (`engine_api/lib/src/mcp/tools.dart`)

```dart
Map<String, Object?> toolFor(Operation op, Policy policy) => {
  'name': op.name,
  'title': op.summary,
  'description': renderToolDescription(op),          // summary + description + Kind line + examples + error codes (G.2)
  'inputSchema': inputSchemaFor(op),                 // C converter + implicit apply/confirmation for writes
  'annotations': {
    'readOnlyHint': op.kind == OperationKind.read,
    'destructiveHint': op.kind == OperationKind.destructive,
    'idempotentHint': op.idempotent,
    'openWorldHint': false,
  },
};

Future<Map<String, Object?>> callTool(OperationRegistry reg, OpContext ctx, String name, Map<String, Object?> args) async {
  final r = await reg.call(name, args, ctx);
  return {
    'content': [{'type': 'text', 'text': const JsonEncoder.withIndent('  ').convert(r.toJson())}],
    'structuredContent': r.toJson(),
    'isError': !r.ok,
  };
}
```

### S.8 Minimal JSON-RPC server loop (shared by stdio and HTTP)

```dart
Future<Object?> handleRpc(Object? message, McpSession s) async {          // message: Map or List (batch)
  if (message is List) return [for (final m in message) await handleRpc(m, s)].where((r) => r != null).toList();
  if (message is! Map) return rpcError(null, -32600, 'Invalid Request');
  final id = message['id'], method = message['method'], params = (message['params'] as Map?)?.cast<String, Object?>() ?? {};
  try {
    final result = await s.dispatch(method as String, params);            // switch on method (G.1); throws RpcException(code, message)
    return id == null ? null : {'jsonrpc': '2.0', 'id': id, 'result': result};   // notification -> no reply
  } on RpcException catch (e) {
    return id == null ? null : rpcError(id, e.code, e.message, e.data);
  }
}
```

stdio: `stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) async { final r = await handleRpc(jsonDecode(line), s); if (r != null) stdout.writeln(jsonEncode(r)); });`.

### S.9 Safety pipeline core (`safety.dart`), pseudo-Dart

```dart
Future<OpResult> finish(Operation op, Map args, OpOutcome out, OpContext ctx) async {
  if (out is! ProposalOutcome) return OpResult.ok(out.data, warnings: out.warnings);
  final p = out.proposal;
  _validate(p);                                          // LevelValidator / graph / prefab by file kind -> validation_failed
  for (final c in p.changes) { ctx.locks.ensureFree(c.path); }       // -> locked
  final diff = diffFor(p);                               // LevelDiff for levels, text summary otherwise
  final wantsApply = args['apply'] == true || args['confirmation'] != null || (op.kind == OperationKind.write && args['apply'] != false);
  if (op.kind == OperationKind.destructive) {
    if (args['confirmation'] != null) tokens.verify(args['confirmation'] as String, op, args, p);      // stale/invalid
    else return OpResult.ok({'preview': true, 'summary': p.summary, 'diff': diff.toJson(), 'confirmation': tokens.issue(op, args, p)}, ...);
  } else if (!wantsApply) { return OpResult.ok({'preview': true, 'diff': diff.toJson()}); }
  final undoId = ctx.undo!.record(op, args, p);          // journal BEFORE the first rename
  for (final c in p.changes) { ctx.files.writeAtomic(ctx.project!.resolve(c.path), c.after!); }
  return OpResult.ok(out.data, diff: diff, undoId: undoId);
}
```

(`readOnly` and allow/deny are enforced earlier in `policy.check`; `world.*` ops return plain data outcomes and never reach this code.)

## T. Test templates and fixtures

### T.1 Fixture project (`packages/engine_core/test/fixtures/ops_project/`, copied to a temp dir per test)

```
pubspec.yaml                      # name: ops_demo\nenvironment: {sdk: ^3.9.0}\n
assets/levels/level1.json         # entities: ground(tileMap 14x8 + position), player(position), coin_1(position)
assets/levels/empty.json          # {"entities": []}
assets/prefabs/                   # empty
graphs/graph1.json                # tiny dialogue graph (say -> end)
lib/main.dart                     # class Hero {}
assets/idle_game.json             # copy of packages/engine_idle/example/cookie_clicker.json
```

Helper `Future<OpContext> scratchContext({bool readOnly = false, FakeClock? clock})` copies the fixture into `Directory.systemTemp`, returns a
context bound to it (and registers `addTearDown` cleanup). **All** per-operation tests start with it.

### T.2 Per-operation test pattern (generated list + hand cases)

```dart
void main() {
  final registry = buildRegistry();
  group('every operation example runs', () {
    for (final op in registry.all.where((o) => !o.requiresFlutter)) {
      for (final ex in op.examples) {
        test('${op.name}: ${ex.title}', () async {
          final ctx = await scratchContext();
          final r = await registry.call(op.name, ex.args, ctx);
          expect(r.ok, isTrue, reason: r.error?.message);
          if (ex.expect != null) expect(r.data, containsPair(...));   // subset match helper
        });
      }
    }
  });
  group('level.add_entity', () {
    test('adds and validates', ...);                       // read file back, compare to legacy CLI output (golden)
    test('invalid component -> invalid_params', ...);
    test('would-be-invalid result -> validation_failed and file untouched', ...);
    test('locked -> locked with owner', ...);
    test('read-only -> read_only', ...);
    test('dry run writes nothing', ...);
    test('undo restores bytes', ...);
  });
}
```

### T.3 Golden comparison with the legacy CLI (proves behaviour is preserved during phase 3/4)

For each migrated command, a test runs the **legacy** command (already exercised by `runStudio([...])` in
`packages/engine_cli/test/support/run_studio.dart`) and the new operation on two copies of the same level and asserts the resulting files are
byte-identical. Delete the golden test only when the legacy command is removed.

### T.4 Parity test skeleton (`engine_api/test/parity_test.dart`)

```dart
test('registry, CLI, MCP, REST, OpenAPI and JSON-RPC cover the same operations', () {
  final reg = buildRegistry();
  final ops = {for (final o in reg.all) o.name: o};
  final flutterOnly = {for (final o in reg.all) if (o.requiresFlutter) o.name};
  final cli = cliOperationNames(buildOpCommands(reg, ...));               // walk Command tree -> 'group.verb' (hyphens -> underscores)
  expect(cli..removeAll(legacyAliasNames), equals(ops.keys.toSet()));
  final served = ops.keys.toSet().difference(flutterOnly);
  expect(mcpToolNames(reg), served);
  expect(restRoutes(reg).map(routeToName).toSet(), served);
  expect(openApiPaths(reg).map(pathToName).toSet(), served);
  expect(rpcMethods(reg), served);
});
```

## U. Files to create verbatim

### U.1 `packages/engine_api/pubspec.yaml`

```yaml
name: engine_api
description: MCP server and HTTP/JSON-RPC API for the engine: every studio command, engine function and project function as one operation.
version: 0.1.0
publish_to: none
homepage: https://github.com/arashrasoulzadeh/agentic-game-engine
repository: https://github.com/arashrasoulzadeh/agentic-game-engine

environment:
  sdk: ^3.9.0

dependencies:
  args: ^2.5.0
  path: ^1.9.0
  yaml: ^3.1.2
  crypto: ^3.0.3
  image: ^4.7.0              # image codec for asset.pack / level.lint render (same version as engine_cli)
  engine_schema:
    git:
      url: https://github.com/arashrasoulzadeh/agentic-game-engine.git
      path: packages/engine_schema
      ref: main
  engine_core:
    git:
      url: https://github.com/arashrasoulzadeh/agentic-game-engine.git
      path: packages/engine_core
      ref: main

dev_dependencies:
  test: ^1.25.0
  lints: ^5.0.0

executables:
  engine_api: engine_api
```

plus `pubspec_overrides.yaml` (gitignored-safe, local development; copy the pattern from `packages/engine_cli/pubspec_overrides.yaml`):

```yaml
dependency_overrides:
  engine_schema:
    path: ../engine_schema
  engine_core:
    path: ../engine_core
```

(`engine_core` is already declared with the self-referencing git dependency pattern described in CLAUDE.md; follow the same comment block.)

### U.2 `.github/workflows/engine_api.yml`

```yaml
name: engine_api
on:
  push:
    branches: [main]
    paths: ['packages/engine_api/**', 'packages/engine_core/**', 'packages/engine_schema/**', 'packages/engine_cli/**', '.github/workflows/engine_api.yml']
  pull_request:
    paths: ['packages/engine_api/**', 'packages/engine_core/**', 'packages/engine_schema/**', 'packages/engine_cli/**', '.github/workflows/engine_api.yml']
jobs:
  test:
    runs-on: ubuntu-latest
    defaults: { run: { working-directory: packages/engine_api } }
    steps:
      - uses: actions/checkout@v7
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      - run: dart analyze --fatal-infos
      - run: dart test
```

Also add `engine_api` to the `paths` of `engine_core.yml` consumers only if needed; add `packages/engine_core/**` changes to `engine_cli.yml` (already present) so the parity test in `engine_cli` runs when the registry changes. `docs.yml`: add `engine_api` to the API-doc loop (`dart doc` works for pure Dart: use `dart pub get`).

### U.3 Docs touch list (do in phase 0 and phase 7)

`CLAUDE.md` package map row: `packages/engine_api` - "MCP/HTTP/JSON-RPC server over the operation registry in `engine_core`; depends on `engine_core` only" ;
`README.md` package table + badge row; `mkdocs.yml` nav: Reference > Operations (generated), MCP server; `docs/engine-releasing.md` dependency
order (insert `engine_api` after `engine_cli`); `CHANGELOG.md` `### Added`; `TODO.md` new item "engine_api: see engine_mcp.md".

## V. Pitfalls already paid for (do not rediscover)

1. **Gate every commit on the real test result.** `cmd | grep ... && git commit` succeeds even when tests fail (this shipped a broken commit once).
   Capture `r=$(dart test 2>&1 | tail -1)` and test `case "$r" in *"All tests passed"*) ... ;; esac`, and also run `dart analyze --fatal-infos`
   (the `unnecessary_import` lint failed CI twice).
2. `engine_core` tests run with `dart test`; Flutter packages with `flutter test --no-pub` and `flutter_test` (not `package:test`).
   Flutter SDK is at `~/develop/flutter/bin` (not on PATH). pub.dev is unreachable in the sandbox: use `--offline`/`--no-pub`; packages
   resolve through `pubspec_overrides.yaml`.
3. Shell aliases `rm`/`cp`/`mv` are interactive and hang or no-op: use `rm -f`, `python3` for copies/moves, `git mv` for repo moves.
4. `dart format` reflows code, so scripted string replacements must re-read the file first; do not run it on packages never formatted
   (unrelated diffs). Format only files you touched.
5. A widget test that spawns a real process leaves a pending timer (FakeAsync): inject runners (`GitRunner`, `ProcessStarter`, `PubProcessStarter`).
   The new ops must never spawn processes except `requiresFlutter` ones.
6. Adding a public `*Event` class requires a row in `docs/reference/events.md` (drift test); adding a component requires a schema +
   `dart run tool/gen_component_docs.dart > ../../docs/reference/components.md` (from `packages/engine_schema`). The same drift-test
   idea applies to the generated operation docs.
7. `release_consistency_test` (engine_core) requires every package to share the version, have `publish_to: none`, LICENSE, README and
   CHANGELOG. Create them in phase 0.
8. `game_agent` legacy exit codes and stdout wording are pinned by ~130 tests in `packages/engine_cli/test/`; keep adapters byte-compatible
   and change those tests only when behaviour is intentionally extended (additive `--json`).
9. Dart records compare lists by identity in `expect`; compare fields separately.
10. GitHub may be unreachable for a while; commit locally and retry the push later, nothing is lost.
11. `FileLock` files are `<path>.lock` next to the level; ignore them in `project.tree` (the studio tree already hides generated files: reuse
    `listProjectTree`).
12. Keep `engine_core` web-compilable: nothing under `src/ops/` may be exported from `engine_core.dart`; `dart:io` code lives behind
    `engine_core_ops.dart` (the same split as `engine_core_io.dart`).

## W. Effort map (for planning, not a promise)

| Phase | Rough size | Largest risk |
|---|---|---|
| 0 scaffolding | small | none |
| 1 registry core | medium (about 1,200 lines + tests) | parameter schema ergonomics; settle it with `engine.*` ops first |
| 2 write safety | medium | atomicity and token design; heavy unit tests |
| 3 move read ops | medium-large | moving files out of `engine_studio` without breaking its tests (do one file per commit) |
| 4 move write ops | medium | byte-identical output vs legacy; golden tests |
| 5 new ops | large (many small handlers) | `graph_editor` extraction, `asset.pack` image-codec injection |
| 6 server | large | MCP details; keep a thin protocol layer and test against the spec text |
| 7 parity/docs/e2e | medium | doc generator drift; e2e flakiness (use ephemeral ports, fixed clocks) |
| 8 release plumbing | small | none |

Suggested working method to minimise tokens: implement **one operation group per session**, starting each by reading only the rows of
sections J and R for that group, the matching legacy source file named in R.3, and the worked example S.3; write the handler, its test
from T.2, run only that test file plus `dart analyze`, commit, move on.

---

# Appendix: one operation on every surface, checklists and rationale

## X. The same call on all five surfaces (use as the doc-generator template and as the e2e expectation)

Operation: `level.set_field` (write; applies immediately; always previewable).

**CLI**
```bash
game_agent level set-field assets/levels/level1.json --entity player --component position --field x --value 48
game_agent level set-field assets/levels/level1.json --entity player --component position --field x --value 48 --dry-run --json
game_agent studio set-field assets/levels/level1.json --entity player --component position --field x --value 48   # legacy alias, same result
```

**MCP `tools/call`** (stdio line or `POST /mcp`)
```json
{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"level.set_field","arguments":
  {"path":"assets/levels/level1.json","entity":"player","component":"position","field":"x","value":48}}}
```
Response `result`: `{"content":[{"type":"text","text":"{...envelope...}"}],"structuredContent":{...envelope...},"isError":false}`.

**REST**
```bash
curl -s -X POST http://127.0.0.1:7421/v1/level/set_field \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"path":"assets/levels/level1.json","entity":"player","component":"position","field":"x","value":48}'
```

**JSON-RPC**
```bash
curl -s -X POST http://127.0.0.1:7421/rpc -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"level.set_field","params":{"path":"assets/levels/level1.json","entity":"player","component":"position","field":"x","value":48}}'
```

**Envelope (identical `data` on every surface)**
```json
{"ok":true,"data":{"before":24,"after":48},"warnings":[],
 "diff":{"added":[],"removed":[],"changed":[{"name":"player","components":[{"component":"position","before":{"x":24,"y":8},"after":{"x":48,"y":8}}]}]},
 "undoId":"000042-20261024T101500Z-level.set_field","durationMs":3}
```

**A destructive call, end to end** (`level.remove_entity`)
1. Call without `confirmation` -> `{"ok":true,"data":{"preview":true,"summary":"Removes entity 'guard' (3 components)","diff":{...},"confirmation":"<token>","expiresAt":"..."}}`; nothing written.
2. Call again with the same args plus `"confirmation":"<token>"` -> `{"ok":true,"data":{"removed":"guard"},"undoId":"..."}`.
3. If the level changed in between -> `{"ok":false,"error":{"code":"confirmation_stale","message":"The level changed since the preview.","hint":"Preview again."}}`.
4. `undo.undo` with no args restores the file bytes.

## Y. Per-phase checklist and commit message templates

Copy the checklist into the working notes of each phase and tick as you go.

- [ ] Read only the J/R rows for this group and the legacy source named in R.3.
- [ ] Extraction commits first (move files with `git mv`, fix imports, shims in `engine_studio`), each green on its own package tests.
- [ ] Handler returns `OpOutcome` (reads) or a `Proposal` (writes); no direct file writes; no `Process`; no `DateTime.now()`.
- [ ] Params typed with descriptions; errors listed; at least one example (executed by the registry test).
- [ ] Per-operation test file from T.2, golden comparison with the legacy command where one exists.
- [ ] CLI command appears automatically; legacy adapter calls the registry; old tests unchanged and green.
- [ ] `dart analyze --fatal-infos` clean in every touched package; format only touched files.
- [ ] CHANGELOG entry; docs example added to the operation (generated docs refreshed in phase 7).
- [ ] Commit gated on the real result line (see V.1), then push; check CI if the push touched shared packages.

Commit message template (the repository asks for the *why*):
```
engine_core ops: <group> operations (<list>)

Why: <what the CLI/API could not do before, or what duplicated logic this removes>.
How verified: <per-operation tests, golden comparison with legacy <command>, counts of tests per package>.
Behaviour: <unchanged for legacy commands | new: ...>.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
```

## Z. Rationale for the less obvious decisions (so they are not re-litigated)

- **Registry in `engine_core`, not in `engine_api`:** the CLI must bind to it without depending on a server package, and the package DAG
  (`engine_schema -> engine_core -> everything else`) must stay one-way (CLAUDE.md).
- **One project per server run:** an agent that can name any path can touch any folder; a single root plus the path sandbox bounds the damage
  and makes the undo log and locks unambiguous.
- **Confirmation tokens instead of a plain `apply:true`:** a preview and the later apply can be separated by minutes and by other writers; the
  token binds the apply to the exact files the human/agent saw, and a poisoned file cannot trigger a destructive call without a fresh
  round-trip.
- **Operations over data, not raw functions:** closures, streams and live objects cannot cross JSON; a curated set stays stable for clients
  while the engine's internals change.
- **Pure Dart, hand-written HTTP:** same toolchain as the engine, no new dependency to resolve offline, and the server compiles to one native
  executable users can drop next to a project.
- **`requiresFlutter` flag instead of excluding commands from the CLI:** keeps the CLI's 1:1 promise (everything is a command) while being honest
  that an API host without the Flutter SDK cannot serve them.
- **Headless `world.*` sandbox:** gives agents the "engine functions" they can actually use (step, snapshot, patch, query) without rendering,
  and is deterministic (fixed clock, seeded random), so results are reproducible across transports.
- **Undo journal inside `.studio/`:** it travels with the project and the studio can adopt it later; capped at 100 so it cannot grow without bound.

## AA. Glossary

| Term | Meaning here |
|---|---|
| Operation | one named, typed, documented function in the registry (`group.verb`) |
| Surface | a way to call operations: CLI, MCP (stdio or HTTP), REST, JSON-RPC |
| Envelope | the uniform `{ok, data, warnings, diff?, undoId?, durationMs}` / `{ok:false, error}` result |
| Proposal | a write handler's list of file changes, not yet applied |
| Preview | the dry-run result of a proposal (diff, summary, confirmation token) |
| Project | a game folder with `pubspec.yaml` and `assets/levels`; at most one is open per server |
| `requiresFlutter` | an operation implemented in the CLI (needs the Flutter SDK or long-running processes) and not served by `engine_api` |
| Parity test | the test that fails when the registry and any surface disagree |
