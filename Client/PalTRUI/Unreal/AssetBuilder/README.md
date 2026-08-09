# PalTR UI Asset Builder

Editor-only Unreal Engine 5.1 commandlet that creates the initial PalTRUI LogicMod assets:

- `/Game/Mods/PalTRUI/ModActor`
- `/Game/Mods/PalTRUI/WBP_PalTRPanel`

The generated widget is a renderer shell. It contains stable, named controls for the Clan, Diplomacy, Alliance, and Chat presentation models. It does not implement diplomacy rules, transport, or game-runtime attachment.

The generator refuses to overwrite either target asset.

Run the commandlet with `-UpdateRelationNavigation` to update an existing
panel in place with the renderer-facing `PreviousRelationButton` and
`NextRelationButton` controls. The update is idempotent and refuses partial
or unexpected widget hierarchies.

Run the commandlet with `-UpdateGuildCatalogPage` to reuse the postponed
chat page as the renderer-facing guild catalog page. The update changes the
visible heading and tab defaults to `Klanlar` and collapses the unused chat
composer without renaming renderer controls. It is idempotent and refuses an
unexpected legacy page hierarchy.

Run the commandlet with `-UpdateDiplomacyTheme` to wrap the existing tab bar
and content switcher in dark renderer frames and apply the gold, teal, green,
amber, and red diplomacy theme. The update preserves every renderer-facing
control name and refuses a partial theme hierarchy.

Run the commandlet with `-UpdatePendingOffersPanel` to add the renderer-facing
pending-offers frame to the Clan dashboard. The update adds stable heading and
content text controls, is idempotent, and refuses partial controls.

Run the commandlet with `-UpdateDashboardQuickActions` to add the renderer-facing
quick-actions card to the Clan dashboard. Its three stable buttons navigate to
the existing Diplomacy and Guilds presentation models without adding gameplay
rules or transport behavior. The update is idempotent and refuses partial controls.

Run the commandlet with `-UpdateDashboardStatusCards` to add side-by-side Clan
and Diplomacy status cards below the Clan heading. The cards consume only the
existing presentation model, preserve the detailed member and offer sections,
and collapse the superseded single-block summary. The update is idempotent and
refuses partial controls.

Run the commandlet with `-UpdateDashboardRelationsPreview` to add a compact
renderer-facing Relations card below the dashboard status cards. It lists only
guild names and relation labels already present in the snapshot presentation
model. The update is idempotent and refuses partial controls.

Run the commandlet with `-Verify` to load both generated classes and check the renderer-facing widget names without modifying the assets.
