#!/usr/bin/env python3
"""Apply the user-confirmed Tencent Sept 13 corrections S13-C01..S13-C15."""

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
CATALOG_PATH = ROOT / "rag_cards/china_market_video_catalog.json"
SOURCE = "confirmed_tencent_sept13_updates_2026_09_14_kb.md"


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value.lower())


def ensure_source(card: dict) -> None:
    sources = card.setdefault("source_files", [])
    if SOURCE not in sources:
        sources.append(SOURCE)


def ensure_resolution(card: dict, *resolution_ids: str) -> None:
    values = list(card.get("resolution_ids", []))
    for resolution_id in resolution_ids:
        if resolution_id != card.get("resolution_id") and resolution_id not in values:
            values.append(resolution_id)
    if values:
        card["resolution_ids"] = values


def stamp(card: dict, *resolution_ids: str) -> dict:
    card["version"] = PACKAGE_VERSION
    card["package_version"] = PACKAGE_VERSION
    ensure_source(card)
    ensure_resolution(card, *resolution_ids)
    return card


def main() -> None:
    cards = [
        json.loads(line)
        for line in CARDS_PATH.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]
    by_id = {card["id"]: card for card in cards}

    def upsert(card_id: str, values: dict, *resolution_ids: str) -> dict:
        card = by_id.get(card_id)
        if card is None:
            card = {"id": card_id, "status": "active"}
            cards.append(card)
            by_id[card_id] = card
        card.update(values)
        return stamp(card, *resolution_ids)

    upsert(
        "dot_matrix_daibaiprint_dotnet_crash",
        {
            "product_line": "dot_matrix_printer",
            "models": ["Windows针式打印机"],
            "intent": "driver_installation_troubleshooting",
            "issue": "DaiBaiPrint崩溃退出或.NET错误",
            "keywords": ["DaiBaiPrint", ".NET", "崩溃", "退出", "安装程序报错"],
            "synonyms": ["DaiBaiPrint打不开", "驱动安装器闪退", "net报错"],
            "risk_level": "low",
            "auto_reply_allowed": True,
            "required_evidence": ["客户明确口述DaiBaiPrint/.NET错误或提供截图"],
            "trigger_policy": "only_when_daibaiprint_or_dotnet_error_is_observed_or_reported",
            "reply_template": "如果当前确实出现DaiBaiPrint崩溃、退出或.NET错误，请先安装或修复官方.NET运行环境，完成后重启Windows，再重新运行安装程序。没有观察到该错误时不使用本步骤。",
            "actions": [
                {"type": "confirm_daibaiprint_or_dotnet_error_evidence"},
                {"type": "install_or_repair_official_dotnet_runtime"},
                {"type": "restart_windows"},
                {"type": "rerun_original_driver_installer"},
            ],
            "do_not_say": ["未出现DaiBaiPrint/.NET错误时也安装.NET", "先更换USB接口"],
            "escalation": "安装或修复.NET并重启后仍崩溃，转人工技术。",
            "priority": 230,
        },
        "S13-C01",
        "S13-C02",
    )

    upsert(
        "printer_universal_installer_package_aliases",
        {
            "product_line": "all_printers",
            "models": ["已支持的热敏打印机", "已支持的针式打印机"],
            "intent": "driver_installation",
            "issue": "ThermalNobleDriver和DotNobleDriver通用安装包别名",
            "keywords": ["ThermalNobleDriver", "DotNobleDriver", "通用安装包", "热敏驱动", "针式驱动"],
            "synonyms": ["两个驱动是不是一样", "通用驱动包"],
            "risk_level": "low",
            "auto_reply_allowed": True,
            "reply_template": "ThermalNobleDriver和DotNobleDriver是同一通用安装包的两个名称，该包可用于已支持的热敏和针式打印机。安装后仍必须按实际产品线、型号和连接方式选择设备与设置，不要把针式纸张设置套用到热敏机。",
            "actions": [
                {"type": "confirm_supported_printer_model"},
                {"type": "use_universal_installer_package"},
                {"type": "select_product_specific_model_and_settings_after_install"},
            ],
            "do_not_say": ["热敏机和针式机的安装后参数完全相同", "把针式纸张设置套用到热敏机"],
            "priority": 225,
        },
        "S13-C03",
    )

    driver = stamp(by_id["printer_driver_confirm_model_label_before_download"])
    driver["reply_template"] = (
        "ThermalNobleDriver和DotNobleDriver是同一通用安装包的名称，"
        "可用于已支持的热敏和针式打印机。请先确认Windows或Mac及具体型号；"
        "安装后再按实际产品线、型号和连接方式选择设备与设置。"
    )
    driver["do_not_say"] = ["所有型号都支持Mac", "热敏和针式的安装后参数完全相同", "编造下载链接"]

    reward = stamp(by_id["positive_review_reward_matrix"], "S13-C04")
    reward["reply_template"] = (
        "好评奖励按平台和产品区分：拼多多所有机器为5元返现券，由后台自动发放，未收到时转人工核实；"
        "天猫和京东考勤机为5元现金奖励，需提供好评截图，并由人工收集办理所必需的付款账号信息；"
        "天猫和京东针式打印机优先赠送色带，客户不需要色带时可选10元返现。不得索取密码或验证码，不得引导私下交易。"
    )
    reward["actions"] = [
        {"type": "identify_platform_and_product_line"},
        {"type": "pdd_verify_automatic_five_yuan_voucher_if_missing"},
        {"type": "route_eligible_tmall_or_jd_cash_reward_to_human_for_necessary_payment_account"},
    ]
    reward["do_not_say"] = ["索取密码", "索取验证码", "引导私下交易", "所有平台都人工返现"]

    external = stamp(by_id["platform_external_contact_risk"])
    external["payment_account_exception"] = "eligible_tmall_or_jd_review_cash_reward_human_collection_only"
    external["reply_template"] = (
        "一般联系、交易和转账保持在购买平台内处理。"
        "仅在符合已确认的天猫/京东好评现金奖励时，由人工收集发放奖励所必需的付款账号信息；"
        "任何情况都不索取密码或验证码。"
    )
    external["do_not_say"] = ["加我微信", "发密码或验证码", "私下转账", "平台外交易", "随便给电话"]

    coupon = stamp(by_id["current_product_page_price_coupon_bulk"], "S13-C05")
    coupon["reply_template"] = (
        "亲，商品页面当前显示的价格是当前实际可下单价格。"
        "平台可能提供平台券或补贴，以您当前页面为准，历史优惠不保证继续有效。"
        "商家不发放优惠券；批量购买的其他商务需求可转人工核实，但不承诺发券或降价。"
    )
    coupon["do_not_say"] = ["可以申请店铺优惠券", "承诺降价", "保证返历史差价"]

    price = stamp(by_id["global_price_coupon_difference_high_risk"])
    price["reply_template"] = (
        "亲，商品页面当前显示的价格是当前实际可下单价格；"
        "平台券或补贴以您当前页面为准。商家不发放优惠券，历史优惠或差价也不直接承诺；"
        "已下单的差价争议需人工按订单和平台规则核实。"
    )

    refund = stamp(by_id["global_refund_return_high_risk"], "S13-C06")
    refund["reply_template"] = (
        "亲，非质量原因可按平台规则核对7天无理由资格；经核实的质量问题可在30天内按平台规则办理退货退款或换货。"
        "请发订单售后状态、机器型号、问题现象和图片/视频，我先帮您排查并转人工核实最终资格、运费归属和订单保障是否适用；这里不直接承诺具体金额。"
    )
    refund["customer_shipping_protection_policy"] = "do_not_instruct_customer_to_select_shipping_insurance_or_return_protection"
    refund["do_not_say"] = list(dict.fromkeys(refund.get("do_not_say", []) + ["指示客户选择运费险或退货保障"]))

    upsert(
        "dot_matrix_portrait_default_orientation",
        {
            "product_line": "dot_matrix_printer",
            "models": ["all"],
            "intent": "document_layout",
            "issue": "打印方向默认纵向",
            "keywords": ["打印方向", "Portrait", "Landscape", "纵向", "横向", "默认"],
            "synonyms": ["默认选什么方向", "纸张方向"],
            "risk_level": "low",
            "auto_reply_allowed": True,
            "default_orientation": "portrait",
            "reply_template": "打印方向默认选纵向（Portrait）。只有您明确需要横向，或原文档/打印预览确实为横向时，才在文档和驱动中一致选择横向（Landscape）。",
            "actions": [{"type": "use_portrait_by_default"}, {"type": "use_landscape_only_when_explicit_or_preview_requires"}],
            "priority": 220,
        },
        "S13-C07",
    )

    font = stamp(by_id["dot_matrix_isolated_glyph_font_compatibility"], "S13-C08")
    font["issue"] = "隶书或个别字体不支持、缺笔画或字形异常"
    font["keywords"] = list(dict.fromkeys(font.get("keywords", []) + ["隶书", "Lishu", "字体不支持", "字形异常"]))
    font["synonyms"] = list(dict.fromkeys(font.get("synonyms", []) + ["隶书打不出来", "Lishu字体异常"]))
    font["reply_template"] = "隶书/Lishu或其他个别字体出现缺笔画、乱码、空白或字形异常时，请先更换为已安装的常用字体，重新预览并试打。只有更换字体后仍在同一固定位置缺印，才继续排查色带和打印头。"

    dark = stamp(by_id["suyintong_reduce_contrast_dark_print"], "S13-C09")
    dark["issue"] = "整页很黑、全黑、拖印、字粗或出现大量网点"
    dark["keywords"] = list(dict.fromkeys(dark.get("keywords", []) + ["整张全黑", "整页很黑", "grayscale threshold", "Windows打印太黑"]))
    dark["reply_template"] = "请先把纸厚扳手调到最高第6档。手机速印通打印请降低对比度；Windows打印请降低grayscale threshold。每次调整后先试打一张，再根据效果微调。"
    dark["actions"] = [
        {"type": "raise_paper_thickness_lever_to_6"},
        {"type": "reduce_suyintong_contrast_or_windows_grayscale_threshold"},
        {"type": "test_one_page"},
    ]
    dark["do_not_say"] = ["同时增加对比度或灰度阈值", "未试打就连续大幅调整"]

    upsert(
        "dot_matrix_immediate_eject_blank_job_router",
        {
            "product_line": "dot_matrix_printer",
            "models": ["Windows针式打印机"],
            "intent": "troubleshooting",
            "issue": "纸张进入后立即退出再放入才打印",
            "keywords": ["进纸立即退纸", "再放纸才打印", "SPOOL", "隐藏任务", "开头空白页"],
            "synonyms": ["第一次进纸直接出来", "重新放纸才开始打"],
            "risk_level": "low",
            "auto_reply_allowed": True,
            "reply_template": "请先清空Windows打印队列和SPOOL/printers中的隐藏任务，再检查文档或表格开头是否有空白页，有则删除。然后只发送一个全新任务测试；仍出现进纸后立即退出，再关机清洁对应进纸方向的纸张感应器。",
            "actions": [
                {"type": "clear_print_queue_and_spool_hidden_jobs"},
                {"type": "remove_leading_blank_pages"},
                {"type": "send_fresh_job"},
                {"type": "clean_sensor_if_still_abnormal"},
            ],
            "priority": 226,
        },
        "S13-C10",
    )

    sensor = stamp(by_id["dot_matrix_feed_sensor"], "S13-C11")
    sensor["issue"] = "前进纸不吸入、异常大量进退纸、吞纸或红灯闪烁"
    sensor["keywords"] = list(dict.fromkeys(sensor.get("keywords", []) + ["纸全部吸进去", "红灯闪烁", "吞纸"]))
    sensor["reply_template"] = (
        "前进纸不自动吸入时不需要按进纸键。纸张全部被拉入且红灯闪烁，或前进纸不吸入时，"
        "请先关机断电，取出纸张并取下色带，用少量酒精清洁对应的纸张感应器，"
        "待完全干燥后重新装回色带和纸张测试。干燥后仍反复吞纸、不吸纸或闪红灯，转人工检测。"
    )
    sensor["actions"] = [
        {"type": "power_off"},
        {"type": "clean_paper_sensor_with_small_amount_of_alcohol"},
        {"type": "dry_completely"},
        {"type": "reload_and_test"},
    ]
    sensor["do_not_say"] = ["前进纸不吸入时按进纸键", "通电清洁感应器", "感应器未干就通电测试", "切换不存在的进纸来源选择杆"]

    upsert(
        "dot_matrix_visible_internal_paper_jam",
        {
            "product_line": "dot_matrix_printer",
            "models": ["all"],
            "intent": "troubleshooting",
            "issue": "机器内部明显卡纸",
            "keywords": ["卡纸", "内部有纸", "纸张卡住", "纸屑", "退纸", "第6档"],
            "synonyms": ["机器里面卡了一张纸", "纸抽不出来"],
            "risk_level": "medium",
            "auto_reply_allowed": True,
            "reply_template": "请立即停止打印并关机断电，把纸厚扳手调到最高第6档。色带挡住取纸路径时先取下色带，再安全地使用进纸/退纸机制辅助退出纸张，清除可见纸屑，最后重新装入平整、规格匹配并对齐的纸张。无法安全取出时转人工。",
            "actions": [
                {"type": "stop_printing_and_power_off"},
                {"type": "set_paper_thickness_lever_to_6"},
                {"type": "remove_ribbon_if_blocking"},
                {"type": "use_feed_eject_controls_safely"},
                {"type": "remove_scraps"},
                {"type": "reload_flat_aligned_paper"},
            ],
            "do_not_say": ["拉扯或调整白色排线", "在通电时强拉纸张", "在通电时强推打印头"],
            "escalation": "卡纸无法安全取出、取出后机械件异常或反复卡纸时转人工维修。",
            "priority": 229,
        },
        "S13-C12",
    )

    mobile = stamp(by_id["suyintong_no_device_found_refresh_icon"], "S13-C13")
    mobile["issue"] = "速印通提示输入IP或显示No Device Found"
    mobile["keywords"] = list(dict.fromkeys(mobile.get("keywords", []) + ["Cancel", "输入IP", "手机IP页面"]))
    mobile["reply_template"] = "速印通提示输入IP时，请点Cancel；确认打印机已开机并正确放纸，然后点Refresh。仍未找到设备时，再点右上角打印机图标重新连接。IP录入仅作为Windows网络打印异常的内部技术备选。"
    mobile["manual_ip_policy"] = "windows_abnormal_internal_only"
    mobile["actions"] = [
        {"type": "cancel_ip_prompt"},
        {"type": "confirm_printer_powered_on_and_paper_loaded"},
        {"type": "tap_refresh"},
        {"type": "reconnect_from_top_right_printer_icon_if_needed"},
    ]

    upsert(
        "website_brand_service_closed_platform_support",
        {
            "product_line": "all",
            "models": ["all"],
            "intent": "support_channel",
            "issue": "网站显示无该品牌",
            "keywords": ["无该品牌", "没有这个品牌", "网站服务关闭", "购买平台聊天"],
            "synonyms": ["官网找不到品牌", "网页没有这个品牌"],
            "risk_level": "low",
            "auto_reply_allowed": True,
            "reply_template": "网站仍可正常下载驱动、观看视频和查找说明书；只有直接客服联系功能已关闭。需要人工支持时请回到购买平台聊天。",
            "actions": [{"type": "continue_using_website_resources"}, {"type": "use_purchase_platform_for_direct_support"}],
            "do_not_say": ["网站服务已关闭", "让客户反复使用已关闭的直接客服入口", "编造网站链接"],
            "priority": 225,
        },
        "S13-C14",
    )

    upsert(
        "document_correct_orientation_content_too_small",
        {
            "product_line": "all_printers",
            "models": ["all"],
            "intent": "document_layout",
            "issue": "打印方向正确但内容或字体太小",
            "keywords": ["方向正确", "字太小", "内容太小", "自动适应", "缩放到一页", "行高", "列宽"],
            "synonyms": ["打出来字很小", "页面方向没错但整体太小"],
            "risk_level": "low",
            "auto_reply_allowed": True,
            "reply_template": "请保持当前正确方向，在原始文档或实际打印软件中增大字号，关闭自动适应/缩放到一页，再按内容调整表格行高和列宽。确认预览不裁切后先试打一份，不要为了放大而改变已正确的方向。",
            "actions": [
                {"type": "preserve_correct_orientation"},
                {"type": "increase_font_size"},
                {"type": "disable_shrink_to_fit_or_fit_to_one_page"},
                {"type": "adjust_table_row_height_and_column_width"},
                {"type": "preview_then_test_one_copy"},
            ],
            "priority": 224,
        },
        "S13-C15",
    )

    CARDS_PATH.write_text(
        "".join(json.dumps(card, ensure_ascii=False, separators=(",", ":")) + "\n" for card in cards),
        encoding="utf-8",
    )

    hf = json.loads(HF_PATH.read_text(encoding="utf-8"))
    hf["version"] = PACKAGE_VERSION
    by_query = {normalize(item["query"]): item for item in hf["queries"]}
    additions = {
        "DaiBaiPrint报错退出": "dot_matrix_daibaiprint_dotnet_crash",
        "没有DaiBaiPrint报错要不要安装net": "dot_matrix_daibaiprint_dotnet_crash",
        "ThermalNobleDriver和DotNobleDriver是同一个驱动吗": "printer_universal_installer_package_aliases",
        "好评返现要支付宝账号吗": "positive_review_reward_matrix",
        "商家可以发优惠券吗": "current_product_page_price_coupon_bulk",
        "退货要不要选运费险": "global_refund_return_high_risk",
        "打印方向默认选纵向还是横向": "dot_matrix_portrait_default_orientation",
        "隶书字体打印异常": "dot_matrix_isolated_glyph_font_compatibility",
        "打印整张全黑怎么办": "suyintong_reduce_contrast_dark_print",
        "纸张进入后立即退出再放才打印": "dot_matrix_immediate_eject_blank_job_router",
        "纸全部被吸进去红灯闪烁": "dot_matrix_feed_sensor",
        "机器里面明显卡纸": "dot_matrix_visible_internal_paper_jam",
        "手机APP提示输入IP": "suyintong_no_device_found_refresh_icon",
        "官网提示无该品牌": "website_brand_service_closed_platform_support",
        "方向正确但打印内容太小": "document_correct_orientation_content_too_small",
    }
    for query, card_id in additions.items():
        key = normalize(query)
        if key in by_query:
            by_query[key]["card_id"] = card_id
        else:
            item = {"query": query, "card_id": card_id}
            hf["queries"].append(item)
            by_query[key] = item
    HF_PATH.write_text(json.dumps(hf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    catalog["version"] = PACKAGE_VERSION
    CATALOG_PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"cards={len(cards)} queries={len(hf['queries'])} version={PACKAGE_VERSION}")


if __name__ == "__main__":
    main()
