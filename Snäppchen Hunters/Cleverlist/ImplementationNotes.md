# Cleverlist

A SwiftUI shopping app with Swedish, German and English interfaces and product names.

## Data and sharing

Shopping lists and items are stored in Application Support/SnappchenHunters/shopping.json. Translated catalog terms, products, specific stores and walking routes live in catalog.json. Both are written atomically per file. Notification rules are device preferences in notification-rules.json; language and theme use UserDefaults.

Sharing uses CloudKit and CKShare, with one custom zone per explicitly shared list. Lists remain local/private until the owner chooses Share list → Set up sharing → Invite people. Invitations are restricted to specified recipients with edit access. Each list has independent participants, removal, stop-sharing and leave-list controls. Owners retain their local list when sharing stops; participants remove the local shared copy when they leave or revocation is observed. Legacy nearby pairing no longer runs, and its credentials do not grant iCloud access. Previously received local lists remain on the device; migration cannot retroactively withdraw copies sent by the old app.

Separate CKSyncEngine instances handle the private and shared databases. Shopping JSON is the durable outbox; cloud-sync.json stores account-scoped engine state, zone-to-local-ID mappings, record system fields and acknowledged payload fingerprints. Only the shared list header and its individual items are uploaded. Items carry their own referenced product/unit/category names; the global catalog, store routes, other lists and notification rules are never uploaded. Local IDs are remapped at the zone boundary to prevent cross-list overwrites. Cached account identity permits offline editing after relaunch, but network engines are created only after verifying the current iCloud account. Account changes stop old engines and isolate their data. Background pushes and foreground refresh trigger synchronization; delivery timing is controlled by the OS. Revocation cannot erase copies on an offline device until it reconnects.

Records have stable IDs, logical revisions and device tie-breaking. Concurrent edits to one record resolve deterministically to one version; simultaneous additions remain separate. Deletion tombstones are retained so older snapshots do not resurrect removed records. This is record-level merging, not field-level collaborative editing.

## Shopping

Create lists from the dashboard. Search in the bottom field; suggestions match all entered words across the three product translations by default. Settings → Search → Search all languages can restrict matching to the selected app language. This device-local choice persists across launches; results always use the selected app language. Tap a suggestion to add it immediately, or hold it to enter quantity and unit before adding. Canceling the quantity form adds nothing. Swipe an item left to reveal Delete. Tap an item to set optional quantity, unit, comment and color. The home banner opens the last-used list, remembered locally across launches. The plus button creates catalog products with all three names.

Choose a specific store in the centered picker to order sections by its walking route. The entire shopping list remains visible; picking a store does not hide items available elsewhere. Grouping and color menus work independently.

The preset catalog contains 1,188 generic products with Swedish, German and English names. The latest expansion adds 179 items across cosmetics, skin and hair care, oral care, baby accessories, first aid, health supplies, cleaning tools, stationery, travel and phone accessories, clothing basics, pet supplies, and convenience food. New entries use permanent IDs 7500–7678; the existing append-only migration adds them to saved catalogs without replacing customized records or restoring deleted products. This is a curated shopping vocabulary, not a sales-ranked top-5,000 dataset. Package sizes, brands and minor formulation variants are consolidated; quantities belong to shopping-list items. Dietary distinctions such as gluten-free pasta and lactose-free yogurt remain separate. GroceryDrugstoreCatalog.swift owns the product definitions and maps all former IDs 2000–6999 to their generic equivalents. Untouched historical variants are excluded from catalog browsing and counts but retained in storage for existing list references and older peers. Product lookup presents their generic names without changing item IDs, quantities, comments, checked state or sync clocks. User-edited products and deletion tombstones are preserved. Nine specific stores remain available; new store routes stay unconfigured until arranged by the shopper.

Settings edits translated chains, product types, sections and units. Specific stores have reorderable section boxes with accessible arrow controls as an alternative to dragging.

Notification rules combine filters within each rule; any matching enabled rule can notify. Name wildcard matching is case-insensitive in the selected language: * for arbitrary text, ? for one character. Notifications concern remote item changes received during sync.

## Artwork

Six seasonal themes use an adapted OpenMoji palette and unmodified OpenMoji vector art. Stronger seasonal gradients appear across shopping, home, settings and editors. Static, irregularly scattered white decorative suns, snowflakes, flowers and leaves are drawn with SF Symbols and original SwiftUI shapes. Decorations do not intercept touches or appear in VoiceOver. Light card surfaces preserve readability and item-specific color markings. See ArtworkCredits.md and in-app Settings for source and CC BY-SA 4.0 attribution.

## Validation

Catalog consolidation checks passed in a standalone Swift harness: 1,009 unique IDs and names in all three languages, valid category references, all 5,000 historical product IDs, fresh installation, upgrade/reload, quantity and checked-state preservation, custom products and edits, deletion tombstones, and repeated peer-sync idempotence. The harness used the production models/catalog and a temporary store copy with observation annotations removed and a minimal Theme stand-in. Xcode reported no diagnostics in the catalog or store files. Full Xcode build and snippet execution were blocked by the project's missing development team/provisioning profile. An unsigned simulator build was also blocked by local simulator services and compiler macro-plugin execution failures; app launch was not verified for this change.

The CloudKit implementation and its test target build successfully for the selected iOS simulator. All 11 Swift Testing regression tests passed: scoped metadata, cross-list overwrite rejection, deterministic conflicts/tombstones, offline persistence, read-only access, cached-account relaunch, retained private lists after retiring a zone, and safe local removal. Xcode runtime snippet checks also passed. Live invitations, CloudKit server conflicts, revocation and account switching across two iCloud accounts have not been exercised. See CloudKitSetup.md for container registration, provisioning, schema deployment and the two-account acceptance checklist.

Simulator interaction checks passed list creation, bottom search suggestions, adding and checking items, quantity editing, Swedish language switching and theme selection.

Data checks exercised persistence/reload, duplicate merge idempotence, deterministic concurrent-edit convergence, deletion preservation, wildcard matching, all three languages and preservation of corrupt files rather than overwriting them.
