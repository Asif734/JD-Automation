from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOP = ROOT / "customer_video_analysis_sop_kb.md"
ATTENDANCE_VIDEO_MATERIALS = ROOT / "rag_cards/attendance_video_materials.json"


def test_video_sop_requires_human_confirmation_before_case_ingestion() -> None:
    text = SOP.read_text(encoding="utf-8")
    for phrase in (
        "用户明确确认",
        "禁止自动入库",
        "每轮只问一个",
        "核对机器型号",
        "核对当前平台",
    ):
        assert phrase in text


def test_video_sop_preserves_safety_priority() -> None:
    text = SOP.read_text(encoding="utf-8")
    assert "停止操作并断电" in text
    assert "开放机芯" in text


def test_attendance_customer_facing_term_is_print_head() -> None:
    sop = SOP.read_text(encoding="utf-8")
    materials = ATTENDANCE_VIDEO_MATERIALS.read_text(encoding="utf-8")
    assert "统一称为“打印头”" in sop
    assert "打印机构" not in sop
    assert "打印机构" not in materials
