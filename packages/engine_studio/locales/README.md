# Studio translations

Each `<code>.json` is `{ "key": "text" }`. To use one, copy it to `~/.game_agent/locales/` and set
`"locale": "<code>"` in `studio_prefs.json`. A key you leave out shows in English.

- `fa.json` — Persian (فارسی). Covers the project, level, graph, code, palette and inspector screens.

`test/locales_test.dart` checks that every catalog only uses keys the studio really has.
