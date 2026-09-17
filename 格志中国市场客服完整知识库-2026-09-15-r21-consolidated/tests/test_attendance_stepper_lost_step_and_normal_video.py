import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "attendance_machine_m880_after_sales_issues_kb.md"
VIDEO_KB = ROOT / "qianniu_video_materials_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"


def load_cards() -> dict[str, dict]:
    cards = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            card = json.loads(line)
            cards[card["id"]] = card
    return cards


def test_normal_punch_reviewed_metadata_is_preserved_without_fabricated_media() -> None:
    card = load_cards()["attendance_normal_punch_mechanical_baseline"]
    evidence = card["evidence"]
    assert evidence["artifact_availability"] == "metadata_only"
    assert evidence["sha256"] == "0fd371f20d1ce373d97a9da5c734f1fbcef3882b02ae25fba959cbd344450136"
    assert evidence["duration_seconds"] == 6.896067
    assert evidence["width"] == 720
    assert evidence["height"] == 1280
    assert evidence["video_codec"] == "h264"
    assert "screenshots" not in evidence
    assert "contact_sheets" not in evidence


def test_active_attendance_cards_do_not_reference_excluded_runtime_evidence() -> None:
    cards = load_cards()
    for card_id in ["attendance_stepper_motor_lost_step", "attendance_normal_punch_mechanical_baseline"]:
        assert all(not source.startswith("outputs/") for source in cards[card_id]["source_files"])


def test_formal_kb_contains_normal_and_fault_comparison() -> None:
    text = KB.read_text(encoding="utf-8")
    assert "M880、M880D、T960、T960S" in text
    assert "步进马达失步" in text
    assert "连续“咔咔”特征声或啸叫声" in text
    assert "优先确认是否使用原装电源" in text
    assert "确认色带安装和色带本身是否正常" in text
    assert "最后检查打印头移动轨道" in text
    assert "没有看到整张卡纸卡在机器内" in text
    assert "办理退回维修" in text
    assert "直接判定为步进马达失步" in text
    assert "不需要再询问异响发生时机" in text
    assert "卡纸被吸入 → 打印头移动定位 → 完成打印 → 卡纸送出" in text
    assert "打印“10 17:58”，并落在卡纸第10日行" in text
    assert "打印机构" not in text


def test_video_kb_links_fault_to_ribbon_tutorial_and_normal_baseline() -> None:
    text = VIDEO_KB.read_text(encoding="utf-8")
    assert "考勤机正常打卡机械流程基准" in text
    assert "0fd371f20d1ce373d97a9da5c734f1fbcef3882b02ae25fba959cbd344450136" in text
    assert "步进马达失步" in text
    assert "attendance_replace_ribbon" in text
    assert "491106253912.mp4" in text
    assert "00:46–00:55" in text
    assert "01:01–01:04" in text


def test_structured_stepper_lost_step_card_is_model_specific() -> None:
    card = load_cards()["attendance_stepper_motor_lost_step"]
    assert card["models"] == ["M880", "M880D", "T960", "T960S"]
    assert card["diagnosis"] == "stepper_motor_lost_step"
    assert card["symptoms"] == ["打印头不移动", "打印头卡住", "伴有咔咔声"]
    assert card["possible_causes"] == [
        "没有使用原装电源",
        "色带安装不正确，或色带破损、缠绕、老化",
        "打印头移动轨道有卡纸碎屑或异物",
    ]
    assert card["cause_check_priority"] == ["原装电源", "色带安装和色带本身", "打印头移动轨道碎屑或异物"]
    assert card["return_for_repair_if_all_checks_normal"] is True
    assert card["must_send_guidance_media_when_available"] is True
    assert card["no_full_card_visible_prompt"] == "先断电，再查看打印头移动轨道上是否有卡纸碎屑或异物"
    assert card["requires_model_confirmation_before_guidance"] is False
    assert "不重复询问型号" in card["model_policy"]
    assert card["requires_platform_confirmation_before_media"] is True
    assert card["auto_reply_allowed"] is False
    assert card["confirmed_audio_signature_is_sufficient"] is True
    assert card["requires_additional_fault_confirmation"] is False
    assert card["confirmed_audio_signatures"] == ["连续咔咔特征声", "啸叫声"]
    assert "ask_one_customer_observable_question" not in [action["type"] for action in card["actions"]]
    assert "不要询问客户打印头是否移动或卡住" in card["do_not_say"]

    material = card["ribbon_tutorial"]
    assert material["content_id"] == "attendance_replace_ribbon"
    assert material["time_cues"] == ["00:46–00:55", "01:01–01:04"]
    assert set(material["platform_urls"]) == {"Tmall", "JD", "Pinduoduo"}
    assert len(material["screenshots"]) == 2
    for screenshot in material["screenshots"]:
        assert (ROOT / screenshot["path"]).is_file()
        assert screenshot["description"]


def test_structured_normal_baseline_card_uses_confirmed_video() -> None:
    card = load_cards()["attendance_normal_punch_mechanical_baseline"]
    assert card["models"] == ["M880", "M880D", "T960", "T960S"]
    assert card["diagnosis"] == "normal_punch_cycle_reference"
    assert card["auto_reply_allowed"] is False
    assert card["process_sequence"] == [
        "卡纸被吸入",
        "打印头移动定位",
        "完成打印",
        "卡纸送出",
    ]
    assert card["reference_result"] == "打印10 17:58并落在卡纸第10日行"
    assert card["evidence"]["sha256"] == "0fd371f20d1ce373d97a9da5c734f1fbcef3882b02ae25fba959cbd344450136"
    assert card["evidence"]["artifact_availability"] == "metadata_only"
    assert "screenshots" not in card["evidence"]
