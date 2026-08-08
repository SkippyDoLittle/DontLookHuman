# Known Issues and Limitations

The current build is a polished prototype, not a content-complete commercial release.

- Keyboard/mouse and standard controller layouts are supported, including camera sensitivity and invert-Y options. Input remapping and broader accessibility presets are not implemented yet.
- Rangers and visitors use lightweight collision recovery rather than a full navigation mesh, so movement around unusually complex obstacle layouts may still be imperfect.
- Best records store the highest score per level. They do not retain a separate fastest-time leaderboard when two runs earn the same score tier.
- Visuals use simple low-poly geometry rather than a final authored asset set. Procedural body animation (player lean, pigeon WATCH crouch, personality ranger wind-ups) now communicates gameplay state without HUD, but artistic polish remains prototype-level.
- `Main.tscn` is retained as a legacy compatibility scene, but the menu and campaign use the reusable scenes under `scenes/levels`.
- Forced headless test shutdown can print non-fatal `ObjectDB instances were leaked at exit` warnings even though every validation exits successfully.

No known issue prevents completing the five-level campaign.
