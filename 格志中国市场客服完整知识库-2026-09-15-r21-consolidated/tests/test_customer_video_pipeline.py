from pathlib import Path
import json
import subprocess

import av
import imageio_ffmpeg
import pytest
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]


def test_video_dependency_contract_names_required_packages() -> None:
    requirements = (ROOT / "requirements-video.txt").read_text(encoding="utf-8")
    for package in ("av", "Pillow", "imageio-ffmpeg"):
        assert package in requirements


def test_short_clip_uses_dense_sampling_and_retains_endpoints() -> None:
    from scripts.customer_video_pipeline import adaptive_interval, sample_timestamps

    assert adaptive_interval(4.0) == 0.25
    stamps = sample_timestamps(4.0, 0.5)
    assert stamps[0] == 0.0
    assert stamps[-1] == 4.0
    assert len(stamps) >= 9
    assert stamps == sorted(set(stamps))


def test_adaptive_intervals_cover_customer_and_tutorial_lengths() -> None:
    from scripts.customer_video_pipeline import adaptive_interval

    assert adaptive_interval(20.0) == 0.5
    assert adaptive_interval(120.0) == 1.0
    assert adaptive_interval(600.0) == 2.0
    assert adaptive_interval(901.0) == 5.0
    assert adaptive_interval(20.0, dense=True) == 0.25


def make_test_video(path: Path, seconds: int = 4, rate: int = 8) -> None:
    container = av.open(str(path), mode="w")
    stream = container.add_stream("mpeg4", rate=rate)
    stream.width, stream.height, stream.pix_fmt = 160, 120, "yuv420p"
    for index in range(seconds * rate):
        image = Image.new("RGB", (160, 120), (index * 5 % 255, 40, 80))
        frame = av.VideoFrame.from_image(image)
        for packet in stream.encode(frame):
            container.mux(packet)
    for packet in stream.encode():
        container.mux(packet)
    container.close()


def test_probe_video_reports_real_metadata_and_hash(tmp_path: Path) -> None:
    from scripts.customer_video_pipeline import probe_video

    source = tmp_path / "sample.mp4"
    make_test_video(source)
    metadata = probe_video(source)
    assert 3.8 <= metadata.duration <= 4.2
    assert (metadata.width, metadata.height) == (160, 120)
    assert metadata.video_codec
    assert len(metadata.sha256) == 64


def test_prepare_video_creates_complete_timestamped_package(tmp_path: Path) -> None:
    from scripts.customer_video_pipeline import prepare_video

    source = tmp_path / "four-seconds.mp4"
    make_test_video(source)
    before = source.read_bytes()
    result = prepare_video(source, tmp_path / "out")
    metadata = json.loads(result.metadata_path.read_text(encoding="utf-8"))
    evidence = json.loads(result.evidence_path.read_text(encoding="utf-8"))
    assert len(result.frame_paths) >= 17
    assert result.contact_sheet_paths
    assert metadata["source_sha256"] == evidence["source_sha256"]
    assert all("timestamp_seconds" in item for item in evidence["frames"])
    assert "待用户确认" in result.draft_path.read_text(encoding="utf-8")
    assert source.read_bytes() == before


def test_prepare_video_with_aac_audio_creates_review_wav(tmp_path: Path) -> None:
    from scripts.customer_video_pipeline import prepare_video

    source = tmp_path / "with-audio.mp4"
    subprocess.run(
        [
            imageio_ffmpeg.get_ffmpeg_exe(),
            "-y",
            "-f",
            "lavfi",
            "-i",
            "color=c=blue:s=160x120:d=1",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=1",
            "-c:v",
            "mpeg4",
            "-c:a",
            "aac",
            "-shortest",
            str(source),
        ],
        capture_output=True,
        check=True,
    )
    result = prepare_video(source, tmp_path / "out")
    assert result.audio_path is not None
    assert result.audio_path.stat().st_size > 44


def test_mainstream_video_decoders_are_preinstalled() -> None:
    required = {"h264", "hevc", "vp8", "vp9", "av1", "mpeg4", "mjpeg", "prores"}
    assert required <= av.codecs_available


@pytest.mark.parametrize(
    ("extension", "encoder"),
    [
        ("mp4", "libx264"),
        ("mov", "libx265"),
        ("mkv", "libx264"),
        ("webm", "libvpx-vp9"),
        ("avi", "mjpeg"),
    ],
)
def test_generated_container_codec_matrix_is_readable(
    tmp_path: Path, extension: str, encoder: str
) -> None:
    from scripts.customer_video_pipeline import prepare_video

    source = tmp_path / f"matrix.{extension}"
    completed = subprocess.run(
        [
            imageio_ffmpeg.get_ffmpeg_exe(),
            "-y",
            "-f",
            "lavfi",
            "-i",
            "testsrc=size=160x120:rate=8:duration=1",
            "-c:v",
            encoder,
            "-pix_fmt",
            "yuv420p",
            str(source),
        ],
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        pytest.skip(f"encoder {encoder} unavailable: {completed.stderr[-300:]}")
    result = prepare_video(source, tmp_path / "out", extract_audio=False)
    assert result.frame_paths
    assert result.contact_sheet_paths
