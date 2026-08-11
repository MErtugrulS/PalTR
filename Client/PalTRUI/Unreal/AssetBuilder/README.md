# PalTR UI Asset Builder

Editor-only Unreal Engine 5.1 commandlet that creates the initial PalTRUI LogicMod assets:

- `/Game/Mods/PalTRUI/ModActor`
- `/Game/Mods/PalTRUI/WBP_PalTRPanel`

The generated widget is a renderer shell. It contains stable, named controls for the Clan, Diplomacy, Alliance, and Chat presentation models. It does not implement diplomacy rules, transport, or game-runtime attachment.

The generator refuses to overwrite either target asset.

Run the commandlet with `-CreateManualDesignTemplate` to create the independent
`/Game/Mods/PalTRUI/WBP_PalTRPanel_DesignTemplate` visual-design starter. It
contains only a reference-like component hierarchy, placeholder content,
button hover styles, and a full-panel pointer shield. It deliberately has no
snapshot binding, diplomacy actions, transport, or runtime attachment and
refuses to overwrite an existing template asset.

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

Run the commandlet with `-UpdateAllianceDetailPanel` to add the renderer-facing
Alliance detail card and Previous/Next controls. The controls reuse the existing
client relation navigator and do not add alliance rules or transport behavior.
The update is idempotent and refuses partial controls.

Run the commandlet with `-UpdateGuildCatalogCards` to replace the visible legacy
chat list with side-by-side Active and Registered guild presentation cards. The
legacy chat controls remain named but collapsed, and no chat behavior is enabled.
The update is idempotent and refuses partial controls.

Run the commandlet with `-UpdateHeaderStatusBadges` to add renderer-facing Guild,
Role, and pending-offer Notification badges to the existing header row. The values
come only from the current snapshot presentation model. The update is idempotent
and refuses partial controls.

Run the commandlet with `-UpdateFooterHints` to add a static F6/Tab usage strip to
the bottom of the existing panel layout. It does not register or alter input
behavior. The update is idempotent and refuses partial controls.

Run the commandlet with `-UpdateClanMembersPanel` to wrap the existing Clan member
list in a renderer-facing card with dynamic member-count and presence summary
controls. It preserves the existing member list control, is idempotent, and
refuses partial or unexpected widget hierarchies.

Run the commandlet with `-UpdatePanelInputShield` to wrap the complete visual panel
in a transparent renderer-facing button. The wrapper consumes otherwise-unhandled
pointer clicks inside the panel bounds without adding gameplay behavior. The
update is idempotent and refuses partial or unexpected widget hierarchies.

Run the commandlet with `-UpdateClanPageScroll` to wrap the existing Clan page in
a vertical scroll container. This keeps the footer and lower dashboard cards
inside the fixed panel bounds without changing presentation data or interactions.
The update is idempotent and refuses partial or unexpected widget hierarchies.

Run the commandlet with `-UpdatePremiumTheme` to apply the dark navy and gold
Palworld-inspired presentation pass. It gives the top navigation equal-width
tabs, harmonizes dashboard/detail frames and status badges, and preserves every
renderer-facing control name and interaction.

Run the commandlet with `-UpdateAllPageScrollInput` to wrap every panel page in
a wheel-consuming scroll box. This prevents wheel events over Diplomacy,
Alliance, and Guilds from reaching gameplay weapon selection.

Run the commandlet with `-UpdateDashboardColumnLayout` to reorganize the Clan
dashboard into a wide status/member workspace and a compact relations,
pending-offers, and quick-actions sidebar. Renderer-facing widget names and
snapshot bindings remain unchanged.

Run the commandlet with `-UpdatePresentationHierarchy` to add a framed command
header, descriptive page introductions, a titled dashboard sidebar, and separate
Diplomacy list/detail cards. It changes presentation hierarchy only and keeps
the existing renderer and action widget names intact.

Run the commandlet with `-UpdateArtDashboard` to import the project-owned panel
art and four dashboard emblems, replace the top tab strip with left navigation,
and compose the Clan home page as four status cards, recent events, quick
actions, relations, and pending offers. Protection and Buildings are explicitly
mocked as future-phase cards; Clan and Diplomacy keep their live bindings.

Run the commandlet with `-UpdateReferenceSecondaryPages` to carry the same
navy, gold, parchment-title, and rounded-card presentation into Diplomacy,
Alliance, and Guilds. The update keeps the existing renderer and action widget
names, and only adds named presentation containers that `-Verify` also checks.

Run the commandlet with `-UpdatePixelMatchVisual` after the art-dashboard and
secondary-page updates. It applies the measured 1920x1080 target anchors and
column weights, imports the project-owned parchment title texture, adds icon
presentation to navigation and recent-event rows, and tightens the shared
header, footer, card, and typography hierarchy. It preserves all renderer,
view-model, interaction, transport, and input control names.

Run the commandlet once with `-CreateSkinV2` to create the parallel
`WBP_PalTRPanel_SkinV2` production candidate. The command imports the cleaned
1672x941 raster shell, duplicates the proven interaction widget tree, and makes
the duplicated tree a dynamic text/input overlay. It refuses to overwrite an
existing SkinV2 asset and never modifies `WBP_PalTRPanel`. Sidebar icons,
labels, ordering, visibility, enabled state, and selection remain runtime UMG
controls rather than baked skin content, so future entries can be replaced
without regenerating the shell texture.

Run the commandlet with `-VerifySkinV2` to verify the parallel panel, full-canvas
shell geometry, and the minimum renderer/interaction controls without modifying
either panel asset.

Run the commandlet with `-Verify` to load both generated classes and check the renderer-facing widget names without modifying the assets.
