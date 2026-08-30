#!/usr/bin/env python3
"""Prepare local, timestamped evidence packages from customer videos."""

from __future__ import annotations

import math
import json
import shutil
import subprocess
import wave
from dataclasses import asdict, dataclass
from hashlib import sha256
from pathlib import Path

import av
from PIL import Image, ImageDraw, ImageOps


@dataclass(frozen=True)
class VideoMetadata:
    source_path: str
    sha256: str
    duration: float
    width: int
    height: int
    fps: float
    container: str
    video_codec: str
    audio_codec: str | None
    has_audio: bool

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


@dataclass(frozen=True)
class PreparationResult:
    case_dir: Path
    metadata_path: Path
    evidence_path: Path
    draft_path: Path
    frame_paths: tuple[Path, ...]
    contact_sheet_paths: tuple[Path, ...]
    audio_path: Path | None
    cached: bool


DRAFT_TEMPLATE = """# 客户视频诊断草稿

## 可见事实

等待客服助手根据联系表和关键帧填写。

## 初步分类

无法确认。

## 不能确认的内容

等待证据阅读。

## 可能分支

等待证据阅读。

## 安全提醒

如画面存在开放机芯、外露滚轮/齿轮或电池异常，先停止操作并断电。

## 单一关键确认问题

等待客服助手根据剩余分支生成一个问题。

## 建议客服回复

客户确认前不发送具体参数、教程、视频或截图。

## 知识库候选条目

状态：待用户确认，禁止自动入库。
"""


def adaptive_interval(duration: float, dense: bool = False) -> float:
    """Choose a review interval based on customer-video duration."""
    if duration <= 0:
        raise ValueError("duration must be positive")
    if dense or duration <= 10:
        return 0.25
    if duration <= 30:
        return 0.5
    if duration <= 300:
        return 1.0
    if duration <= 900:
        return 2.0
    return 5.0


def sample_timestamps(duration: float, interval: float) -> list[float]:
    """Return ordered sample timestamps including both logical endpoints."""
    if duration <= 0 or interval <= 0:
        raise ValueError("duration and interval must be positive")
    count = math.floor(duration / interval)
    values = [round(index * interval, 6) for index in range(count + 1)]
    values.append(round(duration, 6))
    return sorted(set(value for value in values if value <= duration))


def sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def probe_video(path: Path) -> VideoMetadata:
    """Read container/stream metadata without altering the source file."""
    if not path.is_file():
        raise FileNotFoundError(path)
    with av.open(str(path)) as container:
        if not container.streams.video:
            raise ValueError("no video stream")
        video = container.streams.video[0]
        audio = container.streams.audio[0] if container.streams.audio else None
        duration = float(container.duration / av.time_base) if container.duration else 0.0
        if duration <= 0 and video.duration is not None and video.time_base is not None:
            duration = float(video.duration * video.time_base)
        if duration <= 0:
            raise ValueError("video duration unavailable")
        return VideoMetadata(
            source_path=str(path.resolve()),
            sha256=sha256_file(path),
            duration=duration,
            width=video.codec_context.width,
            height=video.codec_context.height,
            fps=float(video.average_rate or 0),
            container=container.format.name,
            video_codec=video.codec_context.name,
            audio_codec=audio.codec_context.name if audio else None,
            has_audio=audio is not None,
        )


def decode_sampled_frames(
    source: Path, timestamps: list[float], frame_dir: Path
) -> list[dict[str, object]]:
    """Decode sequentially and save the first frame at/after each timestamp."""
    frame_dir.mkdir(parents=True, exist_ok=True)
    wanted = iter(timestamps)
    target = next(wanted, None)
    rows: list[dict[str, object]] = []
    with av.open(str(source)) as container:
        stream = container.streams.video[0]
        last_image: Image.Image | None = None
        last_actual = 0.0
        for frame in container.decode(stream):
            if target is None:
                break
            actual = float(frame.time or 0.0)
            last_image = frame.to_image()
            last_actual = actual
            while target is not None and actual + 1e-6 >= target:
                filename = f"frame_{len(rows):04d}_{round(target * 1000):010d}ms.png"
                path = frame_dir / filename
                last_image.save(path)
                rows.append(
                    {
                        "timestamp_seconds": target,
                        "actual_frame_seconds": actual,
                        "path": str(path.resolve()),
                        "ocr": {"status": "not_run", "rows": []},
                    }
                )
                target = next(wanted, None)
        while target is not None and last_image is not None:
            filename = f"frame_{len(rows):04d}_{round(target * 1000):010d}ms.png"
            path = frame_dir / filename
            last_image.save(path)
            rows.append(
                {
                    "timestamp_seconds": target,
                    "actual_frame_seconds": last_actual,
                    "path": str(path.resolve()),
                    "ocr": {"status": "not_run", "rows": []},
                }
            )
            target = next(wanted, None)
    if target is not None or not rows:
        raise RuntimeError("decoded frame count is insufficient for requested timestamps")
    return rows


def create_contact_sheets(
    frame_rows: list[dict[str, object]], output_dir: Path, per_page: int = 20
) -> list[Path]:
    """Lay sampled frames out in time order with labels."""
    output_dir.mkdir(parents=True, exist_ok=True)
    pages: list[Path] = []
    for page_index, start in enumerate(range(0, len(frame_rows), per_page), 1):
        page_rows = frame_rows[start : start + per_page]
        canvas = Image.new("RGB", (1000, 1250), "white")
        draw = ImageDraw.Draw(canvas)
        for local_index, row in enumerate(page_rows):
            with Image.open(str(row["path"])) as opened:
                image = opened.convert("RGB")
            image.thumbnail((230, 210))
            x = (local_index % 4) * 250 + 10
            y = (local_index // 4) * 245 + 10
            tile = ImageOps.pad(image, (230, 210), color="black")
            canvas.paste(tile, (x, y))
            draw.text(
                (x, y + 214),
                f'{float(row["timestamp_seconds"]):.2f}s',
                fill="black",
            )
        path = output_dir / f"contact_sheet_{page_index:03d}.jpg"
        canvas.save(path, quality=90)
        pages.append(path)
    return pages


def extract_audio_wav(source: Path, destination: Path) -> Path | None:
    """Extract a mono 16 kHz review track, or return None for silent videos."""
    with av.open(str(source)) as container:
        if not container.streams.audio:
            return None
        stream = container.streams.audio[0]
        resampler = av.AudioResampler(format="s16", layout="mono", rate=16000)
        destination.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(destination), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(16000)
            for frame in container.decode(stream):
                converted = resampler.resample(frame)
                converted_frames = converted if isinstance(converted, list) else [converted]
                for audio_frame in converted_frames:
                    if audio_frame is not None:
                        output.writeframes(audio_frame.to_ndarray().tobytes())
    return destination


def safe_case_stem(stem: str) -> str:
    cleaned = "".join(
        character if character.isalnum() or character in "-_" else "_"
        for character in stem
    )
    return cleaned[:80] or "video"


def run_ocr(frame_path: Path, root: Path) -> dict[str, object]:
    """Run the existing local OCR helper and make every failure nonfatal."""
    python = root / ".venv-ocr/bin/python"
    script = root / "scripts/ocr_rapid.py"
    if not python.is_file() or not script.is_file():
        return {"status": "unavailable", "rows": []}
    try:
        completed = subprocess.run(
            [str(python), str(script), str(frame_path), "--json"],
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
        )
        return {"status": "ok", "rows": json.loads(completed.stdout or "[]")}
    except (subprocess.SubprocessError, json.JSONDecodeError) as error:
        return {"status": "failed", "rows": [], "error": str(error)}


def ocr_candidate_indexes(frame_count: int, maximum: int = 5) -> list[int]:
    if frame_count <= 0 or maximum <= 0:
        return []
    count = min(frame_count, maximum)
    if count == 1:
        return [0]
    return sorted(
        {
            round(index * (frame_count - 1) / (count - 1))
            for index in range(count)
        }
    )


def _clear_generated_case(case_dir: Path, output_root: Path) -> None:
    resolved_case = case_dir.resolve()
    resolved_root = output_root.resolve()
    if resolved_case.parent != resolved_root:
        raise ValueError("refusing to clear a case outside the output root")
    if resolved_case.is_dir():
        shutil.rmtree(resolved_case)


def prepare_video(
    source: Path,
    output_root: Path,
    interval: float | None = None,
    dense: bool = False,
    extract_audio: bool = True,
    force: bool = False,
    ocr_enabled: bool = False,
) -> PreparationResult:
    """Prepare one local evidence package without diagnosing or ingesting it."""
    metadata = probe_video(source)
    case_dir = output_root / f"{metadata.sha256[:12]}_{safe_case_stem(source.stem)}"
    metadata_path = case_dir / "metadata.json"
    evidence_path = case_dir / "evidence.json"
    draft_path = case_dir / "analysis_draft.md"
    existing_sheets = tuple(sorted((case_dir / "contact_sheets").glob("*.jpg")))
    cached_ocr_compatible = True
    if metadata_path.is_file() and ocr_enabled:
        try:
            cached_ocr_compatible = (
                json.loads(metadata_path.read_text(encoding="utf-8")).get("ocr_status")
                == "enabled"
            )
        except (OSError, json.JSONDecodeError):
            cached_ocr_compatible = False
    if (
        not force
        and metadata_path.is_file()
        and evidence_path.is_file()
        and draft_path.is_file()
        and existing_sheets
        and cached_ocr_compatible
    ):
        existing_frames = tuple(sorted((case_dir / "frames").glob("*.png")))
        existing_audio = case_dir / "audio.wav"
        return PreparationResult(
            case_dir,
            metadata_path,
            evidence_path,
            draft_path,
            existing_frames,
            existing_sheets,
            existing_audio if existing_audio.is_file() else None,
            True,
        )

    if force:
        _clear_generated_case(case_dir, output_root)
    case_dir.mkdir(parents=True, exist_ok=True)
    chosen_interval = interval if interval is not None else adaptive_interval(metadata.duration, dense)
    timestamps = sample_timestamps(metadata.duration, chosen_interval)
    frame_rows = decode_sampled_frames(source, timestamps, case_dir / "frames")
    if ocr_enabled:
        project_root = Path(__file__).resolve().parents[1]
        for index in ocr_candidate_indexes(len(frame_rows)):
            frame_rows[index]["ocr"] = run_ocr(
                Path(str(frame_rows[index]["path"])), project_root
            )
    sheets = create_contact_sheets(frame_rows, case_dir / "contact_sheets")
    audio_path = extract_audio_wav(source, case_dir / "audio.wav") if extract_audio else None
    metadata_payload = metadata.to_dict() | {
        "source_sha256": metadata.sha256,
        "sampling_interval_seconds": chosen_interval,
        "audio_status": "extracted"
        if audio_path
        else ("skipped" if not extract_audio else "absent"),
        "ocr_status": "enabled" if ocr_enabled else "disabled",
    }
    evidence_payload = {
        "source_sha256": metadata.sha256,
        "status": "prepared_for_human_review",
        "frames": frame_rows,
        "knowledge_base_status": "pending_user_confirmation",
    }
    metadata_path.write_text(
        json.dumps(metadata_payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    evidence_path.write_text(
        json.dumps(evidence_payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    draft_path.write_text(DRAFT_TEMPLATE, encoding="utf-8")
    return PreparationResult(
        case_dir,
        metadata_path,
        evidence_path,
        draft_path,
        tuple(Path(str(row["path"])) for row in frame_rows),
        tuple(sheets),
        audio_path,
        False,
    )
