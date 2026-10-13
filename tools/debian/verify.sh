#!/bin/bash
set -euo pipefail
export PATH=/workspace/flutter/bin/cache/dart-sdk/bin:$PATH
cd /workspace/dart_simple_live/simple_live_app
dart /workspace/flutter/bin/cache/flutter_tools.snapshot pub get --offline
dart analyze lib/modules/multi_live lib/services/live_room_link_parser.dart lib/modules/mine/parse/parse_controller.dart lib/modules/home/home_page.dart lib/modules/mine/mine_page.dart lib/modules/live_room/player/player_controller.dart lib/testing/multi_live_probe.dart lib/testing/mini_player_probe.dart test/multi_live_test.dart lib/main.dart lib/routes/app_navigation.dart lib/services/live_room_session_service.dart lib/widgets/live_mini_player.dart lib/routes/app_pages.dart lib/modules/live_room/live_room_page.dart lib/modules/live_room/live_room_controller.dart test/live_room_session_test.dart
dart /workspace/flutter/bin/cache/flutter_tools.snapshot test --no-pub --reporter expanded test/live_playback_recovery_test.dart test/live_playback_monitor_test.dart test/douyin_search_test.dart test/douyu_play_urls_test.dart test/live_room_session_test.dart test/multi_live_test.dart
