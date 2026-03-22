# Notarization Setup

## 1. Developer ID certificate

Install a valid `Developer ID Application` certificate in Keychain Access.

Check available identities:

```bash
security find-identity -v -p codesigning
```

## 2. Store notarytool credentials

Create an app-specific password for your Apple ID, then store credentials once:

```bash
xcrun notarytool store-credentials "MagicTrackNotary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "YOUR_APP_SPECIFIC_PASSWORD"
```

## 3. Build release artifacts

```bash
./tools/package_release.sh
./tools/package_dmg.sh
```

## 4. Sign and notarize the DMG

```bash
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export NOTARY_KEYCHAIN_PROFILE="MagicTrackNotary"
./tools/sign_and_notarize.sh
```

## 5. Verify

```bash
spctl -a -vvv dist/MagicTrack-1.1.0-2.dmg
```
