/// Whole-file JSON Schema (draft 2020-12) for `assets/idle_game.json`.
///
/// Component-level schemas live in `engine_schema`; this describes the
/// definition document [validateIdleDefinition] / [loadIdleDefinition] accept.
/// Exposed to agents as `schema.idle_game`.
Map<String, Object?> idleGameDefinitionJsonSchema() => {
      r'$schema': 'https://json-schema.org/draft/2020-12/schema',
      'title': 'idle_game',
      'description':
          'Whole idle game as data: resources, generators, upgrades, '
          'achievements, prestige layers, challenges, golden offers, offline rules.',
      'type': 'object',
      'additionalProperties': true,
      'properties': {
        'resources': {
          'type': 'object',
          'additionalProperties': {
            'type': 'object',
            'properties': {
              'start': {
                'description': 'Starting amount (BigNumber JSON string or number).',
                'oneOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                ],
              },
            },
            'additionalProperties': true,
          },
        },
        'generators': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['id', 'cost'],
            'properties': {
              'id': {'type': 'string', 'minLength': 1},
              'name': {'type': 'string'},
              'cost': {'type': 'object'},
              'costResource': {'type': 'string'},
              'output': {'type': 'object'},
              'requires': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'milestones': {'type': 'array'},
              'maxOwned': {'type': 'integer', 'minimum': 1},
            },
            'additionalProperties': true,
          },
        },
        'upgrades': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['id', 'cost'],
            'properties': {
              'id': {'type': 'string', 'minLength': 1},
              'name': {'type': 'string'},
              'cost': {'type': 'object'},
              'target': {'type': 'string'},
              'multiplier': {
                'oneOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                ],
              },
              'bonusPerOwned': {
                'oneOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                ],
              },
              'synergyOf': {'type': 'string'},
              'requires': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
            'additionalProperties': true,
          },
        },
        'achievements': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['id', 'stat', 'atLeast'],
            'properties': {
              'id': {'type': 'string', 'minLength': 1},
              'name': {'type': 'string'},
              'stat': {'type': 'string'},
              'atLeast': {
                'oneOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                ],
              },
              'reward': {
                'oneOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                ],
              },
            },
            'additionalProperties': true,
          },
        },
        'prestige': _prestigeRuleSchema,
        'prestiges': {
          'type': 'array',
          'items': _prestigeRuleSchema,
        },
        'challenges': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['id', 'goalStat', 'goalAtLeast'],
            'properties': {
              'id': {'type': 'string', 'minLength': 1},
              'name': {'type': 'string'},
              'rules': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'goalStat': {'type': 'string'},
              'goalAtLeast': {
                'oneOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                ],
              },
              'reward': {
                'oneOf': [
                  {'type': 'string'},
                  {'type': 'number'},
                ],
              },
            },
            'additionalProperties': true,
          },
        },
        'autoBuyer': {
          'type': 'object',
          'properties': {
            'enabled': {'type': 'boolean'},
            'intervalSeconds': {'type': 'number', 'minimum': 0.01},
            'mainResource': {'type': 'string'},
            'maxPerRun': {'type': 'integer', 'minimum': 1},
          },
          'additionalProperties': true,
        },
        'golden': {
          'type': 'object',
          'required': ['meanInterval', 'lifetime', 'rewards'],
          'properties': {
            'meanInterval': {'type': 'number', 'minimum': 1},
            'lifetime': {'type': 'number', 'minimum': 0},
            'rewards': {
              'type': 'array',
              'minItems': 1,
              'items': {'type': 'object'},
            },
          },
          'additionalProperties': true,
        },
        'offline': {
          'type': 'object',
          'properties': {
            'capHours': {'type': 'number', 'minimum': 0},
            'efficiency': {'type': 'number', 'minimum': 0, 'maximum': 1},
          },
          'additionalProperties': true,
        },
        'research': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['id'],
            'properties': {
              'id': {'type': 'string', 'minLength': 1},
              'name': {'type': 'string'},
              'nameKey': {'type': 'string'},
              'cost': {'type': 'object'},
              'requires': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'unlocks': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
            'additionalProperties': true,
          },
        },
        'timeWarps': {
          'type': 'array',
          'items': {
            'type': 'object',
            'required': ['id', 'seconds'],
            'properties': {
              'id': {'type': 'string', 'minLength': 1},
              'name': {'type': 'string'},
              'nameKey': {'type': 'string'},
              'seconds': {'type': 'integer', 'minimum': 1},
              'cost': {'type': 'object'},
            },
            'additionalProperties': true,
          },
        },
      },
    };

const _prestigeRuleSchema = <String, Object?>{
  'type': 'object',
  'required': ['currency', 'basedOn'],
  'properties': {
    'id': {'type': 'string'},
    'currency': {'type': 'string', 'minLength': 1},
    'basedOn': {'type': 'string', 'minLength': 1},
    'divisor': {
      'oneOf': [
        {'type': 'string'},
        {'type': 'number'},
      ],
    },
    'exponent': {'type': 'number', 'minimum': 0},
    'bonusPerUnit': {'type': 'number', 'minimum': 0},
    'startingAmounts': {'type': 'object'},
    'keepUpgrades': {'type': 'boolean'},
    'keepGenerators': {
      'type': 'array',
      'items': {'type': 'string'},
    },
    'resetsCurrencies': {
      'type': 'array',
      'items': {'type': 'string'},
    },
  },
  'additionalProperties': true,
};
