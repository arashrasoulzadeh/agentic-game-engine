# engine_api

An MCP server and an HTTP / JSON-RPC API for the engine. Every operation (every studio command, engine function and project
function) is declared once in a registry in `engine_core` and is available as a `game_agent <group> <verb>` command, an MCP
tool, a REST route and a JSON-RPC method. The full specification is [engine_mcp.md](../../engine_mcp.md).

## Run it

MCP over stdio (what Claude Desktop, Claude Code and other MCP clients launch):

```bash
dart run bin/engine_api.dart --project /path/to/game
```

REST, JSON-RPC and MCP over HTTP on one localhost port:

```bash
dart run bin/engine_api.dart --http --project /path/to/game   # token in <project>/.studio/api-token
curl -H "Authorization: Bearer $(cat /path/to/game/.studio/api-token)" -X POST localhost:7421/v1/level/list
```

| Surface | Where |
|---|---|
| MCP tools | stdio, or `POST /mcp` |
| REST | `POST /v1/<group>/<verb>` (body = parameters), `GET /v1/engine/operations`, `GET /v1/openapi.json` |
| JSON-RPC | `POST /rpc` (method = operation name, batches in order, `rpc.discover`) |
| Health | `GET /v1/health` (no token) |

Flags: `--read-only`, `--allow <glob>`, `--deny <glob>`, `--underscore-tool-names`, `--log`, `--max-result-bytes`,
`--requests-per-minute`, `--port`, `--bind` (beyond localhost needs `--allow-remote`), `--token`, `--rotate-token`,
`--print-token`.

## How operations behave

- Reads change nothing. Writes apply immediately, are validated first, and can be undone with `undo.undo` (last 100 are kept in
  `.studio/undo/`). Destructive writes answer with a preview and a confirmation token; send the token back to apply.
- Results are one envelope: `{ok, data, warnings, diff?, undoId?, durationMs}` or `{ok:false, error:{code, message, hint?}}`.
  Operation failures are `isError` MCP results; the `error.code` is stable (`not_found`, `validation_failed`, `read_only`, ...).
- Operations that need the Flutter SDK (`release.build`, `project.create`, `project.upgrade`) are listed by `engine.capabilities`
  but only run from the CLI.
- Every call is logged to `.studio/api-requests.jsonl` (no arguments or results).

## Security

Loopback only by default, bearer token (constant-time compare, file mode 0600), Host-header check against DNS rebinding, request
size, result size and rate limits. TLS is not terminated here; put a reverse proxy in front for remote use.

```bash
dart test
```
