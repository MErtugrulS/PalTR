# PalTRUI manual widget baseline

The runtime loads only this widget blueprint:

`/Game/Mods/PalTRUI/WBP_PalTRPanel`

`WBP_PalTRPanel_SkinV2` and the generated dashboard chrome layers are no
longer part of the runtime. `WBP_PalTRPanel` is intentionally restored to the
last functional baseline from before the automatic visual redesigns.

## Editing boundary

- Edit layout, brushes, typography, spacing and animations in Unreal Editor.
- Keep the existing named controls when their corresponding runtime feature is
  required.
- Do not rename `ContentSwitcher`, the four tab buttons or their text widgets.
- Presentation-only dashboard controls may be added or removed; the Lua binder
  treats them as optional.
- Keep the images under `DesignReference/pixel-match-1672x941` as visual
  references only. They are not loaded as a full-screen runtime overlay.

## Stable runtime controls

The core runtime expects the existing controls for:

- panel root, input shield, close button and connection status;
- `ContentSwitcher` and the Clan, Diplomacy, Alliance and Guild pages;
- tab buttons and tab label text widgets;
- clan, diplomacy, alliance and guild text fields;
- relation and alliance navigation/action buttons;
- header status text and footer hint text.

Before replacing the asset, run the AssetBuilder verification command or the
Lua tests to catch accidental control-name changes.
