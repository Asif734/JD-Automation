---
knowledge_base: product_model_feature_catalog
version: "2026-09-15-r21-consolidated"
language: zh-CN
purpose: "格志/加普威当前型号识别与售前选型；只记录 r21 已确认的同型号或同 SKU 能力"
source_scope:
  - "all_platform_model_details_2026_09_09_kb.md：型号生命周期、连接、纸宽和平台边界。"
  - "confirmed_consolidated_merge_2026_09_15_kb.md：合并后用户明确修订。"
  - "dot_matrix_product_selling_points_kb.md、thermal_printer_product_selling_points_kb.md、attendance_machine_product_selling_points_kb.md：型号卖点和用途；如与型号主表冲突，以型号主表及较新的明确修订为准。"
models:
  current_count: 38
  legacy_count: 42
  discontinued_count: 12
---

# r21 产品型号与功能目录

## 使用规则

1. `Current` 是 r21 型号主表的生命周期分类，不保证某店铺当前有货。价格、库存、套餐、赠品和平台链接必须核对实时商品页；不能从历史标题或内部 SKU 表推断。
2. 只把同一型号或同一购买选项下已确认的能力组合成推荐。`未确认` 不等于 `不支持`，但不得当成支持对客户承诺。不同型号的纸宽、连接、系统和电池能力不能拼接。
3. `Legacy` 型号只按历史订单、配件或售后需求处理；不能当作当前在售型号推荐。`Discontinued` 型号不得用于售前推荐，老机维修及配件供应需人工实时核实。
4. 客户硬性条件包括设备系统、连接方式、纸张尺寸、进纸方式、平台、便携或电池时，先逐项匹配精确型号和 SKU。缺少决定性证据时说明尚不能确认具体型号，只询问会改变推荐的一项信息。
5. 以下为产品识别和售前选型目录。安装、故障、退换和维修操作以 r21 对应专题文档及当前订单规则为准。

## r21 Current 型号清单

| 产品线 | Current 型号 | 已确认的统一边界 |
|---|---|---|
| 针式打印机（11） | AK910、AK915、TD630、TD630G、TD630PLUS、TG690、TG890、TH850G、TH880、TH880G、TM690 | 所有针式型号支持前部单张进纸；后进连续纸、系统和连接能力按精确型号核对。 |
| 热敏打印机（23） | GZP510、GZP810S、GZP820、GZP820S、GZP860、GZP860S、JPW500、JPW760S、JPW830、JPW850PLUS、TP510、TP518、TP730、TP730S、TP731、TP732、TP732S、TP870、TP870PLUS、TP874、TP874S、TP876、TP876PLUS | 纸宽和 macOS 能力见下表；未列出的连接、手机系统或电池能力不作推断。 |
| 纸卡考勤机（4） | M880、M880D、T960D、T960S | M880D、T960D 的备用电池/停电打卡已确认；普通款不能据此推断。 |

## 可以依据现有证据直接匹配的需求

| 客户明确需求 | 已确认的候选型号 | 必须同时说明的边界 |
|---|---|---|
| 针式多联票据，Windows 或原生 macOS 电脑使用 | TD630 或 TD630G | Mac 端均走 USB。TD630 的 Windows 电脑也仅走 USB；TD630G 的 Windows 电脑可走 USB 或同一 2.4GHz 局域网 Wi-Fi。具体商品页仍需核对。 |
| 针式多联票据，Windows 电脑需要 Wi-Fi | TD630G | Windows Wi-Fi 需同一 2.4GHz 局域网；不能把此电脑 Wi-Fi 能力套到 TD630。 |
| 针式多联票据，需要前部单张及后部链轮连续纸 | TD630、TD630G 或 AK915 | 三者已确认相应进纸能力；根据系统、连接和购买选项继续选择，不把后进能力推给 AK910。 |
| Windows 针式单张票据，明确不需要后进连续纸 | AK910 | 仅前部单张进纸；不支持 A3，也不支持原生 macOS。 |
| 30–80mm 热敏标签，USB+蓝牙，并使用 macOS USB | TP874 | 已确认 203DPI；速度随具体商品版本核对，不承诺电池、便携或未确认的平台直打。 |
| 热敏机且必须使用 macOS USB | TP870PLUS、TP876PLUS、TP874 或 TP874S | TP870、TP876 不支持 macOS；四个候选的纸宽和购买选项不同，需按下表核对。 |
| 纸卡考勤，要求停电也能打卡 | M880D 或 T960D | 已确认内置备用电池；普通 M880、T960S 不据此承诺停电使用。 |

## 针式打印机型号边界

| 型号 | 已确认能力 | 不得混用的边界 |
|---|---|---|
| TD630 | 售前按“蓝牙+USB”；手机速印通可用蓝牙或 2.4GHz Wi-Fi；Windows 和 macOS 电脑用 USB；前进、后进和连续纸已确认。 | 电脑不支持 Wi-Fi 或蓝牙打印；不得发送 TD630G 的 Windows Wi-Fi 教程。 |
| TD630G | 售前按“蓝牙+Wi-Fi+USB”；手机速印通可用蓝牙或 2.4GHz Wi-Fi；Windows 电脑可 USB 或同一 2.4GHz 局域网 Wi-Fi；Mac 用 USB；前进、后进和连续纸已确认。 | Mac 不支持无线打印；电脑蓝牙打印未获确认。 |
| AK910 | Windows、USB、前部单张进纸；1+5 六联复写已确认。 | 不支持后进连续纸、A3 或原生 macOS。 |
| AK915 | Windows、USB、前进和后进连续纸；1+5 六联复写已确认。 | 不支持原生 macOS；其他连接方式不得推断。 |
| TG890 | Windows、USB、后部链轮连续纸；1+5 六联复写已确认。 | Mac 与无线能力不得从其他型号套用。 |
| TD630PLUS、TG690、TH850G、TH880、TH880G、TM690 | r21 列为 Current。 | 本目录没有逐 SKU 核实这些型号的完整连接、进纸及系统组合；不能仅凭 Current 状态作具体功能推荐。 |

针式纸张通用已确认范围为宽 `100–241mm`、可打印内容宽约 `203mm`、总厚度不超过 `0.45mm`；具体进纸路径仍按型号。不能承诺小于 `100mm` 的窄纸、热敏纸或厚硬证书。所有针式机的固定页面高度设置适用；教程步骤仍须按实际型号与进纸方式。

## 热敏打印机纸宽与系统

| 当前型号 | r21 已确认纸宽 | 额外已确认边界 |
|---|---|---|
| GZP510 | 30–100mm；长度记录为 30–300mm | 内置纸仓，卷径约 12cm。 |
| GZP820 | 30–100mm；长度记录为 30–300mm | 无内置纸仓，后部进纸。 |
| GZP810S、GZP820S、GZP860、GZP860S、JPW500、JPW830、JPW850PLUS、TP731、TP732、TP732S、TP874、TP874S | 30–80mm | 纸仓/卷径、手机系统和连接方式仍按精确型号/SKU；其中 TP874 已确认 USB+蓝牙，TP874/TP874S 已确认 macOS USB。 |
| JPW760S、TP510、TP518、TP730、TP730S、TP876 | 30–100mm；介质最高约 104mm 宽 | TP876 不支持 macOS；其他型号的电脑/手机连接方式不得从宽度推断。 |
| TP870、TP870PLUS | 30–100mm | TP870 不支持 macOS；TP870PLUS 支持 macOS USB。 |
| TP876PLUS | 80mm 购买选项为 30–80mm；104mm 购买选项为 30–100mm | 支持 macOS USB；必须核对实际购买选项后答纸宽。 |

`30–100mm` 纸宽组并不表示所有型号都能使用同一纸仓、卷径、长度或 104mm 打印宽度。只有上表明确记录的长度范围可以直接回答。热敏机不能笼统承诺无间隙连续小票纸，纸型、黑标/间隙和驱动能力需按型号/SKU核对。

## 考勤机及旧型号

| 型号 | r21 生命周期 | 售前边界 |
|---|---|---|
| M880 | Current | 纸卡打卡基础款；不要把备用电池、蓝牙、App 或导出能力当作默认配置。 |
| M880D、T960D | Current | 备用电池/停电打卡已确认；具体班次和设置功能仍按型号核对。 |
| T960S | Current | 纸卡考勤机；不得从型号后缀推断备用电池或手机功能。 |
| M880B、P960、T960BT、T960T | Legacy | 历史订单或售后识别用，不作为当前在售推荐。 |
| M880A、M880BT、M880D-T、M880DA、M880DT、M880T | Discontinued | 不作为当前在售推荐；旧知识中关于电池或 App 的历史能力不改变停售状态。 |

针式 Legacy 型号为 AK890、TH650、TH650G、TH850GB、TH850GW、TH880GW。热敏 Legacy 型号按 [型号主表](all_platform_model_details_2026_09_09_kb.md)；不从旧目录的历史价格、活动或用途推断当前在售。装订机全部型号、GD550、JPW560、JPW590、TH680、TH850、TJYD810 也属于 r21 明确的停产清单。

## 缺少证据时的答复边界

- “iPhone + 20×30mm + 便携/电池热敏机”：本目录没有同时核实这些硬性条件的同一型号/SKU，不能拼接多个产品线资料作推荐。
- TP518、TP730 等型号虽在 Current 清单且有纸宽资料，但本目录没有据此确认其蓝牙、Wi-Fi、iOS 或电池能力；客户要求这些条件时先核对精确商品版本。
- 只能在证据覆盖客户全部硬性条件时给出确定推荐。若只有生命周期或纸宽已确认，就说明当前无法确认具体型号，并指出唯一需要核实的关键字段。

## r21 来源

- [全平台型号主表、生命周期、系统与纸宽](all_platform_model_details_2026_09_09_kb.md)
- [合并后用户明确修订](confirmed_consolidated_merge_2026_09_15_kb.md)
- [针式型号卖点与进纸边界](dot_matrix_product_selling_points_kb.md)
- [热敏型号卖点与 TP874 参数](thermal_printer_product_selling_points_kb.md)
- [纸卡考勤机卖点与电池边界](attendance_machine_product_selling_points_kb.md)
