from __future__ import annotations

import json
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DOC = ROOT / "confirmed_dot_matrix_normal_audio_references_2026_09_08_kb.md"
SOURCE_DIR = ROOT / "sources" / "user_uploads" / "dot_matrix_normal_audio_2026_09_08"
AUDIO_MANIFEST = SOURCE_DIR / "audio_reference_manifest.json"
PROFILES = ROOT / "rag_cards" / "dot_matrix_audio_reference_profiles.json"
CARDS = ROOT / "rag_cards" / "customer_service_rag_cards.jsonl"
HF = ROOT / "rag_cards" / "high_frequency_queries.json"
SEARCH = ROOT / "scripts" / "search_rag.py"
MATCHER = ROOT / "scripts" / "dot_matrix_audio_matcher.py"


EXPECTED_OPERATIONS = {
    "normal_printing",
    "front_paper_manual_pullout",
    "front_paper_feed",
    "printer_power_on",
    "rear_paper_feed",
}

EXPECTED_SOURCE_HASHES = {
    "normal_printing": "267a2e8ffe5fe0acb07bd83a81f942689e495720be6d1b4c78f36d9f74cc50df",
    "front_paper_manual_pullout": "a20f76e21d1c29dc0697706d84b06c3f2bb92a52032273bf732516e5b1a06ee0",
    "front_paper_feed": "03e34bb817998380d1b43caa2a82a18e4b4cf4299ccf4f273cdfbca40a62442d",
    "printer_power_on": "334cc8b1565e5f6c9ee3e9d4d256865398fc566f123db6e44d6be8cf6bfca06a",
    "rear_paper_feed": "779af60195a968d1ce48c9a9a1ac2d2ef3803867dfb98cdde953d96087ddd1cd",
}


def load_cards() -> dict[str, dict]:
    return {
        card["id"]: card
        for card in (
            json.loads(line)
            for line in CARDS.read_text(encoding="utf-8").splitlines()
            if line.strip()
        )
    }


def top(query: str) -> dict:
    result = subprocess.run(
        [sys.executable, str(SEARCH), query, "--json", "--top-k", "1"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)[0]


def write_tone(path: Path, sample_rate: int, seconds: float = 1.0) -> None:
    t = np.arange(round(sample_rate * seconds), dtype=np.float64) / sample_rate
    samples = np.int16(np.clip(0.2 * np.sin(2 * np.pi * 440 * t), -1, 1) * 32767)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(samples.astype("<i2").tobytes())


def test_confirmed_source_and_manifest_preserve_all_five_normal_recordings() -> None:
    assert SOURCE_DOC.is_file()
    manifest = json.loads(AUDIO_MANIFEST.read_text(encoding="utf-8"))
    assert manifest["status"] == "confirmed_normal"
    assert manifest["process_scope"] == "all_dot_matrix_printer_models"
    assert set(manifest["recordings"]) == EXPECTED_OPERATIONS
    for operation, expected_hash in EXPECTED_SOURCE_HASHES.items():
        row = manifest["recordings"][operation]
        assert row["source_sha256"] == expected_hash
        assert (ROOT / row["source_file"]).is_file()
        assert (ROOT / row["review_wav"]).is_file()


def test_profiles_are_context_gated_and_do_not_invent_fault_thresholds() -> None:
    data = json.loads(PROFILES.read_text(encoding="utf-8"))
    assert data["status"] == "confirmed_normal_reference_seed"
    assert data["process_scope"] == "all_dot_matrix_printer_models"
    assert data["context_gate_required"] is True
    assert data["normal_abnormal_threshold"] is None
    assert set(data["profiles"]) == EXPECTED_OPERATIONS
    for profile in data["profiles"].values():
        assert len(profile["active_mel_probability_profile"]) == 48
        assert abs(sum(profile["active_mel_probability_profile"]) - 1.0) < 1e-5


def test_matcher_requires_operation_context_and_self_matches_reference() -> None:
    assert MATCHER.is_file()
    from scripts.dot_matrix_audio_matcher import match_wav

    data = json.loads(PROFILES.read_text(encoding="utf-8"))
    reference = ROOT / data["profiles"]["normal_printing"]["review_wav"]
    missing_context = match_wav(reference, None, PROFILES)
    assert missing_context["status"] == "operation_context_required"

    result = match_wav(reference, "normal_printing", PROFILES)
    assert result["status"] == "descriptive_match_only"
    assert result["operation"] == "normal_printing"
    assert result["spectral_similarity"] >= 0.999
    assert result["normality_decision"] == "not_determined"
    assert result["fault_diagnosis"] == "not_determined"


def test_feature_extraction_is_stable_across_16k_and_48k_review_audio(tmp_path: Path) -> None:
    assert MATCHER.is_file()
    from scripts.dot_matrix_audio_matcher import analyze_wav, cosine_similarity

    tone16 = tmp_path / "tone16.wav"
    tone48 = tmp_path / "tone48.wav"
    write_tone(tone16, 16000)
    write_tone(tone48, 48000)
    p16 = analyze_wav(tone16)
    p48 = analyze_wav(tone48)
    assert p16["quality"]["usable"] is True
    assert p48["quality"]["usable"] is True
    assert cosine_similarity(
        p16["active_mel_probability_profile"],
        p48["active_mel_probability_profile"],
    ) >= 0.98


def test_silent_audio_is_not_treated_as_a_normal_or_abnormal_match(tmp_path: Path) -> None:
    assert MATCHER.is_file()
    from scripts.dot_matrix_audio_matcher import analyze_wav

    silent = tmp_path / "silent.wav"
    with wave.open(str(silent), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(16000)
        output.writeframes(np.zeros(16000, dtype="<i2").tobytes())
    result = analyze_wav(silent)
    assert result["quality"]["usable"] is False
    assert "too_quiet" in result["quality"]["reasons"]


def test_rag_cards_and_queries_enforce_safe_audio_matching() -> None:
    cards = load_cards()
    expected_cards = {
        "dot_matrix_audio_reference_matching",
        "dot_matrix_audio_normal_operation_patterns",
        "dot_matrix_audio_uncertain_no_fault_diagnosis",
    }
    assert expected_cards <= cards.keys()

    matching = cards["dot_matrix_audio_reference_matching"]["reply_template"]
    for phrase in ("所有针式打印机型号", "同一操作", "画面或客户说明", "不能只看平均频谱"):
        assert phrase in matching

    uncertainty = cards["dot_matrix_audio_uncertain_no_fault_diagnosis"]["reply_template"]
    for phrase in ("无法确定", "不代表已经确认故障", "不能定位具体部件", "重新录制"):
        assert phrase in uncertainty

    expected_queries = {
        "针式打印机声音正常吗帮我分析视频": "dot_matrix_audio_reference_matching",
        "开机打印前进纸后进纸的正常声音有什么区别": "dot_matrix_audio_normal_operation_patterns",
        "声音和正常参考不一样能判断哪里坏了吗": "dot_matrix_audio_uncertain_no_fault_diagnosis",
    }
    for query, card_id in expected_queries.items():
        assert top(query)["id"] == card_id

    mapped_ids = {
        row["card_id"]
        for row in json.loads(HF.read_text(encoding="utf-8"))["queries"]
    }
    assert expected_cards <= mapped_ids
