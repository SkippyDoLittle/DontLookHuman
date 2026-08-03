# Architecture Summary

## Runtime flow

`MainMenu.tscn` is the project entry point. A new campaign loads `Level01_Park.tscn`; returning players continue from their highest unlocked level. Successful sessions follow the `next_level_scene` path in each level's `LevelConfig` until Level 5 ends the campaign. Level Select exposes unlocked maps and their best scores.

All five playable maps inherit `scenes/game/BaseLevel.tscn`. The base scene owns the shared player, HUD, session controller, pause UI, title/countdown UI, transition layer, and controls screen. Individual level scenes supply their environment, ranger instances and tuning, collectibles, exit placement, water zones, NPC populations, and `LevelConfig` resource.

## Session components

- `game_timer.gd` (`GameSession`) coordinates session state and gameplay events.
- `session_timer.gd` owns countdown and active timer behavior.
- `score_manager.gd` calculates completion grades from level-specific thresholds.
- `best_score_store.gd` persists scores by stable level ID in `user://best_scores.cfg`.
- `campaign_progress_store.gd` records completed levels and the highest unlocked campaign level.
- `session_hud_controller.gd` owns objective, timer, result presentation, and focused result actions.
- `transition_controller.gd` owns fades and screen shake.

Collectibles and the escape zone emit gameplay events. They do not manipulate the HUD directly. `GameSession` counts live members of the `collectibles` group, so levels are not tied to a fixed item count.

## Ranger components

- `ranger.gd` is the scene-facing coordinator and signal source.
- `ranger_suspicion.gd` evaluates suspicious player behavior.
- `ranger_state_machine.gd` selects patrol, investigate, or chase.
- `ranger_movement.gd` handles pursuit movement and lightweight obstacle recovery.
- `ranger_presentation.gd` handles world-space alerts.
- `ranger_hud_controller.gd` aggregates multiple ranger signals for the shared HUD.

Rangers and pigeons use groups rather than exact numbered node names. This allows later levels to add rangers or procedurally scattered pigeons without changing detection code.

## Level configuration and persistence

Each `LevelConfig` contains a stable save key, display text, time limit, next-level path, and Lightning/Great/Nice grade thresholds. Best scores use one `ConfigFile` key per level. Campaign state uses `user://campaign_progress.cfg`; existing per-level records are migrated into equivalent unlock progress. The earlier shared `user://best_score.dat` value remains readable as a Level 1 fallback, avoiding destructive migration.

## Reusable world systems

- `WaterZone.tscn` supplies movable and resizable water slowdown triggers.
- `HUD.tscn` provides the dynamic minimap and a debug-build-only `F3` diagnostics overlay.
- Actor, gameplay, and prop scenes live under `scenes/actors`, `scenes/gameplay`, and `scenes/props`.
- Scatter scripts duplicate reusable templates with deterministic seeds.
- Large visual-only scenery populations use MultiMesh rendering.

## Verification

Permanent headless validation covers base-level contracts, timer and score flow, ranger behavior, route balance, safe spawns, grade boundaries, per-level save isolation, campaign unlocks, dynamic collectibles, controller mappings, menu focus, result actions, modal pause behavior, obstacle recovery, progression paths, and release/debug diagnostics behavior.

`tools/capture_portfolio_screenshots.gd` reproduces the five portfolio screenshots from the actual scenes. `tools/capture_gameplay_video.gd` supplies a repeatable ten-second Festival demo route for Godot's Movie Maker mode.
