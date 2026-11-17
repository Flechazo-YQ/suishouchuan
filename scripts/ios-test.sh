#!/bin/bash
set -euo pipefail
mkdir -p build
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); phones=[x for group in d["devices"].values() for x in group if x["name"].startswith("iPhone")]; print(phones[0]["udid"])')
xcodebuild test -project apps/ios/CommandV.xcodeproj -scheme CommandV \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData -resultBundlePath build/ios-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/ios-test.log
xcrun xcresulttool get test-results summary --path build/ios-tests.xcresult > build/test-summary.json
