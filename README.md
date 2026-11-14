# Cleverlist

Cleverlist is a local-first shopping-list app for Apple platforms. Create lists, organize a multilingual grocery and drugstore catalog, and optionally share an individual list with people you invite through iCloud.

## Privacy at a glance

Shopping data is stored locally by default. Cleverlist has no account system, advertising, third-party analytics, or developer-operated backend. When you choose to share a list, that list and its items are stored in Apple CloudKit and are available to the people you invite. Read the full [data-use information](docs/privacy.md).

## Build and run

1. Open `Cleverlist.xcodeproj` in Xcode.
2. Select the Cleverlist scheme and a compatible simulator or signed device.
3. Build and run.

Local list and catalog features work without any Apple Developer configuration. iCloud sharing and remote change delivery require a signed app identifier, the `iCloud.com.Flygare.Cleverlist` CloudKit container, Push Notifications, and a provisioning profile that includes those capabilities. See [CloudKit setup](Cleverlist/CloudKitSetup.md) before testing that functionality on devices.

## Documentation

- [Support](docs/index.md)
- [Data use and privacy](docs/privacy.md)
- [Contributing](CONTRIBUTING.md)
- [Security policy](SECURITY.md)
- [Artwork and third-party notices](THIRD_PARTY_NOTICES.md)

The `docs` directory is ready to publish with GitHub Pages. In the repository settings, select **Deploy from a branch**, choose the default branch, and set the folder to **/docs**.

## License

The Cleverlist source code is available under the [MIT License](LICENSE). Some bundled artwork is separately licensed under CC BY-SA 4.0; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
