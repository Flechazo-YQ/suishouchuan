#!/bin/bash
set -euo pipefail
mkdir -p build
for variable in APPLE_CERTIFICATE_P12 APPLE_CERTIFICATE_PASSWORD APPLE_PROFILE_APP APPLE_PROFILE_SHARE APPLE_PROFILE_CAPTURE APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER; do
  if [ -z "${!variable:-}" ]; then echo "Missing signing secret: $variable" >&2; exit 1; fi
done
SIGNING_DIR=$(mktemp -d)
KEYCHAIN_PATH="$SIGNING_DIR/commandv.keychain-db"
KEYCHAIN_PASSWORD=$(openssl rand -hex 24)
cleanup() {
  security delete-keychain "$KEYCHAIN_PATH" 2>/dev/null || true
  rm -rf "$SIGNING_DIR"
}
trap cleanup EXIT
export SIGNING_DIR
python3 - <<'PY'
import base64, os, pathlib
root=pathlib.Path(os.environ['SIGNING_DIR'])
for env, filename in [('APPLE_CERTIFICATE_P12','distribution.p12'),('APPLE_PROFILE_APP','app.mobileprovision'),('APPLE_PROFILE_SHARE','share.mobileprovision'),('APPLE_PROFILE_CAPTURE','capture.mobileprovision')]:
    (root/filename).write_bytes(base64.b64decode(os.environ[env]))
(root/('AuthKey_'+os.environ['APPLE_API_KEY_ID']+'.p8')).write_text(os.environ['APPLE_API_KEY'])
PY
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$SIGNING_DIR/distribution.p12" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security list-keychains -d user -s "$KEYCHAIN_PATH"
for profile_dir in "$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  mkdir -p "$profile_dir"
  for profile in "$SIGNING_DIR/"*.mobileprovision; do
    security cms -D -i "$profile" > "$SIGNING_DIR/profile.plist"
    profile_uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$SIGNING_DIR/profile.plist")
    cp "$profile" "$profile_dir/$profile_uuid.mobileprovision"
  done
done
case "${COMMANDC_SPONSORSHIP_PRODUCT_IDS:-}" in
  ''|com.flechazoyq.commandv.sponsorship.once) ;;
  *) echo 'Invalid CommandC sponsorship product ID' >&2; exit 1 ;;
esac
xcodebuild archive -project apps/ios/CommandV.xcodeproj -scheme CommandV \
  -destination 'generic/platform=iOS' -archivePath build/CommandV.xcarchive \
  CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Apple Distribution' \
  COMMANDC_SPONSORSHIP_PRODUCT_IDS="${COMMANDC_SPONSORSHIP_PRODUCT_IDS:-}" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH" \
  2>&1 | tee build/ios-archive.log
codesign --verify --deep --strict build/CommandV.xcarchive/Products/Applications/CommandV.app
python3 - <<'PY'
import json, os, pathlib, plistlib
root=pathlib.Path('build/CommandV.xcarchive/Products/Applications/CommandV.app')
records=[]
for bundle in [root,root/'PlugIns/CommandVShare.appex',root/'PlugIns/CommandVCapture.appex']:
    info=plistlib.loads((bundle/'Info.plist').read_bytes())
    assert info['UIDeviceFamily']==[1], 'Archive must target iPhone only'
    assert info['CFBundleVersion']==os.environ['BUILD_NUMBER'], 'Archive build number is incorrect'
    assert info['CFBundleDisplayName']=='CommandC', 'Incorrect app or extension display name'
    if bundle.name!='CommandVCapture.appex':
        assert info['CommandVKeychainGroup']=='65635WN76L.com.flechazoyq.commandv', 'Shared pairing group is incorrect'
    if bundle == root:
        assert info.get('CommandCSponsorshipProductIDs', '') == os.getenv('COMMANDC_SPONSORSHIP_PRODUCT_IDS', ''), 'Sponsorship build setting did not expand'
    records.append({key:info[key] for key in ['CFBundleIdentifier','CFBundleVersion','CFBundleShortVersionString','UIDeviceFamily','MinimumOSVersion','DTSDKName']})
json.dump(records,open('build/archive-metadata.json','w'),indent=2)
PY
cat > "$SIGNING_DIR/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>teamID</key><string>65635WN76L</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Apple Distribution</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>provisioningProfiles</key><dict>
<key>com.flechazoyq.commandv</key><string>CommandV AppStore</string>
<key>com.flechazoyq.commandv.share</key><string>CommandV Share AppStore</string>
<key>com.flechazoyq.commandv.capture</key><string>CommandV Capture AppStore</string>
</dict></dict></plist>
PLIST
xcodebuild -exportArchive -archivePath build/CommandV.xcarchive -exportOptionsPlist "$SIGNING_DIR/ExportOptions.plist" -exportPath build/export 2>&1 | tee build/ios-export.log
mkdir -p "$SIGNING_DIR/private_keys"
cp "$SIGNING_DIR/AuthKey_${APPLE_API_KEY_ID}.p8" "$SIGNING_DIR/private_keys/"
API_PRIVATE_KEYS_DIR="$SIGNING_DIR/private_keys" xcrun altool --upload-app --type ios --file build/export/CommandV.ipa --apiKey "$APPLE_API_KEY_ID" --apiIssuer "$APPLE_API_ISSUER" 2>&1 | tee build/ios-upload.log
