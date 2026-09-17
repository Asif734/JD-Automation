#!/usr/bin/env python3
"""Apply the user-confirmed Tencent Sept 14 AM corrections S14AM-C01..C29."""

from __future__ import annotations

import json
import re
from pathlib import Path

try:
    from scripts.package_version import PACKAGE_VERSION
except ModuleNotFoundError:
    from package_version import PACKAGE_VERSION


ROOT = Path(__file__).resolve().parents[1]
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF_PATH = ROOT / "rag_cards/high_frequency_queries.json"
QUERY_PATH = ROOT / "rag_cards/customer_service_rag_test_queries.txt"
VIDEO_CATALOG_PATH = ROOT / "rag_cards/china_market_video_catalog.json"
DRIVER_CATALOG_PATH = ROOT / "rag_cards/driver_delivery_catalog.json"
SOURCE = "confirmed_tencent_sept14_am_updates_2026_09_14_kb.md"


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value.lower())


def main() -> None:
    cards = [json.loads(line) for line in CARDS_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]
    by_id = {card["id"]: card for card in cards}

    def stamp(card: dict, *resolution_ids: str) -> dict:
        card["version"] = PACKAGE_VERSION
        card["package_version"] = PACKAGE_VERSION
        sources = card.setdefault("source_files", [])
        if SOURCE not in sources:
            sources.append(SOURCE)
        existing = list(card.get("resolution_ids", []))
        for resolution_id in resolution_ids:
            if resolution_id != card.get("resolution_id") and resolution_id not in existing:
                existing.append(resolution_id)
        if existing:
            card["resolution_ids"] = existing
        return card

    def upsert(card_id: str, values: dict, *resolution_ids: str) -> dict:
        card = by_id.get(card_id)
        if card is None:
            card = {"id": card_id, "status": "active"}
            cards.append(card)
            by_id[card_id] = card
        card.update(values)
        return stamp(card, *resolution_ids)

    def focused_card(issue: str, keywords: list[str], reply: str, *, models: list[str] | None = None,
                     intent: str = "tutorial", priority: int = 225, auto: bool = True,
                     do_not_say: list[str] | None = None) -> dict:
        return {
            "product_line": "dot_matrix_printer",
            "models": models or ["all"],
            "intent": intent,
            "issue": issue,
            "keywords": keywords,
            "synonyms": keywords[1:],
            "risk_level": "low" if auto else "high",
            "auto_reply_allowed": auto,
            "reply_template": reply,
            "do_not_say": do_not_say or [],
            "priority": priority,
        }

    upsert(
        "dot_matrix_preprinted_placeholder_fields",
        focused_card(
            "预印模板中的重复字符占位符",
            ["*****", "11111", "22222", "占位符", "预印表格", "套打"],
            "模板中的*****、11111或22222只是用于定位和校准可变字段的临时占位符，没有特殊含义。正式使用时替换为真实数据；预印纸已有的边框、标签和固定文字不要重复打印。",
            intent="template_editing",
        ),
        "S14AM-C01",
    )

    package = stamp(by_id["family_default_package_contents_20260909"], "S14AM-C02")
    package["required_slots"] = [slot for slot in package.get("required_slots", []) if slot != "精确型号/订单选项"]
    package["reply_template"] = (
        "亲，针式打印机标准包装含机内预装色带、USB数据线和2张测试纸，确认这三项时无需确认具体型号。"
        "热敏机默认含10张测试纸和USB-A转USB-D数据线；考勤机默认含电源适配器、50张考勤卡、预装考勤色带和2颗挂墙螺丝。"
        "额外赠品、套餐数量或特殊电源结构仍按订单选项核实。默认USB数据线长1.2米；更长的数据线只要接头匹配并支持数据传输即可。"
    )

    upsert(
        "suyintong_app_connect_qr_manual_search",
        focused_card(
            "速印通APP连接二维码扫描失败后手动搜索",
            ["APP连接二维码", "二维码扫不出来", "手动搜索", "Search", "打印机开机", "正确放纸"],
            "请先确认打印机已开机并正确放纸，再在速印通内扫描机身上标有APP连接二维码的二维码。扫描失败时，在App内选择手动Search/搜索打印机。",
            models=["速印通", "支持手机连接的针式打印机"],
        ),
        "S14AM-C03",
    )

    login = stamp(by_id["suyintong_account_password_guest"], "S14AM-C04")
    login["template_storage_boundary"] = "guest_and_formal_account_templates_are_local_and_do_not_sync"
    login["do_not_say"] = list(dict.fromkeys(login.get("do_not_say", []) + ["仅回答登录栏时主动展开模板不同步说明"]))

    borders = stamp(by_id["suyintong_missing_table_border_line_width"], "S14AM-C05", "S14AM-C14")
    borders["reply_template"] = "请在速印通模板中选中表格或任意单元格，找到线条粗细并设置为0.6–0.7，确认预览边框完整后试打一张。纸厚扳手只按实际效果作为补充调整，不是第一步。"

    upsert(
        "th880_online_driver_queue_selection",
        focused_card(
            "TH880JM灰色而TH880JMS在线时选择在线队列",
            ["TH880JM灰色", "TH880JMS在线", "脱机队列", "默认打印机", "在线驱动"],
            "TH880JM显示灰色/脱机而TH880JMS在线时，请使用可用在线驱动TH880JMS，也可按需要设为默认打印机。不要只因另一个匹配队列离线就删除驱动；只有连接、端口、队列和隐藏任务排查后仍确认持续重复或错误驱动，才清理错误项并重装。",
            models=["TH880JM", "TH880JMS"],
            intent="troubleshooting",
            priority=232,
        ),
        "S14AM-C06",
    )

    speed = stamp(by_id["dot_matrix_unified_driver_speed"], "S14AM-C07")
    speed["reply_template"] = "提高速度可在打印首选项→Layout→Advanced→Graphic→Print Quality选择DPI:180*144以降低打印质量，或在Configure中取消勾选单向打印/One-way printing以启用双向打印；保存后完全关闭并重新打开打印软件，再取出纸张并正确重新装入后试打一张。双向打印不等于双面打印。"

    upsert(
        "suyintong_android_permission_prompt",
        focused_card(
            "VIVO或Android首次连接时按App提示授权",
            ["VIVO", "Android", "DotMatrix Printer", "蓝牙权限", "位置权限", "附近设备"],
            "打开速印通/SupPrint并选择DotMatrix Printer；App弹出请求时允许蓝牙、位置和附近设备权限。初始步骤不需要先手动进入手机设置。",
            models=["VIVO", "Android", "速印通"],
            do_not_say=["一开始就让客户手动进入系统设置"],
        ),
        "S14AM-C08",
    )

    upsert(
        "suyintong_serial_number_not_required",
        focused_card(
            "速印通连接不需要打印机序列号",
            ["序列号", "Serial Number", "连接凭证", "可选字段"],
            "速印通连接打印机不需要打印机序列号，请不要编造。模板里的Serial Number只是可选的打印字段，不是设备凭证；不需要时可留空或删除。",
            models=["速印通"],
            intent="template_editing",
            do_not_say=["编造打印机序列号", "把模板字段当成连接密码"],
        ),
        "S14AM-C09",
    )

    upsert(
        "dot_matrix_video_slow_printing_speed",
        focused_card(
            "客户视频或音频显示针式打印速度慢",
            ["视频打印慢", "声音打印慢", "降低打印质量", "取消单向打印", "检查画面和声音"],
            "请先完整检查客户视频的画面和声音。确认属于打印速度慢时，降低打印质量，并在Configure中取消勾选One-way printing后试打一张；不要只看画面或只听声音就判断。",
            intent="performance_settings",
            priority=231,
        ),
        "S14AM-C10",
    )

    upsert(
        "quality_return_zto_freight_policy",
        focused_card(
            "质量问题退货的中通运费与人工处理",
            ["质量问题退货", "中通", "顺丰", "京东物流", "运费报销", "运单号", "无法取消售后"],
            "质量问题售后单无法取消重提时，请提供可追踪运单号，转人工继续跟进。经确认的质量问题寄回可使用中通并按规则核实报销；不要建议顺丰或京东物流，这两者不在已确认报销范围。凭证、具体金额和最终处理由人工按订单核实。",
            intent="after_sales",
            priority=270,
            auto=False,
            do_not_say=["承诺具体报销金额", "顺丰可以报销", "京东物流可以报销", "让客户到付"],
        ),
        "S14AM-C11",
    )

    freight_old = stamp(by_id["approved_freight_reimbursement_handoff"])
    freight_old["reply_template"] = "已批准的质量问题运费处理请使用中通等可追踪的经济型快递，不要到付；顺丰或京东物流不建议使用且不在已确认报销范围。请保留运单号和支付凭证，报销上限与具体金额由人工客服按订单核实。"

    upsert(
        "dot_matrix_ribbon_universal_new_models",
        focused_card(
            "所有新款针式打印机色带通用",
            ["新款针式打印机", "色带通用", "针打色带", "耗材"],
            "色带在所有新款针式打印机的支持范围内通用，不需要按具体新款针式型号区分。该结论不适用于考勤机、热敏产品或未确认的老旧型号。",
            intent="presale_consumables",
            priority=240,
            do_not_say=["考勤机色带也通用", "热敏产品使用色带", "所有老款都通用"],
        ),
        "S14AM-C12",
    )

    ribbon = stamp(by_id["dot_matrix_ribbon_install"])
    ribbon["reply_template"] = "请先取下色带，用多联纸检查第二联；第二联没有横线或固定缺线时再更换新款针式打印机通用色带。安装时撕掉透明保护膜，保持平直不扭转，放入打印头和导片之间并收紧；再次变松通常是收带齿轮打滑，需要更换色带。"
    ribbon["do_not_say"] = [item for item in ribbon.get("do_not_say", []) if item != "色带随便买都一样"]

    upsert(
        "th880_portrait_same_paper_size",
        focused_card(
            "TH880JM和TH880JMS纸张尺寸相同并默认纵向",
            ["TH880JM", "TH880JMS", "纸张尺寸一样", "Portrait", "纵向", "内容太小"],
            "默认选纵向Portrait。TH880JM和TH880JMS使用相同纸张尺寸，不要仅为纸张尺寸切换驱动。先选择正确纸张尺寸；内容仍小，再调整原文档的边距、页眉页脚和缩放。",
            models=["TH880JM", "TH880JMS"],
            intent="document_layout",
        ),
        "S14AM-C13",
    )

    upsert(
        "website_resources_contact_only_closed",
        {
            "product_line": "all",
            "models": ["all"],
            "intent": "support_channel",
            "issue": "网站资源正常而直接客服联系功能关闭",
            "keywords": ["官网", "驱动下载", "视频", "说明书", "直接客服关闭", "二维码无法扫描", "zjweiting"],
            "synonyms": ["网站还能用吗", "官网能下载驱动吗", "二维码扫不出来"],
            "risk_level": "low",
            "auto_reply_allowed": True,
            "reply_template": "网站仍正常提供驱动下载、视频和说明书等资源；只有直接客服联系功能已关闭。指南二维码无法扫描时，可打开https://www.zjweiting.com/download.htm 获取已确认资源；需要人工支持时回到购买平台聊天。",
            "actions": [{"type": "use_website_resources"}, {"type": "use_purchase_platform_for_direct_support"}],
            "do_not_say": ["网站服务已关闭", "不能下载驱动", "不能看视频或说明书"],
            "priority": 250,
        },
        "S14AM-C15",
    )

    website_old = stamp(by_id["website_brand_service_closed_platform_support"])
    website_old["issue"] = "网站无品牌结果与直接客服入口关闭"
    website_old["keywords"] = ["无该品牌", "没有这个品牌", "直接客服联系关闭", "购买平台聊天", "网站资源正常"]
    website_old["reply_template"] = "网站仍可正常下载驱动、观看视频和查找说明书；只有直接客服联系功能已关闭。若网站搜索无该品牌，可使用已确认下载页查找资料；需要人工支持时回到购买平台聊天。"
    website_old["actions"] = [{"type": "continue_using_website_resources"}, {"type": "use_purchase_platform_for_direct_support"}]
    website_old["do_not_say"] = ["网站服务已关闭", "让客户反复使用已关闭的直接客服入口", "编造网站链接"]

    upsert(
        "suyintong_fixed_template_edit_paper_rows",
        focused_card(
            "速印通固定模板修改纸张尺寸和行数",
            ["固定模板", "右上角Edit", "纸张尺寸", "增加行数", "编辑模板"],
            "打开速印通固定模板，点击右上角Edit/编辑，选择需要的纸张尺寸，再增加所需行数；确认预览后先试打一份。",
            models=["速印通"],
            intent="template_editing",
        ),
        "S14AM-C16",
    )

    photo_template = stamp(by_id["dot_matrix_delivery_template_precision"], "S14AM-C17")
    photo_template["routing_note"] = "paper_or_document_photo_plus_app_template_photo_and_layout_correction_routes_to_app_template_support"

    third_party = stamp(by_id["suyintong_third_party_order_app_template"], "S14AM-C18")
    third_party["reply_template"] = "其他手机开单App不能直接调用针式打印机。请先保存或导出文件，再进入速印通→DotMatrix Printer→Document Printing/文档打印。多联纸1+5表示一份原件加五份复写联，不等于软件设置多份打印。"

    stale = stamp(by_id["dot_matrix_immediate_eject_blank_job_router"], "S14AM-C19")
    stale["windows_restart_required"] = False
    stale["reply_template"] = "请先清空Windows打印队列和SPOOL/printers隐藏任务，再只发送一份新任务；清理旧任务无需重启电脑。若纸张仍立即退出，再检查开头空白页和纸张感应器。"

    cable = stamp(by_id["dot_matrix_usb_cable_connector_default_length"], "S14AM-C20")
    cable["reply_template"] = "默认USB-A转USB-D数据线长1.2米。更长的数据线只要打印机端接头匹配并支持数据传输即可使用，长度本身不是限制。"

    upsert(
        "suyintong_stuck_print_recent_tasks",
        focused_card(
            "打印机关机后速印通卡在打印界面",
            ["卡在打印界面", "打印机关机", "最近任务", "无需强制停止", "重新打开App"],
            "请把速印通从手机最近任务中移除，无需强制停止；再将打印机开机并正确放纸，重新打开App后重试。",
            models=["速印通"],
            intent="troubleshooting",
        ),
        "S14AM-C21",
    )

    upsert(
        "windows_print_test_page_context_routes",
        focused_card(
            "Windows设置与控制面板的打印测试页入口",
            ["Windows设置", "控制面板", "Print test page", "打印机属性", "打印测试页"],
            "在Windows设置中选择已安装的打印机驱动，直接点击Print test page/打印测试页；在控制面板中右键打印机→Printer Properties/打印机属性→Print Test Page/打印测试页。",
            models=["Windows"],
            intent="driver_testing",
        ),
        "S14AM-C22",
    )

    upsert(
        "suyintong_app_connect_qr_loading",
        focused_card(
            "扫描APP连接二维码后一直加载",
            ["app connect二维码", "一直加载", "蓝牙权限", "位置权限", "重启打印机", "关闭App"],
            "请确认打印机已开机，并允许App使用蓝牙和位置权限；然后重启打印机、关闭App，重新打开后再连接。",
            models=["速印通", "支持手机连接的针式打印机"],
            intent="connectivity_troubleshooting",
            do_not_say=["先切换2.4G Wi-Fi", "先关闭手机流量"],
        ),
        "S14AM-C23",
    )

    upsert(
        "suyintong_excel_document_no_scaling",
        focused_card(
            "速印通打印已保存Excel文件且没有缩放选项",
            ["Excel", "没有缩放选项", "DotMatrix Printer", "Document Printing", "文档打印"],
            "速印通没有缩放选项。请先把Excel文件保存到手机，再选择DotMatrix Printer→Document Printing/文档打印；尺寸问题请在原Excel文件或纸张设置中调整，不要寻找不存在的App缩放控件。",
            models=["速印通"],
            intent="document_printing",
            do_not_say=["速印通有缩放按钮"],
        ),
        "S14AM-C24",
    )

    upsert(
        "suyintong_same_phone_hotspot_bluetooth_first",
        focused_card(
            "同一部手机提供热点并运行速印通",
            ["同一部手机", "手机热点", "速印通", "Wi-Fi打印", "蓝牙优先"],
            "同一部手机可以同时开启热点并运行速印通进行Wi-Fi打印。没有普通Wi-Fi时优先使用蓝牙，步骤更简单；客户明确要求Wi-Fi时再指导手机热点。",
            models=["速印通", "支持Wi-Fi的针式打印机"],
            intent="connectivity",
        ),
        "S14AM-C25",
    )

    upsert(
        "suyintong_harmonyos_bluetooth_setup",
        focused_card(
            "HarmonyOS平板连接新款针式打印机",
            ["鸿蒙", "HarmonyOS", "平板", "速印通", "SupPrint", "蓝牙优先", "色带预装"],
            "新款针式打印机的色带已预装。HarmonyOS平板请使用速印通/SupPrint，优先按蓝牙方式连接；只有客户明确要求Wi-Fi时才走Wi-Fi流程。",
            models=["HarmonyOS", "新款针式打印机"],
            intent="connectivity",
        ),
        "S14AM-C26",
    )

    upsert(
        "dot_matrix_wifi_install_power_cycle_continue",
        focused_card(
            "Wi-Fi安装搜索期间打印机关机后继续",
            ["Automatic", "Search", "Wi-Fi安装", "打印机自动关机", "重新开机", "重新放纸", "继续安装"],
            "Wi-Fi安装请选择Automatic→Search，并确保纸张已正确装入。打印机自动关机后重新开机、重新正确放纸，让安装程序继续即可，不需要从头重复全部步骤。",
            models=["支持Wi-Fi的针式打印机", "Windows"],
            intent="driver_installation",
        ),
        "S14AM-C27",
    )

    bulk = stamp(by_id["current_product_page_price_coupon_bulk"], "S14AM-C28")
    bulk["reply_template"] = "商品页面当前显示的价格是当前实际可下单价格，商家不发放优惠券，也不承诺批量折扣。客户需要批量购买时先询问具体数量，再转人工核实商务方案。"

    dark = stamp(by_id["suyintong_mobile_dark_thick_contrast_lever"], "S14AM-C29")
    dark["reply_template"] = "发黑、模糊或字符粘连时，单向打印与此问题无关。请先在速印通中降低对比度，再把纸厚扳手提高到最高第 6 档，或按实际打印效果选择所需档位，然后只试打一张。彩色PDF可以直接使用，彩色字体会以黑色打印。"
    dark["actions"] = [{"type": "reduce_mobile_app_contrast"}, {"type": "raise_paper_thickness_lever_to_6_or_as_needed"}, {"type": "test_one_page"}]

    offline = stamp(by_id["dot_matrix_no_print_offline_queue"])
    offline["reply_template"] = "先确认打印机开机放纸、USB连接和端口匹配，再使用当前可用在线驱动，清空队列、取消暂停/脱机并删除SPOOL/printers隐藏任务；需要时通过services.msc重启Print Spooler。只有仍确认存在持续的重复或错误驱动故障时，才删除错误项并重装；不要仅因另一个匹配队列离线就全部删除。"
    offline["actions"] = [{"type": "use_available_online_driver"}, {"type": "clear_queue_and_hidden_jobs"}, {"type": "confirm_persistent_duplicate_or_wrong_driver_before_cleanup"}]

    cleanup = stamp(by_id["dot_matrix_remove_duplicate_drivers_clean_reinstall"])
    cleanup["issue"] = "确认持续重复或错误驱动后的定向清理重装"
    cleanup["reply_template"] = "先使用可用在线驱动，并核对连接、端口、队列和隐藏任务。只有仍确认存在持续的重复或错误驱动故障时，才删除错误项并用官方安装包重装；不得仅因另一个匹配队列离线就全部删除。"

    ribbon_match = stamp(by_id["dot_matrix_ribbon_model_match"])
    ribbon_match["issue"] = "新款针式色带通用与产品线边界"
    ribbon_match["reply_template"] = "所有新款针式打印机范围内的色带通用，无需按具体新款针式机型号区分；考勤机、热敏产品和未确认老款仍按各自耗材规则处理。"
    ribbon_match["do_not_say"] = ["把针式色带用于考勤机", "热敏产品使用色带", "承诺未确认老款兼容"]

    combined = stamp(by_id["dot_matrix_speed_rear_app_ribbon_combined"])
    combined["reply_template"] = "提高速度：降低打印质量，并在Configure取消勾选One-way printing以启用双向打印。后进纸仅用于支持型号；手机使用速印通。所有新款针式打印机色带通用，考勤机、热敏产品和未确认老款不套用。"
    combined["actions"] = [{"type": "answer_all_four_subquestions"}, {"type": "use_exact_speed_controls"}, {"type": "gate_rear_feed_by_model"}, {"type": "use_suyintong_china_name"}, {"type": "use_new_dot_matrix_universal_ribbon_boundary"}]

    lifespan = stamp(by_id["dot_matrix_ribbon_invoice_lifespan"])
    lifespan["reply_template"] = "色带技术寿命约500万字符。按普通发票参考通常约可打印1000–2000张；实际会因文字覆盖率、联数和打印浓度变化。字迹明显变浅时，更换新款针式打印机通用色带。"

    email = stamp(by_id["printer_driver_email_reusable_large_attachment"])
    email["reply_template"] = "可以通过邮箱发送Windows通用驱动。请提供客户邮箱并确认电脑为Windows；系统找到仍有至少72小时有效期的大附件后，会先显示收件人、主题、正文、文件名和有效期，获得明确确认后才发送。"
    email["do_not_say"] = list(dict.fromkeys(email.get("do_not_say", []) + ["不要主动说明两个名称是同一个通用安装包"]))

    driver = stamp(by_id["printer_driver_confirm_model_label_before_download"])
    driver["reply_template"] = "请先确认客户电脑是Windows还是Mac；Mac或不明确产品线时再确认具体型号。Windows支持机型可发送已确认通用安装包，安装后按实际产品线、设备和连接方式选择设置。普通回复不主动解释安装包的两个名称。"
    driver["do_not_say"] = list(dict.fromkeys(driver.get("do_not_say", []) + ["普通驱动回复中主动解释ThermalNobleDriver和DotNobleDriver名称关系"]))

    CARDS_PATH.write_text("".join(json.dumps(card, ensure_ascii=False, separators=(",", ":")) + "\n" for card in cards), encoding="utf-8")

    routes = {
        "模板里一排*****是什么意思": "dot_matrix_preprinted_placeholder_fields",
        "针式打印机包装里有色带USB线和测试纸吗": "family_default_package_contents_20260909",
        "APP连接二维码扫不出来怎么手动搜索": "suyintong_app_connect_qr_manual_search",
        "游客和账号模板会同步到新手机吗": "suyintong_account_password_guest",
        "速印通表格少线先调什么": "suyintong_missing_table_border_line_width",
        "TH880JM灰色TH880JMS在线用哪个": "th880_online_driver_queue_selection",
        "双向打印在哪里设置": "dot_matrix_unified_driver_speed",
        "VIVO手机连接打印机权限怎么开": "suyintong_android_permission_prompt",
        "速印通需要打印机序列号吗": "suyintong_serial_number_not_required",
        "视频里打印机速度太慢怎么加快": "dot_matrix_video_slow_printing_speed",
        "质量问题退货中通顺丰京东运费怎么处理": "quality_return_zto_freight_policy",
        "新款针式打印机色带通用吗": "dot_matrix_ribbon_universal_new_models",
        "TH880JM和TH880JMS纸张尺寸一样吗": "th880_portrait_same_paper_size",
        "官网还能下载驱动看视频和说明书吗": "website_resources_contact_only_closed",
        "速印通固定模板怎么改纸张尺寸增加行数": "suyintong_fixed_template_edit_paper_rows",
        "发纸张照片和App模板照片怎样调整版式": "dot_matrix_delivery_template_precision",
        "其他手机开单App怎么用针式打印机打印": "suyintong_third_party_order_app_template",
        "清理Windows旧打印任务要重启电脑吗": "dot_matrix_immediate_eject_blank_job_router",
        "USB打印线超过1.2米能用吗": "dot_matrix_usb_cable_connector_default_length",
        "打印机关机后手机还卡在打印界面": "suyintong_stuck_print_recent_tasks",
        "Windows设置里打印测试页在哪里": "windows_print_test_page_context_routes",
        "扫描app connect二维码一直加载": "suyintong_app_connect_qr_loading",
        "速印通打印手机Excel怎么缩放": "suyintong_excel_document_no_scaling",
        "同一部手机开热点还能用速印通打印吗": "suyintong_same_phone_hotspot_bluetooth_first",
        "鸿蒙平板怎样安装连接针式打印机": "suyintong_harmonyos_bluetooth_setup",
        "换网络后打印机自动关机怎么继续安装": "dot_matrix_wifi_install_power_cycle_continue",
        "批量购买能不能优惠": "current_product_page_price_coupon_bulk",
        "打印文字发黑粘在一起要开单向打印吗": "suyintong_mobile_dark_thick_contrast_lever",
    }
    hf = json.loads(HF_PATH.read_text(encoding="utf-8"))
    hf["version"] = PACKAGE_VERSION
    by_query = {normalize(item["query"]): item for item in hf["queries"]}
    for query, card_id in routes.items():
        key = normalize(query)
        if key in by_query:
            by_query[key]["card_id"] = card_id
        else:
            item = {"query": query, "card_id": card_id}
            hf["queries"].append(item)
            by_query[key] = item
    HF_PATH.write_text(json.dumps(hf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    existing_query_lines = set(QUERY_PATH.read_text(encoding="utf-8").splitlines())
    with QUERY_PATH.open("a", encoding="utf-8") as handle:
        for query, card_id in routes.items():
            line = f"{query} -> {card_id}"
            if line not in existing_query_lines:
                handle.write(line + "\n")
                existing_query_lines.add(line)

    for catalog_path in (VIDEO_CATALOG_PATH, DRIVER_CATALOG_PATH):
        catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
        catalog["version"] = PACKAGE_VERSION
        catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"cards={len(cards)} queries={len(hf['queries'])} version={PACKAGE_VERSION}")


if __name__ == "__main__":
    main()
