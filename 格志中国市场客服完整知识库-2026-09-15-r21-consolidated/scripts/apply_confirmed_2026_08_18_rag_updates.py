#!/usr/bin/env python3
"""Apply the user-confirmed 2026-08-18 rules to machine-readable RAG cards."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
CARDS_PATH = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
VIDEO_MATERIALS_PATH = ROOT / "rag_cards/attendance_video_materials.json"
SOURCE = "confirmed_customer_service_updates_2026_08_18_kb.md"


def replace_card(card: dict) -> dict:
    card_id = card.get("id")
    if card_id == "attendance_manual_shift_setup":
        return {
            "id": card_id,
            "version": "2026-08-18",
            "status": "active",
            "source_files": [SOURCE, "attendance_machine_manual_customer_reply_kb.md", "attendance_shift_overlap_calculation_kb.md"],
            "product_line": "attendance_machine",
            "models": ["all_attendance_machines"],
            "intent": "setup",
            "issue": "考勤机班次/上下班时间设置",
            "keywords": ["考勤机", "班次", "班次怎么设置", "两个班次怎么设置", "02组", "03组", "04组", "05组", "06组", "07组", "08组", "24小时制", "30分钟", "最多3班", "6个时间点"],
            "synonyms": ["考勤时间怎么设置", "上下班时间怎么设置", "相邻班次间隔多久"],
            "risk_level": "medium",
            "auto_reply_allowed": True,
            "model_confirmation_required": False,
            "uniform_rule": "多个团队真实班次重叠时先按交集计算共享班次；最终输入机器的最多3个自动班次必须不重叠、不重复且相邻班次至少间隔30分钟。",
            "required_slots": ["每个班次的上班和下班时间", "是否跨天"],
            "reply_template": "亲，如果多个团队的真实班次重叠，我先按交集计算可共享班次：开始取最晚上班时间，结束取最早下班时间。机器不能直接输入重叠自动班次；最终设置最多3班、6个时间点，必须不重叠、不重复且相邻至少间隔30分钟。",
            "actions": [
                {"type": "collect_shift_times"},
                {"type": "calculate_shared_shift_intersection_if_team_schedules_overlap"},
                {"type": "validate_final_automatic_shifts_nonoverlap_and_30_minute_gap"},
                {"type": "answer_group_mapping_if_valid"},
            ],
            "valid_example": ["08:00-12:00", "12:30-17:30", "18:00-20:30"],
            "do_not_say": ["把重叠的真实班次直接输入机器", "共同班次等于修改员工真实排班", "最终自动班次间隔不足30分钟也能保存"],
            "escalation": "无法形成有效共同班次，或最终自动班次仍重叠、重复、间隔不足30分钟或超过3班时，建议手动模式或转人工。",
            "priority": 120,
        }
    if card_id == "attendance_shift_overlap_intersection":
        return {
            "id": card_id,
            "version": "2026-08-18",
            "status": "active",
            "source_files": [SOURCE, "attendance_shift_overlap_calculation_kb.md"],
            "product_line": "attendance_machine",
            "models": ["all_attendance_machines"],
            "intent": "shift_calculation_and_validation",
            "issue": "重叠团队共享班次交集计算与最终自动班次验证",
            "keywords": ["班次重叠", "重叠班次怎么设置", "时间重复", "间隔30分钟", "间隔不足30分钟", "交集", "共同班次", "自动打卡冲突", "A班", "B班", "08:00", "09:00", "12:15"],
            "risk_level": "medium",
            "auto_reply_allowed": True,
            "intersection_sharing_rule": "active",
            "calculation": {
                "shared_start": "max(各重叠班次上班时间)",
                "shared_end": "min(各重叠班次下班时间)",
                "shared_shift": "重叠开始时间-重叠结束时间",
                "exists_when": "shared_start < shared_end",
            },
            "validation": {
                "maximum_shifts": 3,
                "maximum_punch_points": 6,
                "employee_schedule_overlap_allowed": True,
                "final_machine_shift_overlap_allowed": False,
                "duplicate_points_allowed": False,
                "minimum_adjacent_gap_minutes": 30,
                "time_format": "24-hour",
            },
            "reply_template": "亲，多个团队真实班次重叠时，先取最晚上班时间和最早下班时间作为共享班次。例如A班08:00–17:00、B班09:00–18:00，共享班次为09:00–17:00。机器不能直接输入重叠自动班次；共享班次计算后，最终机器班次仍须互不重叠、相邻至少间隔30分钟。比如12:00下班后12:15上班只间隔15分钟，不能作为自动配置；无法满足时建议手动打卡。",
            "actions": [{"type": "calculate_shared_shift_intersection"}, {"type": "inform_customer_machine_cannot_enter_overlapping_shifts"}, {"type": "validate_final_automatic_shifts"}, {"type": "offer_manual_mode_if_invalid"}],
            "do_not_say": ["把重叠班次直接输入机器", "共享班次取代真实排班", "忽略最终班次30分钟间隔"],
            "priority": 125,
        }
    if card_id == "attendance_shift_employee_group_first":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "attendance_shift_overlap_calculation_kb.md", "attendance_machine_manual_customer_reply_kb.md"],
            core_principle="先收集每组员工真实班次；真实班次重叠时按交集计算共享班次，再验证最终机器班次不重叠、不重复且相邻至少间隔30分钟。",
            workflow=["识别员工组", "整理真实班次", "计算重叠共同开始和共同结束", "说明机器不能直接输入重叠班次", "检查最终最多3班和6个时间点", "检查最终不重叠不重复且至少间隔30分钟", "有效后设置02–08组"],
            merge_rule="存在有效交集时可用共同班次共享自动栏位；共同班次不取代真实排班。最终配置不合规则手动打卡或转人工。",
            reply_template="请按员工组列出真实上下班时间。若时间重叠，我先计算最晚上班到最早下班的共享班次，再检查最终机器班次是否互不重叠并至少间隔30分钟。",
            actions=[{"type": "identify_employee_groups"}, {"type": "calculate_intersection_if_overlapping"}, {"type": "validate_final_machine_shifts"}, {"type": "answer_group_mapping_if_valid"}],
            priority=119,
        )
        return card
    if card_id == "attendance_card_recognition_15_group":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "attendance_machine_m880_after_sales_issues_kb.md"],
            reply_template="亲，原装卡通常把15组设为01，非原装卡或一般位置错误可以暂时设00测试；如果是打印间隔过大或日期行逐渐错位，请确认15组为01，再检查09组。",
            actions=[{"type": "branch_by_symptom", "branches": ["原装卡正反识别=01", "非原装卡或一般位置测试=00", "逐渐错行或间隔过大=01并检查09组"]}],
            priority=116,
        )
        return card
    if card_id == "attendance_manual_print_position_card_detect":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "attendance_machine_m880_after_sales_issues_kb.md", "attendance_machine_manual_customer_reply_kb.md"],
            auto_reply_allowed=True,
            required_slots=[],
            keywords=["考勤机", "打印位置", "逐渐错行", "打印逐渐错行", "打印间隔过大", "09组", "15组", "05:59", "怎么自检", "1号/+增加键"],
            synonyms=["28日打到1日", "10日打到2日", "一直打在最上面蓝色行", "打印位置越来越偏"],
            reply_template="亲，请依次检查原装考勤卡、00组日期、01组时间、03–08组班次、15组和09组。09组最晚05:59；若最后打卡加30分钟超过05:59，就设05:59并要求员工此前打卡。最后打卡在05:59或之后时改用手动或转人工。自检时断电按住1号/+增加键重新插电。",
            actions=[{"type": "run_confirmed_print_position_checklist"}],
            priority=122,
        )
        return card
    if card_id in {"attendance_self_test_video", "attendance_manual_alarm_ribbon_selftest"}:
        card["version"] = "2026-08-18"
        card["source_files"] = list(dict.fromkeys([SOURCE, *card.get("source_files", [])]))
        card["reply_template"] = "亲，请先拔掉电源，按住“1号/+增加键”（同一个按键）不放并重新插上电源，再插入考勤卡打印自检页。自检正常就检查卡片和设置；自检也偏位时清理插卡通道和感应区域，仍异常再转售后。"
        card["priority"] = max(card.get("priority", 0), 117)
        return card
    if card_id == "attendance_cross_day_09_group":
        card.update(
            version="2026-08-18-v2",
            source_files=[SOURCE, "attendance_machine_m880_after_sales_issues_kb.md", "attendance_machine_manual_customer_reply_kb.md"],
            keywords=["09组", "换行", "跨天", "05:59", "最后打卡05:45", "30分钟", "日期打错行"],
            required_slots=["最后一次打卡时间"],
            rule={"latest_group_09": "05:59", "preferred_gap_minutes": 30, "gap_exception": "若延后30分钟超过05:59则设05:59", "punch_deadline": "员工必须在05:59前完成", "at_or_after_05_59": "手动打卡或转人工"},
            reply_template="亲，09组最晚设05:59。正常建议放在最后打卡后至少30分钟；如果加30分钟会超过05:59，就设05:59，员工必须在05:59前打卡。最后打卡在05:59或之后时，自动换行不能可靠设置，建议手动打卡或转人工。",
            actions=[{"type": "calculate_preferred_group_09"}, {"type": "cap_at_05_59"}, {"type": "manual_or_handoff_if_last_punch_at_or_after_05_59"}],
            priority=124,
        )
        return card
    if card_id == "attendance_card_paper_quantity":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "qianniu_customer_service_training_kb.md"],
            models=["M880", "M880D", "T960S", "T960D", "M880A", "M880B", "M880BT", "M880DA", "M880D-A", "880D-A", "M880DT", "M880T"],
            reply_template="亲，这些型号的已确认标准包装包含50张考勤卡、1条已安装色带、1个电源适配器和2颗壁挂螺丝。卡架不属于标准包装，套餐额外赠送以订单SKU为准。",
            priority=118,
        )
        return card
    if card_id == "attendance_wall_mount_install":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "attendance_machine_m880_after_sales_issues_kb.md"],
            reply_template="亲，考勤机可以放在稳定桌面，也可以挂墙。标准包装含2颗壁挂螺丝；安装时请为电源线和插卡位置留出空间。",
            priority=116,
        )
        return card
    if card_id == "attendance_black_red_print_policy":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, *[x for x in card.get("source_files", []) if x != SOURCE]],
            reply_template="亲，固定自动班次下正常打卡打印黑色，迟到或早退可以按设定规则打印红色。02组优先用于设置班次数量，不能把01/00直接当作所有机型通用的颜色开关。",
            priority=118,
        )
        return card
    if card_id == "attendance_shift_collect_times_before_config":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "attendance_machine_manual_customer_reply_kb.md"],
            reply_template="亲，请按员工组发真实上下班时间。若多个团队重叠，我先按最晚上班到最早下班计算共享班次；最终输入机器的自动班次仍须不重叠、不重复且相邻至少间隔30分钟。",
            actions=[{"type": "collect_info", "fields": ["各团队真实班次", "是否跨天"]}, {"type": "calculate_shared_shift_intersection_if_needed"}, {"type": "validate_final_automatic_shifts"}, {"type": "answer_group_mapping_after_validation"}],
            priority=118,
        )
        return card
    if card_id == "global_single_decisive_clarification_policy":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "customer_service_global_clarification_policy_kb.md", "customer_video_analysis_sop_kb.md"],
            platforms=["QianNiu", "Tmall", "JD", "Pinduoduo", "Douyin"],
            block_branch_guidance_before_confirmation=False,
            video_evidence_exception=True,
            model_reask_policy="视频可识别型号或方法通用时不重复询问；只有步骤因型号/平台而异且无法识别时才询问。",
            reply_template="视频画面和音频足以确定问题时，直接说明观察结果并给出分步方案；信息不足时，先说明已观察到的情况，每轮只问一个必要问题。",
            actions=[{"type": "analyze_video_and_audio"}, {"type": "answer_directly_if_evidence_sufficient"}, {"type": "ask_one_question_only_if_needed"}],
            priority=123,
        )
        card.pop("blocked_before_confirmation", None)
        card.pop("after_confirmation", None)
        return card
    if card_id == "attendance_m880_m880d_battery_visual_identification":
        card.update(
            version="2026-08-18",
            source_files=[SOURCE, "attendance_machine_m880_after_sales_issues_kb.md"],
            models=["M880", "M880D", "T960D", "M880DA", "M880D-A", "880D-A", "M880DT"],
            issue="已确认停电打卡型号与内置备用电池",
            requires_model_confirmation_before_guidance=False,
            model_facts={"M880D": "内置备用电池", "T960D": "内置备用电池", "M880DA/M880D-A/880D-A": "同一型号别名，内置备用电池", "M880DT": "内置备用电池", "M880": "无内置备用电池"},
            reply_template="亲，已确认的停电打卡型号是M880D、T960D、M880DA/M880D-A/880D-A和M880DT，备用电池已安装在机器内部，不是包装里的散装配件。M880普通款没有内置备用电池。",
            actions=[{"type": "answer_confirmed_battery_models"}, {"type": "ask_model_only_if_not_visible_and_required"}],
            priority=124,
        )
        return card
    if card_id == "attendance_printed_date_row_mismatch":
        card["version"] = "2026-08-18"
        card["source_files"] = list(dict.fromkeys([SOURCE, *card.get("source_files", [])]))
        card["requires_model_confirmation_before_guidance"] = False
        card["model_policy"] = "先给更换原装THT卡的通用步骤；只有客户选择第三方卡微调、视频无法识别型号且不同型号步骤不同时，才询问型号。"
        card["priority"] = 123
        return card
    if card_id == "attendance_stepper_motor_lost_step":
        card["version"] = "2026-08-18"
        card["source_files"] = list(dict.fromkeys([SOURCE, *card.get("source_files", [])]))
        card["requires_model_confirmation_before_guidance"] = False
        card["model_policy"] = "已确认的连续咔咔声或啸叫声足以进入通用安全排查，不重复询问型号；发送机型专属素材前若视频无法识别再询问。"
        card["do_not_say"] = [item for item in card.get("do_not_say", []) if item != "未确认型号就发送操作教程"]
        card["priority"] = 124
        return card
    if card_id == "attendance_normal_punch_mechanical_baseline":
        card["version"] = "2026-08-18"
        card["source_files"] = list(dict.fromkeys([SOURCE, *card.get("source_files", [])]))
        card["limitations"] = ["视频未展示机器外壳型号标签", "只证明本次第10日打卡过程与日期行定位正常", "内部诊断基准不用于编造视频中未出现的信息"]
        card["reply_template"] = "本条为内部正常动作参考：正常过程应依次完成卡纸吸入、打印头移动、打印和出纸，且打印日期应与物理日期行一致。客户视频证据足够时直接给通用排查；只有机型或平台会改变步骤且无法识别时才询问。"
        card["actions"] = [{"type": "compare_customer_video_with_normal_sequence"}, {"type": "keep_visible_and_audible_facts_separate_from_inference"}, {"type": "ask_model_or_platform_only_if_required_and_not_identifiable"}]
        card["priority"] = 121
        return card
    if card_id == "global_grozziie_china_customer_service_policy":
        card["version"] = "2026-08-18"
        card["platforms"] = ["Tmall", "JD", "Pinduoduo", "Douyin"]
        card["source_files"] = [SOURCE, "grozziie_china_customer_service_policy_kb.md", "customer_service_global_clarification_policy_kb.md"]
        card["priority"] = 125
        return card
    return card


NEW_CARDS = [
    {
        "id": "confirmed_platform_shipping_2026_08_18",
        "version": "2026-08-18",
        "status": "active",
        "source_files": [SOURCE, "qianniu_customer_service_training_kb.md"],
        "product_line": "order_shipping",
        "models": ["all"],
        "platforms": ["JD", "Tmall", "Pinduoduo", "Douyin"],
        "intent": "shipping_policy",
        "issue": "各平台发货仓与16点批次",
        "keywords": ["发货", "什么时候发", "从哪里发货", "京东发货", "抖音发货", "京东仓", "上海工厂", "16点", "16:00", "当天发货", "下一批次"],
        "synonyms": ["京东从哪里发货", "抖音从哪里发货", "16点后什么时候发", "四点后什么时候发"],
        "risk_level": "medium",
        "auto_reply_allowed": True,
        "reply_template": "京东店铺商品从京东仓库发货，具体时间以订单/商品页面为准。拼多多、天猫和抖音统一从上海工厂发货；常规情况下16:00前安排当天发出，16:00后通常顺延至下一批次，但不是绝对时效承诺。",
        "do_not_say": ["16点前一定当天发出", "保证当天揽收"],
        "priority": 125,
    },
    {
        "id": "attendance_confirmed_standard_package_2026_08_18",
        "version": "2026-08-18",
        "status": "active",
        "source_files": [SOURCE],
        "product_line": "attendance_machine",
        "models": ["M880", "M880D", "T960S", "T960D", "M880A", "M880B", "M880BT", "M880DA", "M880D-A", "880D-A", "M880DT", "M880T"],
        "intent": "package_contents",
        "issue": "已确认考勤机标准包装清单",
        "keywords": ["包装清单", "50张考勤卡", "色带已安装", "壁挂螺丝2颗", "内置备用电池", "卡架"],
        "risk_level": "low",
        "auto_reply_allowed": True,
        "standard_package": {"machine": 1, "power_adapter": 1, "attendance_cards": 50, "installed_ribbon": 1, "wall_screws": 2},
        "battery_models": ["M880D", "T960D", "M880DA/M880D-A/880D-A", "M880DT"],
        "battery_location": "installed_inside_machine_not_loose",
        "card_rack_standard": False,
        "reply_template": "标准包装含考勤机1台、电源适配器1个、考勤卡50张、机器内已安装色带1条和壁挂螺丝2颗。M880D、T960D、M880DA/M880D-A/880D-A、M880DT另有机器内部已安装的备用电池。卡架不属于标准包装。",
        "priority": 125,
    },
    {
        "id": "customer_video_audio_direct_analysis_2026_08_18",
        "version": "2026-08-18",
        "status": "active",
        "source_files": [SOURCE, "customer_video_analysis_sop_kb.md"],
        "product_line": "all",
        "models": ["all"],
        "platforms": ["Tmall", "JD", "Pinduoduo", "Douyin"],
        "intent": "video_audio_diagnosis",
        "issue": "自动分析客户视频画面和音频",
        "keywords": ["视频分析", "音频分析", "异常声音", "画面报错", "不要重复描述", "一个澄清问题"],
        "risk_level": "medium",
        "auto_reply_allowed": True,
        "rules": ["同时分析画面和音频", "证据充分时直接给分步方案", "型号可见或方法通用时不重复询问", "不清楚时只问一个必要问题", "不得编造", "安全风险先关机断电"],
        "reply_template": "先说明视频中实际看到和听到的情况；证据足够时直接给分步方案。只有信息不清楚时才询问一个必要问题。发现安全风险先让客户关机并断开电源。",
        "priority": 126,
    },
]


def update_cards() -> None:
    cards = [json.loads(line) for line in CARDS_PATH.read_text(encoding="utf-8").splitlines() if line.strip()]
    new_cards_by_id = {card["id"]: card for card in NEW_CARDS}
    cards = [new_cards_by_id.get(card.get("id"), replace_card(card)) for card in cards]
    existing_ids = {card["id"] for card in cards}
    cards.extend(card for card in NEW_CARDS if card["id"] not in existing_ids)
    CARDS_PATH.write_text("\n".join(json.dumps(card, ensure_ascii=False, separators=(",", ":")) for card in cards) + "\n", encoding="utf-8")


def replace_video_string(value: str) -> str:
    replacements = {
        "说明书明确11V-1800mAh电池仅支持M880D；M880D-A等带电池衍生型号需以实际配置确认。": "已确认M880D、T960D、M880DA/M880D-A/880D-A、M880DT带机器内部已安装的备用电池。",
        "说明书只注明M880D支持电池，没有提供内部开关操作图。": "已确认M880D、T960D、M880DA/M880D-A/880D-A、M880DT带内置备用电池；内部操作仍须以对应机型资料为准。",
    }
    return replacements.get(value, value)


def walk_video_data(value):
    if isinstance(value, dict):
        return {key: walk_video_data(item) for key, item in value.items()}
    if isinstance(value, list):
        return [walk_video_data(item) for item in value]
    if isinstance(value, str):
        return replace_video_string(value)
    return value


def update_video_materials() -> None:
    data = json.loads(VIDEO_MATERIALS_PATH.read_text(encoding="utf-8"))
    data = walk_video_data(data)
    VIDEO_MATERIALS_PATH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    update_cards()
    update_video_materials()
    print("confirmed_2026_08_18_rag_updates_applied")
