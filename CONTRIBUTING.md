# Contributing to Cleverlist

Thanks for helping improve Cleverlist. By participating, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before opening a pull request

1. Search existing issues and pull requests to avoid duplicate work.
2. Keep each change focused and explain the user-visible effect.
3. Do not include personal shopping data, CloudKit identifiers, invitation links, signing profiles, certificates, or credentials.
4. Build the Cleverlist scheme and run relevant tests before submitting.

## Development notes

The app supports Swedish, German, and English. New visible strings should provide all three translations. Keep private, local catalog information separate from data that is intentionally included in an iCloud-shared list.

iCloud sharing needs the app owner's CloudKit container and signing configuration; contributors can work on local features and tests without access to that account. Details are in [CloudKitSetup.md](Cleverlist/CloudKitSetup.md).

## Pull requests

Describe the problem, the solution, and how you tested it. Add or update tests when changing data handling, sharing, or synchronization behavior. Maintainers may request changes before merging.
