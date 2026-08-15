# Known Issues and Limitations

The current build is a polished prototype, not a content-complete commercial release.

- Keyboard/mouse and standard controller layouts are supported, including camera sensitivity and invert-Y options. Reduce Motion & Flashes suppresses camera trauma, danger flashes/pulsing, and close-call slow motion while preserving gameplay cues. Input remapping, subtitle sizing, and dedicated color-vision presets are not implemented yet.
- Rangers and visitors use lightweight collision recovery rather than a full navigation mesh, so movement around unusually complex obstacle layouts may still be imperfect.
- Best records store the highest score per level. They do not retain a separate fastest-time leaderboard when two runs earn the same score tier.
- Visuals intentionally use simple low-poly geometry rather than a fully authored commercial asset set. Shared materials, distinct level palettes, expressive pigeon/ranger/visitor motion, and staged capture reactions now communicate gameplay state, but some props and environments remain prototype-level.
- `Main.tscn` is retained as a legacy compatibility scene, but the menu and campaign use the reusable scenes under `scenes/levels`.
- Some direct forced-shutdown Godot commands can print non-fatal `ObjectDB instances were leaked at exit` warnings. The strict validation runner distinguishes those shutdown diagnostics from runtime `ERROR`, `SCRIPT ERROR`, and parse failures.

No known issue prevents completing the five-level campaign.
