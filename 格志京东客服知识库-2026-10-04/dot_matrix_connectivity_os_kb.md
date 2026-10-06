---
knowledge_base: dot_matrix_connectivity_os
version: "2026-09-09"
language: zh-CN
purpose: "针式打印机型号连接方式与电脑系统支持范围"
source_boundary:
  - "用户于2026-08-10逐项确认连接方式和Mac支持范围。"
  - "用户于2026-08-22确认 TG690 和 Linux 支持边界，并确认 AK910 Windows USB 驱动安装流程。"
  - "用户于2026-08-23提供Nobel Windows USB驱动安装视频与完整可视化指南，确认安装器会自动检测设备，客户应选择Search结果中检测到的打印机，而不是猜测型号。"
  - "用户于2026-09-07确认：TH880仅支持USB连接，不支持Wi-Fi；不得对TH880提供IP或Wi-Fi设置。"
  - "用户于2026-09-09确认：TD630售前按蓝牙+USB展示；手机端允许蓝牙或Wi-Fi，Windows电脑仅USB。TD630G售前按蓝牙+Wi-Fi+USB展示。不得披露内部硬件关系。"
  - "电脑系统支持与手机APP连接是两个维度，不得混为一谈。"
---

# 针式打印机连接方式与系统支持

## 正式型号映射

| 型号 | 售前连接描述 | 手机 | Windows电脑 | macOS电脑 |
|---|---|---|---|---|
| TD630 | 蓝牙 + USB | 速印通蓝牙或2.4GHz Wi-Fi | 仅USB；不支持电脑Wi-Fi/蓝牙 | USB |
| TD630G | 蓝牙 + Wi-Fi + USB | 速印通蓝牙或2.4GHz Wi-Fi | USB或同一2.4GHz局域网Wi-Fi；不支持电脑蓝牙 | 仅USB；不支持Mac无线 |
| TH880 | USB | 不支持 | USB | 不支持 |
| AK910 | USB | 不支持 | USB | 不支持 |
| AK915 | USB | 不支持 | USB | 不支持 |
| AK890 | USB | 不支持 | USB | 不支持 |
| TG890 | USB | 不支持 | USB | 不支持 |
| TG690 | USB | 不支持 | USB | 不支持 |

## 客服规则

- 只有 TD630、TD630G 支持 Windows 和原生 macOS。
- 其他针式打印机电脑端仅支持 Windows；不得发送 macOS 驱动或承诺原生 Mac 可用。
- TD630售前按“蓝牙+USB”介绍；手机端可在速印通使用蓝牙或2.4GHz Wi-Fi，Windows电脑只能USB打印，不能把手机Wi-Fi能力写成电脑Wi-Fi能力。
- TD630G售前按“蓝牙+Wi-Fi+USB”介绍；Windows可USB或2.4GHz局域网Wi-Fi，手机可在速印通使用蓝牙或Wi-Fi，Mac仅USB。
- 对客始终分开说明TD630和TD630G，不披露内部硬件、内部路由或命名关系。
- TH880 仅支持 USB + Windows，不支持蓝牙、Wi-Fi或原生 macOS；回答TH880驱动问题时不得加入IP或Wi-Fi设置。
- AK910、AK915、AK890、TG890、TG690 均按 USB + Windows 回答。
- 所有针式打印机型号均不支持 Linux；不得发送 Linux 驱动或承诺可通过兼容层使用。
- 型号不明确时，先请客户提供机器铭牌和电脑系统。

## Windows USB 驱动安装入口

Windows 电脑通过 USB 安装打印机驱动时，使用 `dot_matrix_windows_usb_driver_install_kb.md` 中已经由视频逐帧核验的完整流程。核心顺序为：

1. 打印机接通电源并开机，再用 USB 数据线连接电脑。
2. 打开来源可信的驱动安装程序。
3. 先按客户目的选择入口：支持手机/WiFi 的机型要配置 WiFi 时选择 `Automatic → Next`；要安装 USB 驱动时选择 `USB → Search`。仅支持 USB 的机型选择 Auto 或 USB 都会安装 USB 驱动。
4. USB 路径中点击搜索结果里检测到的打印机，再点击 `Next`；这是选择自动识别到的设备，不是手动猜型号。
5. 等待 `Installation successful`。
6. 到 Windows `设置 → 蓝牙和其他设备 → 打印机和扫描仪` 打印测试页，并确认是否实际出纸。

完整图文、可信下载拦截处理、下一步画面映射和异常分支见：`dot_matrix_windows_usb_driver_install_kb.md`。
