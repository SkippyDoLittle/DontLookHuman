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

Collectibles and the escape zone emit gameplay events. They do not manipulate the HUD directly. `GameSession` counts live members of the `collectibles` group, so levels are not tied to a fixed item count. A successful peck removes food from that group immediately, then keeps its mesh alive for a short presentation-only arc into the moving player's beak. This preserves objective timing while the player body, wings, crumbs, trail, and synchronized sounds make the theft readable.

## Ranger components

- `ranger.gd` is the scene-facing coordinator and signal source.
- `ranger_suspicion.gd` evaluates suspicious player behavior.
- `ranger_state_machine.gd` selects patrol, investigate, or chase.
- `ranger_movement.gd` handles pursuit movement and lightweight obstacle recovery.
- `ranger_presentation.gd` handles world-space alerts.
- `ranger_hud_controller.gd` aggregates multiple ranger signals for the shared HUD.
- `park_reaction_director.gd` broadcasts grabs, authored environmental surprises, and player exposure to pigeons and visitors; each actor owns its own distance, delay, and animation response.
- `park_chaos_controller.gd` connects shared food, water, ranger, HUD, camera, and prop contracts. It owns one signature event per level plus a rearmable park-wide panic cascade when any ranger reaches Chase.

Rangers and pigeons use groups rather than exact numbered node names. This allows later levels to add rangers or procedurally scattered pigeons without changing detection code.

The approved controlled-chaos capture system now runs across the campaign. A full suspicion meter exposes the player, a committed grab can be dodged, and only contact starts the delayed capture tableau. Levels tune wind-up, lunge speed, and recovery independently. Ranger personality labels provide visible Rookie, Steady, Hothead, and Veteran variations without changing the core controls.

Each campaign map also has one deterministic environmental story: Park feeding frenzy, Playground swing surprise, Lakeside splash alarm, Festival popcorn panic, and the Botanical Gardens sprinkler finale. Separately, the first Chase in each danger cycle scatters the flock, alerts visitors, flashes the HUD, adds a short camera punch, and plays an exposure sting. That feedback rearms only after suspicion falls below 55 and does not alter detection or capture difficulty.

## Level configuration and persistence

Each `LevelConfig` contains a stable save key, display text, time limit, next-level path, and Lightning/Great/Nice grade thresholds. Best scores use one `ConfigFile` key per level. Campaign state uses `user://campaign_progress.cfg`; existing per-level records are migrated into equivalent unlock progress. The earlier shared `user://best_score.dat` value remains readable as a Level 1 fallback, avoiding destructive migration. Settings offers a confirmed reset that clears campaign, current records, and the legacy fallback together.

Camera sensitivity and inverted-Y preferences share `user://settings.cfg` with audio and display preferences. Player instances load those camera values during `_ready()`.

## Reusable world systems

- `WaterZone.tscn` supplies movable and resizable water slowdown triggers.
- `HUD.tscn` provides the dynamic minimap and a debug-build-only `F3` diagnostics overlay.
- Actor, gameplay, and prop scenes live under `scenes/actors`, `scenes/gameplay`, and `scenes/props`.
- Scatter scripts duplicate reusable templates with deterministic seeds.
- Large visual-only scenery populations use MultiMesh rendering.

## Verification

`tools/capture_physical_capture_playtest.gd` stages representative wind-up, miss, personality, crowd-reaction, and caught frames across the campaign for visual QA.

`tools/capture_signature_chaos.gd` and `tools/capture_suspicion_escalation.gd` stage the environmental set pieces and park-wide exposure cascade for repeatable visual QA.

`tools/capture_food_snatch.gd` stages a close successful pickup for repeatable animation, trail, and composition QA.

Permanent headless validation covers base-level contracts, timer and score flow, ranger behavior, physical grab fairness and reaction propagation, route balance, safe spawns, grade boundaries, per-level save isolation, campaign unlocks and reset, dynamic collectibles, camera preferences, controller mappings, menu focus, result actions, modal pause behavior, obstacle recovery, progression paths, branding metadata, release/debug diagnostics behavior, trailer structure, and packaging contracts.

`tools/capture_portfolio_screenshots.gd` reproduces the five portfolio screenshots from the actual scenes. `tools/capture_gameplay_video.gd` directs a repeatable 33-second, four-sequence trailer in Godot Movie Maker mode. It owns the cinematic camera, deterministic gameplay staging, animated text and logo beats, trailer-only portal presentation, and audio mix. `tools/trailer_soundtrack.gd` generates the original synchronized score. `tools/finalize_trailer.ps1` normalizes Godot's RIFF length field and verifies all 990 video and audio chunks plus the AVI index without replacing any animated frame. `tools/package_windows_release.ps1` exports the Windows build into a versioned folder, adds player instructions, creates a ZIP, and writes its SHA-256 checksum.
