#!/usr/bin/env python3
"""Apply the user-confirmed 2026-09-13 C01-C20 RAG/data migration."""

from __future__ import annotations

import json
import re
from pathlib import Path

try:
    from scripts.package_version import PACKAGE_VERSION
except ModuleNotFoundError:  # Direct execution from scripts/.
    from package_version import PACKAGE_VERSION

ROOT = Path(__file__).resolve().parents[1]
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
HF_PATH = ROOT / "rag_cards/high_frequency_queries.json"
CATALOG_PATH = ROOT / "rag_cards/china_market_video_catalog.json"
VERSION = PACKAGE_VERSION
SOURCE = "confirmed_conflict_remediation_2026_09_13_kb.md"


def action(kind: str) -> dict[str, str]:
    return {"type": kind}


def card(
    conflict_id: str,
    card_id: str,
    issue: str,
    keywords: list[str],
    reply: str,
    actions: list[str],
    *,
    risk: str = "medium",
    auto: bool = True,
    models: list[str] | None = None,
    intent: str = "troubleshooting",
    extra: dict | None = None,
) -> dict:
    result = {
        "id": card_id,
        "version": VERSION,
        "package_version": VERSION,
        "resolution_id": conflict_id,
        "status": "active",
        "source_files": [SOURCE],
        "product_line": "dot_matrix_printer",
        "models": models or ["all"],
        "intent": intent,
        "issue": issue,
        "keywords": keywords,
        "synonyms": [],
        "risk_level": risk,
        "auto_reply_allowed": auto,
        "reply_template": reply,
        "actions": [action(kind) for kind in actions],
        "priority": 260,
    }
    if extra:
        result.update(extra)
    return result


NEW_CARDS = [
    card("C01", "dot_matrix_start_position_sensor_after_settings", "起始位置从页面中间开始", ["从中间开始打印", "起始位置", "纸张感应器"], "请先核对进纸方向、纸张规格、固定页高、页边距和装纸位置。这些都正确但仍从中间开始时，请关机后清洁对应进纸方向的纸张感应器，待完全干燥后重新装纸测试。", ["check_orientation_paper_size_fixed_height_and_loading", "clean_matching_paper_sensor_if_still_wrong"]),
    card("C02", "suyintong_bold_text_contrast_lever_6", "手机打印文字太粗", ["手机字太粗", "对比度", "纸厚第6档"], "请先在速印通中降低对比度，再把纸厚扳手调高到最高第 6 档，或按实际打印效果选择所需档位，然后试打一张。", ["lower_mobile_contrast", "raise_paper_thickness_lever_to_6_or_as_needed", "test_one_page"], risk="low", extra={"do_not_say": ["Density", "DPI", "灰度阈值", "图像增强", "位置2"]}),
    card("C03", "tmall_paid_sf_exception_handoff", "天猫客户愿补差价要求顺丰", ["补差价发顺丰", "顺丰", "中通"], "亲，店铺常规使用中通，这里不承诺顺丰，也不承诺留言就能安排。您愿意承担差价的情况，我转人工帮您核实是否可以特殊付费安排。", ["state_zto_normal_rule", "do_not_promise_sf_or_note", "handoff_to_check_paid_exception"], risk="high", auto=False, intent="logistics", extra={"escalation": "转人工核实特殊付费安排；核实前不承诺。"}),
    card("C04", "dot_matrix_dotnet_win7_manual_driver", "Windows 7 缺少 .NET 时安装驱动", ["Windows 7", ".NET 4.8", "手动安装驱动"], "通常请安装 .NET 4.8 后再运行安装程序。如果是 Windows 7，也可以手动安装打印机驱动，手动路线不需要升级 .NET。", ["identify_windows_version", "install_dotnet_48_normally", "offer_manual_driver_on_windows_7"], risk="high", models=["Windows针式打印机"]),
    card("C05", "dot_matrix_windows_offline_usb_detection_first", "Windows 打印机灰色或脱机", ["灰色", "脱机", "AT32", "USB识别"], "请先重新插紧 USB 数据线或更换电脑 USB 接口，确认 Windows 能检测到常见的 AT32 设备；然后核对驱动端口是否匹配。设备已识别后如仍脱机，再检查队列、暂停/脱机状态和隐藏任务。", ["restore_usb_connection", "verify_at32_detection", "check_matching_port", "then_check_queue_offline_state"], risk="high", models=["Windows针式打印机"]),
    card("C06", "dot_matrix_macos_td630_queue_offline", "macOS 中 NOBLE PARAGON TD630 SZ 脱机", ["NOBLE PARAGON TD630 SZ", "Mac Offline", "Mac 脱机"], "NOBLE PARAGON TD630 SZ 是 Mac 中已安装的打印队列/驱动名称，不是物理设备名。显示 Offline 时，请先确认打印机已开机，再检查 USB 数据线和 Mac 端口。", ["identify_macos_queue_name", "check_printer_power", "check_usb_connection"], models=["TD630", "TD630G"], extra={"do_not_say": ["Mac 无线打印", "Standard TCP/IP", "编造新的 Mac 安装功能"]}),
    card("C07", "dot_matrix_vertical_feed_discontinuity_one_way", "纵向断层、表格分段或异常空白带", ["表格断开", "异常空白带", "纵向不连续", "单向打印"], "请在打印首选项的 Configure 中启用 One-way printing/单向打印后试打。如果表格上下分段或异常空白带仍存在，转人工维修。", ["enable_one_way_printing", "test_print", "handoff_if_persistent"], risk="high"),
    card("C08", "dot_matrix_garbled_output_evidence_router", "针式打印乱码的证据分流", ["乱码", "隐藏任务", "第三方App", "Mac错误驱动"], "请按当前证据选择一个分支：有残留任务就清理队列和隐藏任务；Windows 连接不稳定就检查 USB/端口；第三方手机 App 直接打印时先导出文件，再用速印通打开；Mac 则检查系统支持和正确 Mac 驱动。", ["select_evidence_supported_branch", "clear_hidden_jobs_if_present", "check_usb_port_if_unstable", "export_then_open_in_suyintong_for_third_party_mobile", "verify_supported_mac_driver"], extra={"do_not_say": ["一次堆叠所有分支", "购买云盒解决乱码"]}),
    card("C09", "dot_matrix_drag_mark_clean_ribbon_free_test", "水平拖墨或划痕", ["水平划痕", "拖墨", "打印针无法回缩"], "请先关机断电，取下色带，清理打印头和支架周围的纸屑/异物；再不安装色带，用多联纸试打。如果明显划痕仍在，可能是打印针无法回缩，需要转人工维修或更换打印头。", ["power_off_and_remove_ribbon", "clean_printhead_and_bracket", "ribbon_free_multipart_test", "repair_head_if_scratch_persists"]),
    card("C10", "dot_matrix_multipart_paper_delamination", "多联纸分层、卷曲或折叠", ["多联纸分层", "卷曲", "折叠", "进纸歪"], "多联纸应连接成一整套。各联分层、错位、卷曲或折叠会导致走歪/卡纸；请先更换完整纸套，或把整套对齐后重新放置，再判断打印机。", ["inspect_joined_paper_set", "replace_or_align_set", "diagnose_printer_only_after_paper_is_correct"], risk="low"),
    card("C11", "dot_matrix_new_housing_logo_model_label", "新机外壳没有明显 Logo 或型号", ["新机没有logo", "没看到型号", "铭牌", "打印宽度"], "部分新外壳正面不一定显示醒目 Logo，产品也可能按打印宽度分类。准确型号以机身或标签/铭牌为准；需要区分后续操作时，请拍一下标签/铭牌。", ["explain_housing_variation_cautiously", "request_label_only_if_needed"], risk="low", extra={"do_not_say": ["编造具体型号", "没有 Logo 就不是正品"]}),
    card("C12", "dot_matrix_shutdown_and_no_feed_router", "打印机会关机且不进纸", ["自动关机不进纸", "组合症状", "前进纸感应器"], "这两个症状需要拆分。关机方面先换一个已知正常的墙插电源座，仍关机则转人工维修；不进纸方面先从前方正确插纸，仍不吸纸则关机清洁前进纸感应器。", ["split_shutdown_and_no_feed", "try_known_working_outlet", "handoff_if_shutdown_persists", "front_insert_paper", "clean_matching_paper_sensor"], risk="high", extra={"do_not_say": ["拔 USB", "按进纸键"]}),
    card("C13", "dot_matrix_nonfixed_broken_characters_hardware_first", "不固定位置的断字或缺笔画", ["断字不固定", "缺笔画", "色带打印头"], "请先检查色带是否安装正确、扭曲、破损或过旧，再取下色带用多联纸检查打印头。硬件检查后，再改用常见字体，然后将纸厚档位向低调一档试打。", ["diagnose_ribbon", "diagnose_printhead", "then_change_to_common_font", "then_lower_paper_thickness_one_step"], risk="high"),
    card("C14", "dot_matrix_isolated_glyph_font_compatibility", "表格线和其他字体正常时个别字缺笔画", ["个别字缺笔画", "表格线正常", "其他字体正常", "字形兼容"], "如果只有个别字缺笔画，但表格线和其他字体都正常，请先改用常见字体对比。只有更换字体后同一固定位置仍缺线，才继续检查色带和打印头。", ["compare_other_fonts_and_table_lines", "try_common_font_first", "hardware_only_if_fixed_across_fonts"], risk="high"),
    card("C15", "dot_matrix_shutdown_sequence", "打印机无法关机", ["无法关机", "红灯闪烁", "电源键"], "请先取出纸张，按住电源键，看到红灯闪烁时松开。如果打印机仍未关机，请断开打印机的电源供应。", ["remove_paper", "hold_power_until_red_flashes", "release_power_button", "disconnect_power_if_still_on"], risk="low"),
    card("C16", "dot_matrix_windows_wifi_automatic_search", "Windows Wi-Fi 驱动与端口自动安装", ["Automatic Search", "WiFi驱动", "自动端口"], "请在安装程序中选择 Automatic，点击 Search，选中搜索到的打印机后继续，程序会自动安装无线驱动和端口。搜索失败时请拍一张当前页面继续核对。", ["select_automatic", "click_search", "select_detected_printer", "install_wireless_driver_and_port_automatically"], risk="high", models=["TD630G", "Windows Wi-Fi针式打印机"], extra={"manual_tcp_ip_policy": "internal_exception_only"}),
    card("C17", "dot_matrix_driver_zip_exe_fallback", "ZIP 驱动包无法解压", ["ZIP解压失败", "EXE驱动", "驱动压缩包"], "只有 ZIP 压缩包需要解压；EXE 安装程序可以直接运行。如果 ZIP 无法解压，请回到官方下载页选择 EXE 版本并直接运行。", ["identify_zip_or_exe", "extract_zip_only", "download_and_run_exe_if_zip_fails"], risk="high", models=["Windows打印机"]),
    card("C18", "dot_matrix_windows_test_page_overlap", "Windows 测试页文字重叠", ["Windows测试页重叠", "起始边", "实际文档"], "请先重新定位纸张起始边后试打，或暂不使用该测试页判断，改打一份实际文档。只有实际文档也重叠时，再检查纸张规格和驱动安装。", ["reposition_paper_start_edge", "print_actual_document", "check_paper_size_and_driver_only_if_document_overlaps"], models=["Windows针式打印机"]),
    card("C19", "dot_matrix_configure_ui_semantics_internal", "Configure 按钮和附近日期/构建号的含义", ["Configure是什么", "Configure日期", "驱动构建号"], "点击 Configure 会打开独立的驱动设置窗口；附近的日期/构建号不是打印机型号，也不是一项功能。", ["answer_ui_semantics_only_when_asked"], risk="low", auto=False, intent="settings_reference", extra={"usage_policy": "answer_only_when_customer_asks_what_configure_or_adjacent_date_means"}),
    card("C20", "dot_matrix_usb_cable_connector_default_length", "自购 3 米 USB 数据线与默认线长", ["3米USB线", "1.2米", "USB-A转USB-D", "接头匹配"], "默认随机 USB 数据线长度为 1.2 米。自购 3 米 USB 线时，长度本身不是问题；只要打印机端接头匹配且线材支持数据传输，就可以使用。", ["confirm_connector_match", "confirm_data_capability", "allow_regardless_of_length"], risk="low", extra={"do_not_say": ["3 米因长度不能用", "纯充电线也可以"]}),
]


QUERIES = {
    "纸放对了还是从中间开始打印": "dot_matrix_start_position_sensor_after_settings",
    "手机打印字太粗怎么调": "suyintong_bold_text_contrast_lever_6",
    "我补差价可以发顺丰吗": "tmall_paid_sf_exception_handoff",
    "Windows 7缺少NET怎么安装驱动": "dot_matrix_dotnet_win7_manual_driver",
    "打印机灰色脱机而AT32没有出现": "dot_matrix_windows_offline_usb_detection_first",
    "Mac上NOBLE PARAGON TD630 SZ显示Offline": "dot_matrix_macos_td630_queue_offline",
    "表格中间断开有异常空白带": "dot_matrix_vertical_feed_discontinuity_one_way",
    "针式打印机打出来是乱码": "dot_matrix_garbled_output_evidence_router",
    "打印有水平拖墨划痕": "dot_matrix_drag_mark_clean_ribbon_free_test",
    "多联纸分层卷曲进纸歪": "dot_matrix_multipart_paper_delamination",
    "新打印机没有Logo也看不到型号": "dot_matrix_new_housing_logo_model_label",
    "打印机会关机而且不进纸": "dot_matrix_shutdown_and_no_feed_router",
    "打印字符断断续续但不固定": "dot_matrix_nonfixed_broken_characters_hardware_first",
    "只有一个字缺笔画表格线和其他字体正常": "dot_matrix_isolated_glyph_font_compatibility",
    "打印机无法关机": "dot_matrix_shutdown_sequence",
    "TD630G电脑WiFi驱动怎么自动安装": "dot_matrix_windows_wifi_automatic_search",
    "ZIP驱动包解压失败": "dot_matrix_driver_zip_exe_fallback",
    "Windows测试页文字重叠": "dot_matrix_windows_test_page_overlap",
    "Configure按钮和旁边日期是什么": "dot_matrix_configure_ui_semantics_internal",
    "自己买的3米USB线能用吗": "dot_matrix_usb_cable_connector_default_length",
}


def normalized(value: str) -> str:
    return re.sub(r"\s+", "", value.lower())


def main() -> None:
    existing = [json.loads(line) for line in CARDS_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]
    by_id = {item["id"]: item for item in existing}

    # Remove dangling runtime provenance. Preserve reviewed facts as explicit metadata.
    for item in existing:
        item["source_files"] = [source for source in item.get("source_files", []) if not source.startswith(("outputs/", "work/", "tmp/", "logs/"))]
    for catalog_card_id in {
        "dot_matrix_ribbon_install",
        "smart_attendance_tutorial_catalog",
        "dot_matrix_tutorial_catalog",
        "wifi_bluetooth_dot_matrix_tutorial_catalog",
        "thermal_windows_tutorial_catalog",
        "bluetooth_attendance_tutorial_catalog",
    }:
        if catalog_card_id in by_id:
            by_id[catalog_card_id]["version"] = VERSION
            by_id[catalog_card_id]["package_version"] = VERSION
    normal = by_id["attendance_normal_punch_mechanical_baseline"]
    evidence = normal["evidence"]
    for key in ("analysis_directory", "contact_sheets", "screenshots"):
        evidence.pop(key, None)
    evidence["artifact_availability"] = "metadata_only"
    evidence["availability_note"] = "Original runtime frames/contact sheets are absent and excluded from the formal package; reviewed metadata is retained without fabricated replacements."

    # Align older overlapping curated cards so retrieval cannot revive a rejected branch.
    for cid in ("suyintong_reduce_contrast_dark_print", "dot_matrix_thick_table_lines_settings", "suyintong_mobile_dark_thick_contrast_lever", "suyintong_mobile_thick_smudged_contrast"):
        if cid in by_id:
            by_id[cid]["reply_template"] = by_id.get("suyintong_bold_text_contrast_lever_6", NEW_CARDS[1])["reply_template"]
            by_id[cid]["do_not_say"] = ["Density", "DPI", "灰度阈值", "图像增强", "位置2"]
    if "suyintong_mobile_dark_thick_contrast_lever" in by_id:
        by_id["suyintong_mobile_dark_thick_contrast_lever"]["reply_template"] += " 彩色 PDF 可以直接使用，彩色字体会以黑色打印。"
    for cid in ("confirmed_platform_shipping_2026_08_18", "tmall_zto_no_sf_no_next_day_promise"):
        if cid in by_id:
            by_id[cid]["reply_template"] = "天猫常规使用中通，不承诺顺丰或留言就能安排。客户愿承担差价时，转人工核实是否可以特殊付费安排，核实前不承诺。"
            by_id[cid]["auto_reply_allowed"] = False
    if "confirmed_platform_shipping_2026_08_18" in by_id:
        by_id["confirmed_platform_shipping_2026_08_18"]["reply_template"] = "京东店铺从京东仓库发货；拼多多、天猫和抖音店铺从上海工厂发货。常规情况下16:00前订单安排当天发出，但这不是绝对时效承诺。天猫常规使用中通，不承诺顺丰或留言就能安排；客户愿承担差价时，转人工核实是否可以特殊付费安排。"
    if "dot_matrix_no_print_offline_queue" in by_id:
        by_id["dot_matrix_no_print_offline_queue"]["reply_template"] = NEW_CARDS[4]["reply_template"] + " 上述检测和端口正常后仍不打印时，只有确认持续存在错误或重复驱动故障才删除错误项，并通过 services.msc 重启 Print Spooler。"
    if "dot_matrix_garbled_spool_usb_os_driver" in by_id:
        by_id["dot_matrix_garbled_spool_usb_os_driver"]["reply_template"] = NEW_CARDS[7]["reply_template"] + " 每个分支都先对照打印预览；隐藏任务分支清理 SPOOL，并按 USB、系统和驱动证据分别处理。"
    if "dot_matrix_ribbon_film_before_missing_pin" in by_id:
        by_id["dot_matrix_ribbon_film_before_missing_pin"]["reply_template"] = NEW_CARDS[12]["reply_template"]
    if "dot_matrix_top_panel_controls" in by_id:
        by_id["dot_matrix_top_panel_controls"]["reply_template"] = "电源键按一下开机；关机时先取纸，按住电源键到红灯闪烁后松开，仍不关机则断开电源供应。后进连续纸正确装好后再使用进纸/退纸和暂停/微退键；缺纸红灯表示当前未检测到纸张。"
    if "wifi_windows_ip_port" in by_id:
        by_id["wifi_windows_ip_port"]["auto_reply_allowed"] = False
        by_id["wifi_windows_ip_port"]["reply_template"] = "正常对客流程使用 Automatic → Search 自动安装无线驱动/端口。Standard TCP/IP 只是搜索失败后由人工/技术核对自检页 IP 时使用的内部异常备选，不作为正常客户模板。"
    if "family_default_package_contents_20260909" in by_id:
        cable_rule = "默认 USB 数据线长度为1.2米；自购3米线只要打印机端接头匹配且支持数据传输即可使用。"
        if cable_rule not in by_id["family_default_package_contents_20260909"]["reply_template"]:
            by_id["family_default_package_contents_20260909"]["reply_template"] += f" {cable_rule}"

    new_by_id = {item["id"]: item for item in NEW_CARDS}
    merged = [new_by_id.get(item["id"], item) for item in existing]
    known = {item["id"] for item in merged}
    merged.extend(item for item in NEW_CARDS if item["id"] not in known)
    CARDS_PATH.write_text("".join(json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n" for item in merged), encoding="utf-8")

    hf = json.loads(HF_PATH.read_text(encoding="utf-8"))
    hf["version"] = VERSION
    by_query = {normalized(item["query"]): item for item in hf["queries"]}
    for query, card_id in QUERIES.items():
        key = normalized(query)
        if key in by_query:
            by_query[key]["card_id"] = card_id
        else:
            item = {"query": query, "card_id": card_id}
            hf["queries"].append(item)
            by_query[key] = item
    HF_PATH.write_text(json.dumps(hf, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    catalog = json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    catalog["version"] = VERSION
    CATALOG_PATH.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"cards={len(merged)} queries={len(hf['queries'])} version={VERSION}")


if __name__ == "__main__":
    main()
