# 第三方组件与参考来源

## 随程序分发的代码

### vendor/qrcode — 二维码生成

- 来源：`qrcode-terminal` (npm)
- 许可证：**Apache License 2.0**
- 完整许可证文本：`vendor/qrcode/LICENSE`
- 本项目的修改：把 `main.js` / `index.js` 里的相对 `require` 路径改为同目录引用，
  以便脱离 npm 目录结构使用。除此之外未改动算法实现。

内含的 QR 编码器原始作者为 Kazuhiko Arase（`vendor/qrcode/index.js` 头部有原始声明）。

Apache-2.0 要求：保留许可证与声明、注明修改。以上均已满足。

## 仅作协议参考、未复制代码

以下项目用于理解森空岛的签名算法与接口格式。**本项目是独立实现，未复制其源代码。**

| 项目 | 许可证 | 用途 |
|---|---|---|
| [nonebot-plugin-skland](https://github.com/FrostN0v0/nonebot-plugin-skland) | MIT | 签名算法（hmac-sha256 → md5）与终末地接口路径 |
| [Skland_API](https://github.com/ProbiusOfficial/Skland_API) | MIT | 鹰角账号 → OAuth → cred 的登录流程文档 |
| [skland-daily-attendance](https://github.com/AEtherside/skland-daily-attendance) | AGPL-3.0 | 仅阅读，理解签到接口（未参考其实现细节） |

## 不使用、未分发的资源

- 游戏本体资源（立绘、语音、UI 图）—— 版权归鹰角网络，本项目不附带
- 角色「祀」的形象与设定 —— 同上，属二次创作范畴

## 免责声明

本项目通过森空岛官方 App 的授权流程读取**使用者本人**账号的只读数据，
不进行签到、领取奖励或其他写操作。使用风险（包括账号安全）由使用者自行承担。
