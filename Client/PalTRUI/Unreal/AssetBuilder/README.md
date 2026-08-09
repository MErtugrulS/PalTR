# PalTR UI Asset Builder

Editor-only Unreal Engine 5.1 commandlet that creates the initial PalTRUI LogicMod assets:

- `/Game/Mods/PalTRUI/ModActor`
- `/Game/Mods/PalTRUI/WBP_PalTRPanel`

The generated widget is a renderer shell. It contains stable, named controls for the Clan, Diplomacy, Alliance, and Chat presentation models. It does not implement diplomacy rules, transport, or game-runtime attachment.

The generator refuses to overwrite either target asset.

Run the commandlet with `-Verify` to load both generated classes and check the renderer-facing widget names without modifying the assets.
