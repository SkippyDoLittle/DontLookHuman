# Known Issues and Limitations

The current build is a polished prototype, not a content-complete commercial release.

- Keyboard/mouse and standard controller layouts are supported. Input remapping and accessibility presets are not implemented yet.
- Best records store the highest score per level. They do not retain a separate fastest-time leaderboard when two runs earn the same score tier.
- The visuals and procedural audio are prototype-quality and use simple low-poly geometry rather than a final authored asset set.
- `Main.tscn` is retained as a legacy compatibility scene, but the menu and campaign use the reusable scenes under `scenes/levels`.
- Forced headless test shutdown can print non-fatal `ObjectDB instances were leaked at exit` warnings even though every validation exits successfully.

No known issue prevents completing the five-level campaign.
