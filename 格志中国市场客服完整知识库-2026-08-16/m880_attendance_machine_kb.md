---
knowledge_base: "m880_attendance_machine_customer_service"
language: "zh-CN internal notes + English buyer replies"
purpose: "供 GPT 学习 M880/M880T 打卡式考勤机客服回复、售后排查和退货挽回"
compiled_at: "2026-05-15"
shop_context: "Shopee PH / mybestgrozziie / Grozziie"
product_focus:
  - "M880 / M880T punch card attendance machine"
  - "Grozziie Punch Card Attendance Machine / Bundy Clock Time Recorder"
not_in_scope:
  - "AFace01 face recognition attendance machine"
  - "app/cloud-connected face recognition attendance devices"
source_files:
  - path: "/Users/dnying/Documents/Codex/2026-05-15/computer-plugin-computer-use-openai-bundled/outputs/shopee_service_data/2026-05-15/normalized/mybestgrozziie_PH_customer_service_kb.md"
    relevant_sections: "产品知识: M880/M880T; cases CS-PH-20260515-003, 011, 012, 013"
  - path: "/Users/dnying/Documents/Codex/2026-05-15/computer-plugin-computer-use-openai-bundled/outputs/shopee_service_data/2026-05-15/normalized/mybestgrozziie_PH_case_index.csv"
    relevant_rows: "M880, punch_card_machine, return_save, troubleshooting"
  - path: "/Users/dnying/Documents/Codex/2026-05-14/computer-plugin-computer-use-openai-bundled/outputs/shopee_service_data/2026-05-15/normalized/daily_records.csv"
    relevant_rows: "M880T return note: buyer does not know how to use it"
source_links_observed_in_chat:
  - "https://printernoble.com/m880series/"
privacy: "本文件不保存买家姓名、电话、地址、完整订单号等敏感信息。"
verification_note: "本文件只整理聊天和本地客服数据中已观察到的信息；未核实的机器参数、按钮名称、安装步骤不得编造。"
---

# M880/M880T 考勤机客服学习资料

## 0. GPT 使用说明

当客户提到 `M880`、`M880T`、`punch card attendance machine`、`Bundy Clock`、`time recorder`、`punch card`、`card not printing`、`not punching time`、`I don't know how to use it` 时，优先调用本文件。

回复策略：

1. 先确认产品是 `M880/M880T punch card attendance machine`，不要混到 AFace01 人脸识别考勤机。
2. 使用问题先询问客户卡在哪一步，再发送知识库中对应的国内可用教程、视频或截图。
3. 故障问题先要短视频/照片，视频要拍到插卡动作和机器反应。
4. 退货中客户说不会用时，先帮助解决，不要一开始要求客户取消退货。
5. 只有问题解决且客户愿意保留商品时，才可以温和提醒客户可取消 Shopee 退货申请。

## 1. learned_facts 已学习事实

- 产品定位：M880/M880T 是打卡式考勤机、纸卡打卡机，也可称为 `punch card attendance machine` 或 `Bundy Clock Time Recorder`。
- 主要售后风险：客户不会使用，可能直接发起退货。
- 关键预防动作：购买后和客户反馈不会用时，应发送知识库中已确认的国内可用教程、视频或截图。
- 教程链接：`https://printernoble.com/m880series/`
- 打卡纸缺货时：客户可以从其他店或文具店购买，但必须确认卡片尺寸与机器可用卡片尺寸一致。
- 机器不打时间/停止打卡时：先请客户发送短视频，视频需展示插卡过程和机器反应，再判断是卡片、设置、色带还是机器问题。
- 色带/打印变浅相关：天气可能导致色带变干；可先尝试按视频指引轻微顺时针转动色带旋钮并换色带面，不要直接让客户购买新色带。

## 2. intent_routing 意图识别

| 客户表达 | 识别意图 | GPT 动作 |
|---|---|---|
| I don't know how to use it / How to use / manual / tutorial | 不会使用/需要教程 | 询问卡在哪一步，再发送知识库中对应的国内视频或截图 |
| I opened return because I cannot use it | 退货挽回+使用指导 | 道歉，问具体困难，发教程，请客户发视频/照片；解决后再提取消退货 |
| Machine stopped punching time / not punching / no time printed | 打卡失败/不打印时间 | 请求短视频，要求拍插卡和机器反应，再排查卡片、设置、色带、机器 |
| Punch card no stock / can I buy card outside / bookstore | 打卡纸耗材 | 可以外购同尺寸卡片，强调尺寸必须一致 |
| Light print / ribbon dry / need replace ribbon? | 色带/打印浅 | 先按视频尝试转动色带旋钮和换面；无效再继续排查 |
| Is this face recognition / app / internet? | 可能混淆产品 | 确认是否是 M880/M880T 纸卡机；不要套用 AFace01 人脸机回复 |

## 3. required_triage 排查时必须收集的信息

### 3.1 不会使用

- 客户卡在哪一步：设置时间、插卡、打印、换卡、看记录、安装纸卡等。
- 是否已看教程页和视频。
- 是否愿意发送照片或短视频。

### 3.2 机器不打时间/不打印

- 请客户发短视频，拍到：
  - 使用的卡片。
  - 插卡过程。
  - 机器屏幕或可见状态。
  - 机器是否有声音、动作或打印痕迹。
- 排查方向只能说：卡片、设置、色带、机器问题。不要在没有视频前直接判断机器坏了。

### 3.3 打卡纸/耗材

- 确认客户要买的是 punch card，不是色带。
- 如果本店缺货，允许客户去其他店或文具店买。
- 必须提醒：尺寸要与机器可用卡片尺寸一致，否则可能无法正常打卡。

### 3.4 色带/打印浅

- 先提示天气可能让色带变干。
- 先尝试轻微顺时针转动色带旋钮，并换色带面。
- 如果客户不会操作，要求客户按视频操作并发短视频。

## 4. safe_reply_templates 英文客服模板

### 4.1 购买后主动发送教程

> Thank you for your order. For the M880/M880T punch card attendance machine, please tell us which setup step you need help with. We will send the corresponding tutorial video or screenshots directly in the chat and guide you step by step.

### 4.2 客户说不会使用

> Sorry for the inconvenience sir/ma'am. May I know which step is difficult for you? We will send the corresponding tutorial video or screenshots directly in the chat. If it is still unclear, please send us a short video/photo so we can guide you step by step.

### 4.3 已发起退货但原因是不会使用

> Sorry for the inconvenience sir/ma'am. May I know which step is difficult or what problem you met? Please send a short video/photo here so we can guide you step by step. We will send the corresponding tutorial video or screenshots directly in the chat. If the issue is solved and you want to keep the item, you may cancel the return request in Shopee. If it is still not solved, please continue the Shopee return process.

### 4.4 机器停止打卡/不打印时间

> Could you please send a short video showing the issue? Please show how you insert the card and what the machine does. This will help us understand whether it is a card, setting, ribbon, or machine issue.

### 4.5 打卡纸缺货/想去别处买卡

> If our punch cards are not available, you can buy from another shop or bookstore, sir. Please make sure the card size is the same as our card size so it can work properly with the machine.

### 4.6 色带变干/打印浅

> Sometimes the ribbon can dry because of weather. Please turn the ribbon screw clockwise a little and change the ribbon side, following the video instruction. No need to replace first unless it still does not work after trying this. If it is still unclear, please send us a short video.

## 5. do_not_say 禁用表达

- 不要说：“Please cancel return first.”  
  应先解决客户不会使用的问题，解决后再温和提醒客户可以取消退货。
- 不要说：“The machine is broken.”  
  没有视频前不能直接判断机器故障。
- 不要说：“Any card is OK.”  
  必须强调卡片尺寸要一致。
- 不要说：“You must buy only from us.”  
  本地资料显示可以从其他店或文具店买同尺寸卡片。
- 不要把 M880/M880T 回复成 AFace01 人脸识别考勤机，不要提扫码下载 App、联网或订阅，除非客户明确购买的是对应设备。
- 不要承诺未核实参数、按钮路径、维修赔付或换新结果。

## 6. escalation_rules 转人工/升级规则

- 客户已经申请退货，并表示不会使用：优先转人工跟进，发送教程和视频，并记录是否解决。
- 客户发来视频后仍无法判断：转技术/售后专员。
- 客户说机器完全无反应、无法开机、严重损坏：要求视频/照片并转售后。
- 客户情绪激动、投诉客服、差评风险：停止自动重复回复，转人工安抚。
- 涉及 Shopee 退货流程、退款进度、平台裁定：不要替平台作最终判断，按 Shopee 流程处理。

## 7. memory_cards 给 GPT 的短记忆卡

### card: m880_usage_risk

- 触发词：`M880`, `M880T`, `how to use`, `tutorial`, `manual`, `I don't know how to use it`
- 动作：发教程链接 + 视频列表 + 问具体卡点 + 要照片/视频
- 风险：客户因不会用发起退货

### card: m880_return_save

- 触发词：`return`, `refund`, `cannot use`, `don't know how`
- 动作：先道歉和帮助，不先要求取消退货；解决后再提醒可取消退货
- 风险：强迫取消退货会引发投诉

### card: m880_not_punching_time

- 触发词：`not punching`, `stopped punching time`, `no time`, `not print`
- 动作：要短视频，展示插卡和机器反应
- 排查方向：card / setting / ribbon / machine issue

### card: m880_punch_card_consumable

- 触发词：`punch card`, `card available`, `bookstore`, `buy card`
- 动作：可外购，但必须同尺寸
- 风险：卡片尺寸不对导致无法正常打卡

### card: ribbon_light_printing

- 触发词：`ribbon`, `light print`, `dry`, `replace ribbon`
- 动作：先轻微顺时针转动色带旋钮并换色带面；仍不行再发视频
- 风险：过早要求客户买新色带，增加售后不满

## 8. source_case_index 来源案例索引

| Case ID | 主题 | 产品 | 关键学习点 |
|---|---|---|---|
| CS-PH-20260515-003 | return_save_usage_issue_m880 | M880/M880T punch card attendance machine | 不会使用导致退货；先教学和要视频，解决后再提取消退货 |
| CS-PH-20260515-011 | ribbon_dry_or_light_printing | Ribbon cartridge / punch card machine | 色带可能因天气变干，先转动色带旋钮并换面 |
| CS-PH-20260515-012 | punch_card_availability_same_size | M880 punch card attendance machine | 打卡纸可外购，但尺寸必须一致 |
| CS-PH-20260515-013 | m880_stopped_punching_time | M880 punch card attendance machine | 机器不打时间时先要视频，拍插卡和机器反应 |

## 9. next_actions 建议后续动作

- 把 `4.1 购买后主动发送教程` 加入 M880/M880T 售后关怀或发货后快捷回复。
- 把 `4.2`、`4.3`、`4.4` 加入 Shopee Seller Chat 快捷短语。
- 若以后从 M880 教程页或视频中提取到具体安装/设置步骤，再追加“step_by_step_setup”章节；在此之前不要编造具体按钮或菜单。
