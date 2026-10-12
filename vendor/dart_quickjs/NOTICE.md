# Dependency provenance

Source: https://github.com/xiaoyaocz/dart_quickjs at a31682801e209f925cdb90fcf4e379e512b713d2. Its upstream README declares MIT License. Source copyright comments are retained.

QuickJS-ng source and MIT terms: third_party/quickjs-ng/LICENSE.
Dart native_toolchain_c source and BSD terms: packages/native_toolchain_c/LICENSE.

Local hook/build.dart uses the existing Windows x64 DLL when available; other targets retain source builds. The DLL came from the upstream Simple Live 1.11.4 Windows runtime, SHA256 dcd840ae142589614519fb498ffd6f0fd29f9af94c920731e01723a33622a296. The release retains original native notices.
