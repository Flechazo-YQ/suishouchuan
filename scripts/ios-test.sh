#!/bin/bash
set -euo pipefail
mkdir -p build
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
xcodebuild test -project apps/ios/CommandV.xcodeproj -scheme CommandV \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" \
  -derivedDataPath build/DerivedData -resultBundlePath build/ios-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee build/ios-test.log
xcrun xcresulttool get test-results summary --path build/ios-tests.xcresult > build/test-summary.json
