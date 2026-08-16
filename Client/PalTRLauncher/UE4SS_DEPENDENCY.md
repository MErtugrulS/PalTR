# PalTR Launcher dependency payload

This directory contains the Palworld-compatible UE4SS distribution required by
PalTRUI. It was staged from the verified local Steam Workshop installation:

- Package: `UE4SSExperimentalPW`
- Version: `experimental-palworld-6`
- Author: `Oak`
- Steam Workshop ID: `3625223587`
- UE4SS.dll SHA-256:
  `D0107F63E567313CB6A15C505B5DB2BDBA38130964A04E019BDA7611C6178022`

The upstream UE4SS license is distributed at
`Mods/NativeMods/UE4SS/LICENSE`. Launcher installation preserves an existing
`UE4SS-settings.ini`, `mods.txt`, and `mods.json` while backing up other files
before replacement.
