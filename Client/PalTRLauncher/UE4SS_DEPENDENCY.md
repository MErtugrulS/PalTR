# PalTR Launcher dependency payload

This directory contains the Palworld-compatible UE4SS distribution required by
PalTRUI. The runtime is installed under `Pal/Binaries/Win64` so the proxy DLL
can load UE4SS before PalTRUI starts:

- Runtime package: `Okaetsu/RE-UE4SS`, release `experimental-palworld`
- Asset: `UE4SS-Palworld.zip`
- Published: `2025-02-20`
- Steam Workshop ID: `3625223587`
- Archive SHA-256:
  `768A45718FBB9E429AC5CC3CE4A139A1B7B468BFF31B4A136AE483D725ACA1CA`

The upstream UE4SS license is distributed at
`Pal/Binaries/Win64/ue4ss/LICENSE`. Launcher installation preserves an existing
`UE4SS-settings.ini`, `mods.txt`, and `mods.json`, backs up replaced files, and
disables the conflicting Workshop `UE4SS.dll` instead of double-loading it.
