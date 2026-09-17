---
knowledge_base: printernoble_td630_dot_matrix
compiled_at: 2026-05-15
language: zh-CN
purpose: "供 GPT 客服自动回复学习：TD630 系列针式打印机官方规格、安装、耗材、维护与排查"
source_scope: "仅整理 printernoble.com TD630 Series 官方页面、TD630/TD630G 产品页、USB/Bluetooth/WiFi Dot Printer 官方 PDF 手册"
models:
  - TD630
  - TD630G
  - AK910
  - AK915
  - TH850GB
  - TH850GW
  - AK890
  - TH880
sources:
  - title: "TD630 Series support page"
    url: "https://printernoble.com/td630series/"
    note: "驱动、App、视频、TD630 系列说明书入口"
  - title: "TD630 product page"
    url: "https://printernoble.com/product/td630/"
    note: "页面标题为 TD630，规格区出现 Model: AK890，需客服核对客户实物型号"
  - title: "TD630G product page"
    url: "https://printernoble.com/product/td630g/"
    note: "页面标题为 TD630G，规格区出现 Model: TH880，需客服核对客户实物型号"
  - title: "User manual of Dot Matrix Printer USB/Bluetooth/WiFi"
    url: "https://printernoble.com/2025/08/27/user-manual-of-dot-matrix-printer-usb_bluetooth_wifi/"
    pdf: "sources/printernoble/td630_usb_bluetooth_wifi_dot_matrix_user_manual.pdf"
    text: "sources/printernoble/td630_usb_bluetooth_wifi_dot_matrix_user_manual.txt"
    note: "官方 PDF 手册，覆盖 TD630/TD630G/TH850GB/TH850GW 等"
source_boundary:
  - "TD630/TD630G 产品页的规格区出现 AK890/TH880 型号名，客服不能直接把所有型号混为同一台机器。"
  - "用户于2026-09-09确认：TD630售前按蓝牙+USB，手机端允许蓝牙或Wi-Fi，电脑端仅USB；TD630G售前按蓝牙+Wi-Fi+USB。不得披露内部硬件关系。"
  - "用户于2026-08-10确认：只有TD630、TD630G支持Windows和原生macOS，其他针式型号仅支持Windows。"
  - "针式打印机使用碳纸/连续纸等适配纸张，不是热敏打印机，不要引导客户使用热敏纸。"
---

# Printernoble TD630 针式打印机官方客服知识库

## 1. GPT 使用原则

- 先确认客户型号：TD630 或 TD630G；不得仅凭旧产品页的接口字段判断。
- 先问清楚客户设备：Windows 电脑、Mac、Android 手机、iPhone/iPad。
- 连接问题按“电源和纸张 -> 连接线/蓝牙/WiFi -> 驱动/App -> 测试页/自检页 -> 端口或 IP”顺序处理。
- 打印浅、漏针、卡纸、复写不清晰时，优先检查色带、纸厚调节杆、纸张层数、纸路和打印区域。
- 不把手机Wi-Fi能力承诺成电脑Wi-Fi：TD630手机可用蓝牙或Wi-Fi，但电脑仅USB；只有TD630G的Windows电脑可使用已确认的2.4GHz局域网Wi-Fi教程。
- 客户只问一个按键、指示灯或进纸位置时，只回答该问题所需的信息，不一次发送整套面板说明。

### 1.1 TD630“打印慢、声音大/刺耳”的分流

- 本节面板布局已确认适用于 TD630、TD630G；两者均支持前进纸、后进纸和连续纸。其他型号只有在面板标识相同时才可套用基础按键和缺纸灯说明。
- 电源键：按一下开机；没有反应时可以长按尝试开机。需要关机时先取出纸张，按住电源键，看到红灯闪烁时松开；仍未关机则断开电源供应。左侧绿色电源灯亮表示机器已通电。若电源灯只在按住时亮、松开立即关机，属于异常，按售后故障分流处理。
- `进纸/退纸`键：装好后进连续纸后按一下进纸；按下或长按可继续向前送纸。
- `暂停/微退`键：打印过程中按下可暂停打印；按下或长按可使纸张向后微退。
- 缺纸红灯：亮起表示机器没有检测到纸张；正确装入前进纸或后进纸后应熄灭。正确装纸仍亮时再检查进纸通道和纸张感应器。
- 最右侧绿色指示灯必须按客户实际连接版本解释：TD630和TD630G使用无线连接时，开机连接过程会闪烁约 `2–4秒`，常亮表示已连接，持续闪烁表示未连接；纯USB使用时正常一般保持常亮，打印过程中按下暂停键后也可能闪烁。不得把该灯统一称为暂停灯或网络灯，也不得向客户解释内部硬件关系。

### 1.2 TD630“打印慢、声音大/刺耳”的分流

- 先确认型号确实为 TD630，再只问一个最能区分处理路径的问题：这种情况是从买来一直如此，还是最近突然出现？
- 如果客户确认“一直如此”，并且进纸、打印内容、走纸均正常：按针式打印机正常特性解释。机器支持最高 `1+5` 六联复写，为了让最后一联也清晰，打印针击打力度较大，因此机械声会明显，速度也会慢于热敏打印机；这本身不代表故障。
- 如果客户确认“最近突然出现”，或视频已显示打印头卡在中间并持续异响，或同时存在卡纸、漏打、缺针、走纸异常、打印中断：不得解释为正常声音。让客户关机断电，取下色带，清理打印头移动轨道和可见纸屑；重新开机时只从外部观察打印头是否会自动左右移动一次，不得在通电状态触摸或强推打印头。
- 对客回复不披露“内部分析过程”；只说明观察到的现象、原因和下一步操作。
- 当前没有经过中国市场审核的“TD630正常声音”视频。客户要求视频时转人工，不得发送YouTube、海外平台视频或英文说明书。
- 知识库内已有用户确认正常的针式打印机开机、打印、前进纸、后进纸和手动抽纸内部音频参考，仅供内部声纹比对和视频分析，不作为客户教程素材。
- 需要提高打印速度时，可在`打印首选项 → Layout → Advanced → Graphic → Print Quality`选择`DPI:180*144`；也可在`Configure`中取消勾选`One-way printing/单向打印`以启用双向打印。保存后完全关闭并重新打开打印软件，再取出纸张并正确重新装入后试打一份。低DPI会降低打印质量；双向打印用于提速，不等于双面打印。

中国市场简短回复模板：

> 亲，TD630是针式打印机，并且支持最高六联纸。为确保最后一联也能复写清楚，打印针击打力度会比较大，所以正常打印时声音会比热敏打印机明显一些。

客户确认一直如此且打印正常后：

> 亲，TD630是针式打印机，工作时由打印针击打色带和纸张，所以会有连续的机械击打声，打印速度也会比热敏打印机慢；如果进纸和打印内容一直正常，这属于针式打印机的正常工作特性。

## 2. 型号和版本边界

官网 TD630 Series 页面覆盖多种针式打印机型号，包括 TD630、TD630G、TH850GB、TH850GW 等。

产品页存在需要客服注意的显示差异：

| 页面 | 页面标题/URL | 规格区显示 | 客服处理 |
|---|---|---|---|
| TD630 | `https://printernoble.com/product/td630/` | 旧页面混写 Model: AK890、USB/Windows | 售前按USB+蓝牙；手机速印通可蓝牙或Wi-Fi；Windows电脑仅USB；macOS为USB |
| TD630G | `https://printernoble.com/product/td630g/` | 旧页面混写 Model: TH880、USB+Bluetooth/Android+Windows | 以正式确认口径为准：USB+蓝牙+Wi-Fi，支持Windows和macOS |
| TD630 Series 支持页 | `https://printernoble.com/td630series/` | 说明书覆盖 TD630, TD630G, TH850GB, TH850GW 等 | 用作驱动、App、手册入口 |

客服追问模板：

> 请发一下机器铭牌或订单选项。TD630售前按蓝牙+USB，手机速印通可选蓝牙或Wi-Fi，但电脑只用USB；TD630G售前按蓝牙+Wi-Fi+USB，Windows电脑可USB或同一2.4GHz局域网Wi-Fi，Mac使用USB。

## 3. 官方规格卡

| 项目 | 官方资料整理 |
|---|---|
| 产品类型 | Dot Matrix Printer / 针式打印机 |
| 打印方式 | Serial impact dot matrix |
| 打印运行 | Bidirectional logic seeking print |
| 分辨率 | 产品页列出 180DPI high-resolution printing head |
| 打印速度 | 产品页列出 153mm/sec high-speed printing |
| 复写能力 | 1 original + 5 copies |
| 列数 | 82 columns |
| 点直径 | 0.25mm |
| 纸张 | 符合规格的普通纸或多联复写纸；纸宽 100-241mm；最大可打印宽度约 203mm |
| 纸张厚度 | ≤ 0.45mm |
| 进纸方式 | TD630、TD630G：均支持前进纸、后进纸和连续打印 |
| 接口 | TD630售前：USB+Bluetooth；手机速印通支持Bluetooth或Wi-Fi，电脑仅USB。TD630G售前：USB+Bluetooth+Wi-Fi；Windows电脑支持USB或Wi-Fi，Mac仅USB |
| 电脑系统 | TD630、TD630G均支持Windows和原生macOS |
| 电源 | 100-240V ~ 50/60Hz, 2.0A |
| 重量 | 约 3.5kg |
| 机器尺寸 | TD630、TD630G、AK910、AK915 均约 370 × 320 × 180mm |
| 色带寿命 | 技术寿命约 500 万字符；客户侧可参考约 1000–2000 张普通发票，其他单据随覆盖率、联数和浓度变化 |
| 软件升级 | USB upgrade |
| 保修 | 整机保修 3 年，打印头包含在 3 年保修范围内；具体故障是否免费维修仍按订单和售后检测结果处理 |

## 4. 包装和部件

官方手册列出的主要包装/部件：

- Printer
- Ribbon Cartridge
- Paper Holder
- USB Cable
- Power Cable
- User Manual
- Warranty Card
- Control Panel
- Paper Thickness Adjustment Lever
- Paper Guide Roller
- Printer Cover
- Print Head
- USB Interface

客服不要承诺每个销售组合都一定包含额外耗材，需以订单页面和实际包裹为准。

## 5. 纸张安装和进纸

TD630 / TD630G 同标识面板的已确认操作：

- 电源键按一下开机，如无反应可尝试长按；关机时先取纸，按住电源键到红灯闪烁后松开，仍不关机则断开电源供应；左绿灯亮表示已开机。
- 后进连续纸装好后，按一下 `进纸/退纸` 进纸，按住继续向前走纸。
- 打印中按一下 `暂停/微退` 暂停，按住使纸小幅后退。
- 缺纸红灯亮表示缺纸，前进或后进纸被正确检测后应熄灭。
- 最右绿灯需按版本解释：蓝牙/Wi-Fi 版开机后闪烁 `2–4秒` 属正常，常亮表示已连接，持续闪烁表示未连接；纯 USB 版通常常亮，按暂停键时可能闪烁。

连续纸安装要点：

1. 取出纸架/纸托，并把打印机放在平稳桌面。
2. 打开两侧链轮夹。
3. 将连续纸孔对准链轮针。
4. 关闭链轮盖，并把纸拉直。
5. 锁紧链轮夹。
6. 打开电源，按 `Feed/Eject` 进纸或调整纸位。

驱动中常用连续纸固定页高：三等分 `93.1mm（holes 22/3）`、`101.6mm（holes 8）`、`127mm（holes 10）`、二等分 `139.7mm（holes 11）`、整张 `279.4mm（holes 22）`。常见连续纸实际纸宽约 `241mm`，驱动预设宽度为 `240mm`。`holes 22/3` 表示22除以3，约 `7⅓` 个孔位间隔，不是22或23孔。“二联/三联/六联”只用于表述复写纸层数。孔位如 `O--O--O` 时，第一孔中心到第三孔中心约1英寸，所以相邻孔中心距约0.5英寸。

后进连续纸打印后的出纸基准：三等分1页约 `7⅓`、2页约 `14–15`、3页约 `22` 个孔位间隔；二等分1页约 `11` 个孔位间隔。这些只是诊断基准，软件页面大小、驱动纸张大小和固定页高必须一致。

正常纸位：后进连续纸待机时，前方只露出一小段窄纸边；设置和装纸正确时，打印后自动把分页线送到可撕位置。前进单页纸时，纸张前端到机内钢杆处属正常，前盖关闭时约有 `5厘米` 被吸入。明显超过这些位置时，检查纸型、固定页高、装纸和纸张传感器。

客服提醒：

- 纸张必须平直，不要斜着进入。
- 打印内容要在可打印区域内；手册提示超出打印区域可能损坏打印头针。
- 如果客户使用多联纸，要根据层数调整纸厚杆。

## 6. 色带安装和更换

安全步骤：

1. 先关闭打印机电源。
2. 打开上盖。
3. 将纸厚调节杆拨到最高位置，手册提到更换色带时设到位置 6。
4. 将打印头移动到中间。
5. 不要在通电时更换色带。
6. 旋转色带盒旋钮，让色带拉紧且不皱。
7. 将色带导片正确放入打印头位置。
8. 左右移动打印头，确认色带平顺且没有扭转。
9. 恢复纸厚调节杆到适合纸张的位置。

高风险点：

- 色带颜色变淡时应及时更换。
- 色带已经撕裂、断开或无法收紧时直接更换新色带，不继续勉强安装。
- 长期使用磨损色带会影响打印质量，严重时可能损伤打印头。
- 手册要求使用原厂认可色带；第三方色带造成的损坏可能不在保修范围内。

客服模板：

> Please turn off the printer before replacing the ribbon. Move the paper thickness lever to position 6, move the print head to the center, tighten the new ribbon with the knob, and make sure the ribbon is flat between the print head and the ribbon guide before closing the cover.

## 7. 纸厚调节杆

- 手册显示纸厚调节杆有 6 个位置。
- 1 联到 6 联纸应选择对应纸厚。
- 纸太厚但调节杆太低，可能导致卡纸、打印吃力、打印头撞击。
- 纸太薄但调节杆太高，可能导致打印浅或复写不清。

客服回复逻辑：

> If the print is too light or the paper jams, please check the paper thickness lever. For multi-copy paper, increase the lever position; for single thin paper, use a lower position. Please adjust one level at a time and test again.

## 8. Windows USB 驱动安装

官网入口：

- 从 TD630 Series 页面下载最新 Windows Driver。
- 官方手册要求用 USB 连接并保持打印机开机。

基础步骤：

1. 连接电源并开机。
2. 使用 USB 线连接 Windows 电脑。
3. 从 `https://printernoble.com/td630series/` 下载并安装对应驱动。
4. 安装时如安全软件拦截，可临时关闭后再安装；安装后再开启安全软件。
5. 插入纸张。
6. 到 Windows 打印机列表中找到对应打印机。
7. 打印 Windows 测试页。

客服注意：

- 不要让客户先安装来源不明的第三方驱动。
- 如果客户看不到设备，检查 USB 线、USB 口、打印机电源、是否已开机。
- 如果同名打印机出现多个，需区分 USB 和 WiFi 端口。

## 9. Mac 安装

本节仅适用于 TD630、TD630G；其他针式型号不得使用本节教程或 macOS 驱动。

官方手册步骤要点：

1. 使用 USB 连接 MacBook 和打印机。
2. 下载官方 Mac 驱动：`https://zjweiting.com/nobel/apk/MacDriver.pkg`。
3. 先安装驱动，安装时输入 Mac 密码。
4. 驱动安装完成后，再打开 System Settings > Printers & Scanners。
5. 点击 Add Printer/Scanner/Fax。
6. 确认打印机开机并已 USB 连接，否则不会出现在列表。
7. 首次打印前可重启 Mac 或重新插拔 USB。

macOS 列表中的 `NOBLE PARAGON TD630 SZ` 是已安装的打印队列/驱动名称，不是物理 USB 设备名。它显示 Offline/脱机时，先确认打印机已开机，再检查 USB 数据线和 Mac 端口。其他 Mac 安装指导和系统功能等待后续确认资料，不在本次自行补充。

连接边界：TD630G在Mac上按USB连接处理，不承诺或指导Mac无线打印。客户明确询问Mac无线打印时，应直接说明“目前仅支持Mac通过USB连接，不支持Mac无线打印”，不要套用Windows的TCP/IP端口教程。

客服模板：

> For Mac, please connect the TD630/TD630G by USB first, download and install `https://zjweiting.com/nobel/apk/MacDriver.pkg`, then add the printer in System Settings > Printers & Scanners. If it does not appear, please reconnect USB or restart the Mac once.

### 9.1 TD630G 多台 Windows 电脑共享无线打印

1. 打印机和所有 Windows 电脑连接同一个 2.4GHz 局域网。
2. 每台 Windows 电脑分别安装 TD630G 驱动。
3. 安装时选择 `Automatic` 并搜索安装，程序会自动识别 IP 端口。
4. 打印 Windows 测试页验证。
5. Automatic 搜索失败时转人工/技术继续排查；手动 `Standard TCP/IP Port` 只作内部异常备选，不放入正常客户回复模板。

### 9.2 TD630G 在 iPhone 上使用

1. 在App Store搜索并安装 `速印通`，认准 G 图标。
2. iPhone先连接2.4GHz Wi-Fi，并允许App使用蓝牙和本地网络权限。
3. 打开App，进入针式打印机/连接Wi-Fi入口，按页面提示为TD630G配置同一Wi-Fi。
4. 配置和打印均在速印通 App 内完成。TD630与TD630G、iPhone与Android/鸿蒙均使用同一套App操作方法。

## 10. 自检页和基础排查

自检页用途：

- 查看机器状态。
- 查看 WiFi 版本的 IP 地址。
- 核对蓝牙/WiFi 信息。

手册中的自检方式：

1. 关闭打印机。
2. 按住右侧按钮，同时按电源键开机。
3. 打印机亮起后松开电源键。
4. 继续按住右侧按钮约 3 秒。
5. 松开右侧按钮。
6. 插入纸张，等待打印自检页。

客服模板：

> Please print a self-test page first. It helps us confirm the printer status and, for Wi-Fi models, the printer IP address. Turn off the printer, hold the right-side button, power it on, keep holding the right-side button for about 3 seconds, then insert paper.

## 11. 维护和安全

维护：

- 手册建议每 3 个月或约 300 工作小时清洁一次。
- 清洁前拔掉电源。
- 使用干布清洁纸路和平台。
- 不要在打印头仍很热时清洁。
- 不要使用易燃溶剂或硬布。
- 需要时清洁/润滑 carriage shaft。

安全：

- 打印工作时不要触摸打印头，可能烫伤。
- 不要把打印内容排到可打印区域外，可能损伤打印针。
- 不要使用不匹配纸张或热敏纸替代碳纸/连续纸。

## 12. 常见问题排查卡

### 12.1 打印很浅

检查：

- 色带是否老化或安装不平。
- 纸厚杆是否太高。
- 多联纸层数是否超过机器能力。
- 是否使用了不适配纸张。

安全回复：

> Light printing is usually related to ribbon condition, ribbon installation, or paper thickness lever position. Please check whether the ribbon is flat and not worn out, then adjust the paper thickness lever one level lower and test again.

### 12.2 卡纸

检查：

- 连续纸孔是否对准链轮。
- 纸是否拉直。
- 链轮夹是否锁紧。
- 纸厚杆是否和纸张层数匹配。
- 是否有碎纸或异物。
- 卡纸排查时可把纸厚扳手调到最高的第 6 档，使进纸更顺畅并减少卡纸。该结构的调法为右手拇指向右按住扳手，再向上推。

安全回复：

> Please turn off the printer first, remove the paper gently, check both sprockets and paper holes, then reload the paper straight. For paper-jam troubleshooting, move the paper thickness lever to the top, sixth position, then reload and test.

### 12.3 打印头过热

手册说明：

- 连续打印时打印头发热通常属于正常现象，工作时不要触摸打印头。
- 打四五张后打印头发烫并停止打印时，也按本节先区分正常温控暂停和异常故障，不归入普通打印队列问题。
- 打印头过热时，打印机可能自动从双向打印切换为单向打印。
- 等温度下降后再继续。
- 如果出现反复停止、烧焦味、冒烟或异常声音，应立即暂停使用并转人工售后。

安全回复：

> It is usually normal for the print head to become hot during continuous printing, so please do not touch it. If printing repeatedly stops, or there is a burning smell, smoke, or abnormal noise, stop using the printer and contact human customer service.

### 12.4 Windows 打不出测试页

检查：

- USB 是否连接。
- 是否选择了正确打印机。
- 驱动是否从官网安装。
- 是否有纸。
- 若为 WiFi 版本，端口 IP 是否与自检页 IP 一致。

安全回复：

> Please make sure the official driver is installed, the printer is powered on, USB is connected, and paper is loaded. If your model is Wi-Fi version, please print a self-test page and confirm the driver port IP is the same as the printer IP.

## 13. 禁止话术

- 禁止把TD630手机Wi-Fi说成电脑Wi-Fi；TD630电脑仅USB。也禁止向客户披露TD630与TD630G的内部硬件关系。
- 禁止说“任何纸都能打”，必须使用适配碳纸/连续纸并注意纸厚。
- 禁止说“不用装驱动”，Windows/Mac 通常需要官方驱动或添加打印机。
- 禁止说“色带随便买都一样”，手册要求使用原厂认可色带。
- 针式打印机默认整机3年且包含打印头；历史天猫加普威TH850老款/纯USB路线例外为1年。必须按订单、店铺和路线核实，不得把热敏打印头3个月口径套到针式机。
- 禁止忽略官网型号显示差异，客服需让客户发机器铭牌或订单型号。
