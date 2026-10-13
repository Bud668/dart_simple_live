# Simple Live 多画面 V4

基于 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live) 的修改版，上游基线 ba828e6783b176ea5709fcd09f0eb01dfaceeb51（1.11.4+11104），保留原作者版权与 GPL-3.0 许可证。

[下载 Windows x64 便携包](https://github.com/Bud668/dart_simple_live/releases/latest) · [V4 使用说明](docs/RELEASE_V4.md) · [V3 修复记录](docs/RELEASE_V3.md) · [构建说明](docs/BUILD.md)

## V4 多画面

- 支持 APP 内 2、3、4、9 画面，从关注列表、房间号或手机分享链接添加直播。
- 每格可暂停、刷新、切清晰度、放大和关闭。双击放大或还原；每一路独立检测卡流和有限重连。
- 点喇叭切换声音，同一时间只收听一路；支持全部静音。
- 从直播间或悬浮小窗进入，会将当前房间接入第一格。返回首页会停止全部多画面。
- 默认中间清晰度，每路缓存最多 16 MiB。九路播放的实际负载取决于视频分辨率、解码器和网络。

首页右上角网格按钮、「我的 → 多画面」以及直播间「加入多画面」均可进入。V3 的普通直播间悬浮小窗、斗鱼断流恢复与抖音官方网页搜索保留。抖音官网可能要求登录或验证码，登录后的完整搜索结果和跳转尚未验收。

## 使用与验证

退出旧版后完整解压 Simple-Live-Windows-x64-V4.zip，运行 simple_live_app.exe，保留全部 DLL 与 data 目录。窗口标题为「Simple Live（多画面 V4）」。新旧版本共享用户设置，请只运行一个正式版本。

修改代码静态检查及 33 项回归测试通过。Windows 实机验证范围和结果见发布附件 Windows-runtime-validation.json。其他平台保留源码，本次没有进行二进制验证。

Flutter 3.38.10 / Dart 3.10.9。Dart AOT 与资源在 Debian 构建，通过 Wine 使用匹配的 Windows snapshot compiler。Windows 启动器和原生插件复用已有运行文件，未重新编译原生代码。源码、许可与第三方声明随版本提供。

原项目文档见 [UPSTREAM_README.md](docs/UPSTREAM_README.md)。以下保留上游项目介绍。

---

<p align="center">
    <img width="128" src="/assets/logo.png" alt="Simple Live logo">
</p>
<h2 align="center">Simple Live</h2>

<p align="center">
简简单单的看直播
</p>

![浅色模式](/assets/screenshot_light.jpg)

![深色模式](/assets/screenshot_dark.jpg)

## 支持直播平台：

- 虎牙直播

- 斗鱼直播

- 哔哩哔哩直播

- 抖音直播

## APP支持平台

- [x] Android
- [x] iOS
- [x] Windows `BETA`
- [x] MacOS `BETA`
- [x] Linux `BETA`
- [x] Android TV `BETA`

## 项目结构

- `simple_live_core` 项目核心库，实现获取各个网站的信息及弹幕。
- `simple_live_console` 基于simple_live_core的控制台程序。
- `simple_live_app` 基于核心库实现的Flutter APP客户端。
- `simple_live_tv_app` 基于核心库实现的Flutter Android TV客户端。

## 环境

Flutter : `3.38`

## 参考及引用

[AllLive](https://github.com/xiaoyaocz/AllLive) `本项目的C#版，有兴趣可以看看`

[dart_tars_protocol](https://github.com/xiaoyaocz/dart_tars_protocol.git)

[wbt5/real-url](https://github.com/wbt5/real-url)

[lovelyyoshino/Bilibili-Live-API](https://github.com/lovelyyoshino/Bilibili-Live-API/blob/master/API.WebSocket.md)

[IsoaSFlus/danmaku](https://github.com/IsoaSFlus/danmaku)

[BacooTang/huya-danmu](https://github.com/BacooTang/huya-danmu)

[TarsCloud/Tars](https://github.com/TarsCloud/Tars)

[YunzhiYike/douyin-live](https://github.com/YunzhiYike/douyin-live)

[5ime/Tiktok_Signature](https://github.com/5ime/Tiktok_Signature)

## 声明

本项目的所有功能都是基于互联网上公开的资料开发，无任何破解、逆向工程等行为。

本项目仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关。

如果本项目存在侵犯您的合法权益的情况，请及时与开发者联系，开发者将会及时删除有关内容。

## Star History

<a href="https://www.star-history.com/#xiaoyaocz/dart_simple_live&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=xiaoyaocz/dart_simple_live&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=xiaoyaocz/dart_simple_live&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=xiaoyaocz/dart_simple_live&type=Date" />
 </picture>
</a>
