# engine_mcp: an API and MCP server for the engine (plan, not implemented)

Status: **planning only.** Nothing here is built. The owner answered the first round of questions (see Decisions); a
second round is listed under "Still open".

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

### Still open (to ask next)

- Where the undo log lives and how long it is kept (proposal: `.studio/undo/` inside the project, last 100 writes).
- Concurrency with a running studio: respect the existing advisory `FileLock`, or take over?
- Whether destructive-operation previews return a diff in the existing `LevelDiff` format (proposal: yes).
- Observability: request log, per-operation timing, and a `health` / `capabilities` operation.
- How MCP prompts are authored and tested (proposal: files under `engine_api/prompts/`, each executed by a test against a scratch project).

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
3. **Write-safety layer** (shared by every surface): dry-run result as a `LevelDiff`-style preview, `apply` flag, undo log,
   read-only enforcement, advisory-lock handling. Tested once, inherited by all operations.
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
