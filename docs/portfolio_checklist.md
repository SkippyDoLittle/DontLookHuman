# Portfolio and Release Checklist

## Completed in Phase 6

- [x] Project name and version metadata
- [x] README with premise, controls, features, levels, and setup
- [x] Architecture summary
- [x] Known-issues list
- [x] Five reproducible 1280×720 level screenshots
- [x] Reproducible 10-second gameplay preview showing suspicion and a food pickup (historical; superseded by the 33-second trailer)
- [x] Per-level save records and fair level-specific grade thresholds
- [x] Automated score, grade, timer, collectible, progression, save, and debug-overlay validation
- [x] Toggleable `F3` development overlay
- [x] Windows export preset
- [x] Generated exports and ZIP packages excluded from Git

## Final publishing tasks

- [x] Replace the automated preview with a directed hook-first trailer showing a full escape
- [x] Add a final game icon and store capsule art
- [ ] Perform a clean-machine Windows playtest of the exported executable
- [ ] Choose a license before publishing source code
- [ ] Upload the packaged build to a release page or game platform rather than committing it to Git

## Completed in Phase 7

- [x] Persistent five-level campaign unlocks with existing-score migration
- [x] Level Select best-score presentation and Continue behavior
- [x] Controller gameplay, camera, pause, results, and menu navigation
- [x] Deterministic focus for menu and pause UI
- [x] Debug diagnostics disabled in release exports
- [x] Automated campaign, input, focus, and release-gating validation

## Completed in Phase 8

- [x] Frozen result state with Next Level, Replay Level, Main Menu, and Play Again actions
- [x] Modal controls overlay that cannot accidentally resume gameplay
- [x] Lightweight ranger and visitor obstacle recovery
- [x] Automated result, pause-modal, and obstacle-recovery validation

## Completed in Phase 9

- [x] Confirmed Reset Campaign & Scores flow
- [x] Persistent mouse/controller sensitivity and inverted-Y settings
- [x] Original low-poly pigeon icon and wide store capsule
- [x] Windows `0.9.0` release-candidate metadata
- [x] Publishing-status documentation and automated publishing validation

## Completed in Phase 10

- [x] Directed 33-second, 1280×720 release trailer spanning four escalating gameplay sequences
- [x] Immediate gameplay hook, beat-synchronized cuts, original score, emphasized effects, and animated wishlist reveal
- [x] Versioned Windows ZIP packaging with included controls and SHA-256 checksum
- [x] Automated trailer-container and release-workflow validation

## Completed in Phase 26

- [x] Rebuilt release trailer tool to showcase Phases 21–25 moments: Festival hook, Lakeside blend gag, Playground ranger collision comedy, Botanical Gardens gauntlet escape
- [x] Updated architecture documentation to reflect Phases 23–25 systems (near-exit alert, chaos window bonuses, procedural body animation)
- [x] Updated known-issues assessment to reflect Phase 25 visual communication improvements

## Completed in release-candidate polish (Phases P0–P6)

- [x] Removed the unsafe global material override and short repetitive music loop
- [x] Added five distinct authored lighting profiles, shared low-poly materials, camera composition, and Low/Medium/High quality presets
- [x] Added expressive player, NPC pigeon, ranger, and visitor movement while preserving gameplay roots and action timing
- [x] Added deterministic, collision-free themed MultiMesh details to every level
- [x] Added a 16-bar adaptive score plus independent level ambience and Music/Ambience/SFX controls
- [x] Added readable chaos-window and Perfect Alibi opportunities without changing suspicion or reward balance
- [x] Added a shared branded menu/HUD theme with intact controller focus and scripted node paths
- [x] Added persistent Reduce Motion & Flashes behavior for camera trauma, danger flashes/pulses, and close-call slow motion
- [x] Added strict all-suite runtime validation, visible-renderer performance reporting, deterministic media tooling, and verified Windows package smoke testing
- [x] Regenerated and inspected the five level screenshots and 33-second trailer from shipping scenes
- [x] Produced a fresh ignored Windows release candidate with exact ZIP-content and SHA-256 verification

## Final trailer structure

1. Open immediately on a Festival theft beside a ranger.
2. Turn the first pickup into an alert and chase within the opening second.
3. Use the Lakeside flock for the "ACT NATURAL." visual gag.
4. Cut to a Playground ranger collision — player sidesteps a charging ranger, who stumbles while the player escapes.
5. Escalate into a four-ranger Botanical Gardens gauntlet and glowing exit.
6. Hard cut from the escape flash to "JUST A PIGEON.", then reveal the logo and wishlist call to action.

See `docs/trailer_treatment.md` for the full creative rationale and future footage priorities.
