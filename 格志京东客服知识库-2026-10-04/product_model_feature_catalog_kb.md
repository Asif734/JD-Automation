---
knowledge_base: product_model_feature_catalog
version: "2026-10-04-jd-grozziie-v1"
language: zh-CN
platform: JD
brand: "格志 / Grozziie"
purpose: "京东客服的型号识别、售前选型、连接、纸张、包装、质保与能力边界"
source_scope:
  - "all_platform_model_details_2026_09_09_kb.md"
  - "dot_matrix_connectivity_os_kb.md"
  - "dot_matrix_product_selling_points_kb.md"
  - "thermal_printer_product_selling_points_kb.md"
  - "attendance_machine_product_selling_points_kb.md"
  - "confirmed_thermal_platform_neutral_update_2026_09_29_kb.md"
  - "confirmed_operating_sales_policy_2026_09_24_kb.md"
  - "jd_confirmed_technical_corrections_2026_09_25_kb.md"
precedence:
  - "jd_customer_service_rules.md 控制平台、品牌、商业政策与运行能力"
  - "2026-09-29 及之后的已确认修订"
  - "精确型号/SKU 已确认资料"
  - "产品系列通用规则"
---

# 格志京东产品型号与功能目录

## 1. 使用规则

1. 本目录用于型号识别和售前选型，不代表京东店铺实时库存、价格、套餐或赠品。这些信息必须以当前商品页和订单为准。
2. `Current` 表示型号主表中的当前产品，不等于当前链接一定有货。`Legacy` 只用于历史订单、配件或售后识别。`Discontinued` 不得用于售前推荐。
3. 只能组合同一精确型号或同一 SKU 中已确认的能力。不得把不同型号的纸宽、连接、系统、电池或进纸能力拼成一个推荐。
4. 格志全部热敏打印机和全部针式打印机都支持 Android 和 iOS/iPhone 设备。任何具体型号被问到手机、Android、安卓、iOS、iPhone或移动设备兼容性时，都直接确认支持，不得回复“未确认”“仅电脑可用”或“不支持手机”。
5. 手机连接方式按产品接口区分：支持USB的产品可直接使用USB连接手机，不需要通过App；使用蓝牙或Wi-Fi连接手机时，使用官方 `Grozziie App`（中国区名称：`速印通`）。同时具备USB和无线接口的产品可按客户选择的连接方式答复。具体线材、接口和操作步骤按精确型号说明书说明。
6. 客户已明确设备、连接、纸张或用途时，不重复追问。信息不足时每轮只问一个会改变结论的条件。
7. 当前平台固定为京东，店铺品牌固定为格志（Grozziie）。不把历史来源中的店铺名、品牌名或其他平台当作当前店铺信息。

## 2. 型号生命周期总表

已登记规范型号 `92` 个：针式 `19`、热敏 `59`、考勤机 `13`、便携磅单机 `1`；其中 `Current 38`、`Legacy 42`、`Discontinued 12`。

### 2.1 Current

- 针式打印机（11）：AK910、AK915、TD630、TD630G、TD630PLUS、TG690、TG890、TH850G、TH880、TH880G、TM690。
- 热敏打印机（23）：GZP510、GZP810S、GZP820、GZP820S、GZP860、GZP860S、JPW500、JPW760S、JPW830、JPW850PLUS、TP510、TP518、TP730、TP730S、TP731、TP732、TP732S、TP870、TP870PLUS、TP874、TP874S、TP876、TP876PLUS。
- 纸卡考勤机（4）：M880、M880D、T960D、T960S。

### 2.2 Legacy

- 针式：AK890、TH650、TH650G、TH850GB、TH850GW、TH880GW。
- 热敏：DP21、GZP810、GZP850、JPW500H、JPW510、JPW520、JPW580、JPW760、JPW820、JPW820H、JPW830H、JPW840、JPW850、JPW850H、JPW860、JPW870、JPW876、JPW910、JPW920、JPW950、JPW970、JPW980、QR380A、TP630、TP635、TP635H、TP731S、TP733、TP734、TP872、TP878、TP879。
- 考勤机：M880B、P960、T960BT、T960T。

### 2.3 Discontinued

装订机全部型号、GD550、JPW560、JPW590、M880A、M880BT、M880D-T、M880DA、M880DT、M880T、TH680、TH850、TJYD810 不得作为当前在售型号推荐。老机维修或配件必须由人工实时确认是否还有配件。

### 2.4 全型号手机App兼容性（最高优先级）

- 针式打印机：AK910、AK915、TD630、TD630G、TD630PLUS、TG690、TG890、TH850G、TH880、TH880G、TM690、AK890、TH650、TH650G、TH850GB、TH850GW、TH880GW、TH680、TH850。
- 热敏打印机：GZP510、GZP810S、GZP820、GZP820S、GZP860、GZP860S、JPW500、JPW760S、JPW830、JPW850PLUS、TP510、TP518、TP730、TP730S、TP731、TP732、TP732S、TP870、TP870PLUS、TP874、TP874S、TP876、TP876PLUS、DP21、GZP810、GZP850、JPW500H、JPW510、JPW520、JPW580、JPW760、JPW820、JPW820H、JPW830H、JPW840、JPW850、JPW850H、JPW860、JPW870、JPW876、JPW910、JPW920、JPW950、JPW970、JPW980、QR380A、TP630、TP635、TP635H、TP731S、TP733、TP734、TP872、TP878、TP879、GD550、JPW560、JPW590、TJYD810。
- 上述每个型号均支持 Android 和 iOS/iPhone 设备。支持USB的产品可直接用USB连接手机，不需要App；使用蓝牙或Wi-Fi连接时使用Grozziie App/速印通。Current、Legacy 或 Discontinued 只影响销售推荐和售后状态，不改变手机系统兼容结论。

## 3. 针式打印机型号边界

| 型号 | 已确认连接和系统 | 进纸/用途边界 |
|---|---|---|
| TD630 | 售前按“蓝牙+USB”；手机速印通可用蓝牙或2.4GHz Wi-Fi；Windows、Mac电脑仅USB | 支持前进、后进和后部拖纸器连续纸；不得宣称电脑Wi-Fi/蓝牙 |
| TD630G | 售前按“蓝牙+Wi-Fi+USB”；手机速印通蓝牙或Wi-Fi；Windows可USB或同一2.4GHz局域网Wi-Fi；Mac仅USB | 支持前进、后进和后部拖纸器连续纸；电脑不支持蓝牙，Mac不支持无线 |
| AK910 | Windows USB；Android/iOS手机可直接USB连接且不需要App；不支持原生macOS | 前部单张进纸，不使用后部拖纸器；不支持A3；支持1+5六联复写 |
| AK915 | Windows USB；Android/iOS手机可直接USB连接且不需要App；不支持原生macOS | 支持前进及后部拖纸器连续纸；支持1+5六联复写 |
| TG890 | Windows USB；Android/iOS手机可直接USB连接且不需要App；不支持原生macOS | 支持前部单张及后部链轮连续纸；支持1+5六联复写 |
| TH880 | Windows USB；Android/iOS手机可直接USB连接且不需要App；不支持电脑Wi-Fi或原生macOS | 不得发送电脑IP/Wi-Fi配置步骤 |
| AK890 | Legacy；Windows USB | 前部平推，不使用后部拖纸器；只用于历史订单/售后 |
| TG690 | Windows USB；Android/iOS手机可直接USB连接且不需要App；不支持原生macOS | 已确认255cps高速；其他进纸能力按精确资料核对 |
| TD630PLUS、TH850G、TH880G、TM690 | Current | 目录未完整核对每个SKU的连接、系统和进纸组合，不能只凭Current状态作具体功能承诺 |

针式打印机已确认通用纸宽为 `100–241mm`，最大可打印内容宽约 `203mm`，总厚度不超过 `0.45mm`，支持普通纸和1+5六联无碳复写纸。不使用热敏纸，不支持证书、硬卡或超厚介质。带孔纸不等于必须后进；只有使用后部拖纸器时才按型号核对后进能力。

## 4. 热敏打印机型号边界

| 型号/组 | 已确认纸宽 | 系统与连接边界 |
|---|---|---|
| GZP510 | 30–100mm；长度30–300mm | 内置纸仓，卷径约12cm；其他连接按SKU核对 |
| GZP820 | 30–100mm；长度30–300mm | 无内置纸仓，后部进纸；其他连接按SKU核对 |
| GZP810S、GZP820S、GZP860、GZP860S、JPW500、JPW830、JPW850PLUS | 30–80mm | 纸仓、卷径、手机和连接方式按精确型号/SKU |
| TP731、TP732、TP732S | 30–80mm | Android/iOS手机可通过USB连接且不需要App；Windows可按型号使用USB |
| TP874 | 30–80mm | 已确认USB+蓝牙、203DPI、Windows USB、macOS USB；手机通过蓝牙使用官方Grozziie App（中国区名称：速印通）打印，Android和iOS/iPhone均支持；不承诺未确认的电池能力 |
| TP874S | 30–80mm | 支持macOS USB；其他连接按SKU核对 |
| JPW760S、TP510、TP518、TP730、TP730S、TP876 | 30–100mm | TP518/TP730/TP730S/TP876不支持macOS；TP730标签长度已确认30–300mm |
| TP870 | 30–100mm | Android/iOS手机可通过USB连接且不需要App；Windows USB；不支持macOS |
| TP870PLUS | 30–100mm | 支持macOS USB；不据此承诺电脑Wi-Fi |
| TP876PLUS | 80mm选项为30–80mm；104mm选项为30–100mm | 支持macOS USB；必须先核对购买选项 |

已确认 TP518、TP730、TP730S、TP731、TP732、TP732S、TP870、TP870PLUS、TP874、TP874S、TP876、TP876PLUS 不支持 Linux。未列出的型号不得简单扩大为支持或不支持。热敏打印机只支持黑白热敏打印，不支持彩色打印。

## 5. 考勤机型号边界

| 型号 | 生命周期 | 已确认边界 |
|---|---|---|
| M880 | Current | 纸卡考勤基础款；适用卡宽85mm、高185mm，同时核对底部识别点和卡片结构；不把备用电池、蓝牙或App当作默认配置 |
| M880D | Current | 已确认内置备用电池，停电时可继续打卡；其他设置按精确型号 |
| T960D | Current | 已确认内置备用电池，停电时可继续打卡 |
| T960S | Current | 纸卡考勤机；不得从后缀推断电池或手机能力 |
| M880B、P960、T960BT、T960T | Legacy | 仅用于历史订单或售后识别，不作为当前在售推荐 |
| M880A、M880BT、M880D-T、M880DA、M880DT、M880T | Discontinued | 不作为当前在售推荐；维修和配件由人工实时核对 |

## 6. 已确认的直接选型

| 客户硬性需求 | 可依据现有证据给出的候选 | 必须同时说明 |
|---|---|---|
| Windows或Mac电脑的针式多联票据 | TD630或TD630G | Mac均仅USB；TD630的Windows电脑也仅USB；TD630G的Windows电脑可USB或同一2.4GHz局域网Wi-Fi |
| Windows针式打印必须使用电脑Wi-Fi | TD630G | 电脑与打印机在同一2.4GHz局域网；不得把此能力套给TD630 |
| 针式需要前部单张和后部链轮连续纸 | TD630、TD630G、AK915或TG890 | 再按系统和连接需求缩小范围 |
| Windows USB针式单张票据，不需要后进 | AK910 | 不支持A3或原生macOS；Android/iOS手机可直接USB连接且不需要App |
| 30–80mm热敏标签，需USB+蓝牙、手机App和Mac USB | TP874 | 已确认203DPI；手机通过Grozziie App/速印通连接，Android和iOS/iPhone均支持；不承诺未确认的电池能力 |
| 热敏机必须用macOS USB | TP870PLUS、TP876PLUS、TP874或TP874S | 各型号纸宽不同；TP876PLUS必须核对购买选项 |
| 纸卡考勤机需停电打卡 | M880D或T960D | 普通M880、T960S不据此承诺备用电池 |

## 7. 包装、耗材与保修速查

- 针式：默认含2张测试纸、1根USB-A转USB-D数据线、机内预装色带和电源线。正式多联纸和额外色带不默认包含。默认整机3年且包含针式打印头，历史订单例外按订单核对。
- 热敏：默认含10张测试纸和1根USB-A转USB-D数据线。只有当前SKU明确标注才确认120张纸、外置纸架或其他赠品。整机除打印头外1年，打印头3个月；不添加里程或固定张数限制。
- 考勤机：默认含1个电源适配器、50张考勤卡、机内预装1个通用考勤色带、2颗挂墙螺丝。考勤卡优先使用原装并核对尺寸及识别点。
- 库存、价格、套餐、赠品、免费维修资格和最终售后审批必须按当前京东商品页/订单和人工审核。

## 8. 证据不足时的答复边界

- 仅有型号生命周期不足以承诺蓝牙、Wi-Fi、macOS、Linux、手机、电池、纸仓或后进连续纸。
- 型号未确定时，优先请客户提供机身标签/铭牌或当前京东商品链接。
- 无法用同一精确型号/SKU覆盖客户全部硬性条件时，不拼接推荐，只说明当前哪一项尚未确认。
- 当客户问京东手机App直打、价格、库存、开票、运费、赠品或订单操作时，使用JD全局规则及当前订单能力，不从技术型号表推断。
