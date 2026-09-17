import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIRMED = ROOT / "confirmed_customer_service_updates_2026_08_18_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"


def load_cards() -> dict[str, dict]:
    return {
        card["id"]: card
        for line in CARDS.read_text(encoding="utf-8").splitlines()
        if line.strip()
        for card in [json.loads(line)]
    }


def test_shipping_policy_is_platform_specific_and_conditional() -> None:
    card = load_cards()["confirmed_platform_shipping_2026_08_18"]
    text = card["reply_template"]
    assert "京东仓库" in text
    assert "上海工厂" in text
    assert "16:00前" in text
    assert "不是绝对时效承诺" in text
    assert "Douyin" in card["platforms"]


def test_confirmed_shift_limits_and_mapping() -> None:
    text = CONFIRMED.read_text(encoding="utf-8")
    for phrase in (
        "每天最多设置 3 个班次",
        "最多设置 6 个打卡时间点",
        "先计算共同班次",
        "最终输入机器的自动班次不能互相重叠",
        "至少间隔 30 分钟",
        "不需要每个月重新设置班次",
        "第一班：`08:00–12:00`",
        "第二班：`12:30–17:30`",
        "第三班：`18:00–20:30`",
    ):
        assert phrase in text


def test_confirmed_package_and_battery_aliases() -> None:
    card = load_cards()["attendance_confirmed_standard_package_2026_08_18"]
    package = card["standard_package"]
    assert package == {
        "machine": 1,
        "power_adapter": 1,
        "attendance_cards": 50,
        "installed_ribbon": 1,
        "wall_screws": 2,
    }
    assert "M880DA/M880D-A/880D-A" in card["battery_models"]
    assert card["battery_location"] == "installed_inside_machine_not_loose"
    assert card["card_rack_standard"] is False


def test_video_policy_analyzes_audio_and_avoids_reasking() -> None:
    card = load_cards()["customer_video_audio_direct_analysis_2026_08_18"]
    rules = " ".join(card["rules"])
    assert "同时分析画面和音频" in rules
    assert "证据充分时直接给分步方案" in rules
    assert "型号可见或方法通用时不重复询问" in rules
    assert "安全风险先关机断电" in rules


def test_print_position_card_has_confirmed_order_and_self_test_key() -> None:
    card = load_cards()["attendance_manual_print_position_card_detect"]
    text = card["reply_template"]
    assert "00组日期" in text
    assert "01组时间" in text
    assert "03–08组班次" in text
    assert "15组和09组" in text
    assert "09组最晚05:59" in text
    assert "最后打卡在05:59或之后" in text
    assert "按住1号/+增加键" in text


def test_group_09_caps_at_05_59_and_has_late_boundary() -> None:
    card = load_cards()["attendance_cross_day_09_group"]
    assert card["rule"]["latest_group_09"] == "05:59"
    assert card["rule"]["preferred_gap_minutes"] == 30
    assert card["rule"]["gap_exception"] == "若延后30分钟超过05:59则设05:59"
    assert card["rule"]["at_or_after_05_59"] == "手动打卡或转人工"
    assert "员工必须在05:59前打卡" in card["reply_template"]
