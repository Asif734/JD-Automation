"""Platform-safe retrieval for ordinary attendance-machine video cards."""

from __future__ import annotations

import json
import re
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parent
MANIFEST_PATH = ROOT / "rag_cards/attendance_video_materials.json"
PLATFORM_ALIASES = {
    "jd": "JD",
    "京东": "JD",
    "tmall": "Tmall",
    "天猫": "Tmall",
    "qianniu": "Tmall",
    "千牛": "Tmall",
    "pinduoduo": "Pinduoduo",
    "拼多多": "Pinduoduo",
    "pdd": "Pinduoduo",
}
ALLOWED_HOSTS = {
    "JD": {"vod.300hu.com", "jvod.300hu.com"},
    "Tmall": {"cloud.video.taobao.com"},
    "Pinduoduo": {"video5.pddpic.com"},
}
HIGH_RISK_TERMS = {
    "手机号", "身份证", "隐私", "客户信息", "订单", "退款", "投诉", "赔偿",
    "账号异常", "盗号", "验证码", "银行卡", "密码发我", "查询密码",
}


class VideoMaterialError(RuntimeError):
    pass


class PlatformRequiredError(VideoMaterialError):
    pass


class PlatformLinkError(VideoMaterialError):
    pass


def normalize_text(value: str) -> str:
    text = re.sub(r"\s+", "", value.lower())
    for digit, chinese in (("1", "一"), ("2", "两"), ("3", "三")):
        text = text.replace(f"{digit}个班次", f"{chinese}个班次")
        text = text.replace(f"{digit}班", f"{chinese}班")
    return text


def normalize_platform(platform: str | None) -> str:
    if not platform:
        raise PlatformRequiredError("platform is required before selecting a video link")
    normalized = PLATFORM_ALIASES.get(normalize_text(platform))
    if not normalized:
        raise PlatformRequiredError(f"unsupported platform: {platform}")
    return normalized


def load_manifest() -> dict:
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def _score_terms(message: str, terms: list[str]) -> tuple[int, int]:
    compact = normalize_text(message)
    matched = [normalize_text(term) for term in terms if normalize_text(term) in compact]
    fuzzy_hits = 0
    if not matched:
        for raw_term in terms:
            term = normalize_text(raw_term)
            bigrams = {term[index:index + 2] for index in range(max(0, len(term) - 1))}
            hits = sum(1 for gram in bigrams if gram in compact)
            if len(bigrams) >= 2 and hits >= 2 and hits / len(bigrams) >= 0.6:
                matched.append(term)
                fuzzy_hits = max(fuzzy_hits, hits)
    if not matched:
        score = 0
    elif fuzzy_hits:
        score = 15 + fuzzy_hits * 3
    else:
        score = 100 + sum(20 + len(term) * 3 for term in matched)
    return score, max((len(term) for term in matched), default=0)


def _score_segment(message: str, content: dict, segment: dict) -> tuple[int, int]:
    terms = [*segment.get("triggers", []), *segment.get("applicable_questions", [])]
    for node in _operation_nodes_for_segment(content, segment):
        terms.extend(node.get("triggers", []))
        terms.extend(node.get("applicable_questions", []))
    score, longest = _score_terms(message, terms)
    title = normalize_text(content.get("title", ""))
    compact = normalize_text(message)
    if title and title in compact:
        score += 35
    return score, longest


def _operation_nodes_for_segment(content: dict, segment: dict) -> list[dict]:
    nodes = segment.get("operation_nodes") or []
    if nodes:
        return nodes
    content_nodes = content.get("operation_nodes") or []
    allowed_ids = set(segment.get("operation_node_ids") or [])
    if not allowed_ids:
        return []
    return [node for node in content_nodes if node.get("node_id") in allowed_ids]


def select_operation_nodes(content: dict, segment: dict, message: str) -> list[dict]:
    nodes = _operation_nodes_for_segment(content, segment)
    if not nodes:
        return []
    by_id = {node["node_id"]: node for node in nodes}
    compact = normalize_text(message)

    shift_field_nodes = {
        "第一班开始": "set_first_shift_start",
        "第一班上班": "set_first_shift_start",
        "第一班结束": "set_first_shift_end",
        "第一班下班": "set_first_shift_end",
        "第二班开始": "set_second_shift_start",
        "第二班上班": "set_second_shift_start",
        "第二班结束": "set_second_shift_end",
        "第二班下班": "set_second_shift_end",
        "第三班开始": "set_third_shift_start",
        "第三班上班": "set_third_shift_start",
        "第三班结束": "set_third_shift_end_and_save",
        "第三班下班": "set_third_shift_end_and_save",
    }
    for phrase, node_id in shift_field_nodes.items():
        if phrase in compact and node_id in by_id:
            return [by_id[node_id]]
    if any(term in compact for term in ["迟到红色", "迟到打卡", "迟到为什么红"]):
        if "demonstrate_late_punch" in by_id:
            return [by_id["demonstrate_late_punch"]]
    if any(term in compact for term in ["早退红色", "早退打卡", "早退为什么红"]):
        if "demonstrate_early_leave" in by_id:
            return [by_id["demonstrate_early_leave"]]
    generic_shift_pairs = {
        "one_shift": ("set_first_shift_start", "set_first_shift_end"),
        "two_shifts": ("set_second_shift_start", "set_second_shift_end"),
        "three_shifts": ("set_third_shift_start", "set_third_shift_end_and_save"),
    }
    generic_pair = generic_shift_pairs.get(segment.get("segment_id"))
    if generic_pair and any(term in compact for term in ["怎么设置", "如何设置", "怎么调", "设置班次"]):
        if all(node_id in by_id for node_id in generic_pair):
            return [by_id[node_id] for node_id in generic_pair]

    reset_focused_nodes = {
        "enter_reset_mode": ("hold_settings_until_hh", "hold_next_until_music"),
        "enter_default_after_reset": (
            "enter_default_password_after_reset",
            "confirm_default_and_enter_f1",
        ),
        "set_and_confirm_new_password": (
            "enter_new_password_in_f1",
            "repeat_new_password_in_f2",
        ),
    }
    focused_reset_ids = reset_focused_nodes.get(segment.get("segment_id"))
    if focused_reset_ids and all(node_id in by_id for node_id in focused_reset_ids):
        return [by_id[node_id] for node_id in focused_reset_ids]

    remaining_focused_nodes = {
        "start_self_test": ("test_disconnect_power", "test_hold_plus"),
        "power_on_self_test": ("test_reconnect_while_holding", "test_screen_90"),
        "insert_and_print_test": ("test_insert_card", "test_auto_print_result"),
        "enter_ring_group": ("ring_hold_settings_ff", "ring_reach_group_14"),
        "adjust_ring_seconds": ("ring_identify_seconds", "ring_adjust_00_59"),
        "enter_password_change": ("password_hold_to_hh", "password_enter_current"),
        "set_new_password_f1_f2": ("password_enter_new_f1", "password_repeat_f2"),
        "enable_manual_punch": ("manual_hold_settings_ff", "manual_set_group_02_zero"),
        "manual_first_shift": ("manual_group_03_start", "manual_group_04_end"),
        "manual_second_shift": ("manual_group_05_start", "manual_group_06_end"),
        "manual_third_shift": ("manual_group_07_start", "manual_group_08_end"),
        "enter_print_position_group": ("hold_settings_to_ff", "confirm_and_reach_group_13"),
        "third_party_card_adjustment": ("keep_default_for_company_card", "adjust_for_third_party_card"),
        "raise_print_position": ("increase_moves_print_up",),
        "lower_print_position": ("decrease_moves_print_down",),
    }
    focused_remaining_ids = remaining_focused_nodes.get(segment.get("segment_id"))
    if focused_remaining_ids and all(node_id in by_id for node_id in focused_remaining_ids):
        return [by_id[node_id] for node_id in focused_remaining_ids]

    if "identify_time_fields" in by_id:
        if "01组" in compact and any(term in compact for term in ["进入", "怎么到", "怎样到", "转到"]):
            return [by_id["confirm_open_group_01"]]
        hour_focus = any(term in compact for term in ["小时怎么调", "修改小时", "调整小时", "小时不对"])
        if hour_focus:
            return [by_id["move_between_time_digits"]]
        generic_time = (
            "时间" in compact
            and any(term in compact for term in ["怎么调整", "怎么调", "如何调整", "修改时间", "时间不准"])
            and not any(term in compact for term in ["小时", "分钟", "保存", "确认", "密码", "01组", "设置键", "进入"])
        )
        if generic_time:
            return [by_id["enter_settings"], by_id["identify_time_fields"]]

    day_focus = any(term in compact for term in ["日期中的日", "日字段", "日怎么改", "几号怎么改", "号数"])
    if day_focus:
        return [by_id["move_to_month_or_day"], by_id["adjust_month_or_day_value"]]

    generic_date = (
        "日期" in compact
        and any(term in compact for term in ["怎么调整", "怎么调", "如何调整", "修改日期", "日期不对"])
        and not any(term in compact for term in ["年份", "月份", "保存", "确认", "密码", "00组", "设置键"])
    )
    if generic_date:
        return [by_id["enter_settings"], by_id["identify_date_fields"]]

    candidates: list[tuple[int, int, int, dict]] = []
    for index, node in enumerate(nodes):
        score, longest = _score_terms(
            message,
            [*node.get("triggers", []), *node.get("applicable_questions", [])],
        )
        if score:
            candidates.append((score, longest, -index, node))
    if not candidates:
        return []
    candidates.sort(key=lambda item: (item[0], item[1], item[2]), reverse=True)
    return [candidates[0][3]]


def operation_time_cue(segment: dict, selected_nodes: list[dict]) -> str | None:
    if not selected_nodes:
        return None
    if [node["node_id"] for node in selected_nodes] in (
        ["enter_settings", "identify_date_fields"],
        ["enter_settings", "identify_time_fields"],
    ):
        return segment.get("full_operation_range")
    start = selected_nodes[0]["timestamp_label"].split("–", 1)[0]
    end = selected_nodes[-1]["timestamp_label"].split("–", 1)[1]
    return f"{start}–{end}"


def _video_url(content: dict, segment: dict, platform: str) -> str:
    value = content["platform_urls"].get(platform)
    if isinstance(value, dict):
        key = segment.get("platform_link_key")
        value = value.get(key)
    if not isinstance(value, str) or not value.strip():
        raise PlatformLinkError(
            f"missing {platform} link for {content['content_id']}/{segment['segment_id']}"
        )
    host = (urlparse(value).hostname or "").lower()
    if host not in ALLOWED_HOSTS[platform]:
        raise PlatformLinkError(f"cross-platform or unexpected host for {platform}: {host}")
    return value


def _unconfirmed_supported_models(message: str, selected_nodes: list[dict]) -> list[str]:
    required_models = sorted({
        model
        for node in selected_nodes
        if node.get("requires_model_confirmation")
        for model in node.get("supported_models", [])
    })
    if not required_models:
        return []
    compact = normalize_text(message)
    if any(normalize_text(model) in compact for model in required_models):
        return []
    if any(term in compact for term in ["带电池版本", "带电池款", "带备用电池版本"]):
        return []
    return required_models


def _clarification_card(platform: str, conflict_id: str, reply: str) -> dict:
    return {
        "type": "clarification",
        "content_id": conflict_id,
        "segment_id": conflict_id,
        "title": "考勤机设置条件确认",
        "platform": platform,
        "video_url": None,
        "reply": reply,
        "screenshots": [],
        "selected_nodes": [],
        "time_cue": None,
        "score": 999,
        "risk_level": "workflow_conflict_confirmation_required",
        "auto_reply_allowed": True,
        "needs_clarification": True,
        "confidence": "high",
        "actions": [],
        "sources": ["attendance_video_materials.json", "考勤机说明书.pdf"],
        "matches": [{"id": conflict_id, "type": "clarification", "score": 999}],
    }


def _text_answer_card(platform: str, answer_id: str, reply: str) -> dict:
    return {
        "type": "text_answer",
        "content_id": answer_id,
        "segment_id": answer_id,
        "title": "考勤机安全说明",
        "platform": platform,
        "video_url": None,
        "reply": reply,
        "screenshots": [],
        "selected_nodes": [],
        "time_cue": None,
        "score": 999,
        "risk_level": "low",
        "auto_reply_allowed": True,
        "needs_clarification": False,
        "confidence": "high",
        "actions": [],
        "sources": ["attendance_video_materials.json", "考勤机说明书.pdf"],
        "matches": [{"id": answer_id, "type": "text_answer", "score": 999}],
    }


def match_video_material(message: str, platform: str | None) -> dict | None:
    """Return at most one material card, with no cross-platform fallback."""
    selected_platform = normalize_platform(platform)
    compact = normalize_text(message)
    if any(term in compact for term in HIGH_RISK_TERMS):
        return None
    forgotten_password_focus = any(term in compact for term in [
        "忘记密码", "密码忘了", "忘了密码", "不记得密码", "不知道当前密码",
    ])
    changed_password_default_question = (
        "0000" in compact
        and any(term in compact for term in ["修改过密码", "改过密码", "更改过密码", "换过密码"])
    )
    if changed_password_default_question:
        return _text_answer_card(
            selected_platform,
            "changed_password_requires_current_password",
            "亲，如果密码已经修改过，进入设置或再次修改密码时必须输入当前密码，不能继续使用默认的 0000；0000 只适用于仍未修改过密码的机器。",
        )
    group_02_focus = "02组" in compact or "第02组" in compact
    color_change_request = (
        any(term in compact for term in ["双色", "黑红", "黑色", "红色"])
        and any(term in compact for term in [
            "开启", "启用", "关闭", "设置", "改成", "调成", "调整颜色",
            "只打印", "只想打印", "只要黑色", "全部黑色", "不要红色",
        ])
    )
    if color_change_request:
        return _clarification_card(
            selected_platform,
            "group_02_color_change_requires_context",
            "亲，第 02 组同时关联班次数量、手动打卡和打印颜色。为避免改值后影响现有班次，请先提供机器型号、当前第 02 组数值、需要保留的班次数，以及您是想修改班次还是打印颜色；确认前先不发送改值视频。",
        )
    multi_shift_color_conflict = (
        any(term in compact for term in ["双色", "红色", "黑红"])
        and any(term in compact for term in ["两个班次", "两班", "第二班", "三个班次", "三班", "第三班"])
    )
    if multi_shift_color_conflict:
        return _clarification_card(
            selected_platform,
            "group_02_overloaded_meaning",
            "亲，第 02 组同时关联班次数量和打印模式：两班/三班时不能直接照双色教程改成 01，否则可能把班次数改成一班。请先确认机器型号、当前第 02 组数值和需要保留的班次数；未确认前先不发送改值视频，必要时转人工核对。",
        )
    group_02_value_01_focus = group_02_focus and (
        re.search(r"(?:设为?|调(?:成|到)?|等于|是)0?1", compact)
        or re.search(r"0?1(?:是什么|什么意思|代表什么|的?含义)", compact)
    )
    if group_02_value_01_focus:
        return _clarification_card(
            selected_platform,
            "group_02_value_01_ambiguous",
            "亲，第 02 组的 01 在现有教程中同时用于“一班自动打卡”和“黑红双色”说明。请先确认您是在设置班次数量，还是只想调整打印颜色；未确认前先不要改值。",
        )
    card_layout_focus = any(term in compact for term in [
        "纸卡", "考勤卡", "打卡栏", "哪一列", "哪两列", "栏位", "overtime",
    ])
    manual_punch_focus = "手动打卡" in compact
    password_change_focus = not forgotten_password_focus and (
        any(term in compact for term in ["修改密码", "更改密码", "改密码"])
        or ("密码" in compact and any(term in compact for term in ["修改", "更改", "改成", "换成"]))
    )
    forced_content_id = None
    forced_segment_id = None
    if forgotten_password_focus:
        forced_content_id, forced_segment_id = "attendance_reset_password", "enter_reset_mode"
    elif group_02_focus and re.search(r"(?:设为?|调(?:成|到)?|等于|是)00", compact):
        forced_content_id, forced_segment_id = "attendance_manual_punch", "enable_manual_punch"
    elif group_02_focus and re.search(r"(?:设为?|调(?:成|到)?|等于|是)0?2", compact):
        forced_content_id, forced_segment_id = "attendance_set_shifts", "two_shifts"
    elif group_02_focus and re.search(r"(?:设为?|调(?:成|到)?|等于|是)0?3", compact):
        forced_content_id, forced_segment_id = "attendance_set_shifts", "three_shifts"
    elif (
        any(term in compact for term in ["第三方纸卡", "其他公司纸卡", "别家纸卡"])
        and any(term in compact for term in ["打印位置", "打印偏", "位置偏"])
    ):
        forced_content_id, forced_segment_id = "attendance_punch_position", "third_party_card_adjustment"
    elif "偏上" in compact and any(term in compact for term in ["打印", "字迹", "位置"]):
        forced_content_id, forced_segment_id = "attendance_punch_position", "lower_print_position"
    elif "偏下" in compact and any(term in compact for term in ["打印", "字迹", "位置"]):
        forced_content_id, forced_segment_id = "attendance_punch_position", "raise_print_position"
    shift_focus = (
        not card_layout_focus
        and not manual_punch_focus
        and any(term in compact for term in [
            "第一班", "第二班", "第三班", "一个班次", "两个班次", "三个班次",
            "单班次", "迟到打卡", "早退打卡", "迟到为什么红", "早退为什么红",
        ])
    )
    time_field_focus = (
        any(term in compact for term in ["小时", "分钟", "01组", "当前时间"])
        or (
            not shift_focus
            and "时间" in compact
            and any(term in compact for term in ["怎么调", "如何调", "修改", "不准", "保存", "设置"])
        )
    )

    candidates: list[tuple[int, int, dict, dict]] = []
    for content in load_manifest()["contents"]:
        if forced_content_id and content.get("content_id") != forced_content_id:
            continue
        if manual_punch_focus and content.get("content_id") != "attendance_manual_punch":
            continue
        if password_change_focus and content.get("content_id") != "attendance_modify_password":
            continue
        if time_field_focus and content.get("content_id") != "attendance_set_time":
            continue
        if shift_focus and content.get("content_id") != "attendance_set_shifts":
            continue
        for segment in content.get("segments", []):
            if forced_segment_id and segment.get("segment_id") != forced_segment_id:
                continue
            score, longest = _score_segment(message, content, segment)
            if score:
                candidates.append((score, longest, content, segment))
    if not candidates:
        return None
    candidates.sort(key=lambda item: (item[0], item[1]), reverse=True)
    score, _, content, segment = candidates[0]
    selected_nodes = select_operation_nodes(content, segment, message)
    unconfirmed_models = _unconfirmed_supported_models(message, selected_nodes)
    if unconfirmed_models:
        model_text = "/".join(unconfirmed_models)
        return {
            "type": "clarification",
            "content_id": content["content_id"],
            "segment_id": segment["segment_id"],
            "title": content["title"],
            "platform": selected_platform,
            "video_url": None,
            "reply": f"亲，备用电池功能有机型限制，请先确认机器是否为{model_text}等带电池版本；未确认前先不发送内部开关教程。",
            "screenshots": [],
            "selected_nodes": selected_nodes,
            "time_cue": None,
            "score": score,
            "risk_level": "model_confirmation_required",
            "auto_reply_allowed": False,
            "needs_clarification": True,
            "confidence": "high",
            "actions": [],
            "sources": ["attendance_video_materials.json"],
            "matches": [{
                "id": f"video_{content['content_id']}_{segment['segment_id']}",
                "type": "clarification",
                "score": score,
            }],
        }
    video_url = _video_url(content, segment, selected_platform)
    time_cue = operation_time_cue(segment, selected_nodes)
    if not time_cue and segment.get("start_ms") is not None and segment.get("end_ms") is not None:
        start_seconds = int(segment["start_ms"] / 1000)
        end_seconds = int(segment["end_ms"] / 1000)
        time_cue = f"{start_seconds // 60:02d}:{start_seconds % 60:02d}–{end_seconds // 60:02d}:{end_seconds % 60:02d}"
    if selected_platform == "Pinduoduo" and content.get("content_id") == "attendance_set_shifts":
        # Pinduoduo uses three separately edited shift videos; canonical JD/Tmall
        # timestamps must not be presented as if they applied to those cuts.
        time_cue = None
    source_screenshots = (
        [node["screenshot"] for node in selected_nodes]
        if selected_nodes
        else segment["screenshots"][:2]
    )
    screenshots = []
    for screenshot in source_screenshots[:2]:
        path = (ROOT / screenshot["path"]).resolve()
        asset_root = (ROOT / "assets/qianniu_video_materials").resolve()
        if asset_root not in path.parents or not path.is_file():
            raise VideoMaterialError(f"invalid or missing screenshot: {path}")
        screenshots.append({**screenshot, "absolute_path": str(path)})

    reply = f"{segment['customer_reply']}\n原视频：{video_url}"
    if time_cue:
        start_time = time_cue.split("–", 1)[0]
        reply += f"\n本段内容从视频 {start_time} 开始（对应操作范围 {time_cue}）。"
    elif selected_platform == "Pinduoduo" and content.get("content_id") == "attendance_set_shifts":
        reply += "\n拼多多是对应班次数的拆分版，请按截图中的组号定位操作。"
    return {
        "type": "video_material_card",
        "content_id": content["content_id"],
        "segment_id": segment["segment_id"],
        "title": content["title"],
        "platform": selected_platform,
        "video_url": video_url,
        "reply": reply,
        "screenshots": screenshots,
        "selected_nodes": selected_nodes,
        "time_cue": time_cue,
        "score": score,
        "risk_level": segment.get("risk_level", "low"),
        "auto_reply_allowed": segment.get("risk_level", "low") == "low",
        "confidence": "high",
        "actions": [
            action
            for screenshot in screenshots
            for action in (
                {"type": "send_image", "path": screenshot["absolute_path"]},
                {"type": "send_text", "text": f"截图说明：{screenshot['description']}"},
            )
        ],
        "sources": ["attendance_video_materials.json"],
        "matches": [{
            "id": f"video_{content['content_id']}_{segment['segment_id']}",
            "type": "video_material_card",
            "score": score,
        }],
    }
