# engine_api

An MCP server and an HTTP / JSON-RPC API for the engine. Every operation (every studio command, engine function and project
function) is declared once in a registry in `engine_core` and is available as a `game_agent <group> <op>` command, an MCP tool,
a REST route and a JSON-RPC method.

**Status: scaffold (phase 0).** The package exists and is wired into CI; the work is built in the order given in
[engine_mcp.md](../../engine_mcp.md), which is the full specification.

```bash
dart run bin/engine_api.dart --version
```
