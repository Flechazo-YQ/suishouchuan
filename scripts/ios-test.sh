#!/bin/bash
set -euo pipefail
mkdir -p build
# The simulator SDK omits ScreenCaptureKit, so validate the real capture implementation separately.
xcodebuild build -project apps/ios/CommandV.xcodeproj -scheme CommandV \
  -destination 'generic/platform=iOS' -derivedDataPath build/DeviceData \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO PROVISIONING_PROFILE_SPECIFIER= \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" 2>&1 | tee build/ios-device-build.log
npm --prefix apps/desktop ci --ignore-scripts --no-audit --no-fund > build/ios-dependencies.log 2>&1
export COMMANDV_TEST_FIXTURE="$RUNNER_TEMP/commandv-receiver.json"
node apps/desktop/node_modules/tsx/dist/cli.mjs scripts/ios-receiver-fixture.ts "$COMMANDV_TEST_FIXTURE" > build/receiver.log 2>&1 &
RECEIVER_PID=$!
trap 'kill "$RECEIVER_PID" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  [ -f "$COMMANDV_TEST_FIXTURE" ] && break
  kill -0 "$RECEIVER_PID"
  sleep 1
done
test -f "$COMMANDV_TEST_FIXTURE"
swift test --package-path apps/ios 2>&1 | tee build/ios-core.log
kill "$RECEIVER_PID"
wait "$RECEIVER_PID"
python3 - <<'PY'
import json, os
result=json.load(open(os.environ['COMMANDV_TEST_FIXTURE']+'.result'))
assert result['clipboardWrites']==2 and result['successfulTransfers']==2, result
json.dump(result,open('build/receiver-result.json','w'))
PY
trap - EXIT
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); phones=[x for group in d["devices"].values() for x in group if x["name"].startswith("iPhone")]; print(phones[0]["udid"])')
xcodebuild build-for-testing -project apps/ios/CommandV.xcodeproj -scheme CommandV \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES \
  'CODE_SIGN_LOCAL_EXECUTION_IDENTITY=Ad Hoc' PROVISIONING_PROFILE_SPECIFIER= \
  AppIdentifierPrefix=65635WN76L. CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" 2>&1 | tee build/ios-build.log
# Simulator entitlements are linked into Mach-O, separate from the ad-hoc signature.
python3 - <<'PY'
import os, plistlib, pathlib
base=pathlib.Path('build/DerivedData/Build')
for target, product in [('CommandV','CommandV.app'),('CommandVShare','CommandVShare.appex')]:
    root=base/'Products/Debug-iphonesimulator'/product
    info=plistlib.loads((root/'Info.plist').read_bytes())
    assert info['UIDeviceFamily']==[1], 'This target must be iPhone only'
    assert info['CFBundleVersion']==os.environ.get('GITHUB_RUN_NUMBER','1'), 'Build number was not expanded'
    raw=(base/'Intermediates.noindex/CommandV.build/Debug-iphonesimulator'/(target+'.build')/(product+'-Simulated.xcent')).read_bytes()
    entitlements=plistlib.loads(raw)
    assert info['CommandVKeychainGroup'] in entitlements.get('keychain-access-groups',[]), entitlements
    assert raw in (root/info['CFBundleExecutable']).read_bytes(), 'Simulator entitlement section missing'
PY
test_selection=(-parallel-testing-enabled NO)
if [[ "${COMMANDC_TEST_SPONSORSHIP_ONLY:-0}" == '1' ]]; then
  test_selection+=(-only-testing:CommandVTests/SponsorshipStoreTests -test-timeouts-enabled YES -default-test-execution-time-allowance 90 -maximum-test-execution-time-allowance 180)
fi
xcodebuild test-without-building -project apps/ios/CommandV.xcodeproj -scheme CommandV \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData -resultBundlePath build/ios-tests.xcresult \
  "${test_selection[@]}" \
  2>&1 | tee build/ios-test.log
xcrun xcresulttool get test-results summary --path build/ios-tests.xcresult > build/test-summary.json
