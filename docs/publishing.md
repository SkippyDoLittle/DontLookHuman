# Publishing Status

The project is prepared as a `0.9.0` Windows release candidate. Automated validation and local release smoke testing are repeatable, but publishing still requires decisions and checks that should belong to the developer rather than the codebase.

## Ready

- Custom game icon at `assets/branding/game_icon.png`
- Store capsule at `assets/branding/store_capsule.png`
- Windows release metadata and export preset
- Generated exports kept outside Git
- Persistent campaign reset and camera preferences
- Reproducible screenshots and 33-second hook-first release trailer
- Versioned Windows ZIP and SHA-256 checksum workflow
- Permanent Phase 3–10 validation suite

## Developer decisions still required

1. Choose a source-code license. Add a root `LICENSE` only after deciding between an open-source license and all-rights-reserved distribution.
2. Supply the developer, studio, or legal name for Windows company and copyright metadata.
3. Run the exported build on a separate Windows machine without Godot installed.
4. Choose a publishing destination, complete its store fields, and upload the ignored packaged build there.

## Release-candidate check

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/phase9_publishing_validation.gd
Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/phase10_release_media_validation.gd
.\tools\package_windows_release.ps1 -GodotPath "C:\path\to\Godot_v4.7-stable_win64_console.exe" -Version "0.9.0"
```

The versioned executable folder, ZIP, and checksum are written under `export/release/`; that directory is intentionally ignored by Git.
