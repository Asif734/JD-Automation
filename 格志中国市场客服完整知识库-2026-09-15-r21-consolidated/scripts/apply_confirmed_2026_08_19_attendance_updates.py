#!/usr/bin/env python3
"""Apply user-confirmed 2026-08-19 attendance troubleshooting rules."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
SOURCE = "confirmed_attendance_troubleshooting_updates_2026_08_19_kb.md"
COMMON_SOURCES = [SOURCE, "attendance_machine_m880_after_sales_issues_kb.md", "attendance_machine_manual_customer_reply_kb.md"]


NEW_CARDS = [
    {
        "id": "attendance_card_absorbed_ejected_no_print",
        "version": "2026-08-19",
        "status": "active",
        "source_files": COMMON_SOURCES,
        "product_line": "attendance_machine",
        "models": ["M880", "M880D", "T960", "T960S", "纸卡考勤机"],
        "intent": "troubleshooting",
        "issue": "卡片吸入后自动退卡且不打印",
        "keywords": ["吸卡后退卡", "自动弹出不打印", "吸入又弹出", "有光标不打印", "15组00", "09组0000"],
        "synonyms": ["卡被吸进去又退出来", "自动退卡", "进卡但没打印"],
        "risk_level": "medium",
        "auto_reply_allowed": True,
        "reply_template": "亲，请先用原装考勤卡测试，再针对此症状把15组暂设00、09组暂设00:00（屏幕0000）后重试。09组只能在00:00–05:59之间设置，测试后按实际班次和最后打卡时间恢复。原装卡仍退卡不打印时做自检。",
        "rules": {"normal_original_card_group_15": "01", "symptom_test_group_15": "00", "temporary_group_09": "00:00", "group_09_range": "00:00-05:59", "restore_group_09_after_test": True},
        "actions": [{"type": "test_original_card"}, {"type": "temporarily_set_group_15_00"}, {"type": "temporarily_set_group_09_00_00"}, {"type": "self_test_if_still_ejected"}],
        "do_not_say": ["原装卡永久都要设15组00", "09组可以晚于05:59"],
        "escalation": "原装卡和临时设置后仍退卡不打印且自检异常时转人工。",
        "priority": 126,
    },
    {
        "id": "attendance_error_5004_printhead_stuck",
        "version": "2026-08-19",
        "status": "active",
        "source_files": COMMON_SOURCES,
        "product_line": "attendance_machine",
        "models": ["M880", "M880D", "T960", "T960S", "纸卡考勤机"],
        "intent": "troubleshooting",
        "issue": "屏幕显示5004错误代码且无法打卡",
        "diagnosis": "printhead_stuck_or_cannot_move",
        "keywords": ["5004", "5004错误", "错误代码5004", "屏幕显示5004", "打印头卡住", "打印头不移动"],
        "synonyms": ["显示5004不能打卡", "5004不是时间", "开机打印头不动"],
        "risk_level": "medium",
        "auto_reply_allowed": True,
        "reply_template": "亲，5004是错误代码，不是时间，主要表示打印头卡住或不能移动。请确认使用原装电源；建议关机取下透明上盖，再开机只观察打印头是否自动移动，通电时不要触摸内部。检查色带、纸屑或异物前请先关机拔电；仍显示5004时转人工客服。",
        "actions": [{"type": "confirm_original_power_adapter"}, {"type": "switch_off_remove_cover_then_power_on_observe_only"}, {"type": "power_off_unplug_before_clearing_obstruction"}, {"type": "handoff_if_5004_remains"}],
        "safety": ["取下透明上盖本身不强制断电", "推荐关机取盖后再开机观察", "通电时不触摸或推动打印头", "清除异物前关机拔电"],
        "do_not_say": ["5004是时间", "通电时用手推动打印头", "仍显示5004还让客户拆机"],
        "escalation": "原装电源和基础检查后仍显示5004，转人工客服。",
        "priority": 127,
    },
    {
        "id": "attendance_single_imprint_mixed_red_black",
        "version": "2026-08-19",
        "status": "active",
        "source_files": COMMON_SOURCES + ["rag_cards/attendance_video_materials.json"],
        "product_line": "attendance_machine",
        "models": ["M880", "M880D", "T960", "T960S", "纸卡考勤机"],
        "intent": "troubleshooting",
        "issue": "同一个打卡印迹红黑混色",
        "keywords": ["红黑混色", "一半红一半黑", "同一个时间两种颜色", "红黑交界", "双色带"],
        "synonyms": ["数字半红半黑", "一次打卡两种颜色"],
        "risk_level": "low",
        "auto_reply_allowed": True,
        "reply_template": "亲，每次打卡只能打印一种颜色，同一印迹红黑混色属于异常。请打开透明盖，把色带盒移到中间，检查色带是否扭曲、松动或位于红黑交界；重新安装时让色带位于打印头与不锈钢片之间，转动小轮收紧并调到单一颜色区域后测试。",
        "actions": [{"type": "move_ribbon_cartridge_to_center"}, {"type": "inspect_red_black_boundary_twist_and_slack"}, {"type": "install_between_printhead_and_stainless_plate"}, {"type": "tighten_and_select_single_color_section"}],
        "do_not_say": ["同一个印迹红黑混色是正常迟到效果"],
        "priority": 125,
    },
    {
        "id": "attendance_print_white_line_fixed_missing_band",
        "version": "2026-08-19",
        "status": "active",
        "source_files": COMMON_SOURCES,
        "product_line": "attendance_machine",
        "models": ["M880", "M880D", "T960", "T960S", "纸卡考勤机"],
        "intent": "troubleshooting",
        "issue": "打印时间中间白线或固定缺印",
        "keywords": ["打印白线", "中间没打印", "固定缺印", "未打印条带", "打印头针损坏"],
        "synonyms": ["时间中间空白", "数字中间少一段", "每次同一位置缺失"],
        "risk_level": "medium",
        "auto_reply_allowed": True,
        "reply_template": "亲，请先关机拔电，打开透明盖检查打印头区域是否有灰尘、纸屑、色带碎片或异物，不要强拆打印头。确认色带不扭曲、不松动且位于打印头与不锈钢片之间，收紧后用原装卡自检；每次完全相同位置仍缺印时，打印头针可能损坏，需要维修。",
        "actions": [{"type": "power_off_unplug"}, {"type": "clean_printhead_area_without_disassembly"}, {"type": "check_and_tighten_ribbon"}, {"type": "self_test_with_original_card"}, {"type": "repair_if_fixed_band_repeats"}],
        "do_not_say": ["固定白线一定只是色带问题", "让客户拆卸打印头"],
        "escalation": "原装卡自检每次在完全相同位置出现相同缺印条带时申请维修。",
        "priority": 125,
    },
    {
        "id": "attendance_card_not_inserted_or_auto_feed",
        "version": "2026-08-19",
        "status": "active",
        "source_files": COMMON_SOURCES,
        "product_line": "attendance_machine",
        "models": ["M880", "M880D", "T960", "T960S", "纸卡考勤机"],
        "intent": "troubleshooting",
        "issue": "卡片无法插入或机器不自动吸卡",
        "keywords": ["卡片无法插入", "不自动吸卡", "机器不吸卡", "纸张传感器", "屏幕没有光标", "09组0000"],
        "synonyms": ["卡塞不进去", "放卡不吸入", "考勤卡不进机器"],
        "risk_level": "medium",
        "auto_reply_allowed": True,
        "reply_template": "亲，请先取出卡片。手动模式按对应1–6号键选列，等光标出现后再插原装卡；确认正反面、缺口和方向。仍不吸卡时关机清洁插卡通道和纸张传感器，并把09组暂设00:00（屏幕0000）测试；09组只能在00:00–05:59之间，测试后按班次恢复。自动模式另查02–08组。",
        "actions": [{"type": "remove_card"}, {"type": "manual_mode_select_column_1_to_6_and_wait_for_cursor"}, {"type": "test_original_card"}, {"type": "power_off_clean_card_channel_and_paper_sensor"}, {"type": "temporarily_set_group_09_00_00"}, {"type": "check_groups_02_to_08_in_auto_mode"}],
        "self_test_key": "1号/+增加键（同一个按键）",
        "do_not_say": ["自动模式也必须先手动选列", "09组可以晚于05:59"],
        "escalation": "自检也不能吸卡时收集型号、屏幕照片和视频后转人工。",
        "priority": 126,
    },
]


def update_existing(card: dict) -> dict:
    card_id = card.get("id")
    if card_id == "attendance_card_recognition_15_group":
        card["version"] = "2026-08-19"
        card["source_files"] = list(dict.fromkeys([SOURCE, *card.get("source_files", [])]))
        card["reply_template"] = "亲，原装卡正常默认15组为01；如果卡片吸入后立即退卡且不打印，可针对此症状暂设15组00，并把09组暂设00:00测试。09组只能在00:00–05:59之间，测试后按实际班次恢复。"
        card["actions"] = [{"type": "branch_by_symptom", "branches": ["原装卡正常默认=01", "吸入后退卡不打印临时=00", "非原装卡测试=00", "逐渐错行=01并检查09组"]}]
        card["priority"] = 123
    elif card_id == "attendance_stepper_motor_lost_step":
        card["version"] = "2026-08-19"
        card["source_files"] = list(dict.fromkeys([SOURCE, *card.get("source_files", [])]))
        card["related_error_card_id"] = "attendance_error_5004_printhead_stuck"
        card["diagnostic_boundary"] = "5004错误代码可独立进入打印头卡住排查；无需先出现咔咔声。"
    elif card_id == "attendance_black_red_print_policy":
        card["version"] = "2026-08-19"
        card["source_files"] = list(dict.fromkeys([SOURCE, *card.get("source_files", [])]))
        card["mixed_color_boundary"] = "同一个印迹只能是一种颜色；红黑混色属于色带异常。"
    return card


def main() -> None:
    cards = [json.loads(line) for line in CARDS_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]
    cards = [update_existing(card) for card in cards]
    by_id = {card["id"]: card for card in cards}
    for card in NEW_CARDS:
        by_id[card["id"]] = card
    ordered_ids = [card["id"] for card in cards]
    ordered_ids.extend(card["id"] for card in NEW_CARDS if card["id"] not in ordered_ids)
    CARDS_PATH.write_text("\n".join(json.dumps(by_id[card_id], ensure_ascii=False, separators=(",", ":")) for card_id in ordered_ids) + "\n", encoding="utf-8")
    print(f"active_cards={sum(card.get('status') == 'active' for card in by_id.values())}")
    print("confirmed_2026_08_19_attendance_updates_applied")


if __name__ == "__main__":
    main()
