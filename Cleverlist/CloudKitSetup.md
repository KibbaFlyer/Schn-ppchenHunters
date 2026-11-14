# CloudKit sharing setup

The code uses container `iCloud.com.Flygare.Cleverlist` and app identifier `com.Flygare.Cleverlist`. Local code, capabilities, share acceptance, per-list controls and regression tests are implemented. Registering the container, provisioning and exercising real iCloud accounts still require the app owner's Apple Developer account.

## Signing and container

1. In the Cleverlist target's Signing & Capabilities, select the intended Apple Developer team. The existing manual signing/profile choices have been preserved.
2. Enable iCloud → CloudKit and select/create `iCloud.com.Flygare.Cleverlist`. Associate the container with the app identifier in the developer account.
3. Enable Push Notifications. Background Modes → Remote notifications and CKSharingSupported are already configured in the Info.plist.
4. Regenerate the manual provisioning profiles with CloudKit and push entitlements, or use automatic signing with the chosen team. Check both device and macOS signing if distributing both.
5. Ensure archived distribution entitlements use the push environment from the distribution profile. The checked-in development entitlements are intended for development; Xcode's distribution export must use the matching profile.

The separate macOS entitlement file uses `com.apple.developer.aps-environment`; iOS uses `aps-environment`.

## Schema

In the container's development environment, create the record type `CleverlistRecord` with one field:

| Field | CloudKit type | Purpose |
| --- | --- | --- |
| payload | Bytes | Versioned JSON for one list header or one item, including its referenced display names. |

The first development save can create this type automatically when the account permits schema changes. No query indexes are needed: the app fetches record-zone changes through CKSyncEngine. Do not make the records publicly readable. The app uses only private/shared databases, and CKShare manages participant access.

Each custom zone is named `cleverlist-v1-<UUID>`. Its header record is named `list`; item record names are UUIDs. CKShare is a zone-wide share with publicPermission set to none.

Before TestFlight/App Store distribution, deploy the development schema to Production in CloudKit Console. Development and Production data are separate. Verify the signed build's container entitlement and environment.

## Acceptance on two accounts

Use two devices or simulators signed in to different iCloud accounts in the same CloudKit environment.

- Create lists A and B on the owner. Share A, invite the second account, and accept with the app both closed and already running. B must never appear on the participant.
- Add, rename, check/uncheck, change quantities and delete items from each side.
- Edit different items concurrently; both changes should arrive. Edit the same item concurrently; record revision then device ID resolves the conflict deterministically. This does not merge separate fields within one item.
- Disconnect a device, edit, terminate/relaunch, reconnect and use Sync now. Confirm that pending edits upload without duplication.
- Revoke a participant and reconnect their device. Confirm the list disappears, queued writes cannot restore it, and another private list is untouched.
- Stop sharing as owner, retain the local list, then share again. A new zone must be used; old invitations must not gain access to the new zone.
- Switch iCloud accounts. Old-account bindings must never upload to the new account.
- Verify product details on a shared item do not overwrite or expose the participant's private catalog.

Local Swift Testing coverage lives in CleverlistTests/CloudListSyncTests.swift and runs through the Cleverlist scheme. These tests validate local privacy boundaries, conflict ordering, tombstones, permissions and persistence. They do not replace the live CloudKit acceptance checks above.
