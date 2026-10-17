# Glossary

| Term | Meaning |
|---|---|
| **Action** | What a `Behavior` returns: a proposed change the engine applies (real-time agents). |
| **Action points (AP)** | A unit's per-turn budget. Spent by moving and attacking; refilled when its team's turn starts. |
| **Agent** | Anything that decides: a script, an AI opponent, an LLM, a learned policy. It observes JSON and acts through orders/`Action`s, never by mutating state directly. |
| **Archetype** | Internal grouping of entities with the same component set (an optimisation, not an API). |
| **Atlas** | A packed sprite sheet plus a name → rectangle manifest. |
| **Behavior** | Sandboxed decision logic for one entity. Reads a `WorldView`, returns an `Action`. |
| **Cell** | One square of a grid, addressed `(col, row)`. |
| **Chebyshev distance** | Distance where diagonal steps count as one: `max(|dc|, |dr|)`. Used for attack range. |
| **Component** | Plain data attached to an entity. Registered by name to serialize. |
| **Content as data** | Authoring levels/entities as JSON rather than Dart. |
| **Dense iteration** | Walking a `ComponentStore` by index (`length` / `entityAt` / `denseAt`) — fast and gap-free. |
| **Entity** | An integer id. Owns nothing; components are stored under it. |
| **Event** | A message on `world.events`, delivered at the end of a step. |
| **Explored** | Fog cells a team has ever seen (remembered). Contrast **visible**. |
| **Fixed timestep** | Simulation advances in equal steps regardless of frame rate. |
| **Flush** | Delivering queued events; happens once per `World.step`. |
| **Fog of war** | Per-team visibility. Hides enemies and blocks attacking what you can't see. |
| **Grid navigator** | `GridNavigator`: bounds, terrain costs and diagonal rules for strategy movement. |
| **Order** | A JSON-serializable intent (`MoveOrder`, `AttackOrder`) queued on a unit. |
| **Registry** | `world.components`: component name ↔ JSON codec. |
| **Round** | One full cycle through every team's turn. |
| **Scene** | A screen of the game; owns a fresh `World`. |
| **Schema** | Hand-written description of a component's JSON fields (`engine_schema`). |
| **Store** | `ComponentStore<T>`: sparse-set storage for one component type. |
| **System** | One unit of simulation logic run every step, in registration order. |
| **Team** | A string id grouping entities into a side. |
| **Terrain cost** | Action points needed to enter a cell; `null` = impassable. |
| **TurnAI** | A class that plays a whole team's turn by submitting orders. |
| **Visible** | Fog cells currently in sight. Recomputed every tick. |
| **WorldView** | The read-only window a `Behavior` sees. |
