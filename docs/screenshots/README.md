# Screenshots

The five PNG files in this folder are captured from the actual Godot levels at 1280×720 without HUD overlays. The capture uses a fixed per-level seed, an explicit High presentation preset, staged camera/player transforms, silent music and ambience directors, and frozen actors after staging so local user settings and frame timing cannot rearrange the composition.

Regenerate them from the project root with:

```powershell
Godot_v4.7-stable_win64_console.exe --path . --script res://tools/capture_portfolio_screenshots.gd
```
