import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KB = ROOT / "attendance_machine_m880_after_sales_issues_kb.md"
CARDS = ROOT / "rag_cards/customer_service_rag_cards.jsonl"
EVIDENCE_IMAGE = ROOT / "sources/user_uploads/attendance_machine/printed_date_24_on_row_23.png"
THIRD_PARTY_ANNOTATED = ROOT / "sources/user_uploads/attendance_machine/third_party_card_without_tht_mark_annotated.png"
THT_OFFICIAL_CARD = ROOT / "sources/user_uploads/attendance_machine/tht_official_attendance_card_mark.png"


def load_cards() -> dict[str, dict]:
    cards = {}
    for line in CARDS.read_text(encoding="utf-8").splitlines():
        if line.strip():
            card = json.loads(line)
            cards[card["id"]] = card
    return cards


def test_date_row_mismatch_visual_evidence_is_preserved() -> None:
    assert EVIDENCE_IMAGE.is_file()
    assert EVIDENCE_IMAGE.stat().st_size > 0


def test_third_party_and_tht_card_visual_evidence_are_preserved() -> None:
    assert THIRD_PARTY_ANNOTATED.is_file() and THIRD_PARTY_ANNOTATED.stat().st_size > 0
    assert THT_OFFICIAL_CARD.is_file() and THT_OFFICIAL_CARD.stat().st_size > 0


def test_kb_distinguishes_printed_date_content_from_physical_row() -> None:
    text = KB.read_text(encoding="utf-8")
    assert "打印内容显示 24 日，但落在卡纸 23 日的行位" in text
    assert "实际日期与打印的物理位置不匹配" in text
    assert "不属于月底日期跳转问题" in text
    assert "printed_date_24_on_row_23.png" in text
    assert "本案例根因是非 THT 卡纸版式与机器不匹配" in text
    assert "THT微型电脑考勤机专用" in text
    assert "微电脑打卡钟专用" in text
    assert "未用 THT 卡纸复测前，不调整机器打印位置" in text
    assert "打印位置不对先看完整考勤时间" not in text
    assert "请看一下卡纸顶部是否印有THT标记" in text


def test_structured_date_row_mismatch_card_requires_model_before_steps() -> None:
    card = load_cards()["attendance_printed_date_row_mismatch"]
    assert card["diagnosis"] == "third_party_card_layout_mismatch"
    assert card["auto_reply_allowed"] is False
    assert card["requires_model_confirmation_before_guidance"] is True
    assert card["printed_content_example"] == "24日"
    assert card["physical_row_example"] == "23日行"
    assert card["official_card_mark"] == "THT微型电脑考勤机专用"
    assert card["third_party_card_mark"] == "微电脑打卡钟专用"
    assert card["do_not_adjust_machine_before_tht_card_test"] is False
    assert "是想更换顶部带THT标记的本公司考勤卡" in card["reply_template"]
    assert "还是继续使用这张第三方卡微调位置" in card["reply_template"]
    assert "13组" not in card["reply_template"]


def test_generic_print_position_card_checks_tht_card_before_machine_adjustment() -> None:
    card = load_cards()["attendance_manual_print_position_card_detect"]
    assert card["auto_reply_allowed"] is False
    assert "THT" in card["reply_template"]
    assert "13组" not in card["reply_template"]
    assert card["check_tht_card_before_machine_adjustment"] is True


def test_third_party_card_adjustment_branch_has_exact_platform_video_and_screenshots() -> None:
    card = load_cards()["attendance_printed_date_row_mismatch"]
    assert card["third_party_card_options"] == [
        "replace_with_official_tht_card",
        "continue_third_party_card_and_micro_adjust",
    ]
    assert "更换THT卡" in card["choice_question"]
    assert "继续使用这张第三方卡微调位置" in card["choice_question"]

    video = card["third_party_adjustment_video"]
    assert video["content_id"] == "attendance_punch_position"
    assert video["segment_id"] == "third_party_card_adjustment"
    assert video["time_cue"] == "00:26–00:38"
    assert set(video["platform_urls"]) == {"Tmall", "JD", "Pinduoduo"}
    assert len(video["screenshots"]) == 2
    for relative_path in video["screenshots"]:
        assert (ROOT / relative_path).is_file()


def test_kb_documents_third_party_card_micro_adjustment_video_branch() -> None:
    text = KB.read_text(encoding="utf-8")
    assert "客户明确继续使用第三方卡纸时，可以自行小幅微调打印位置" in text
    assert "第三方卡纸位置微调视频" in text
    assert "00:26–00:38" in text
    assert "491279178909.mp4" in text
    assert "ed2a79ddf042649eaf77336bf18a16e1.mp4" in text
    assert "7123d37d905842367050850305" in text
