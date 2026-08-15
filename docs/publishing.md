# Publishing Status

The project is prepared as a `0.9.0` Windows release candidate. Automated validation, deterministic media generation, visible-renderer performance measurement, and local packaged-build smoke testing are repeatable. Store submission still requires identity, licensing, and external-machine decisions that belong to the developer rather than the codebase.

## Ready

- Custom game icon at `assets/branding/game_icon.png`
- Store capsule at `assets/branding/store_capsule.png`
- Windows release metadata and export preset
- Generated exports kept outside Git
- Persistent campaign reset and camera preferences
- Branded, controller-focusable menu, pause, HUD, and result presentation
- Persistent graphics, audio, and Reduce Motion & Flashes settings
- Reproducible screenshots and 33-second hook-first release trailer
- Five-level visible-renderer performance baseline
- Versioned Windows ZIP, bounded exported-EXE smoke test, exact-content verification, and SHA-256 checksum workflow
- Strict all-script validation runner

## Developer decisions still required

1. Choose a source-code license. Add a root `LICENSE` only after deciding between an open-source license and all-rights-reserved distribution.
2. Supply the developer, studio, or legal name for Windows company and copyright metadata.
3. Run the exported build on a separate Windows machine without Godot installed.
4. Choose a publishing destination, complete its store fields, and upload the ignored packaged build there.

## Release-candidate pipeline

Run the following from the project root. Replace the Godot path once and reuse it for each command.

```powershell
$godot = "C:\path\to\Godot_v4.7-stable_win64_console.exe"

.\tools\run_validations.ps1 -GodotPath $godot
.\tools\run_performance_benchmark.ps1 -GodotPath $godot

& $godot --path . --script res://tools/capture_portfolio_screenshots.gd
& $godot --path . --fixed-fps 30 --write-movie docs/gameplay_preview.avi --script res://tools/capture_gameplay_video.gd
.\tools\finalize_trailer.ps1 -Path docs\gameplay_preview.avi

.\tools\package_windows_release.ps1 `
  -GodotPath $godot `
  -Version "0.9.0" `
  -OutputRoot "export\release-candidate-p6"
```

The benchmark must use a visible renderer; its FPS figures are hardware-specific and advisory. The package script verifies an `MZ` executable, runs the exact staged executable headlessly with a timeout, verifies that the ZIP contains only the executable and player README, then writes and rechecks the checksum. The smoke test proves that the embedded PCK can start, its autoloads and main scene parse, and startup runs without detected errors; it does not load every campaign resource. It also does not prove Forward+ GPU compatibility, display/fullscreen/input behavior, clean-machine prerequisites, code signing, or SmartScreen reputation.

The versioned executable folder, ZIP, and checksum are written below `export/`; that directory is intentionally ignored by Git. Existing targets are never overwritten implicitly. Choose a new `-OutputRoot` for another candidate, increment the project/package version, or pass `-Force` only for an intentional same-version rebuild of the exact generated targets. Before uploading, complete one visible playthrough of the ZIP on a separate Windows machine without Godot installed.
