# Gameplay Preview

The repository includes `gameplay_preview.avi`, a ten-second, 30 FPS capture from the live Festival level. It demonstrates movement, sprint-triggered suspicion, ranger state feedback, a food pickup, NPC cover, and the minimap.

Regenerate the clip from the project root with Godot's Movie Maker mode:

```powershell
Godot_v4.7-stable_win64_console.exe `
  --path . `
  --fixed-fps 30 `
  --write-movie docs/gameplay_preview.avi `
  --script res://tools/capture_gameplay_video.gd
```

The automated clip is intended as a portfolio preview and capture regression. A manually directed and edited trailer remains a publishing task.
