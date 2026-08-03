# Release Trailer

The repository includes `gameplay_preview.avi`, a 33-second, 1280×720, 30 FPS hook-first release trailer captured from the live Godot project.

The cut deliberately avoids an opening logo. It begins on a Festival theft beside a ranger, turns that pickup into immediate danger, uses Lakeside for the "ACT NATURAL." flock gag, cuts three Playground pickups to the rising beat, and escalates into a four-ranger Botanical Gardens escape. The pigeon vanishes into the exit just before the rangers arrive; "JUST A PIGEON." provides the final hook before the animated store artwork and "WISHLIST NOW" reveal.

`tools/trailer_soundtrack.gd` generates the original synchronized score. The capture emphasizes pecks, pickups, alerts, the portal, and the escape sting over that music bed.

## Regenerate and validate

Run these commands from the project root:

```powershell
Godot_v4.7-stable_win64_console.exe `
  --path . `
  --fixed-fps 30 `
  --write-movie docs/gameplay_preview.avi `
  --script res://tools/capture_gameplay_video.gd

.\tools\finalize_trailer.ps1 -Path docs\gameplay_preview.avi
```

The capture produces exactly 990 video frames and 990 synchronized audio chunks. All text and artwork are animated during capture, so the finalizer no longer replaces static frames. It normalizes Godot's four-byte RIFF length field when necessary, then verifies the movie chunks, audio/video parity, and complete AVI index before the trailer is shipped.

See `docs/trailer_treatment.md` for the creative treatment, timing map, and honest recommendations for future footage upgrades.
