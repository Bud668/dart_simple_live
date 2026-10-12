#!/bin/bash
set -euo pipefail
cd /workspace
export PATH=/workspace/flutter/bin/cache/dart-sdk/bin:$PATH
printf '%s\n' 'cafcda5721a78a7884db92f13c5e89f7643d52dd' > flutter/bin/cache/engine.stamp
printf '%s\n' 'cafcda5721a78a7884db92f13c5e89f7643d52dd' > flutter/bin/cache/engine-dart-sdk.stamp
chmod +x flutter/bin/cache/dart-sdk/bin/utils/* || true
cd /workspace/flutter/packages/flutter_tools
dart pub get --offline
cd /workspace
dart --snapshot=flutter/bin/cache/flutter_tools.snapshot --snapshot-kind=app-jit flutter/packages/flutter_tools/bin/flutter_tools.dart --version
dart flutter/bin/cache/flutter_tools.snapshot precache --linux --no-android --no-ios --no-web --no-windows --no-macos
