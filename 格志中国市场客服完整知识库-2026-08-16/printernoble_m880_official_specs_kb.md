---
knowledge_base: printernoble_m880_official_specs
compiled_at: 2026-05-15
language: zh-CN
purpose: "供 GPT 客服自动回复学习：M880/M880D/M880UT 等考勤机官方规格、设置、排查与安全话术"
source_scope: "仅整理 printernoble.com 官方产品页、M880 Series 支持页、官方 PDF 用户手册"
models:
  - M880
  - M880D
  - M880UT
  - M880T
  - M880BT
  - M880DT
  - T960S/T960D/T960B/T960ST/T960DT/T960BT
sources:
  - title: "M880 Series support page"
    url: "https://printernoble.com/m880series/"
    note: "M880 系列手册、视频与下载入口"
  - title: "Grozziie Punch Card Attendance Machine product page"
    url: "https://printernoble.com/product/351-10/"
    note: "产品卖点、规格、卡片、保修信息"
  - title: "TIMOZIA standard attendance machine user manual"
    url: "https://printernoble.com/2025/01/26/timozia-attendance-machine-user-manual/"
    pdf: "sources/printernoble/m880_standard_attendance_machine_user_manual.pdf"
    text: "sources/printernoble/m880_standard_attendance_machine_user_manual.txt"
    note: "适用 M880/M880D 等标准按键设置机型"
  - title: "Bluetooth attendance machine user manual"
    url: "https://printernoble.com/2025/02/23/bluetooth-attendance-machine-user-manual/"
    pdf: "sources/printernoble/m880_bluetooth_attendance_machine_user_manual.pdf"
    text: "sources/printernoble/m880_bluetooth_attendance_machine_user_manual.txt"
    note: "适用 M880UT/M880T 等蓝牙 App 机型"
source_boundary:
  - "标准 M880/M880D 和蓝牙 M880UT/M880T 的密码、设置入口不同，回复时必须先确认客户机型。"
  - "产品页卡片尺寸写法与蓝牙手册存在单位差异：产品页出现 18.5mm x 8.5mm，蓝牙手册写 18.5cm x 8.5cm。客服对外建议说“请以原装卡片实际尺寸/说明书为准”，避免直接承诺错误单位。"
---

# Printernoble M880 考勤机官方客服知识库

## 1. GPT 使用原则

- 先确认客户手上是哪一类机型：标准按键机型 M880/M880D，还是蓝牙 App 机型 M880UT/M880T/M880BT/M880DT。
- 涉及密码、App 连接、考勤周期、班次、颜色、打印位置、卡纸/色带时，按“机型确认 -> 现象确认 -> 按步骤排查 -> 必要时转人工/售后”的顺序回复。
- 不承诺超出官网说明的功能，不把标准机型说成一定支持 App，不把蓝牙机型的六位密码流程套用到标准机型。
- 对外回复要简洁，避免一次性抛出全部菜单编号；先给 2-4 个关键步骤，客户执行后再继续。

## 2. 型号识别卡

| 类别 | 常见型号 | 主要设置方式 | 默认密码/入口 | 适合回复场景 |
|---|---|---|---|---|
| 标准考勤机 | M880, M880D, M880B, T960S/T960D/T960B, DY-8888 等 | 机器按键菜单 | 长按 Setting，出现 FF 后输入默认密码 `0000` | 设置日期时间、班次、打印位置、闹铃、自动识别 |
| 蓝牙考勤机 | M880UT, M880T, M880BT, M880DT, T960ST/T960DT/T960BT | Grozziie App + 机器按键 | 初始密码 `000000`，首次连接需设置新的 6 位数字密码 | App 连接、二维码/MAC 搜索、Pay Period、Flexible/Shift 工作时间 |

客服追问模板：

> May I confirm the exact model printed on your machine or order page? M880 standard model and M880UT Bluetooth model use different setup steps, so I will guide you with the correct instructions.

## 3. M880/M880D 官方规格卡

| 项目 | 官方资料整理 |
|---|---|
| 产品类型 | Punch Card Attendance Machine / Time Tracker / Bundy Clock |
| 打印方式 | 色带打印 / Printer ribbon |
| 供电 | Input 90V-240V, Output 12V-2A |
| 电池 | 11V 1800mAh，标准手册注明仅 M880D 支持；产品页也强调内置 1800mAh 电池用于断电影响降低 |
| 显示 | 4 英寸 LED display / infotainment screen |
| 重量 | 约 1.1kg |
| 包装尺寸 | 295mm(L) x 290mm(W) x 170mm(H) |
| 颜色 | White |
| 产品尺寸 | 产品页列出 22cm x 12cm x 19cm |
| 打卡颜色 | 黑色代表正常，红色可用于迟到/早退等异常标记 |
| 打卡频次 | 产品页描述可跟踪每日 6 次打卡 |
| 时间格式 | 支持 12 小时/24 小时格式 |
| 保修 | 产品页/手册均出现 1-year / 12-month warranty；具体以销售平台订单政策为准 |

## 4. 标准 M880 按键菜单速查

进入设置：

1. 长按 `Setting`，屏幕出现 `FF`。
2. 输入默认密码 `0000`。
3. 使用 `Increase` / `Decrease` 调整值，按 `Setting` 切换项目。

常用功能组：

| 组号 | 功能 | 客服备注 |
|---|---|---|
| 00 | 日期设置 | 年/月/日按机器显示顺序调整 |
| 01 | 时间设置 | 设置当前时间 |
| 02 | 工作班次/颜色打印 | 可设置 1-3 个班次；设为 `00` 时为手动打卡模式 |
| 03 | 第一班开始时间 | 固定班次使用 |
| 04 | 第一班结束时间 | 固定班次使用 |
| 05 | 第二班开始时间 | 如无第二班，不建议客户乱改 |
| 06 | 第二班结束时间 | 如无第二班，不建议客户乱改 |
| 07 | 第三班开始时间 | 如无第三班，不建议客户乱改 |
| 08 | 第三班结束时间 | 如无第三班，不建议客户乱改 |
| 13 | 打印位置 | 打印偏上/偏下时微调 |
| 14 | 闹铃/音乐提醒 | 用于上班、下班等提醒 |
| 15 | 自动识别模式 | 与自动识别卡片/列位相关 |

手动打卡模式：

- 组号 02 设为 `00`。
- 客户通过功能键选择上班/下班等列位。
- 官方手册提示：手动模式打印均为黑色；如客户要求自动红黑区分，需要改用固定班次/自动颜色相关设置。

打印位置：

- 组号 13 用于调整打印位置。
- 若打印偏上或偏下，引导客户少量调整，每次调整后试打一张。
- 不要让客户连续大幅调整，避免越调越偏。

## 5. M880UT/M880T 蓝牙 App 机型速查

App：

- iOS App Store: `Grozziie`
- Google Play: `Grozziie`
- App 内入口：选择 `Attendance Machine` 图标，再选择 M880UT 等对应型号。

连接方式：

1. 打开手机蓝牙。
2. 打开 Grozziie App 并登录。
3. 选择 Attendance Machine。
4. 选择机型 M880UT。
5. 可通过扫描机器背面的二维码连接，或用 Search 搜索附近设备。
6. Search 列表中可通过机器的 Bluetooth MAC 地址确认设备。
7. 首次连接时，按 App 提示设置新的 6 位数字密码。

密码边界：

- 蓝牙手册初始密码是 `000000`。
- 新密码必须是 6 位数字。
- 不建议继续使用 `000000` 作为新密码。
- 如果客户忘记密码，不要随意编造万能密码；按 App/机器“Password Clear”流程或转人工售后确认。

蓝牙 MAC 查看：

- 长按机器 `Setting`。
- 使用 `Increase` 找到 `MAC` 菜单。
- 用该 MAC 与 App 搜索列表中的设备核对。

首次设置向导：

- `Set Time & Date`: 设置时间日期。
- `Pay Period`: 设置工资/考勤周期。
- `Set Working Time`: 设置工作时间。
- 完成后点击 `Complete`。

## 6. 蓝牙机型班次和颜色逻辑

| 模式 | 适合情况 | 颜色/迟到早退逻辑 |
|---|---|---|
| Flexible Work Schedule | 兼职、临时工、上班时间不固定 | 不按固定时间判断迟到/早退；可手动选择 Black/Red |
| Shift 1/2/3 | 固定上班、下班时间 | 可按设置时间自动判断，启用 Auto Color 后迟到/早退可打印红色 |

跨凌晨设置：

- `Cross-midnight time` 用于定义次日考勤切换点。
- 例：设置为 03:00，则凌晨 03:00 前的打卡仍可归到前一个工作日。

打印格式：

- `Day Format`: 默认 90 degrees。
- `Time Format`: 12 小时或 24 小时。
- `UTC format`: Normal / USA。
- `Color`: Auto / Black / Red。
- 如果客户选择 Flexible Work Schedule，建议用 Black 或 Red 手动控制；如果要自动红黑，需使用 Shift 1/2/3 并开启 Auto。

## 7. 纸卡、色带和安装要点

安装环境：

- 标准手册建议放在稳定桌面上，桌面高度至少约 75cm。
- 避免灰尘、阳光直射、热源、潮湿、雨水、水源、强震动或撞击。
- 蓝牙手册墙装部分建议离地约 36-40cm，并按孔位安装。

考勤卡：

- 官方蓝牙手册中 `Setup Paper` 提到：如使用其他公司考勤卡，需要尺寸与官方卡一致，Height 18.5cm，Width 8.5cm。
- 产品页出现 Punch Card Size `18.5mm x 8.5mm`，与手册单位不一致。客服应避免直接写死为 mm；建议客户拍卡片或使用原装卡确认。

色带更换：

- 打开透明盖。
- 取出旧色带盒。
- 旋转色带旋钮，让色带保持平整。
- 把色带放在打印头和不锈钢片之间。
- App 蓝牙机型可使用 `Replace Ribbon` 功能让打印头移动到中间位置，方便更换。

## 8. 常见问题排查卡

### 8.1 App 搜不到 M880UT

排查顺序：

1. 确认客户机型是 M880UT/M880T 等蓝牙版。
2. 手机蓝牙已开启，并授权 Grozziie 使用蓝牙。
3. 机器通电，距离手机较近。
4. 用机器 `MAC` 菜单查看 Bluetooth MAC，再和 App Search 列表核对。
5. 仍搜不到时，重启手机蓝牙、重启机器，再重新搜索。

安全回复：

> Please check if your machine is the Bluetooth version, such as M880UT. Then turn on phone Bluetooth, open Grozziie App, choose Attendance Machine, and use Search or scan the QR code on the back of the machine. If several devices appear, please compare the Bluetooth MAC address shown on the machine.

### 8.2 密码不对

先分机型：

- 标准 M880/M880D：设置入口默认密码为 `0000`。
- M880UT 蓝牙机型：初始密码为 `000000`，首次连接后应设置新的 6 位密码。

禁止直接回复：

- “所有 M880 都是 000000。”
- “所有密码都是 0000。”
- “忘记密码只能换新机。”

安全回复：

> The password depends on your model. For the standard M880 setup menu, the default password is usually 0000. For M880UT Bluetooth version, the initial password is 000000 and the app will ask you to set a new 6-digit password. Please confirm your exact model first so I can guide you correctly.

### 8.3 打印颜色不自动变红

原因判断：

- 客户是否处于 Flexible Work Schedule。
- 是否设置了固定 Shift 1/2/3。
- 是否启用了 Auto Color。
- 标准机型手动打卡模式下，官方手册提示打印均为黑色。

安全回复：

> If the machine is in manual/flexible schedule mode, it may not automatically judge late or early leave. To print red automatically, please set fixed Shift working time and enable Auto Color. If you prefer manual control, you can choose Black or Red manually.

### 8.4 打印位置偏上/偏下

标准机型：

- 进入设置后找到组号 13。
- 每次小幅调整后试打一张。

蓝牙机型：

- App 中使用 `Setup Paper` / `Column Position` 进行微调。
- Column Position 可按 0.1mm 精度调整；正值向右，负值向左。

安全回复：

> Please adjust the print position only a little each time and test with one card. For standard M880, use setting group 13. For M880UT App version, use Setup Paper or Column Position in the Grozziie App.

### 8.5 第三方考勤卡无法识别

排查：

- 是否尺寸与官方卡一致。
- 是否有正确识别点。
- App 中是否开启 AutoCheck。

安全回复：

> If you use non-original time cards, please make sure the size and recognition point match the original card. The official manual lists the card size as about 18.5cm x 8.5cm. If the card is not detected, please try original cards first to confirm whether it is a card compatibility issue.

## 9. 客服安全模板

### 客户问：这台 M880 能不能用 App？

> M880 系列有标准按键版和蓝牙 App 版，不同版本设置方式不同。请您发一下机器铭牌或订单型号，如果是 M880UT/M880T 等蓝牙版，可以用 Grozziie App 连接；如果是标准 M880/M880D，则主要通过机器按键菜单设置。

### 客户问：怎么设置上班下班时间？

> 可以的。请先确认您的机型：标准 M880 是通过机器设置菜单调整班次，蓝牙 M880UT 是在 Grozziie App 里设置 Working Time。您发我机器型号后，我按对应版本一步步发您设置方法。

### 客户问：为什么迟到没有红色？

> 红色通常需要固定班次时间和自动颜色规则配合。如果机器在手动/弹性工作时间模式，可能不会自动判断迟到早退。请先确认当前是 Flexible Work Schedule 还是 Shift 1/2/3，我再帮您检查颜色设置。

### 客户问：可以退换吗？

> 我先帮您判断是设置问题还是机器异常。请您提供订单号、机器型号、问题视频和已尝试的步骤。若确认属于产品质量或售后范围，我们会按店铺和平台售后规则为您处理。

## 10. 禁止话术

- 禁止说“这个很简单你自己看说明书”。
- 禁止说“所有 M880 密码一样”，必须分标准版和蓝牙版。
- 禁止承诺“任何考勤卡都能用”，第三方卡要看尺寸和识别点。
- 禁止承诺“App 一定支持所有 M880”，先确认是否蓝牙版。
- 禁止承诺“打印头/色带/人为损坏都保修”，保修以官方和平台政策为准。
- 禁止把产品页存在疑点的卡片尺寸单位直接当成最终事实对外强承诺。
