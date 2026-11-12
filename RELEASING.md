<!-- SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech> -->
<!-- SPDX-License-Identifier: GPL-2.0-only -->

# CI and releases

Pull requests and pushes to `main` run two independent GitHub Actions checks:

- **Test** runs `swift test` against in-memory brightness storage. It does not
  change the runner's brightness settings or require illuminated-logo hardware.
- **Build** assembles and verifies an ad hoc signed ARM64 app and packages it
  in a DMG. The downloadable artifact is retained for 14 days. Ad hoc builds
  are for development and have not been notarized by Apple.

Both checks can also be started manually from the CI workflow. They use GitHub's
`xcode-27` ARM64 preview runner with Xcode 27.2, matching the app's macOS 27
minimum and Icon Composer requirements.

Pushing a stable version tag such as `v0.1.0` triggers the Release workflow.
It runs tests, signs with Developer ID and the hardened runtime, notarizes and
staples the app before packaging it, then signs, notarizes, and staples the DMG.
Only after verification succeeds does it publish the GitHub release with the
DMG, Sparkle appcast, corresponding source archive, and SHA-256 checksums. A
rerun replaces the assets on an existing release for that tag.

The tag sets the app's marketing version. The commit count at the tag sets its
numeric build version, which Sparkle compares to decide whether an update is
newer; release newer versions from the continuing `main` history so build
numbers keep increasing.

The Release workflow requires these repository Actions secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERT_P12` | Base64-encoded Developer ID Application certificate and matching private key, exported as PKCS#12 |
| `MACOS_CERT_PASSWORD` | Password protecting the PKCS#12 export |
| `NOTARY_KEY_P8` | Contents of the App Store Connect team API private key |
| `NOTARY_KEY_ID` | API key ID |
| `NOTARY_ISSUER_ID` | Team API issuer ID |
| `SPARKLE_ED_PRIVATE_KEY` | Sparkle EdDSA private key, exported with `generate_keys --account logoglow -x` |

The signing identity is pinned by fingerprint in the Release workflow and must
be updated when the certificate is replaced. Signing credentials are imported
into a temporary keychain and removed after the job, including on failure.
PR checks do not use these secrets.

For local signing, `Scripts/make-app.sh` accepts `CODESIGN_IDENTITY`,
`APP_VERSION`, and `BUILD_NUMBER`. `Scripts/notarize.sh` performs the full release
packaging and notarization process without publishing a GitHub release. It
requires `CODESIGN_IDENTITY` and either all three of `NOTARY_KEY_FILE`,
`NOTARY_KEY_ID`, and `NOTARY_ISSUER_ID`, or a `notarytool` Keychain profile named
`logoglow` (overridable with `NOTARY_PROFILE`). Keep private keys and certificate
exports outside the repository and back them up securely; Apple permits only
one download of an API private key.

## Updates

The app checks for updates with [Sparkle](https://sparkle-project.org). Its
`SUFeedURL` points at the `appcast.xml` attached to the latest GitHub release,
so every tag must publish as a full release, not a draft or pre-release.
The Release workflow signs the stapled DMG with the EdDSA private key and
generates `appcast.xml` from it; the app accepts only updates that verify
against `SUPublicEDKey` in `Scripts/Info.plist`.

The update prompt shows the release's notes followed by the notes of up to
four earlier releases, so someone skipping versions still sees what changed.
A release created in the GitHub UI keeps its written notes; a plain pushed tag
gets GitHub's generated notes.

The key pair was created with Sparkle's `generate_keys --account logoglow` and
lives in the login keychain of the machine that created it. Keep a backup of
the private key: losing it means existing installs can no longer verify
updates.
