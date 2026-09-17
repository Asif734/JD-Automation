#!/usr/bin/env python3
"""Timestamped speech, audio-event, frame-alignment, and KB retrieval helpers.

The module deliberately writes case evidence only. It never creates or mutates a
knowledge database; suggested answers are retrieved from the existing RAG index.
"""

from __future__ import annotations

import json
import math
import os
import statistics
import wave
from array import array
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Protocol

from PIL import Image, ImageChops, ImageStat

try:
    from .search_rag import search
except ImportError:  # Direct script execution.
    from search_rag import search


DEFAULT_MODEL = "small"
CHINESE_INITIAL_PROMPT = (
    "这是一段中国市场客服收到的客户视频。请优先准确转写普通话和中文方言口音，"
    "保留机器型号、数字、时间、错误代码、英文缩写和中英混合表达。"
)


@dataclass(frozen=True)
class TranscriptWord:
    start: float
    end: float
    text: str
    probability: float | None = None


@dataclass(frozen=True)
class TranscriptSegment:
    start: float
    end: float
    text: str
    words: tuple[TranscriptWord, ...] = ()


@dataclass(frozen=True)
class TranscriptionResult:
    language: str | None
    language_probability: float | None
    segments: tuple[TranscriptSegment, ...]
    backend: str
    model: str

    @property
    def text(self) -> str:
        return " ".join(segment.text.strip() for segment in self.segments if segment.text.strip())

    def to_dict(self) -> dict[str, object]:
        return {
            "status": "ok",
            "voice_analysis_claimed": True,
            "backend": self.backend,
            "model": self.model,
            "language": self.language,
            "language_probability": self.language_probability,
            "text": self.text,
            "segments": [asdict(segment) for segment in self.segments],
        }


class SpeechTranscriber(Protocol):
    def transcribe(self, audio_path: Path) -> TranscriptionResult: ...


class FasterWhisperTranscriber:
    """Lazy local multilingual Whisper backend with Chinese-first prompting."""

    def __init__(
        self,
        model_name: str | None = None,
        device: str | None = None,
        compute_type: str | None = None,
    ) -> None:
        self.model_name = model_name or os.getenv("GROZZIIE_WHISPER_MODEL", DEFAULT_MODEL)
        self.device = device or os.getenv("GROZZIIE_WHISPER_DEVICE", "auto")
        self.compute_type = compute_type or os.getenv("GROZZIIE_WHISPER_COMPUTE_TYPE", "int8")
        self._model: Any | None = None

    def _load_model(self) -> Any:
        if self._model is None:
            try:
                from faster_whisper import WhisperModel
            except ImportError as error:
                raise RuntimeError(
                    "faster-whisper is not installed; run the video dependency installer"
                ) from error
            self._model = WhisperModel(
                self.model_name,
                device=self.device,
                compute_type=self.compute_type,
            )
        return self._model

    def transcribe(self, audio_path: Path) -> TranscriptionResult:
        model = self._load_model()
        raw_segments, info = model.transcribe(
            str(audio_path),
            language=None,
            beam_size=5,
            best_of=5,
            vad_filter=True,
            word_timestamps=True,
            condition_on_previous_text=True,
            initial_prompt=CHINESE_INITIAL_PROMPT,
        )
        segments: list[TranscriptSegment] = []
        for segment in raw_segments:
            words = tuple(
                TranscriptWord(
                    start=round(float(word.start), 3),
                    end=round(float(word.end), 3),
                    text=str(word.word),
                    probability=round(float(word.probability), 4)
                    if getattr(word, "probability", None) is not None
                    else None,
                )
                for word in (getattr(segment, "words", None) or [])
            )
            text = str(segment.text).strip()
            if text:
                segments.append(
                    TranscriptSegment(
                        start=round(float(segment.start), 3),
                        end=round(float(segment.end), 3),
                        text=text,
                        words=words,
                    )
                )
        return TranscriptionResult(
            language=getattr(info, "language", None),
            language_probability=round(float(info.language_probability), 4)
            if getattr(info, "language_probability", None) is not None
            else None,
            segments=tuple(segments),
            backend="faster-whisper",
            model=self.model_name,
        )


def transcribe_audio_safely(
    audio_path: Path | None,
    *,
    transcriber: SpeechTranscriber | None = None,
    audio_status: str = "extracted",
) -> dict[str, object]:
    """Return an explicit transcription status without overstating success."""
    if audio_status == "failed":
        return {
            "status": "audio_extraction_failed",
            "voice_analysis_claimed": False,
            "text": "",
            "segments": [],
            "limitation": "视频音轨提取失败，无法分析客户语音。",
        }
    if audio_path is None:
        return {
            "status": "absent",
            "voice_analysis_claimed": False,
            "text": "",
            "segments": [],
            "limitation": "视频没有可提取的音轨。",
        }
    selected = transcriber or FasterWhisperTranscriber()
    try:
        result = selected.transcribe(audio_path)
        payload = result.to_dict()
        if not result.text:
            payload.update(
                {
                    "status": "no_speech",
                    "voice_analysis_claimed": True,
                    "limitation": "音轨提取和识别已完成，但未识别到清晰语音。",
                }
            )
        return payload
    except Exception as error:  # Every backend/model failure must be an honest fallback.
        return {
            "status": "failed",
            "voice_analysis_claimed": False,
            "text": "",
            "segments": [],
            "limitation": "音轨已提取，但语音转写失败，无法确认客户说话内容。",
            "error": f"{type(error).__name__}: {error}",
        }


def wav_duration_seconds(path: Path) -> float:
    with wave.open(str(path), "rb") as audio:
        return round(audio.getnframes() / audio.getframerate(), 6)


def detect_audio_event_candidates(path: Path, window_seconds: float = 0.25) -> list[dict[str, object]]:
    """Locate unusually loud windows without assigning an unsupported fault label."""
    with wave.open(str(path), "rb") as audio:
        channels = audio.getnchannels()
        sample_width = audio.getsampwidth()
        rate = audio.getframerate()
        if sample_width != 2:
            return []
        frame_count = max(1, round(rate * window_seconds))
        values: list[tuple[float, float]] = []
        index = 0
        while True:
            raw = audio.readframes(frame_count)
            if not raw:
                break
            samples = array("h")
            samples.frombytes(raw)
            if channels > 1:
                samples = array("h", samples[::channels])
            if not samples:
                continue
            rms = math.sqrt(sum(sample * sample for sample in samples) / len(samples))
            values.append((index * window_seconds, rms))
            index += 1
    nonzero = [value for _, value in values if value > 0]
    if not nonzero:
        return []
    baseline = statistics.median(nonzero)
    threshold = max(2500.0, baseline * 3.5)
    return [
        {
            "start": round(start, 3),
            "end": round(start + window_seconds, 3),
            "type": "loud_sound_candidate",
            "rms": round(rms, 2),
            "interpretation": "仅表示音量突增候选，需结合画面和语音判断，不能单独认定故障。",
        }
        for start, rms in values
        if rms >= threshold
    ]


def frame_motion_scores(frame_rows: list[dict[str, object]]) -> list[dict[str, object]]:
    """Measure whole-frame visual change across the complete sampled timeline."""
    results: list[dict[str, object]] = []
    previous: Image.Image | None = None
    for row in frame_rows:
        with Image.open(str(row["path"])) as opened:
            current = opened.convert("L").resize((160, 120))
        score = 0.0
        if previous is not None:
            difference = ImageChops.difference(previous, current)
            score = float(ImageStat.Stat(difference).mean[0])
        results.append(
            {
                "timestamp_seconds": float(row["timestamp_seconds"]),
                "motion_score": round(score, 3),
                "motion_observed": score >= 8.0,
            }
        )
        previous = current
    return results


def _segment_dicts(transcription: dict[str, object]) -> list[dict[str, object]]:
    return [dict(segment) for segment in transcription.get("segments", []) if isinstance(segment, dict)]


def align_transcript_with_frames(
    frame_rows: list[dict[str, object]], transcription: dict[str, object]
) -> dict[str, object]:
    """Attach spoken segments to the corresponding sampled frames and OCR text."""
    segments = _segment_dicts(transcription)
    frames: list[dict[str, object]] = []
    for index, row in enumerate(frame_rows):
        timestamp = float(row["timestamp_seconds"])
        active = [
            segment
            for segment in segments
            if float(segment.get("start", 0)) <= timestamp <= float(segment.get("end", 0))
        ]
        ocr_rows = row.get("ocr", {}).get("rows", []) if isinstance(row.get("ocr"), dict) else []
        frames.append(
            {
                "frame_index": index,
                "timestamp_seconds": timestamp,
                "path": row["path"],
                "spoken_text": " ".join(str(segment.get("text", "")).strip() for segment in active).strip(),
                "segment_indexes": [segments.index(segment) for segment in active],
                "screen_text": _flatten_ocr_text(ocr_rows),
            }
        )

    aligned_segments: list[dict[str, object]] = []
    for index, segment in enumerate(segments):
        start = float(segment.get("start", 0))
        end = float(segment.get("end", start))
        frame_indexes = [
            frame["frame_index"]
            for frame in frames
            if start <= float(frame["timestamp_seconds"]) <= end
        ]
        if not frame_indexes and frames:
            midpoint = (start + end) / 2
            nearest = min(frames, key=lambda frame: abs(float(frame["timestamp_seconds"]) - midpoint))
            frame_indexes = [nearest["frame_index"]]
        aligned_segments.append(
            dict(segment)
            | {
                "segment_index": index,
                "frame_indexes": frame_indexes,
                "screen_text": " ".join(
                    str(frames[frame_index]["screen_text"])
                    for frame_index in frame_indexes
                    if frames[frame_index]["screen_text"]
                ).strip(),
            }
        )
    return {"frames": frames, "segments": aligned_segments}


def _flatten_ocr_text(rows: Any) -> str:
    texts: list[str] = []
    if not isinstance(rows, list):
        return ""
    for row in rows:
        if isinstance(row, str):
            texts.append(row)
        elif isinstance(row, dict):
            for key in ("text", "value", "label"):
                value = row.get(key)
                if isinstance(value, str) and value.strip():
                    texts.append(value.strip())
                    break
        elif isinstance(row, (list, tuple)):
            for value in row:
                if isinstance(value, str) and value.strip():
                    texts.append(value.strip())
    return " ".join(texts)


def build_video_diagnosis(
    transcription: dict[str, object],
    timeline: dict[str, object],
    *,
    index_path: Path,
    audio_events: list[dict[str, object]] | None = None,
    top_k: int = 3,
) -> dict[str, object]:
    """Retrieve an existing KB solution from combined timestamped evidence."""
    status = str(transcription.get("status", "failed"))
    transcript_text = str(transcription.get("text", "")).strip()
    screen_text = " ".join(
        str(frame.get("screen_text", "")).strip()
        for frame in timeline.get("frames", [])
        if isinstance(frame, dict) and str(frame.get("screen_text", "")).strip()
    )
    query = " ".join(value for value in [transcript_text, screen_text] if value).strip()
    motion_timestamps = [
        float(frame.get("timestamp_seconds", 0))
        for frame in timeline.get("frames", [])
        if isinstance(frame, dict) and frame.get("motion_observed")
    ]
    combined_evidence = {
        "spoken_text": transcript_text,
        "screen_text": screen_text,
        "customer_action_timestamps": motion_timestamps,
        "abnormal_sound_candidates": audio_events or [],
    }
    matches: list[dict[str, object]] = []
    if query and index_path.is_file():
        index = json.loads(index_path.read_text(encoding="utf-8"))
        matches = search(index, query, top_k=top_k)

    transcription_failed = status in {"audio_extraction_failed", "failed"}
    if transcription_failed:
        limitation = str(transcription.get("limitation") or "语音分析失败。")
        return {
            "status": "needs_one_clarification",
            "voice_analysis_claimed": False,
            "limitation": limitation,
            "evidence_query": screen_text,
            "combined_evidence": combined_evidence,
            "matches": matches,
            "problem": None,
            "answer": f"{limitation}请问视频里客户主要说的故障是什么？",
            "clarification_questions": ["请问视频里客户主要说的故障是什么？"],
            "audio_event_candidates": audio_events or [],
        }

    top = matches[0] if matches else None
    if top and _is_confident_kb_match(top) and str(top.get("reply_template", "")).strip():
        return {
            "status": "answered_from_existing_kb",
            "voice_analysis_claimed": bool(transcription.get("voice_analysis_claimed", False)),
            "limitation": transcription.get("limitation"),
            "evidence_query": query,
            "combined_evidence": combined_evidence,
            "matches": matches,
            "problem": top.get("issue"),
            "answer": top.get("reply_template"),
            "clarification_questions": [],
            "audio_event_candidates": audio_events or [],
        }

    limitation = str(transcription.get("limitation") or "")
    question = "请问视频中需要解决的是哪个机器异常？"
    return {
        "status": "needs_one_clarification",
        "voice_analysis_claimed": bool(transcription.get("voice_analysis_claimed", False)),
        "limitation": limitation or None,
        "evidence_query": query,
        "combined_evidence": combined_evidence,
        "matches": matches,
        "problem": None,
        "answer": f"{limitation}{question}" if limitation else question,
        "clarification_questions": [question],
        "audio_event_candidates": audio_events or [],
    }


def _is_confident_kb_match(match: dict[str, object], minimum_score: float = 60.0) -> bool:
    reasons = [str(reason) for reason in match.get("reasons", [])]
    has_intent = any(
        reason == "high_frequency_exact"
        or reason.startswith("keyword:")
        or reason.startswith("high_risk:")
        for reason in reasons
    )
    has_mismatch = any(reason.startswith("product_mismatch:") for reason in reasons)
    return (
        match.get("type") == "card"
        and float(match.get("score") or 0) >= minimum_score
        and has_intent
        and not has_mismatch
    )
