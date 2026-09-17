#!/usr/bin/env python3
"""Create and compare context-gated dot-matrix printer sound profiles.

The matcher intentionally returns descriptive similarity only.  The confirmed
dataset contains one normal seed recording per operation, so it cannot support
a learned normal/abnormal threshold or fault-specific diagnosis yet.
"""

from __future__ import annotations

import argparse
import json
import math
import wave
from hashlib import sha256
from pathlib import Path
from typing import Sequence

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PROFILES = ROOT / "rag_cards" / "dot_matrix_audio_reference_profiles.json"
MEL_BANDS = 48
FMIN_HZ = 100.0
FMAX_HZ = 7500.0
FRAME_SECONDS = 2048 / 48000
HOP_SECONDS = 512 / 48000


def sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_pcm_wav(path: Path) -> tuple[np.ndarray, int]:
    """Read mono/stereo 16-bit PCM WAV and return normalized mono samples."""
    path = Path(path)
    with wave.open(str(path), "rb") as source:
        if source.getsampwidth() != 2:
            raise ValueError("only 16-bit PCM WAV is supported")
        channels = source.getnchannels()
        sample_rate = source.getframerate()
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
    if channels < 1:
        raise ValueError("WAV has no channels")
    if len(samples) % channels:
        raise ValueError("invalid interleaved PCM sample count")
    audio = samples.astype(np.float32).reshape(-1, channels).mean(axis=1) / 32768.0
    return audio, sample_rate


def _hz_to_mel(hz: np.ndarray | float) -> np.ndarray:
    return 2595.0 * np.log10(1.0 + np.asarray(hz) / 700.0)


def _mel_to_hz(mel: np.ndarray | float) -> np.ndarray:
    return 700.0 * (10.0 ** (np.asarray(mel) / 2595.0) - 1.0)


def _mel_filterbank(sample_rate: int, n_fft: int) -> tuple[np.ndarray, np.ndarray]:
    nyquist = sample_rate / 2
    if nyquist <= FMIN_HZ:
        raise ValueError("sample rate is too low for audio matching")
    fmax = min(FMAX_HZ, nyquist * 0.95)
    freqs = np.fft.rfftfreq(n_fft, 1 / sample_rate)
    edges = _mel_to_hz(
        np.linspace(_hz_to_mel(FMIN_HZ), _hz_to_mel(fmax), MEL_BANDS + 2)
    )
    filters = np.zeros((MEL_BANDS, len(freqs)), dtype=np.float32)
    for index in range(MEL_BANDS):
        left, center, right = edges[index : index + 3]
        rising = (freqs - left) / max(center - left, 1e-12)
        falling = (right - freqs) / max(right - center, 1e-12)
        filters[index] = np.maximum(0.0, np.minimum(rising, falling))
        weight = filters[index].sum()
        if weight:
            filters[index] /= weight
    return filters, edges[1:-1]


def _runs(mask: np.ndarray) -> list[tuple[int, int]]:
    changes = np.diff(np.pad(mask.astype(np.int8), (1, 1)))
    starts = np.flatnonzero(changes == 1)
    ends = np.flatnonzero(changes == -1)
    return list(zip(starts.tolist(), ends.tolist()))


def _merge_active(mask: np.ndarray, sample_rate: int) -> np.ndarray:
    max_gap = max(1, round(0.12 / HOP_SECONDS))
    min_length = max(1, round(0.06 / HOP_SECONDS))
    padding = max(1, round(0.04 / HOP_SECONDS))
    merged: list[list[int]] = []
    for start, end in _runs(mask):
        if merged and start - merged[-1][1] <= max_gap:
            merged[-1][1] = end
        else:
            merged.append([start, end])
    output = np.zeros_like(mask, dtype=bool)
    for start, end in merged:
        if end - start >= min_length:
            output[max(0, start - padding) : min(len(mask), end + padding)] = True
    return output


def _round_list(values: Sequence[float], digits: int = 9) -> list[float]:
    return [round(float(value), digits) for value in values]


def cosine_similarity(left: Sequence[float], right: Sequence[float]) -> float:
    a = np.asarray(left, dtype=np.float64)
    b = np.asarray(right, dtype=np.float64)
    if a.shape != b.shape:
        raise ValueError("profile dimensions do not match")
    denominator = float(np.linalg.norm(a) * np.linalg.norm(b))
    return float(np.dot(a, b) / denominator) if denominator else 0.0


def analyze_wav(path: Path) -> dict[str, object]:
    """Extract amplitude-normalized active-span features from a review WAV."""
    path = Path(path)
    audio, sample_rate = read_pcm_wav(path)
    duration = len(audio) / sample_rate if sample_rate else 0.0
    rms = float(np.sqrt(np.mean(audio * audio) + 1e-15)) if len(audio) else 0.0
    rms_dbfs = 20 * math.log10(rms + 1e-15)
    clipped_fraction = float(np.mean(np.abs(audio) >= 0.999)) if len(audio) else 0.0
    quality_reasons: list[str] = []
    if duration < 0.5:
        quality_reasons.append("too_short")
    if rms_dbfs < -55:
        quality_reasons.append("too_quiet")
    if clipped_fraction > 0.05:
        quality_reasons.append("severe_clipping")

    frame_size = max(64, round(FRAME_SECONDS * sample_rate))
    hop_size = max(16, round(HOP_SECONDS * sample_rate))
    n_fft = 1 << (frame_size - 1).bit_length()
    if len(audio) < frame_size:
        audio = np.pad(audio, (0, frame_size - len(audio)))
    frames = np.lib.stride_tricks.sliding_window_view(audio, frame_size)[::hop_size]
    window = np.hanning(frame_size).astype(np.float32)
    filters, centers = _mel_filterbank(sample_rate, n_fft)
    frame_count = len(frames)
    mel_power = np.empty((frame_count, MEL_BANDS), dtype=np.float32)
    match_energy_db = np.empty(frame_count, dtype=np.float32)
    zcr = np.empty(frame_count, dtype=np.float32)
    centroid = np.empty(frame_count, dtype=np.float32)
    frequencies = np.fft.rfftfreq(n_fft, 1 / sample_rate)
    matching_bins = (frequencies >= FMIN_HZ) & (frequencies <= min(FMAX_HZ, sample_rate * 0.475))

    for start in range(0, frame_count, 512):
        stop = min(frame_count, start + 512)
        batch = np.asarray(frames[start:stop], dtype=np.float32)
        zcr[start:stop] = np.mean(
            np.signbit(batch[:, 1:]) != np.signbit(batch[:, :-1]), axis=1
        )
        spectrum = np.fft.rfft(batch * window, n=n_fft, axis=1)
        power = (np.abs(spectrum) ** 2).astype(np.float32)
        mel_power[start:stop] = power @ filters.T
        selected = power[:, matching_bins]
        totals = selected.sum(axis=1) + 1e-20
        match_energy_db[start:stop] = 10 * np.log10(totals)
        centroid[start:stop] = (
            selected * frequencies[matching_bins]
        ).sum(axis=1) / totals

    valid = np.isfinite(match_energy_db)
    floor = float(np.percentile(match_energy_db[valid], 20))
    p95 = float(np.percentile(match_energy_db[valid], 95))
    spread = p95 - floor
    if spread < 1.0:
        active = valid.copy()
        threshold = floor
    else:
        threshold = floor + max(4.0, 0.30 * spread)
        active = valid & (match_energy_db >= threshold)
    active = _merge_active(active, sample_rate)
    if not active.any():
        quality_reasons.append("no_active_event")
        active = valid

    active_mel = mel_power[active] + 1e-20
    distributions = active_mel / active_mel.sum(axis=1, keepdims=True)
    profile = np.median(distributions, axis=0)
    profile_sum = float(profile.sum())
    if profile_sum:
        profile /= profile_sum
    spans = _runs(active)
    span_durations = np.array(
        [(end - start) * hop_size / sample_rate for start, end in spans],
        dtype=np.float64,
    )
    return {
        "path": str(path.resolve()),
        "sha256": sha256_file(path),
        "sample_rate_hz": sample_rate,
        "duration_s": round(duration, 6),
        "quality": {
            "usable": not quality_reasons,
            "reasons": quality_reasons,
            "rms_dbfs": round(rms_dbfs, 3),
            "clipped_sample_fraction": round(clipped_fraction, 8),
        },
        "matching_band_hz": [FMIN_HZ, min(FMAX_HZ, sample_rate * 0.475)],
        "active_frame_ratio": round(float(active.mean()), 6),
        "detected_span_count": len(spans),
        "span_duration_median_s": round(float(np.median(span_durations)), 3)
        if len(span_durations)
        else 0.0,
        "spectral_centroid_hz_median": round(float(np.median(centroid[active])), 1),
        "zero_crossing_rate_median": round(float(np.median(zcr[active])), 6),
        "active_mel_centers_hz": _round_list(centers, 2),
        "active_mel_probability_profile": _round_list(profile),
        "event_detection_threshold_relative_db": round(threshold, 3),
    }


def build_reference_profiles(manifest_path: Path, output_path: Path) -> dict[str, object]:
    """Build reproducible machine-readable profiles from a confirmed manifest."""
    manifest_path = Path(manifest_path).resolve()
    root = manifest_path.parents[3]
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("status") != "confirmed_normal":
        raise ValueError("audio manifest is not confirmed_normal")
    profiles: dict[str, object] = {}
    for operation, row in manifest["recordings"].items():
        review_wav = root / row["review_wav"]
        if sha256_file(root / row["source_file"]) != row["source_sha256"]:
            raise ValueError(f"source hash mismatch for {operation}")
        if sha256_file(review_wav) != row["review_wav_sha256"]:
            raise ValueError(f"review WAV hash mismatch for {operation}")
        analysis = analyze_wav(review_wav)
        profiles[operation] = {
            "description": row["description"],
            "source_file": row["source_file"],
            "source_sha256": row["source_sha256"],
            "review_wav": row["review_wav"],
            "review_wav_sha256": row["review_wav_sha256"],
            "sample_rate_hz": analysis["sample_rate_hz"],
            "duration_s": analysis["duration_s"],
            "active_frame_ratio": analysis["active_frame_ratio"],
            "detected_span_count": analysis["detected_span_count"],
            "span_duration_median_s": analysis["span_duration_median_s"],
            "spectral_centroid_hz_median": analysis["spectral_centroid_hz_median"],
            "zero_crossing_rate_median": analysis["zero_crossing_rate_median"],
            "active_mel_centers_hz": analysis["active_mel_centers_hz"],
            "active_mel_probability_profile": analysis["active_mel_probability_profile"],
        }
    payload: dict[str, object] = {
        "version": "2026-09-08-r13",
        "status": "confirmed_normal_reference_seed",
        "process_scope": "all_dot_matrix_printer_models",
        "connection_scope": ["USB", "Bluetooth", "Wi-Fi"],
        "context_gate_required": True,
        "matching_band_hz": [FMIN_HZ, FMAX_HZ],
        "normal_abnormal_threshold": None,
        "fault_specific_labels_available": False,
        "safe_use": "Descriptive comparison with the same operation only. A mismatch is not a confirmed fault.",
        "profiles": profiles,
    }
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return payload


def match_wav(
    wav_path: Path,
    operation: str | None,
    profiles_path: Path = DEFAULT_PROFILES,
) -> dict[str, object]:
    """Compare one review WAV to the confirmed seed for the same operation."""
    references = json.loads(Path(profiles_path).read_text(encoding="utf-8"))
    if not operation:
        return {
            "status": "operation_context_required",
            "available_operations": sorted(references["profiles"]),
            "normality_decision": "not_determined",
            "fault_diagnosis": "not_determined",
        }
    if operation not in references["profiles"]:
        return {
            "status": "unknown_operation",
            "operation": operation,
            "available_operations": sorted(references["profiles"]),
            "normality_decision": "not_determined",
            "fault_diagnosis": "not_determined",
        }
    observed = analyze_wav(Path(wav_path))
    if not observed["quality"]["usable"]:
        return {
            "status": "unusable_audio",
            "operation": operation,
            "quality": observed["quality"],
            "normality_decision": "not_determined",
            "fault_diagnosis": "not_determined",
        }
    reference = references["profiles"][operation]
    similarity = cosine_similarity(
        observed["active_mel_probability_profile"],
        reference["active_mel_probability_profile"],
    )
    return {
        "status": "descriptive_match_only",
        "operation": operation,
        "spectral_similarity": round(similarity, 6),
        "observed": {
            key: observed[key]
            for key in (
                "duration_s",
                "active_frame_ratio",
                "detected_span_count",
                "span_duration_median_s",
                "spectral_centroid_hz_median",
                "zero_crossing_rate_median",
            )
        },
        "reference": {
            "source_sha256": reference["source_sha256"],
            "description": reference["description"],
        },
        "normality_decision": "not_determined",
        "fault_diagnosis": "not_determined",
        "reason": "One confirmed normal seed per operation is insufficient to set a normal/abnormal threshold or diagnose a component fault.",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    analyze_parser = subparsers.add_parser("analyze")
    analyze_parser.add_argument("wav", type=Path)
    match_parser = subparsers.add_parser("match")
    match_parser.add_argument("wav", type=Path)
    match_parser.add_argument("--operation")
    match_parser.add_argument("--profiles", type=Path, default=DEFAULT_PROFILES)
    build_parser = subparsers.add_parser("build")
    build_parser.add_argument("manifest", type=Path)
    build_parser.add_argument("output", type=Path)
    args = parser.parse_args()
    if args.command == "analyze":
        result = analyze_wav(args.wav)
    elif args.command == "match":
        result = match_wav(args.wav, args.operation, args.profiles)
    else:
        result = build_reference_profiles(args.manifest, args.output)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
