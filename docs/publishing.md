# Publishing Status

The project is prepared as a `0.9.0` Windows release candidate. Automated validation and local release smoke testing are repeatable, but publishing still requires decisions and checks that should belong to the developer rather than the codebase.

## Ready

- Custom game icon at `assets/branding/game_icon.png`
- Store capsule at `docs/branding/store_capsule.png`
- Windows release metadata and export preset
- Generated exports kept outside Git
- Persistent campaign reset and camera preferences
- Reproducible screenshots and gameplay preview
- Permanent Phase 3–9 validation suite

## Developer decisions still required

1. Choose a source-code license. Add a root `LICENSE` only after deciding between an open-source license and all-rights-reserved distribution.
2. Supply the developer, studio, or legal name for Windows company and copyright metadata.
3. Run the exported build on a separate Windows machine without Godot installed.
4. Replace or extend the automated ten-second preview with a hand-edited 20–30 second trailer.
5. Choose a publishing destination, complete its store fields, and upload the ignored packaged build there.

## Release-candidate check

```powershell
Godot_v4.7-stable_win64_console.exe --headless --path . --script res://tests/phase9_publishing_validation.gd
Godot_v4.7-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" "export/phase9/DontLookHuman.exe"
```

The executable and any ZIP package belong under `export/`; that directory is intentionally ignored by Git.
