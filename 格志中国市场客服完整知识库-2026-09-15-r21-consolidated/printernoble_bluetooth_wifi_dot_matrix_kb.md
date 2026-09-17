---
knowledge_base: printernoble_bluetooth_wifi_dot_matrix
compiled_at: 2026-05-15
language: zh-CN
purpose: "供 GPT 客服自动回复学习：蓝牙/WiFi 针式打印机 App、无线连接、Windows WiFi 端口排查与打印操作"
source_scope: "整理 printernoble.com TD630 Series、TD630G 产品页、USB/Bluetooth/WiFi Dot Printer 官方 PDF 手册"
models:
  - TD630G
  - TD630
  - TH850GB
  - TH850GW
sources:
  - title: "TD630 Series support page"
    url: "https://printernoble.com/td630series/"
  - title: "TD630G product page"
    url: "https://printernoble.com/product/td630g/"
    note: "产品页规格区显示 Interface Type: USB + Bluetooth；Support Devices: Android and Windows；页面还出现 WiFi+USB+Bluetooth 选项"
  - title: "User manual of Dot Matrix Printer USB/Bluetooth/WiFi"
    url: "https://printernoble.com/2025/08/27/user-manual-of-dot-matrix-printer-usb_bluetooth_wifi/"
    pdf: "sources/printernoble/td630_usb_bluetooth_wifi_dot_matrix_user_manual.pdf"
    text: "sources/printernoble/td630_usb_bluetooth_wifi_dot_matrix_user_manual.txt"
  - title: "Grozziie iOS App"
    url: "https://apps.apple.com/us/app/grozziie/id6476171035"
  - title: "Grozziie Android App"
    url: "https://play.google.com/store/apps/details?id=com.grozziie.printer"
source_boundary:
  - "TD630售前按蓝牙+USB，手机端可在速印通用蓝牙或Wi-Fi，电脑端仅USB；TD630G售前按蓝牙+Wi-Fi+USB。"
  - "只有TD630、TD630G支持Windows和原生macOS；其他针式型号只支持Windows。"
  - "蓝牙和 WiFi 是不同连接链路：蓝牙用于手机 App 近距离连接；WiFi 需要 2.4G 网络与正确 SSID/密码。"
  - "Windows WiFi 设置通常需要先通过 USB 和官方驱动配置，再检查端口 IP。"
  - "App 支持 Document Print 和 Label Print，但具体文件兼容性以 App 实际导入结果为准。"
---

# Printernoble 蓝牙/WiFi 针式打印机客服操作知识库

> 2026-08-24 中国市场覆盖规则：对客 App 名称统一为“速印通”。本文旧资料中出现的 `Grozziie App` 仅视为海外/技术名称，不得在中国市场对客回复中使用。iPhone/鸿蒙在应用商店搜索“速印通”（G 图标）；Android 扫描机器 G 二维码或使用 `https://www.zjweiting.com/files_dot/Grozziie.apk`。

## 1. GPT 使用原则

- 先确认型号和设备：TD630售前按USB+Bluetooth，手机速印通可用蓝牙或Wi-Fi，但电脑仅USB；只有TD630G的Windows电脑可使用电脑Wi-Fi教程。
- 中国市场手机端问题优先走速印通 App；Windows 端问题优先走官方驱动和端口；Mac 端优先走 USB 驱动添加打印机。
- WiFi 问题必须确认 2.4G 网络、SSID/密码、同一网络、打印机 IP。
- 蓝牙问题必须确认手机蓝牙权限、App 机型入口、二维码或搜索列表、MAC 地址。
- 不把 App 打印和电脑驱动打印混在同一套步骤里。

## 2. 快速分流

| 客户问题 | 优先入口 | 关键确认 |
|---|---|---|
| 手机搜不到打印机 | 速印通 > 针式打印机 > Search/扫码 | 是否蓝牙版、手机蓝牙权限、机器背面二维码/MAC |
| 手机想用 WiFi 打印 | 速印通 > 针式打印机 > Connect Wi-Fi | 是否TD630/TD630G、是否2.4G、SSID/密码是否正确 |
| Windows 电脑无线打不出 | Windows 驱动安装器 `AUTO` + `Search` | 是否先 USB 配置、电脑与打印机是否在同一局域网 |
| Mac 电脑打印 | MacOS driver + USB 添加打印机 | 手册主要按 USB 连接添加 |
| WhatsApp/WeChat 文件打印 | App Document Print | 文件能否被 App 导入、纸张尺寸、方向、页码 |
| 打标签/条码/二维码 | App Label Print | 模板尺寸、内容对象、预览位置 |

### 2.1 TD630 / TD630G 平台连接边界（中国市场统一口径）

- TD630：售前按蓝牙+USB描述；手机端可在速印通使用蓝牙或2.4GHz Wi-Fi；Windows电脑和Mac电脑均只按USB打印，不支持电脑Wi-Fi或电脑蓝牙。
- TD630G：售前按蓝牙+Wi-Fi+USB描述；Windows电脑可USB或同一2.4GHz局域网Wi-Fi，手机速印通可蓝牙或Wi-Fi；Mac仅USB。
- Mac：仅按USB连接处理，不支持Mac无线打印；不得把Windows的 `Standard TCP/IP Port` 操作发给Mac客户。
- 多台Windows电脑：先由一台电脑通过USB完成TD630G的2.4GHz Wi-Fi配置；其他电脑运行驱动安装器，选择 `AUTO` 后点击 `Search`，由安装器自动检测打印机IP并安装端口，不手动创建TCP/IP端口。
- iPhone：先在 App Store 安装 `速印通`；支持手机蓝牙打印的机型优先在 App 内使用蓝牙连接，只有机型或客户场景明确需要 WiFi 时才配置2.4GHz Wi-Fi，并按需要允许 App 使用蓝牙和本地网络权限。
- 所有针式打印机都不支持云打印、云端远程打印或内置云打印；TD630的Wi-Fi只用于手机速印通，TD630G的Wi-Fi可用于手机速印通或同一局域网中的Windows电脑。Mac仅支持USB打印。
- 不向客户解释TD630与TD630G的内部硬件、内部路由或命名关系。
- 蓝牙与Wi-Fi不会自动切换。Wi-Fi断网后需要在速印通的针式打印机页面点击“切换设备/连接另一台设备”，再选择蓝牙连接。
- 中国市场只发送天猫、京东、拼多多等已审核国内平台的视频和中文截图说明；无匹配素材时转人工，不发送YouTube或英文说明书。

## 3. App 安装和基础入口

官方 App：

- iPhone/鸿蒙：应用商店搜索 `速印通`，认准 G 图标
- Android：机器 G 二维码或 `https://www.zjweiting.com/files_dot/Grozziie.apk`

基础步骤：

1. 中国市场 iPhone/鸿蒙搜索 `速印通`；Android 扫描机器 G 二维码或打开官方安装链接。
2. 安装并登录。
3. 如无账号，用邮箱注册。
4. 如需切换语言：`Profile > Switch Language`。
5. 选择 `Dot Printer` 图标。
6. 根据需要选择 `Connect Bluetooth` 或 `Connect Wi-Fi`。

二维码区分：

- 手机连接请在 `速印通App内` 扫描机身上标有 `APP连接二维码` 的码，不要使用手机系统相机扫描。
- 驱动/教程二维码指向 `https://www.zjweiting.com/download.htm`。
- 客服二维码只用于联系客服。
- 只有支持手机连接的型号才使用 App 连接二维码。

客服模板：

> Please install the Suyintong (速印通) App for the China market, then choose the Dot Printer icon. Use Connect Bluetooth for Bluetooth printing, or Connect Wi-Fi with a 2.4G network for a Wi-Fi model.

## 4. 蓝牙连接流程

适用：

- USB+Bluetooth 版本。
- WiFi+USB+Bluetooth 版本中的蓝牙连接。

步骤：

1. 打开手机蓝牙。
2. 允许速印通 App 使用蓝牙权限。
3. 打开速印通 App。
4. 点击 `Dot Printer`。
5. 选择扫描机器背面二维码，或点击 Search 搜索附近打印机。
6. 如果列表有多个设备，用打印机 MAC 地址核对。
7. 连接成功后进入 `Document Print` 或 `Label Print`。

排查：

- 搜不到：重启手机蓝牙、重启打印机、靠近机器、确认不是纯 USB 版本。
- 连上但不能打印：检查纸张、纸厚杆、色带、App 内打印机选择。
- 多台设备混淆：打印自检页或查看机器标签，核对 MAC。

客服模板：

> Please turn on phone Bluetooth and allow Bluetooth permission for the Suyintong (速印通) App. Open Suyintong, choose Dot Printer, then scan the QR code labeled “APP Connection QR Code” or use Search. If several printers appear, please compare the MAC address before connecting.

## 5. WiFi App 连接流程

适用：

- 确认客户购买的是 WiFi+USB+Bluetooth 版本。
- WiFi 只支持 2.4G，手册规格列出 Wi-Fi: 2.4G。

步骤：

1. 手机连接到要给打印机使用的 2.4G WiFi。
2. 打开速印通 App。
3. 点击 `Dot Printer`。
4. 点击 `Connect Wi-Fi`。
5. 输入 WiFi 名称和密码。
6. 点击 `Set`。
7. 连接后选择 `Document Print` 或 `Label Print`。

排查：

- 不支持 5G-only 网络；请使用 2.4G。
- WiFi 名称/密码需准确，注意大小写、空格和特殊字符。
- 若配置失败，先确认使用 2.4GHz 网络、密码准确并靠近路由器重试；不把重启路由器作为常规步骤。
- 如客户是 Windows 电脑 WiFi 打印，不要只发 App 步骤，还要检查驱动端口。

客服模板：

> This printer Wi-Fi function works with 2.4G Wi-Fi. Please connect your phone to the same 2.4G Wi-Fi first, open Suyintong (速印通) > Dot Printer > Connect Wi-Fi, enter the Wi-Fi name and password, then tap Set.

## 6. Windows WiFi 配置和端口排查

官方手册核心流程：

1. 使用 USB 连接打印机和 Windows 电脑。
2. 打开打印机电源。
3. 从 TD630 Series 页面下载最新 Windows Driver。
4. 安装驱动。
5. 安装/设置窗口出现后点击 `Search`。
6. 插入纸张。
7. 输入与电脑同一网络的 WiFi SSID 和密码。
8. 点击 `Next`。
9. 设置成功时，打印机应自动关机。
10. 重新开机，纸张会自动走出；重新放纸并等待。
11. 打印 Windows 测试页。

如果测试页不打印：

1. 打印自检页，查看打印机 IP。
2. 打开 Windows `Control Panel > Devices and Printers`。
3. 找到对应打印机。
4. 右键进入 Printer properties。
5. 检查 Port。
6. 如果驱动端口 IP 和自检页 IP 不一致，添加 `Standard TCP/IP Port`。
7. 输入自检页显示的打印机 IP。
8. 应用后重新打印测试页。

客服模板：

> For Windows Wi-Fi printing, please configure the printer by USB first using the official TD630 Series driver. After Wi-Fi setup, print a self-test page and check the printer IP. If the Windows test page does not print, please make sure the printer port IP is the same as the IP shown on the self-test page.

## 7. 自检页：什么时候必须让客户打印

必须让客户打印自检页的情况：

- Windows WiFi 打不出测试页。
- 需要确认打印机 IP。
- 需要确认连接状态或设备信息。
- 多台打印机混淆。
- 客户说“已连接但没反应”。

自检步骤：

1. 关闭打印机。
2. 按住右侧按钮。
3. 同时按电源键开机。
4. 开机后松开电源键。
5. 继续按右侧按钮约 3 秒。
6. 松开按钮。
7. 放入纸张，等待打印。

客服模板：

> Please print a self-test page so we can check the printer IP and status. Turn off the printer, hold the right-side button, power it on, keep holding the right-side button for about 3 seconds, then release it and insert paper.

## 8. App Document Print 操作

官方手册提到可从 WhatsApp、WeChat、文件/文档中选择文件打印。

常用设置：

- `Paper Size W/H`: 纸张宽高。
- `Contrast`: 调整文字深浅/加粗效果。
- `Copies`: 份数。
- `Direction`: 打印方向。
- `Position Right/Left`: 左右位置。
- `Page Start/End`: 页码范围。
- `Rotate`: 旋转。
- `Color Effect`: 打印效果。
- `Printer`: 选择打印机。
- `Preview`: 预览。

客服模板：

> In Suyintong (速印通), choose Dot Printer > Document Print, import the file, set paper size, direction, copies and page range, then preview before printing. If the text is too light, you can try increasing Contrast.

## 9. App Label Print 操作

官方手册提到 Label Print 可使用模板或创建标签。
速印通的模板功能也可创建、编辑并打印库存管理等单据，不仅限于导入现有文件。

可添加内容：

- Text
- Barcode
- QR
- Table
- Image
- Scan
- Time
- Emoji
- Serial Number

客服模板：

> For labels, please use Dot Printer > Label Print. You can choose a model template or Create Label, then add text, barcode, QR code, table or image. Please check the preview and paper size before printing.

## 10. 蓝牙/WiFi 常见问题排查卡

### 10.1 手机 App 蓝牙搜索不到

检查：

- 机器是否为蓝牙版本。
- 手机蓝牙是否打开。
- App 是否有蓝牙权限。
- 打印机是否通电。
- 距离是否太远。
- 是否扫了机器背面二维码。

回复：

> Please confirm your printer is the Bluetooth version. Then turn on phone Bluetooth, allow Bluetooth permission for Suyintong (速印通), keep the phone close to the printer, and try the APP connection QR code or Search again.

### 10.2 WiFi 设置失败

检查：

- 是否 WiFi 版本。
- 是否使用 2.4G WiFi。
- WiFi 名称和密码是否正确。
- 是否有特殊符号、空格或大小写错误。
- 打印机是否靠近路由器。

回复：

> Please use a 2.4G Wi-Fi network and enter the exact Wi-Fi name and password. If it fails, restart the printer, keep it near the router, and try Connect Wi-Fi again in Suyintong (速印通).

### 10.3 Windows 显示已安装但不能 WiFi 打印

检查：

- 是否打印了自检页。
- 驱动端口 IP 是否等于自检页 IP。
- Windows 是否有两个同名 TD630S 打印机，一个 USB，一个 WiFi。
- 是否选错打印机。

回复：

> Please print a self-test page and check the printer IP. In Windows printer properties, the port IP should match the self-test page IP. If there are two similar printer names, please choose the Wi-Fi one or add a Standard TCP/IP Port with the self-test IP.

### 10.4 App 可以连接但打印空白/很浅

检查：

- 色带是否安装。
- 色带是否已磨损。
- 纸厚调节杆是否太高。
- 是否使用正确碳纸/连续纸。
- 预览是否有内容。

回复：

> If the App shows connected but the print is blank or very light, please check the ribbon first, make sure it is installed flat and not worn out. Then check the paper thickness lever and confirm the preview has printable content.

### 10.5 客户想从 WhatsApp/WeChat 打印

回复：

> Suyintong (速印通) supports importing documents from apps such as WhatsApp or WeChat for Document Print. Please open the file, share/import it to Suyintong if available, then set paper size, direction, copies and preview before printing.

## 11. 禁止话术

- 禁止说“WiFi 版本支持 5G WiFi”，官方手册列出 2.4G。
- 禁止说“蓝牙连不上就一定是机器坏了”，先排查权限、距离、版本、二维码/MAC。
- 禁止让客户给纯 USB 版本配置 WiFi。
- 禁止把 Windows WiFi 端口问题当成 App 问题处理。
- 禁止承诺所有 WhatsApp/WeChat 文件格式一定能打印，需以 App 导入和预览为准。
- 禁止让客户在打印机通电时更换色带。
