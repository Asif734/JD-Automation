#!/usr/bin/env python3
"""Upsert the confirmed 2026-08-24 afternoon dot-matrix RAG data."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF_PATH = ROOT / "rag_cards/high_frequency_queries.json"
TEST_QUERIES_PATH = ROOT / "rag_cards/customer_service_rag_test_queries.txt"
SOURCE = "confirmed_dot_matrix_updates_2026_08_24_afternoon_kb.md"


def card(card_id: str, issue: str, keywords: list[str], synonyms: list[str], reply: str, *, intent: str = "troubleshooting", models: list[str] | None = None, risk: str = "low", priority: int = 142, escalation: str = "") -> dict:
    value = {
        "id": card_id,
        "version": "2026-08-24",
        "status": "active",
        "source_files": [SOURCE],
        "product_line": "dot_matrix_printer",
        "models": models or ["针式打印机"],
        "intent": intent,
        "issue": issue,
        "keywords": keywords,
        "synonyms": synonyms,
        "risk_level": risk,
        "auto_reply_allowed": risk != "high",
        "reply_template": reply,
        "priority": priority,
    }
    if escalation:
        value["escalation"] = escalation
    return value


NEW_CARDS = [
    card("dot_matrix_windows_driver_cross_model_port_test", "Windows针打型号间驱动通用与端口测试", ["针打驱动通用", "AK890", "TG890", "TD630", "端口", "测试页"], ["不同型号驱动能用吗", "AK890驱动能给TG890用吗", "AK890驱动能给TD630用吗"], "Windows针式打印机的不同型号驱动可能通用，例如AK890/TG890或AK890/TD630。请确认驱动端口对应当前实体打印机，再打印测试页验证。这个规则不适用于热敏机、标签机或考勤机。", intent="compatibility", priority=150),
    card("dot_matrix_remove_duplicate_drivers_clean_reinstall", "重复或离线驱动导致不打印", ["重复驱动", "离线驱动", "干净重装", "打印队列"], ["有多个同名打印机", "删哪个驱动", "驱动装了还是脱机"], "请先清空打印任务，删除电脑中所有重复的在线/离线驱动，然后使用官方安装包重新安装，选对端口后打印测试页。", priority=149),
    card("dot_matrix_front_feed_paper_sensor", "前进纸不吸纸或红灯不灭", ["前进纸", "不吸纸", "红灯", "纸张感应器", "取下色带"], ["前面放纸不进", "放纸红灯一直亮"], "前进纸不自动吸入时不需要按进纸键。取出纸张和色带，关机后用少量酒精清洁纸张感应器，完全干燥后重新装回测试；仍异常转人工返厂。", priority=166, escalation="清洁并干燥后仍无法吸纸时转人工返厂检测。"),
    card("suyintong_template_inventory_records", "速印通模板创建库存和销售单据", ["速印通", "库存管理", "销售订单", "创建模板", "编辑模板"], ["手机记录销售单", "同一客户订单", "APP能做表格吗"], "可以在速印通的模板功能中创建、编辑和打印库存管理或销售单据，不仅限于导入文件。请先选择合适模板或新建模板，添加文字、表格等内容，预览位置正确后再打印。", intent="tutorial", models=["TD630", "TD630G", "支持速印通的针式打印机"], priority=147),
    card("suyintong_no_device_found_refresh_icon", "速印通显示No Device Found", ["No Device Found", "未找到设备", "Refresh", "右上角打印机图标", "Enter IP"], ["APP搜不到打印机", "手机没找到设备"], "请先确认打印机已开机并正确放纸，然后在速印通中点击Refresh/刷新。如果仍无设备，点击右上角打印机图标重新连接。App正常连接不使用Enter IP；IP端口只用于Windows网络打印排查。", intent="connection", models=["TD630", "TD630G", "速印通App"], priority=151),
    card("dot_matrix_narrow_front_feed_skew", "前进纸因纸张过窄而倾斜", ["纸太窄", "100-241mm", "100–241mm", "前进纸倾斜", "导纸器"], ["进纸斜了", "孔位不对称", "纸张走斜"], "图中是前进纸，纸张宽度明显过窄，容易走斜。建议使用100–241mm宽的纸张，放平后让导纸器贴合纸边再进纸。", priority=148),
    card("dot_matrix_left_sprocket_hole_offset", "打印内容压到左侧链轮孔", ["左侧链轮孔", "Remove Left Blank", "删除左边空白", "内容偏左"], ["字打在左边孔上", "打印压到进纸孔"], "请打开Windows打印首选项→Configure，取消勾选“删除左边空白/Remove Left Blank”，再检查导纸位置和文档左边距后测试。", priority=149),
    card("dot_matrix_page_too_black_reduce_density", "整页过黑或图片大面积实黑", ["整页黑", "大面积实黑", "降低对比度", "降低Density", "阈值"], ["为什么打出来全黑", "图片打印太黑"], "手机打印请在速印通中降低对比度；Windows打印请在打印首选项→Configure中降低Density/阈值，数值越高通常越深。调整后先用普通文字文档测试；仍异常时转人工检测。", priority=149, escalation="降低对比度/阈值后普通文字仍异常，或怀疑打印头损伤时转人工。"),
    card("dot_matrix_density_dpi_location", "Density阈值与DPI打印质量设置", ["Density", "阈值", "DPI", "打印质量", "Configure"], ["浓度在哪设置", "如何调DPI", "打印深浅怎么调"], "请进入Windows的打印首选项→Configure调整Density/阈值。DPI/打印质量也会影响打印深浅、清晰度和速度，调整后请用测试页确认效果。", intent="settings", priority=145),
    card("dot_matrix_package_test_paper_layers", "包装测试纸和1至6联纸规格", ["两张测试纸", "1-6联", "1–6联", "0.45mm", "100-241mm", "纸张长度不限"], ["包装有纸吗", "支持几联", "纸张宽度和厚度"], "标准包装内含两张测试纸，正式使用的打印纸需另行购买。支持100–241mm宽、总厚度不超过0.45mm、长度不限的纸张，可打1–6联（原件+最多5张复写）。", intent="presale", priority=150),
    card("tmall_zto_no_sf_no_next_day_promise", "天猫中通发货与时效边界", ["天猫快递", "中通", "顺丰", "次日达", "发货"], ["发什么快递", "能发顺丰吗", "明天能到吗"], "天猫店铺常规使用中通快递，不支持顺丰，也不承诺次日必达。具体发货和物流时效以实际订单页为准。", intent="shipping_policy", models=["all"], risk="medium", priority=150),
    card("dot_matrix_multi_device_sequential_jobs", "多台设备共用打印机时任务顺序", ["多台设备", "两台Mac", "两台电脑", "两台手机", "队列", "顺序打印"], ["能同时连两台吗", "多个人能一起打印吗"], "多台设备可以配置使用同一台打印机，但打印任务会按队列顺序执行，同一时间只处理一个任务。请等前一个任务完成后再发送下一个。", intent="compatibility", priority=146),
    card("platform_chat_then_phone_handoff", "微信或电话指导请求", ["微信指导", "电话指导", "平台聊天", "转人工"], ["加微信教我", "给我打电话", "电话安装"], "我可以先在这里发您简单步骤、图片或已审核教程，您按步骤操作时有问题可以继续问我。如果您仍需要电话指导，我帮您转人工客服。", intent="compliance", models=["all"], risk="high", priority=151, escalation="客户坚持电话指导时转人工。"),
    card("dot_matrix_standard_half_third_page_height", "标准二等分和三等分连续纸高度", ["93.1mm", "139.7mm", "三等分", "二等分", "Fixed Page Height"], ["三联纸高度多少", "二联纸高度多少", "需要量纸吗"], "标准三等分连续纸高度设为93.1mm，标准二等分高度设为139.7mm。标准规格不需要重新测量；只有非标准纸才需要实际测量。", intent="settings", priority=149),
    card("dot_matrix_qr_code_types_china", "机身App连接驱动教程和客服二维码区分", ["APP连接二维码", "驱动二维码", "教程二维码", "客服二维码", "download.htm", "速印通"], ["应该扫哪个二维码", "机器上几个码有什么区别"], "手机连接请扫描标有“APP连接二维码”的码。驱动/教程二维码对应https://www.zjweiting.com/download.htm，客服二维码用于联系客服。中国市场App对客名称为速印通。", intent="tutorial", models=["支持手机连接的针式打印机"], priority=150),
    card("tmall_invoice_return_dot_matrix", "天猫电子普票与7天无理由退货", ["电子普票", "订单页开票", "7天无理由", "非质量问题", "退货运费"], ["怎么开发票", "七天可以退吗", "退货运费谁付"], "天猫电子普通发票可在订单页申请；修改、撤销、重开、专票或税务争议转人工财务。天猫订单按平台规则支持7天无理由退货；非质量问题寄回运费由买家承担，以订单售后页为准。", intent="after_sales", models=["all"], risk="high", priority=150, escalation="发票修改/重开/专票/税务争议或退货争议转人工。"),
    card("dot_matrix_preprinted_form_duplicate_overlay", "预印表格出现双重线或双重文字", ["双重线", "双重文字", "预印表格", "重复打印", "可变数据"], ["表格重影", "预印单据打了两层", "为什么表格叠在一起"], "请先检查同一张纸是否重复打印了两次。使用预印单据时，模板只保留需填写的可变数据，不要再打表格线和固定文字；需要打完整表格时请使用空白纸。", priority=150),
    card("dot_matrix_ribbon_model_match", "新款针式色带通用与产品线边界", ["买色带", "色带通用", "针式打印机", "耗材边界"], ["色带能通用吗", "应该买哪个色带"], "所有新款针式打印机色带通用；考勤机、热敏产品和未确认老款仍按各自耗材规则处理。", intent="presale", priority=143),
    card("dot_matrix_outdoor_power_800w", "车载或逆变器使用针式打印机", ["200W", "车载", "户外电源", "逆变器", "内置电源线", "AC输出"], ["在车里用买多大逆变器", "车载打印"], "车内使用时，逆变器需要至少200W功率输出，并提供稳定且符合机器额定输入的AC输出；使用机器内置电源线连接。", intent="power", priority=166),
]


HF_QUERIES = {
    "不同针式打印机驱动能通用吗": "dot_matrix_windows_driver_cross_model_port_test",
    "有多个离线驱动怎么办": "dot_matrix_remove_duplicate_drivers_clean_reinstall",
    "前进纸不吸纸红灯亮": "dot_matrix_front_feed_paper_sensor",
    "速印通怎么做库存单": "suyintong_template_inventory_records",
    "APP显示No Device Found": "suyintong_no_device_found_refresh_icon",
    "纸太窄进纸倾斜": "dot_matrix_narrow_front_feed_skew",
    "打印压到左侧链轮孔": "dot_matrix_left_sprocket_hole_offset",
    "整页打印太黑": "dot_matrix_page_too_black_reduce_density",
    "Density和DPI在哪调": "dot_matrix_density_dpi_location",
    "包装有几张测试纸支持几联": "dot_matrix_package_test_paper_layers",
    "天猫发什么快递能发顺丰吗": "tmall_zto_no_sf_no_next_day_promise",
    "多台设备能同时打印吗": "dot_matrix_multi_device_sequential_jobs",
    "能加微信或电话教我吗": "platform_chat_then_phone_handoff",
    "三等分和二等分纸高多少": "dot_matrix_standard_half_third_page_height",
    "手机连接应该扫哪个二维码": "dot_matrix_qr_code_types_china",
    "天猫怎么开普票和七天退货": "tmall_invoice_return_dot_matrix",
    "预印表格打出双重线": "dot_matrix_preprinted_form_duplicate_overlay",
    "应该买哪个色带": "dot_matrix_ribbon_model_match",
    "车里使用针式打印机逆变器要多大功率": "dot_matrix_outdoor_power_800w",
}


def main() -> None:
    cards = [json.loads(line) for line in CARDS_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]
    by_id = {item["id"]: item for item in cards}

    # Update existing cards whose old wording conflicts with the confirmed rules.
    by_id["dot_matrix_no_print_offline_queue"].update({
        "version": "2026-08-24",
        "source_files": ["dot_matrix_after_sales_issues_kb.md", SOURCE],
        "reply_template": "请先使用可用在线驱动，取消脱机/暂停并清空任务，再核对连接和端口。只有仍确认持续存在错误或重复驱动故障时，才删除错误项并用官方安装包重装。",
        "priority": 149,
    })
    by_id["dot_matrix_feed_sensor"].update({
        "version": "2026-08-24",
        "source_files": ["dot_matrix_after_sales_issues_kb.md", SOURCE],
        "reply_template": "前进纸不自动吸入时不需要按进纸键。取出纸张和色带，关机后清洁纸张感应器并完全干燥后重试；仍异常转人工返厂。",
        "priority": 148,
    })
    by_id["wifi_search_device_not_found"].update({
        "version": "2026-08-24",
        "models": ["蓝牙WiFi针打", "WiFi打印机", "速印通 App"],
        "source_files": ["wifi_bluetooth_printer_kb.md", "printernoble_bluetooth_wifi_dot_matrix_kb.md", SOURCE],
        "reply_template": "请先确认打印机已开机并正确放纸。速印通显示未找到设备时，先点刷新，仍无设备再点右上角打印机图标重新连接。Wi-Fi机型请使用2.4G网络。",
        "priority": 148,
    })
    by_id["dot_matrix_windows_business_software_printing"].update({
        "version": "2026-08-24",
        "source_files": ["confirmed_needle_printer_updates_2026_08_24_kb.md", "dot_matrix_product_selling_points_kb.md", SOURCE],
        "reply_template": "安装好Windows驱动后，只要软件能调用Windows已安装的打印机，一般就可在软件中选择本机驱动打印，不受打印机品牌限制。我们可协助远程安装驱动和调试，但不提供或维护第三方业务软件。",
        "priority": 146,
    })
    by_id["suyintong_multiple_phones_templates"].update({
        "version": "2026-08-24",
        "source_files": ["confirmed_needle_printer_updates_2026_08_24_kb.md", "wifi_bluetooth_printer_kb.md", SOURCE],
        "reply_template": "本地模板不能导出、分享、同步或转移；客服后台模板只有客户以前申请过时才可按对应订单编号搜索。",
        "priority": 146,
    })
    by_id["confirmed_platform_shipping_2026_08_18"].update({
        "version": "2026-08-24",
        "source_files": ["confirmed_customer_service_updates_2026_08_18_kb.md", "qianniu_customer_service_training_kb.md", SOURCE],
        "keywords": list(dict.fromkeys(by_id["confirmed_platform_shipping_2026_08_18"]["keywords"] + ["中通", "顺丰", "次日达"])),
        "reply_template": "京东店铺从京东仓库发货，具体时间以订单/商品页为准。拼多多、天猫和抖音从上海工厂发货；天猫常规使用中通，不支持顺丰，不承诺次日必达。16:00前通常当天安排，之后顺延至下一批次；这不是绝对时效承诺，以实际订单为准。",
        "do_not_say": ["16点前一定当天发出", "保证当天揽收", "可以发顺丰", "保证次日到达"],
        "priority": 150,
    })
    by_id["platform_external_contact_risk"].update({
        "version": "2026-08-24",
        "source_files": by_id["platform_external_contact_risk"]["source_files"] + [SOURCE],
        "reply_template": "为了保障您的订单和售后安全，我可以先在这里发简单步骤、图片或已审核教程，您遇到问题可以继续问我。如果您仍需要电话指导，我帮您转人工客服。",
        "escalation": "客户坚持平台外联系、交易、转账或电话指导时转人工。",
        "priority": 151,
    })
    by_id["global_invoice_high_risk"].update({
        "version": "2026-08-24",
        "source_files": by_id["global_invoice_high_risk"]["source_files"] + [SOURCE],
        "reply_template": "天猫电子普通发票可在订单页申请。如果需要修改、撤销、重开、申请专票，或者页面无法申请，请说明需求，我帮您转人工财务核对。",
        "priority": 150,
    })
    by_id["printer_driver_confirm_model_label_before_download"].update({
        "version": "2026-08-24",
        "source_files": ["qianniu_customer_service_training_kb.md", "dot_matrix_windows_usb_driver_install_kb.md", SOURCE],
        "required_slots": ["电脑系统", "Mac或非针打时的具体型号"],
        "reply_template": "请先确认是Windows还是Mac。Windows针式打印机可用官方通用安装包搜索设备；安装后再确认端口并打测试页。Mac或非针式打印机请提供具体型号。",
        "do_not_say": ["所有型号都支持Mac", "把针式机安装后的纸张或进纸设置套用到热敏机", "编造下载链接"],
        "priority": 149,
    })
    by_id["dot_matrix_system_compatibility_selling_point"].update({
        "version": "2026-08-24",
        "source_files": ["dot_matrix_product_selling_points_kb.md", SOURCE],
        "reply_template": "只有TD630和TD630G支持Windows和原生macOS，其他针式型号只支持Windows。Windows针式打印机的型号间驱动可能通用，但必须选对端口并打测试页验证。",
        "priority": 149,
    })
    by_id["windows_usb_driver_install_visual_guide"].update({
        "version": "2026-08-24",
        "source_files": ["dot_matrix_windows_usb_driver_install_kb.md", "sources/user_uploads/dot_matrix_driver_installation/nobel_auto_install_windows.mp4", SOURCE],
        "reply_template": "1. 打印机通电开机；2. 用USB线连接Windows电脑；3. 运行店铺或可信官方安装程序；4. 选择USB→搜索→选中搜索到的打印机→下一步；5. 安装成功后在Windows打印机和扫描仪中打印测试页并确认实际出纸。",
        "do_not_say": ["让客户猜打印机型号", "驱动来源不明也继续运行", "所有型号都支持Mac", "看到1 document in queue就断言实体测试页已打印"],
        "priority": 149,
    })

    for item in NEW_CARDS:
        by_id[item["id"]] = item

    # Preserve original order and append newly created IDs in declared order.
    original_ids = [item["id"] for item in cards]
    output = [by_id[card_id] for card_id in original_ids]
    output.extend(item for item in NEW_CARDS if item["id"] not in original_ids)
    CARDS_PATH.write_text("".join(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n" for item in output), encoding="utf-8")

    hf = json.loads(HF_PATH.read_text(encoding="utf-8"))
    hf["version"] = "2026-08-24"
    existing = {item["query"]: item for item in hf["queries"]}
    for query, card_id in HF_QUERIES.items():
        existing[query] = {"query": query, "card_id": card_id}
    hf["queries"] = list(existing.values())
    HF_PATH.write_text(json.dumps(hf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    lines = TEST_QUERIES_PATH.read_text(encoding="utf-8").splitlines()
    existing_lines = set(lines)
    for query, card_id in HF_QUERIES.items():
        line = f"{query} -> {card_id}"
        if line not in existing_lines:
            lines.append(line)
    TEST_QUERIES_PATH.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

    print(f"cards={len(output)}")
    print(f"high_frequency_queries={len(hf['queries'])}")
    print(f"added_or_updated={len(NEW_CARDS) + 11}")


if __name__ == "__main__":
    main()
