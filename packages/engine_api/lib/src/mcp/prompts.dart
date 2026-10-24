/// One guided workflow an MCP client can offer the user.
///
/// Prompts live in code rather than loose files so they ship with the package however it is installed; a test checks
/// that every operation a prompt names exists, so a renamed operation cannot leave a stale instruction behind.
class PromptSpec {
  const PromptSpec(this.name, this.description, this.arguments, this.template);

  final String name;
  final String description;

  /// `(name, description, required)` per argument; `{{name}}` in [template] is replaced by its value.
  final List<(String, String, bool)> arguments;
  final String template;

  Map<String, Object?> toListJson() => {
    'name': name,
    'description': description,
    'arguments': [
      for (final (n, d, r) in arguments)
        {'name': n, 'description': d, 'required': r},
    ],
  };

  /// The prompt text with [args] filled in; a missing required argument is an [ArgumentError].
  String render(Map<String, String> args) {
    var text = template;
    for (final (n, _, required) in arguments) {
      final v = args[n];
      if (v == null && required) {
        throw ArgumentError('Missing required argument "$n".');
      }
      text = text.replaceAll('{{$n}}', v ?? '');
    }
    return text.trim();
  }
}

const enginePrompts = [
  PromptSpec(
    'build_level',
    'Build a platformer level step by step and validate it.',
    [
      ('theme', 'What the level is like', false),
      ('path', 'Level file to create, e.g. assets/levels/forest.json', true),
    ],
    '''
You are editing the open project with the engine tools. Build the level `{{path}}`. Theme: {{theme}}.

1. Call `project.info` and `schema.components` to see what the project and engine support.
2. Create the file with `level.create`.
3. Add a ground entity with a `tileMap` using `level.add_entity`, then shape it with `level.paint_tile` and `level.fill_region`.
4. Add the player and a few pickups or enemies with `level.add_entity`; position them with `level.move_entity`.
5. After every few edits call `level.validate` and fix every error before continuing. Edits are undoable with `undo.undo`.
6. Finish with `level.read` and describe what you built.
''',
  ),
  PromptSpec(
    'fix_validation_problems',
    'Find and fix everything `project.validate` reports.',
    [],
    '''
Call `project.validate`. For each level with errors, call `level.read` for the offending entity and fix it with
`level.set_field`, `level.add_component` or `level.remove_entity`. Destructive operations return a preview and a
confirmation token: show the preview to the user before sending the token back. Call `project.validate` again until it
reports ok, then summarise what you changed.
''',
  ),
  PromptSpec(
    'balance_idle_game',
    'Check an idle game definition for dead ends and tune its pacing.',
    [('path', 'The idle game file', false)],
    '''
Call `idle.validate` on the game file {{path}} and fix every error. Then call `idle.simulate` for 1 day and 7 days of
play and look at when each generator becomes affordable and when prestige becomes worth it. Use `idle.format_number`
to report values the way players see them. Propose changes to costs or outputs before applying them.
''',
  ),
];
