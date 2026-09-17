from __future__ import annotations

from app import build_reply
from tutorial_video_catalog import enrich_reply_with_tutorial
from video_materials import match_video_material


def test_response_keeps_answer_first_then_adds_one_exact_same_platform_video() -> None:
    result = enrich_reply_with_tutorial(
        "亲，请先在打印机属性中打开速度设置。",
        "Win11打印速度太慢，怎么调节打印速度？",
        "京东",
        product_line="thermal_printer",
    )

    assert result["reply"].startswith("亲，请先在打印机属性中打开速度设置。")
    assert result["reply"].count("操作视频（京东）") == 1
    assert len(result["actions"]) == 1
    assert result["actions"][0]["type"] == "send_video"
    assert result["actions"][0]["platform"] == "JD"


def test_response_does_not_add_cross_platform_or_pending_link() -> None:
    result = enrich_reply_with_tutorial(
        "亲，请先打印测试页查看IP地址。",
        "测试打印并查看打印机IP地址",
        "拼多多",
        product_line="wifi_bluetooth_dot_matrix_printer",
    )

    assert result == {
        "reply": "亲，请先打印测试页查看IP地址。",
        "actions": [],
        "tutorial": None,
    }


def test_existing_attendance_detailed_video_routing_is_unchanged() -> None:
    result = match_video_material("考勤机日期怎么设置", "天猫")

    assert result is not None
    assert result["content_id"] == "attendance_modify_date"
    assert result["platform"] == "Tmall"
    assert result["video_url"].startswith("http")


def test_main_response_appends_relevant_tutorial_when_platform_is_available() -> None:
    result = build_reply(
        "Win11热敏打印机打印暂停了，怎么恢复？",
        product="thermal_printer",
        platform="天猫",
    )

    assert "操作视频（天猫）" in result["reply"]
    assert sum(action.get("type") == "send_video" for action in result["actions"]) == 1


def test_non_attendance_printer_question_is_not_hijacked_by_attendance_video() -> None:
    result = build_reply(
        "针式打印机色带怎么更换？",
        product="dot_matrix_printer",
        platform="天猫",
    )

    assert result.get("content_id") != "attendance_replace_ribbon"
    assert result["tutorial"]["content_id"] == "cloud_dot_matrix_printer_how_to_replace_ribbon"


def test_wifi_dot_matrix_ip_question_is_not_hijacked_by_attendance_self_test() -> None:
    result = build_reply(
        "WiFi针式打印机怎么测试打印查看IP地址",
        product="wifi_bluetooth_dot_matrix_printer",
        platform="京东",
    )

    assert result.get("content_id") != "attendance_test_print"
    assert result["tutorial"]["source_cells"] == ["Sheet1!E38"]


def test_specialized_attendance_catalogs_do_not_use_ordinary_attendance_nodes() -> None:
    smart = build_reply(
        "智能考勤机如何登录或注册APP新账户",
        product="smart_attendance_machine",
        platform="京东",
    )
    bluetooth = build_reply(
        "蓝牙考勤机APP怎么连接和设置密码",
        product="bluetooth_attendance_machine",
        platform="天猫",
    )

    assert smart["tutorial"]["product_line"] == "smart_attendance_machine"
    assert bluetooth["tutorial"]["product_line"] == "bluetooth_attendance_machine"
    assert smart.get("content_id") is None
    assert bluetooth.get("content_id") is None
