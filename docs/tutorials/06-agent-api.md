# 6 · Drive the engine from an AI agent (MCP, REST, CLI)

Everything the studio and the CLI can do to a project is also an **operation** an agent can call: build a level, validate
it, step the world, undo a mistake. One registry, four doors:

| Door | Use it for |
|---|---|
| `game_agent <group> <verb>` | scripts, CI, humans in a terminal |
| MCP tools (`engine_api`, stdio or HTTP) | Claude Desktop, Claude Code and other MCP clients |
| REST `POST /v1/<group>/<verb>` | your own services |
| JSON-RPC `POST /rpc` | batches, typed clients |

The full list, with every parameter, is the generated [operations reference](../reference/operations.md).

## 1. Start the server

From a checkout of the engine repo:

```bash
cd packages/engine_api
dart run bin/engine_api.dart --project /path/to/your/game
```

That speaks MCP over stdio, which is what MCP clients launch. To use it from Claude Desktop add it to the client's MCP
server list:

```json
{
  "mcpServers": {
    "game-engine": {
      "command": "dart",
      "args": ["run", "/path/to/engine/packages/engine_api/bin/engine_api.dart", "--project", "/path/to/your/game"]
    }
  }
}
```

Useful flags: `--read-only` (agent can look but not touch), `--deny 'release.*'`, `--allow 'level.*'`.

## 2. What an agent does

A typical session, as tool calls:

1. `project.info`, `schema.components` - what is here, what can an entity hold?
2. `level.create`, `level.add_entity`, `level.move_entity`, `level.paint_tile` - build.
3. `level.validate` / `level.lint` with `playable: true` / `project.problems` - check it. Fix what they report.
4. `world.build` then `world.step` and `world.query` - run the level headlessly and look at the result. Nothing is written.
5. `undo.undo` - take back the last change. Every write is journalled in `.studio/undo/` (the last 100).

Removing things (`level.remove_entity`, `graph.remove_node`, ...) is **destructive**: the first call returns a preview and
a `confirmation` token, the second call with that token applies it. Tokens are tied to the server process and expire
after five minutes.

## 3. The same thing from a shell

```bash
game_agent level add-entity assets/levels/forest.json --name coin --components position
game_agent level lint assets/levels/forest.json --playable
game_agent undo undo
game_agent --read-only level list --json     # the exact result envelope
```

Every command takes `--json` (print the envelope), `--stdin` or `--args '{...}'` (parameters as JSON), and writes take
`--dry-run` to preview.

## 4. Over HTTP

```bash
dart run bin/engine_api.dart --http --project /path/to/your/game
TOKEN=$(cat /path/to/your/game/.studio/api-token)
curl -H "Authorization: Bearer $TOKEN" -X POST localhost:7421/v1/level/list
curl -H "Authorization: Bearer $TOKEN" localhost:7421/v1/openapi.json
```

The server listens on localhost only, needs the token for everything except `GET /v1/health`, limits request and result
sizes and rate, and logs each call (no arguments, no results) to `.studio/api-requests.jsonl`. Send an
`Idempotency-Key` header with a write to make retries safe. Configuration can live in `engine_api.yaml` in the project.

## What an agent cannot do

Operations that need the Flutter SDK (`project.create`, `project.upgrade`, `release.build`) exist as CLI commands only
(`game_agent create`, `upgrade`, `build-release`); `engine.capabilities` lists them as unsupported.
