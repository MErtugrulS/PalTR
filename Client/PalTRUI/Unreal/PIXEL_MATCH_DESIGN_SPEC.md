# PalTR UI Pixel Match Design Spec

Reference viewport: 1920 x 1080. Measurements are normalized from the
1680 x 945 target capture.

## Geometry

| Region | X | Y | Width | Height |
| --- | ---: | ---: | ---: | ---: |
| Root panel | 107 | 45 | 1696 | 978 |
| Header | 115 | 48 | 1680 | 76 |
| Sidebar | 115 | 137 | 297 | 806 |
| Main content | 448 | 137 | 901 | 806 |
| Right column | 1379 | 137 | 402 | 806 |
| Footer | 115 | 967 | 1680 | 56 |

- Root anchors: `(0.055, 0.040)` to `(0.945, 0.955)`.
- Header crest: 70 x 68; header padding: 8.
- Sidebar width: 296; body column gap: 32.
- Main/right dashboard weight ratio: 2.25:1.
- Dashboard height: 650; status-card gap: 16; lower-row gap: 16.
- Status cards: approximately 205 x 286.
- Parchment title bands: 56-66 high with 12 x 8 content padding.
- Navigation row: 58 high; icon: 36; label gap: 14.
- Quick-action row: 56 high; icon: 32; arrow: 20.
- Footer: 56 high, centered usage hint.

## Typography

- Brand: 32 UMG font units, warm ivory, heavy shadow.
- Page title: 26 UMG font units, warm ivory.
- Section title: 18-20 UMG font units, warm ivory/gold.
- Card title: 17-18 UMG font units.
- Card value: 22-24 UMG font units.
- Body: 13-15 UMG font units.
- Metadata/time: 11-12 UMG font units.

The packaged font fallback remains in place until a redistributable serif
font is imported. Headings and body copy still use distinct size, color,
weight, and shadow hierarchies.

## Theme palette

| Token | Hex |
| --- | --- |
| Background | `#0B1720` |
| Panel dark | `#182833` |
| Sidebar dark | `#19262F` |
| Panel blue | `#284255` |
| Relation dark | `#2E2E2A` |
| Card teal | `#2C4B4B` |
| Card blue | `#304758` |
| Card gold | `#5C4B2C` |
| Card bronze | `#46392B` |
| Gold | `#C69A48` |
| Gold muted | `#836B3C` |
| Cyan selected | `#2F5261` |
| Cyan glow | `#28D9ED` |
| Green success | `#39795B` |
| Red danger | `#87382D` |
| Parchment | `#C3A47B` |
| Text primary | `#F2E8D5` |
| Text secondary | `#B8B9B5` |

## Asset roles

- `paltr_panel_frame.png`: scalable outer frame and navy textured surface.
- `paltr_parchment_header.png`: scalable parchment section-title surface.
- `paltr_icon_clan.png`: crest, clan cards, guild rows, and clan navigation.
- `paltr_icon_diplomacy.png`: diplomacy cards/actions/navigation.
- `paltr_icon_protection.png`: future protection card/action/navigation.
- `paltr_icon_buildings.png`: future structures card/navigation.

All gameplay, transport, snapshot, view-model, interaction, and input
contracts remain outside this visual pass.
