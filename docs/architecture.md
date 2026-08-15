# Architecture Summary

## Runtime flow

`MainMenu.tscn` is the project entry point. A new campaign loads `Level01_Park.tscn`; returning players continue from their highest unlocked level. Successful sessions follow the `next_level_scene` path in each level's `LevelConfig` until Level 5 ends the campaign. Level Select exposes unlocked maps and their best scores. The menu, pause screen, HUD, and results share one branded low-poly park theme while retaining stable scripted node paths and controller focus order.

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

The approved controlled-chaos capture system now runs across the campaign. A full suspicion meter exposes the player, a committed grab can be dodged, and only contact starts the delayed capture tableau. Levels tune wind-up, lunge speed, and recovery independently. Rookie, Steady, Hothead, and Veteran rangers now use distinct miss poses, escalating failure callouts, and teammate responses. The first miss preserves its approved timing; later misses add a capped player-favoring recovery bonus so comedy also prevents frustration.

Rangers track the actual closest distance reached during each lunge. A miss within the configured close-call margin triggers a 0.14-second real-time-safe cinematic beat after recovery has already begun: brief slow motion when reduced motion is off, feathers, camera/audio feedback, and a dedicated HUD punchline. Comfortable dodges remain ordinary misses. The controller restores the previous global time scale both on its safety timer and if the level exits mid-effect.

Calm NPC pigeons now answer a nearby player peck with a capped, distance-delayed mimic wave. Each pigeon decides independently whether it is eligible, so ranger proximity, fleeing, and every park reaction retain priority. The park controller only coordinates the six-bird cap, short presentation cooldown, chime, and low-priority HUD acknowledgment; flock sync never changes suspicion, objectives, or capture timing.

An earned lunge dodge can now produce mistaken identity when a calm or wind-up-watching NPC pigeon is within 0.9 units of the ranger's miss endpoint. Wind-up watchers remain still through the slowest campaign grab and its full lunge, so they do not resume fleeing just before the eligibility check. The nearest eligible decoy struggles between the ranger's arms, sheds feathers, draws personality and teammate callouts, and panics after release. The tableau ends inside the existing miss recovery, has a six-second per-ranger lockout, suppresses overlapping close-call presentation, and never changes suspicion or successful-capture state.

Panicking pigeons use a bounded two-stage path: a 0.72-second outward burst followed by a curved return to a deterministic loose ring near the event, clamped inside their normal roaming area. This prevents the flock from emptying to map boundaries and keeps birds available for later ranger interactions. A narrow 0.72-unit ranger flyby can occur along that path; each bird gets one proximity attempt per panic and each ranger has a 5.5-second presentation cooldown. An accepted flyby adds a personality flinch, short world callout, flutter sound, and small feather burst while deliberately preserving the ranger's movement, state, suspicion, grab phase, and capture timing.

Each campaign map also has one deterministic environmental story: Park feeding frenzy, Playground swing surprise, Lakeside splash alarm, Festival popcorn panic, and the Botanical Gardens sprinkler finale. Separately, the first Chase in each danger cycle scatters the flock, alerts visitors, flashes the HUD and adds a short camera punch when reduced motion is off, and plays an exposure sting. That feedback rearms only after suspicion falls below 55 and does not alter detection or capture difficulty.

A food theft or dodge near the active escape zone triggers a brief orange near-exit alert with personality-specific caught-near-escape poses. Timed steals during active blend windows or park-wide chaos events add bonus seconds to the session clock.

The Perfect Alibi opportunity layer connects existing systems rather than inventing another suspicion rule. A valid two-or-more-bird flock-sync wave can arm a short candidate only when the player begins at meaningful suspicion. If normal peck-driven decay brings every ranger below the established blend threshold while the player remains with the flock, `GameSession` promotes a short teal theft prompt. The next food-theft attempt consumes the prompt; if the player is still blended, it uses the existing +5-second reward. Overlap with the existing +4-second chaos window remains exactly +9 seconds. It never writes suspicion, movement, ranger state, or capture timing.

Rangers and the player now express state through per-frame procedural body animation: personality-matched wind-up poses, forward body lean on acceleration, turn roll on sharp direction changes, and a sprint strain wobble when stamina runs low. NPC pigeons enter a crouched alert pose during WATCH reactions and apply a velocity-based lean through PANIC turns.

Player and NPC pigeon scenes share authored low-poly eyes, feet, wings, tail, and neck accents. Stable per-instance phases prevent the flock from bobbing in sync. `RangerPresentation` blends rest-relative patrol, investigate, and chase gaits around its existing action-pose lock; visitors use inexpensive limb motion and reaction poses. Presentation code never moves gameplay roots or changes AI velocities.

`CameraFeedbackController` is the single owner of gameplay camera trauma and offsets. Player and transition feedback share it instead of overwriting one another. Reduce Motion & Flashes immediately clears and suppresses camera trauma, makes suspicion and ranger world alerts steady semantic amber/red instead of pulsing, suppresses the danger overlay flash, and skips close-call slow motion. It preserves particles, fades, audio, gameplay animation, cooldowns, counters, and signals.

## Level configuration and persistence

Each `LevelConfig` contains a stable save key, display text, time limit, next-level path, and Lightning/Great/Nice grade thresholds. Best scores use one `ConfigFile` key per level. Campaign state uses `user://campaign_progress.cfg`; existing per-level records are migrated into equivalent unlock progress. The earlier shared `user://best_score.dat` value remains readable as a Level 1 fallback, avoiding destructive migration. Settings offers a confirmed reset that clears campaign, current records, and the legacy fallback together.

Camera sensitivity and inverted-Y preferences share `user://settings.cfg` with separate Music, Ambience, and SFX levels, fullscreen state, graphics quality, and the Reduce Motion & Flashes preference. Player instances load the camera values during `_ready()`. `AccessibilitySettings` is a lazy static helper rather than an autoload, so direct scene boots and legacy compatibility tests still obtain the same persistent value.

`QualitySettings` is the only presentation-settings autoload. Low, Medium, and High presets adjust viewport scaling/antialiasing, SSAO, and directional shadows while leaving authored level palettes intact. Every `WorldEnvironment` owns an instance-local environment resource, preventing a preset applied in one level from leaking into another.

## Audio direction

`SoundManager` retains the semantic gameplay SFX API and owns the separate Music, Ambience, and SFX buses. `AdaptiveMusicDirector` generates four synchronized 24-second stems and crossfades normal, tension, rhythm, and chase layers from existing session state. It replaces the earlier short repeating melody without changing gameplay calls.

Each `BaseLevel` owns a `ParkAmbienceDirector`. Five deterministic profiles combine wind, birds, people, water where appropriate, and Festival crowd texture; ambience continues underneath a muted score because it is routed to its own bus. NPC pecks and steps use bounded concurrency and quiet canonical emitter gains so a large flock cannot overwhelm the mix.

## Reusable world systems

- `WaterZone.tscn` supplies movable and resizable water slowdown triggers.
- `HUD.tscn` provides the dynamic minimap and a debug-build-only `F3` diagnostics overlay.
- Actor, gameplay, and prop scenes live under `scenes/actors`, `scenes/gameplay`, and `scenes/props`.
- Scatter scripts duplicate reusable templates with deterministic seeds.
- Large visual-only scenery populations use MultiMesh rendering.
- `WorldDetailScatter` adds two or three deterministic, collision-free MultiMesh layers per level: grass/leaves, pebbles/chalk, reeds/stones, confetti/paper, or foliage/flowers. A single bounded GPU sway shader is used only where motion helps.
- Each level keeps its own authored sky, ambient light, fog, sun, and color identity. Shared opaque `StandardMaterial3D` resources are assigned only to intended pigeon and park-prop surfaces; no runtime material-tree replacement is permitted.

## Verification

`tools/capture_physical_capture_playtest.gd` stages representative wind-up, miss, personality, crowd-reaction, and caught frames across the campaign for visual QA.

`tools/capture_signature_chaos.gd` and `tools/capture_suspicion_escalation.gd` stage the environmental set pieces and park-wide exposure cascade for repeatable visual QA.

`tools/capture_food_snatch.gd` stages a close successful pickup for repeatable animation, trail, and composition QA.

`tools/capture_ranger_personality_miss.gd` stages a repeated Hothead failure and Veteran teammate response for social-reaction and pose QA.

`tools/capture_close_call.gd` stages a qualifying narrow dodge for slow-motion, feather, miss-pose, and HUD composition QA.

`tools/capture_flock_sync.gd` stages the player pecking in formation with six pigeons while a ranger observes, making the distance wave and blend feedback reproducible for visual QA.

`tools/capture_mistaken_identity.gd` stages a ranger holding the wrong pigeon while the real player escapes and a teammate reacts, covering the held anchor, struggle wings, feathers, callouts, and HUD priority.

`tools/capture_panic_flyby.gd` stages a panicking pigeon crossing a Rookie ranger's face for repeatable flinch, feather, callout, and composition QA.

`tools/phase25_anim_monitor.gd` logs body lean, turn roll, sprint strain, and personality windup events during live playtesting sessions.

`tools/run_validations.ps1` discovers every permanent validation script, runs it in a fresh headless Godot process, and treats nonzero exits plus runtime `ERROR`, `SCRIPT ERROR`, and parse-error output as failures. Coverage includes base-level contracts, timer and score flow, ranger behavior, physical grab fairness and reaction propagation, route balance, safe spawns, grade boundaries, persistence, input and focus, accessibility, audio, visuals, media determinism, performance/report schemas, and packaging contracts.

`tools/capture_portfolio_screenshots.gd` reproduces the five portfolio screenshots from the actual scenes using a fixed seed, explicit capture preset, fixed resolution, silent audio directors, and frozen staged actors. `tools/capture_gameplay_video.gd` directs a repeatable 33-second, four-sequence trailer in Godot Movie Maker mode: a Festival food theft beside an alert ranger, a Lakeside flock blend gag, a Playground ranger collision, and a Botanical Gardens gauntlet escape. It owns the cinematic camera, deterministic gameplay staging, animated text and logo beats, trailer-only portal presentation, and audio mix. `tools/trailer_soundtrack.gd` generates the original synchronized score. `tools/finalize_trailer.ps1` normalizes Godot's RIFF length field and verifies all 990 (or a custom `-FrameCount`) video and audio chunks plus the AVI index without replacing any animated frame.

`tools/performance_benchmark.gd` collects a visible-renderer, machine-specific baseline for every level and writes both JSON and Markdown reports. Frame-rate targets are advisory, while runtime errors and deliberately generous runaway-scene budgets are blocking. `tools/package_windows_release.ps1` exports the embedded-PCK Windows build into a versioned folder, verifies the executable header and exact ZIP contents, performs a bounded boot smoke test, and writes and rechecks its SHA-256 checksum.
