# Contributing

Thanks for helping improve DeepSeek Harness iOS.

## Before opening an issue or pull request

- Search existing issues first.
- Reproduce the problem on a supported iOS version when possible.
- Remove private URLs, cookies, tokens, certificates, screenshots and personal data from logs.
- Keep changes focused on the iOS client shell; server-side Harness changes belong in the server project.

## Development

1. Fork the repository and create a focused branch.
2. Open `DeepSeekHarness.xcodeproj` with Xcode on macOS.
3. Test on an iOS 15+ simulator or physical device. Network, WebSocket/SSE and file behavior should also be checked against a real Harness instance when relevant.
4. Confirm that no signing material or private deployment details are included.
5. Describe behavior changes and test coverage in the pull request.

There is no requirement to submit a signed binary. The repository workflow builds an unsigned IPA for maintainers and personal users.
