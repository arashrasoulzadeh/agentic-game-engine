# Build your first level

A level is a JSON file of entities, each with components. In this walkthrough you make a small one: a ground
made of tiles, one step to jump onto, and a player standing on it. You do it twice, once in the studio and
once with the command line; both produce the same file, and each command below is run by a test.

## 1. Make the file

In your game project, create `assets/levels/level1.json` containing:

```json
{ "entities": [] }
```

## 2. The ground

**Studio:** open the level, search the palette for `tileMap`, pick it and click the canvas. Rename the entity to
`ground`. In the inspector set `cols` 8, `rows` 3, `tileWidth` 16, `tileHeight` 16.

**Command line:**

```bash
game_agent studio add-entity assets/levels/level1.json --name ground --component position --component tileMap
game_agent studio set-field assets/levels/level1.json --entity ground --component tileMap --field cols --value 8
game_agent studio set-field assets/levels/level1.json --entity ground --component tileMap --field rows --value 3
game_agent studio set-field assets/levels/level1.json --entity ground --component tileMap --field tileWidth --value 16
game_agent studio set-field assets/levels/level1.json --entity ground --component tileMap --field tileHeight --value 16
game_agent studio set-field assets/levels/level1.json --entity ground --component tileMap --field solidTileIds --value '[1]'
game_agent studio set-field assets/levels/level1.json --entity ground --component tileMap --field tiles \
  --value '[0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 1,1,1,1,1,1,1,1]'
```

`tiles` is the grid read row by row; `1` is a solid tile and `0` is empty. Here the bottom row is floor.

## 3. A step

**Studio:** choose the brush tool, pick tile 1 and click the square above the floor, fourth from the left.

**Command line:**

```bash
game_agent studio paint-tile assets/levels/level1.json --entity ground --col 3 --row 1 --tile-id 1
```

## 4. The player

**Studio:** pick `position` in the palette, click the canvas near the left, rename the entity to `player`, and set `x`
24 and `y` 16 in the inspector.

**Command line:**

```bash
game_agent studio add-entity assets/levels/level1.json --name player --component position
game_agent studio set-field assets/levels/level1.json --entity player --component position --field x --value 24
game_agent studio set-field assets/levels/level1.json --entity player --component position --field y --value 16
```

## 5. Check it

```bash
game_agent studio validate .
```

It exits 0 when every level in the project is valid, and otherwise names the entity, component and field that
is wrong. The Problems panel in the studio shows the same list. When it passes, use the play button for a
preview, or **Run game** to start your game on this level. See the [user guide](user-guide.md) for the rest of the
studio.
