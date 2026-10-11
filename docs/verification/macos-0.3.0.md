# Sofatap 0.3.0 Mac 公证与实机验收

本文品牌写法已统一为 Sofatap；下文引号中的旧 `.app` 文件名是已公证归档内的实际路径，不代表当前品牌写法。

记录日期：**2026-10-11**。发布：[v0.3.0-alpha](https://github.com/chekusu/sofatap/releases/tag/v0.3.0-alpha)。

两份 Mac 安装包均由干净的源码版本 **`8e6d0cea771b1e1b7879aff94bce437cb971298a`** 构建。此记录是随后补充的验证文档；后续文档提交不会改变已签名、公证安装包对应的源码版本。

## 安装包验证

| 项目 | Apple Silicon（arm64） | Intel（x64） |
| --- | --- | --- |
| Developer ID 签名 | CHEKUSU INC.；应用、原生窗口与接收组件校验通过 | 同左 |
| Apple 公证 | `Accepted` | `Accepted` |
| 票据装订与校验 | 完成；`stapler validate` 通过 | 同左 |
| Gatekeeper | `spctl` 接受，来源为 `Notarized Developer ID` | 同左 |
| 最终 ZIP 重新解压检查 | 架构、严格签名、装订票据与 Gatekeeper 均通过 | 同左 |
| 真实桌面输入 | 下表所列项目已通过 | 尚未在 Intel Mac 上验收 |

最终文件及 SHA256：

| 文件 | SHA256 |
| --- | --- |
| `SofaTap-macOS-arm64-notarized.zip` | `f053b90f24a0975911a01b03dd7cc0e6a4ef4091ab329c01948ef61d3fd26b2c` |
| `SofaTap-macOS-x64-notarized.zip` | `084bacfd7e603c3ca7cec6a00f7c60ef6f94fdd12d5faa42061449004815b374` |

已重新计算本地最终 ZIP 的 SHA256，并与对应校验文件及完成态公证回执一致；发布后匿名从公网下载的 arm64 ZIP 也已重新计算 SHA256，结果相同。分发 ZIP 仅含 **Sofa Tap Receiver.app** 及 macOS 归档元数据；构建 manifest、原始公证回执、本地配置和配对资料不在分发包中。原始回执含本地环境信息，维护者仅保留在本地，不原样公开。

本地构建与归档验证记录中的 `physicalInputVerified: false` 保持不变：它们记录的是打包步骤，当时没有执行实机输入。下述实测发生在最终公证包安装之后，单独留存记录，不回写安装包。

## 真实 iPhone → Mac 验收

环境为 **iPhone 17 Pro Max、Sofatap 0.3.0 (4)** 与 **Apple Silicon Mac**。Mac 安装的是上述最终公证版本，位于用户“应用程序”目录，已获得正常系统授权，接收端显示桌面就绪。

| 操作 | 观察结果 |
| --- | --- |
| 相机扫码配对 | 使用 iPhone 的真实相机扫描 Mac 原生窗口二维码，配对成功 |
| 局域网连接 | iPhone 与 Mac 建立 TLS 连接，接收端显示手机已连接 |
| 更新后的配对 | 替换为最终公证 App 后保留已有配对；手机手动重连成功 |
| ASCII 文字 | TextEdit 中出现发送内容，读回精确一致 |
| 多语言与换行 | 包含中文、英文、日文、emoji、é 和换行的测试文字，在 TextEdit 中读回精确一致 |
| 键盘操作 | 全选、退格、Enter、Esc 已实际验证 |
| 触控板移动 | 一次手机移动操作后，Mac 光标 x 坐标增加 126 |
| 鼠标点击 | 右键出现上下文菜单；左键取消选区 |

验收前确认 TextEdit 是系统实际前台应用，并点击正文使其获得键盘焦点。工具中选中一个窗口、窗口可见或成功收到 ACK，都不足以单独证明文字已进入该文档。此次文字验收依据目标文档的精确读回；手机的“已向电脑系统提交文字”仍保留原有含义，不承诺其他应用已经接收、保存或提交。

## 尚未完成的实测

- 实际语音听写、Typeless 和其他第三方语音键盘流程。
- 实体手机陀螺仪空中鼠标的方向、灵敏度与长期手感。
- 拖拽、滚动及更长时间的连续控制。
- Intel Mac 的真实输入；本版 Windows 原生窗口与 iPhone 联合操作；Linux GTK GUI。
- TextEdit 之外的目标软件兼容性，以及完整的 [实机验收清单](../ACCEPTANCE.md)。

在本记录对应的 0.3.0 版本中，Linux 仍是原生配对界面的 dry-run 预览。之后的 [0.4.0 Linux 预览版](linux-0.4.0.md) 增加了桌面输入；其测试结果单独记录。

## 自动检查证据

[GitHub Actions CI #38122300344](https://github.com/chekusu/sofatap/actions/runs/38122300344) 在同一源码版本上全部通过，包含 macOS、Windows 和 Linux 三个 job。检查覆盖协议、TLS dry-run、原生窗口解析和管道、进程退出、iOS 编译及桌面端构建；CI 没有代替上述实机验收，也没有把 Linux GUI 或 Windows 本版真实输入标为通过。
