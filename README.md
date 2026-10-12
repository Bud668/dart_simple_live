# Simple Live 小窗与稳定性修复 V3

这是 [xiaoyaocz/dart_simple_live](https://github.com/xiaoyaocz/dart_simple_live) 的修改版，基于 ba828e6783b176ea5709fcd09f0eb01dfaceeb51（1.11.4+11104），保留原作者版权和 GPL-3.0 许可证。

[下载 Windows x64 便携包](https://github.com/Bud668/dart_simple_live/releases/latest) · [修复与验证](docs/RELEASE_V3.md) · [构建说明](docs/BUILD.md)

## V3 改动

- 返回首页、搜索页时在 APP 内悬浮小窗继续播放；可拖动、暂停、关闭，点击返回原直播间。切房替换原播放，只保留一个会话。
- 斗鱼断流后重新获取房间状态、签名与播放地址，优先换线；只有平台确认下播才显示“未开播”。加入卡流检测、请求失效处理和有限重试。
- 斗鱼线路并发获取，一条失败保留其他可用线路；Windows 使用内存缓存。
- 抖音主播搜索使用内嵌官方“用户”页，房间搜索接口失败转官方“直播”页；旧搜索响应不会覆盖新关键词。

当前实际验证平台为 Windows x64。抖音官网可能要求自行登录或验证码，登录后的完整搜索结果和跳转尚未验收。其他平台保留源码，未发布本次二进制包。

## 使用

退出原来的 Simple Live，完整解压发布页上的 Simple-Live-Windows-x64-V3.zip，运行 simple_live_app.exe。窗口标题为“Simple Live（小窗修复 V3）”。DLL 与 data 目录必须保留；新旧版本共享设置目录，请只运行一个版本。

观看直播时返回上一页即显示小窗。点击画面返回时保留暂停状态，关闭小窗会停止播放并释放播放器。

26 项回归测试通过，Debian 生成的验证程序已在 Windows 完成真实视频和小窗操作验证。V2 恢复逻辑曾完成 12 分钟实播、4 次模拟断流并恢复；这些结果不能覆盖所有网络故障。

Flutter 3.38.10 / Dart 3.10.9。Windows 包的 Dart AOT 和资源在 Debian 构建，经 Wine 使用匹配的 Windows snapshot compiler。EXE 启动器和插件 DLL 沿用已有 1.11.4 Windows 文件，配套 Flutter 引擎已更新；本次没有重新编译 Windows 原生代码。

原项目文档见 [UPSTREAM_README.md](docs/UPSTREAM_README.md)。原始参考项目和声明保留如下。

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
