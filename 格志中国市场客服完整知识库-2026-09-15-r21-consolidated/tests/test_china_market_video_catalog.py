from __future__ import annotations

from urllib.parse import urlparse

from tutorial_video_catalog import load_catalog, match_tutorial, validate_catalog


ALLOWED_HOSTS = {
    "JD": {"vod.300hu.com", "jvod.300hu.com"},
    "Tmall": {"cloud.video.taobao.com"},
    "Pinduoduo": {"video5.pddpic.com"},
}


def test_catalog_preserves_all_confirmed_assignments_and_audit_exceptions() -> None:
    catalog = load_catalog()
    summary = validate_catalog(catalog)

    assert summary == {
        "topics": 83,
        "active_primary_links": 204,
        "active_alternate_links": 1,
        "pending_assignments": 8,
        "quarantined_assignments": 1,
    }
    assert catalog["source_files"][0]["sha256"] == (
        "92b8ad5960971caf88e23925e938e4bfa1ab5700eb39d6867812d722d7825127"
    )


def test_every_active_link_uses_the_host_for_its_own_platform() -> None:
    catalog = load_catalog()
    for entry in catalog["entries"]:
        for platform, url in entry["platform_urls"].items():
            assert (urlparse(url).hostname or "").lower() in ALLOWED_HOSTS[platform]
        for platform, urls in entry.get("alternate_platform_urls", {}).items():
            for url in urls:
                assert (urlparse(url).hostname or "").lower() in ALLOWED_HOSTS[platform]


def test_duplicate_jd_link_is_kept_for_speed_and_not_driver_package_deletion() -> None:
    speed = match_tutorial(
        "Win11打印速度太慢，怎么调节打印速度？",
        "京东",
        product_line="thermal_printer",
    )
    deletion = match_tutorial(
        "Win11手动删除驱动时无法删除安装包，怎么解决？",
        "京东",
        product_line="thermal_printer",
    )
    tmall_deletion = match_tutorial(
        "Win11手动删除驱动时无法删除安装包，怎么解决？",
        "天猫",
        product_line="thermal_printer",
    )

    assert speed is not None
    assert speed["source_cells"] == ["Sheet1!E63"]
    assert speed["video_url"].endswith("3cbb5389717f4aedb621fdf1ed2eb066.mp4")
    assert deletion is None
    assert tmall_deletion is not None
    assert tmall_deletion["source_cells"] == ["Sheet1!E149"]


def test_pending_pinduoduo_link_is_not_emitted_and_other_platform_still_matches() -> None:
    pdd = match_tutorial(
        "测试打印并查看打印机IP地址",
        "拼多多",
        product_line="wifi_bluetooth_dot_matrix_printer",
    )
    jd = match_tutorial(
        "测试打印并查看打印机IP地址",
        "京东",
        product_line="wifi_bluetooth_dot_matrix_printer",
    )

    assert pdd is None
    assert jd is not None
    assert jd["source_cells"] == ["Sheet1!E38"]


def test_ribbon_match_uses_existing_confirmed_tmall_link_and_keeps_workbook_link_alternate() -> None:
    match = match_tutorial(
        "针式打印机色带怎么更换？",
        "天猫",
        product_line="dot_matrix_printer",
    )

    assert match is not None
    assert match["video_url"] == (
        "https://cloud.video.taobao.com/vod/"
        "RZwoZfAVTYHTqRO4MjSrj1pp1PAGRMdQI45fvIOwWZk.mp4"
    )
    assert match["alternate_video_urls"] == [
        "http://cloud.video.taobao.com/play/u/null/p/1/e/6/t/1/491049700762.mp4"
    ]


def test_thermal_sequence_labels_are_not_exposed_as_models() -> None:
    catalog = load_catalog()
    thermal = [entry for entry in catalog["entries"] if entry["product_line"] == "thermal_printer"]

    assert len(thermal) == 40
    assert {entry["operating_system"] for entry in thermal} == {"Windows 10", "Windows 11"}
    assert all(entry["models"] == [] for entry in thermal)
    assert any("w10 Thermal Printer" in entry["source_labels"] for entry in thermal)


def test_ambiguous_generic_request_does_not_guess_a_tutorial() -> None:
    assert match_tutorial("驱动怎么弄？", "天猫") is None

