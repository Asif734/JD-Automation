from pathlib import Path
import json

from PIL import Image

from tests.test_customer_video_pipeline import make_test_video


def test_ocr_failure_is_recorded_not_raised(tmp_path: Path) -> None:
    from scripts.customer_video_pipeline import run_ocr

    image = tmp_path / "frame.png"
    Image.new("RGB", (40, 40), "white").save(image)
    result = run_ocr(image, tmp_path / "missing-project")
    assert result["status"] == "unavailable"
    assert result["rows"] == []


def test_recursive_collection_filters_supported_extensions(tmp_path: Path) -> None:
    from scripts.prepare_customer_videos import collect_video_paths

    (tmp_path / "a.mp4").write_bytes(b"x")
    (tmp_path / "b.txt").write_text("x", encoding="utf-8")
    assert [path.name for path in collect_video_paths(tmp_path, recursive=True)] == [
        "a.mp4"
    ]


def test_batch_failure_does_not_discard_success(tmp_path: Path) -> None:
    from scripts.prepare_customer_videos import process_paths

    good = tmp_path / "good.mp4"
    bad = tmp_path / "bad.mp4"
    make_test_video(good)
    bad.write_bytes(b"broken")
    summary = process_paths([good, bad], tmp_path / "out")
    assert summary["succeeded"] == 1
    assert summary["failed"] == 1


def test_enabled_ocr_is_limited_and_attached_to_timestamped_frames(
    tmp_path: Path, monkeypatch
) -> None:
    from scripts import customer_video_pipeline as pipeline

    source = tmp_path / "ocr.mp4"
    make_test_video(source)
    calls: list[Path] = []

    def fake_ocr(frame_path: Path, root: Path) -> dict[str, object]:
        calls.append(frame_path)
        return {"status": "ok", "rows": [{"text": "88:88", "confidence": 0.9}]}

    monkeypatch.setattr(pipeline, "run_ocr", fake_ocr)
    result = pipeline.prepare_video(source, tmp_path / "out", ocr_enabled=True)
    evidence = json.loads(result.evidence_path.read_text(encoding="utf-8"))
    attached = [row for row in evidence["frames"] if row["ocr"]["status"] == "ok"]
    assert 3 <= len(calls) <= 6
    assert len(attached) == len(calls)
    assert attached[0]["timestamp_seconds"] == 0.0
    assert attached[-1]["timestamp_seconds"] == 4.0
