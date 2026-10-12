# 构建说明

## 常规 Windows 构建

Flutter 3.38.10 / Dart 3.10.9，配备 Flutter 要求的 Visual Studio C++ 桌面工具链：

    cd simple_live_app
    flutter pub get
    flutter build windows --release

pubspec_overrides.yaml 使用相对路径 ../vendor/dart_quickjs。Windows x64 hook 使用附带 DLL，其他平台从附带源码构建；本次不是全平台二进制验证。

回归测试：

    cd simple_live_app
    flutter test test/live_playback_recovery_test.dart test/live_playback_monitor_test.dart test/douyin_search_test.dart test/douyu_play_urls_test.dart test/live_room_session_test.dart

## 本次 Debian 构建

只重新构建 Windows Dart AOT 和资源：Linux Dart 前端搭配同版本 Windows gen_snapshot.exe，由 Wine 运行。启动器和插件未重编译；如修改 C++ 或升级原生插件，需完整 Windows 工具链和验证。

tools/debian 保留已配置环境的重复构建脚本，不是首次安装一键脚本。工作目录挂载到容器 /workspace，需准备：

- dart_simple_live/：本仓库与 vendor；
- flutter/：Flutter 3.38.10 源码、Linux Dart SDK、已初始化 flutter_tools snapshot、匹配的 Windows 引擎资源与字体工具；
- pub-cache/：Flutter 工具及应用依赖缓存；
- windows-compiler/gen_snapshot.exe：匹配引擎的 Windows x64 编译器；
- logs/、wine-runtime/、wine-prefix/：构建目录。

复制 tools/debian 中脚本到工作目录根；将 gen_snapshot.py 放到 flutter/bin/cache/artifacts/engine/windows-x64-release/gen_snapshot 并赋予执行权限。引擎版本 cafcda5721a78a7884db92f13c5e89f7643d52dd。

    docker build -t simple-live-build:v3 .
    ./run-build.sh

容器限制 6 CPU、8 GiB 内存，先编译发布与小窗验证入口，再检查和测试。输出在 simple_live_app/build/remote_release 与 remote_probe；需结合匹配的 Windows runtime 打包，不能单独运行。

清空 Flutter 编译缓存、保留 SDK 和依赖后，实测发布 AOT/资源构建 29.23 秒，重复 2.61 秒；不含首次准备、传输及 Windows 验证。

## 依赖来源

vendor/dart_quickjs 基于 https://github.com/xiaoyaocz/dart_quickjs 提交 a31682801e209f925cdb90fcf4e379e512b713d2。保留 QuickJS-ng 与 native_toolchain_c 源码及许可。详见 vendor/dart_quickjs/NOTICE.md。
