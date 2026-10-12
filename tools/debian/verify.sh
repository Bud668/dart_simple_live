#!/bin/bash
set -euo pipefail
export PATH=/workspace/flutter/bin/cache/dart-sdk/bin:$PATH
cd /workspace/dart_simple_live/simple_live_app
dart /workspace/flutter/bin/cache/flutter_tools.snapshot pub get --offline
dart analyze lib/main.dart lib/routes/app_navigation.dart lib/services/live_room_session_service.dart lib/widgets/live_mini_player.dart lib/routes/app_pages.dart lib/modules/live_room/live_room_page.dart lib/modules/live_room/live_room_controller.dart test/live_room_session_test.dart
dart /workspace/flutter/bin/cache/flutter_tools.snapshot test --no-pub --reporter expanded test/live_playback_recovery_test.dart test/live_playback_monitor_test.dart test/douyin_search_test.dart test/douyu_play_urls_test.dart test/live_room_session_test.dart
