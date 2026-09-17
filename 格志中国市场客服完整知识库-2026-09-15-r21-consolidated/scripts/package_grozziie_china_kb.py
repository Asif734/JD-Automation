#!/usr/bin/env python3
"""Build and verify the complete Grozziie China-market customer-service KB."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from datetime import date
from pathlib import Path
from typing import Iterable

try:
    from scripts.package_version import PACKAGE_ROOT
except ModuleNotFoundError:  # Direct execution from scripts/.
    from package_version import PACKAGE_ROOT

INCLUDE_DIRS = (
    "rag_cards",
    "rag_index",
    "assets/qianniu_video_materials",
    "sources",
    "scripts",
    "tests",
    "docs",
)
ROOT_SUPPORT_SUFFIXES = {".md", ".py", ".json", ".txt"}
EXCLUDED_PARTS = {
    ".git",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "__pycache__",
    "outputs",
    "work",
    "tmp",
    "logs",
}
GENERATED_ROOT_FILES = {"README.md", "PACKAGE_MANIFEST.json"}


def _is_excluded(relative: Path) -> bool:
    return any(part in EXCLUDED_PARTS or part.startswith(".venv") for part in relative.parts)


def collect_package_files(root: Path) -> list[Path]:
    """Return stable, explicit payload files for the formal package."""
    root = root.resolve()
    selected: set[Path] = set()

    for path in root.iterdir():
        if (
            path.is_file()
            and path.suffix.lower() in ROOT_SUPPORT_SUFFIXES
            and path.name not in GENERATED_ROOT_FILES
        ):
            selected.add(path.resolve())

    for directory_name in INCLUDE_DIRS:
        directory = root / directory_name
        if not directory.is_dir():
            continue
        for path in directory.rglob("*"):
            if not path.is_file() or path.is_symlink():
                continue
            relative = path.relative_to(root)
            if _is_excluded(relative) or path.name in {".DS_Store"}:
                continue
            selected.add(path.resolve())

    return sorted(selected, key=lambda item: item.relative_to(root).as_posix())


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _manifest_entries(root: Path, files: Iterable[Path]) -> list[dict[str, object]]:
    return [
        {
            "path": path.relative_to(root).as_posix(),
            "size": path.stat().st_size,
            "sha256": _sha256_file(path),
        }
        for path in files
    ]


def _readme_text(manifest: dict[str, object]) -> str:
    return f"""# 格志中国市场客服完整知识库

生成日期：{manifest['created_on']}

本包用于格志在天猫、京东、拼多多和抖音中国市场的客服检索与售后排障，包含正式知识文档、RAG卡片与索引、国内平台视频截图素材、来源资料、运行脚本和测试。

使用要求：

- 客服回复先给直接答案；简单问题通常1–3句，标准操作通常3–5步，可按实际复杂度调整。只能使用知识库确认过的设置，不得自行编造菜单或参数。
- `all_platform_model_details_2026_09_09_kb.md` 是本版型号、连接、纸张、包装、质保、维修与退换的统一治理源；只导入 Approved/Corrected 记录，不使用 Needs confirmation/Unreviewed 内容对客。
- 规范型号共92个：Current 38、Legacy 42、Discontinued 12。Legacy不等于当前在售；Discontinued仅处理历史售后或配件查询，不作售前推荐。
- TD630售前按蓝牙+USB：手机速印通可蓝牙或2.4GHz Wi-Fi，Windows/Mac电脑均仅USB。TD630G售前按蓝牙+Wi-Fi+USB：Windows可USB或同一2.4GHz局域网Wi-Fi，手机可蓝牙或Wi-Fi，Mac仅USB。不对客披露两型号内部硬件关系。
- 热敏机纸宽按精确型号/SKU使用30–80mm或30–100mm口径；TP876PLUS需核对80mm或104mm购买选项。TP870、TP876不支持macOS；TP870PLUS、TP876PLUS、TP874、TP874S支持macOS USB。
- 热敏机手机端只有千牛和抖音/抖店已确认可直接发起打印；抖音/抖店首次需先在电脑设置PID。拼多多、1688、快手和风火递需先保存文件，再用速印通打开打印。
- 针式机默认整机3年且包含打印头（历史天猫加普威TH850老款/纯USB路线例外1年）；热敏机整机除打印头外1年，热敏打印头只按3个月，不加入里程限制。
- 有偿维修固定参考费：热敏机订单不超1年50元、超过1年80元，针式机150元，考勤机80元；远程安装/排障免费，客服时间08:30–21:00，正常维修约3–5个工作日，有偿维修后另3个月维修服务质保。
- 非质量原因按平台规则申请7天无理由；经核实的质量问题可在30天内按平台规则退换。运费和平台保障是否适用由人工按订单核实，不在自动回复中指示客户选择运费险。
- 文字答案完成后，若产品线、问题主题、系统和当前平台均严格匹配 `rag_cards/china_market_video_catalog.json`，在答案后附加一个当前平台首选视频；待重传、已隔离或有歧义时不加链接，不跨平台替代。
- 视频画面和音频足以确定问题时直接提供分步方案；只有型号或平台会改变操作且无法识别时才补充询问。
- 针式打印机声音分析流程适用于所有针式打印机型号：先确认开机、打印、前进纸、后进纸或手动抽纸，再和同一操作的正常参考比较。当前只有单个正常种子参考，只输出描述性相似度，不设置正常/异常阈值，也不据此定位具体故障。
- 中国市场不得发送YouTube、海外平台视频或英文说明书。
- Windows驱动入口按目的分流：支持手机/WiFi的机型配置WiFi时选Automatic→下一步；安装USB驱动时选USB→搜索→选中设备→下一步。仅USB机型选Auto或USB都可安装USB驱动。
- 当前打印机驱动安装包不按USB、Wi-Fi或蓝牙连接方式区分下载，同一安装包也用于热敏打印机；安装时仍需选择实际检测到且兼容的打印机/连接路径，针式驱动设置不得套用到其他产品线。
- TD630和TD630G均支持前进纸、后进纸和连续纸；同标识面板上，电源键按一下开机、长按关机，进纸/退纸用于后进连续纸走纸，暂停/微退按一下暂停、按住小幅后退，缺纸红灯在纸张正确检测后熄灭。
- 最右绿灯按版本解释：蓝牙/Wi-Fi机型开机后闪烁2–4秒属正常，常亮表示已连接，持续闪烁表示未连接；纯USB机型通常常亮，按暂停键时可能闪烁。
- 手机连接二维码必须在速印通App内扫描，不使用手机系统相机；驱动/教程二维码对应 `https://www.zjweiting.com/download.htm`。
- 网站仍可正常下载驱动、观看视频和查找说明书；只有直接客服联系功能已关闭。指南二维码无法扫描时发送上述已确认下载地址。
- 中国市场针式打印机手机App统一称“速印通”；手机连接优先使用蓝牙，iPhone与Android流程基本相同；客户明确要求Wi-Fi时才按2.4GHz配网指导。
- 所有新款针式打印机色带通用；该结论不扩展到考勤机、热敏产品或未确认老款。针式标准包装含机内预装色带、USB数据线和2张测试纸，这三项无需按具体型号确认。
- 速印通没有缩放选项；已保存的Excel等文件走DotMatrix Printer→Document Printing。二维码连接一直加载时先查打印机电源及App蓝牙/位置权限，再重启打印机和App，不先排查Wi-Fi或手机流量。
- App提示输入IP时点Cancel；先确认开机和放纸，再点Refresh，仍无设备则点右上角打印机图标重连。IP手动输入只用于Windows网络打印异常的内部技术备选。
- 包装内含两张测试纸，正式用纸另购；支持100–241mm宽、总厚度不超过0.45mm、长度不限及1–6联，覆盖市面95%以上常用针式打印纸。
- 连续纸孔位如O--O--O时，第一孔到第三孔中心距约1英寸，即相邻孔中心距约0.5英寸。
- 常见连续纸实际纸宽约241mm，对应驱动预设宽度为240mm。`holes 22/3`表示22陥以3，约7⅓个孔位间隔，不是22或23孔。
- 后进出纸基准：三等分1页约7⅓、2页约14–15、3页约22个孔位间隔；二等分1页约11个孔位间隔。该数值只是诊断基准，页面、驱动纸型和固定页高仍须一致。
- 后进连续纸待机时前方只露出一小段窄纸边；前进单页纸到内部钢杆处属正常，前盖关闭时约5厘米被吸入。明显超过这些位置才按异常进纸处理。
- Windows针式打印机驱动纸张设置路径：打印首选项→高级→纸张/输出→纸张规格；再进入Configure选择固定页面高度，点击导入后确定。
- 固定页高常用值：三等分93.1mm（holes 22/3）、101.6mm（holes 8）、127mm（holes 10）、二等分139.7mm（holes 11）、整张279.4mm（holes 22）。
- 修改固定页高、孔数或纸张规格后，必须完全关闭并重新打开打印软件，再取出纸张并正确重新装入后测试。
- 多条竖向笔画在同一高度出现清晰、连续且固定的横向白线，可直接判断打印头针断裂并返厂维修；只有不清楚或不稳定时才用无色带多联纸查看第二联。
- 客户只说“打印有白线”且无法识别产品线时，只确认一次机器型号或类型；不得直接套用热敏机话术。
- 连续打印时打印头发热通常正常；反复停止、烧焦味、冒烟或异常声音时立即暂停并转人工。
- 卡纸排查时纸厚扳手调到最高第6档；打印头动一下停一下再继续时优先清理SPOOL/printers隐藏任务。
- 针式打印机不开机时保持简洁：更换正常工作的电源插座、长按电源按钮尝试开机，仍不开机则转人工客服申请维修。
- 连续纸第一份正确但第二份标题落在撕纸线时，按实际撕纸线间距设置固定页高；保存后完全关闭并重新打开打印软件，再取出纸张并正确重新装入后连续打印两份客户表单；此专项不需要另外打印Windows测试页。
- 手机App预览已缺笔画时调整字体和对比度，预览中表格线缺失时增加线条粗细。
- TD630/TD630G的Mac驱动必须先安装，再到系统中添加打印机；正式下载地址为 `https://zjweiting.com/nobel/apk/MacDriver.pkg`。
- 白色宽排线自然弯曲属于正常状态，不得拉直或调整；卡纸时将纸厚杆调到最高档、取下色带并查看多联纸第二联，仍有横线或卡纸则返厂维修。
- 预印表格套打必须匹配实际纸张宽度和长度，并分别调整水平和垂直偏移。
- 车载/逆变器使用需要至少200W功率输出，并使用机器内置电源线连接稳定且符合额定输入的AC输出。
- 连续纸后进纸仅用于支持型号：左右各三个孔套入拖纸器后按中间走纸键；不支持型号不得发送本步骤。
- 乱码优先清理SPOOL/printers隐藏任务并检查USB松动、系统兼容性和Mac驱动。
- 前后进纸一次吸入半张以上或打印后大量吐纸时，关机清理对应传感器。
- USB单一连接版本没有本机自检功能，不要求执行不存在的自检。
- 打印中突然关机时，支持自检的型号先读取自检页和固件版本，升级旧固件后复测；仍关机则返厂维修。
- 第三方开单App直接打印空白或乱码时不建议购买云盒；先导出文件，再用速印通打开打印或使用内置模板。
- 客户提出版式制作需求时，收集纸张照片、尺寸及电脑/App使用环境，并主动提供模板制作服务。
- 已批准质量问题运费报销使用经济型快递，不到付、不发顺丰或其他高价快递，保存凭证并按批准上限转人工核实。
- 速印通本地模板可重复使用但不能导出、分享、同步或跨手机转移；客服后台模板仅在客户以前申请过时按对应订单编号搜索。
- 正确设置软件页面尺寸、驱动纸张规格、固定页高并正确进纸后，连续纸会自动到正确撕纸位置；只剩少量偏差时用Configure的tear-off position按2mm微调。D-label主要用于热敏标签打印机，通常不用于针式打印机。
- 统一版Windows针式驱动适用于支持的USB、Wi-Fi和蓝牙型号；整页偏移使用Horizontal/Vertical adjustment，提速使用DPI:180*144或取消勾选One-way printing。不得编造未展示设置。
- 只有京东自营店铺支持对公转账；好评奖励按拼多多、天猫/京东以及考勤机/针式打印机的已确认规则处理。
- 低质量PDF整体发灰或类似重影时使用高质量原文件并降低灰度阈值/手机对比度，不使用单向打印；速印通表格边框缺失时把线条粗细调为0.6或0.7。
- Windows显示设备描述符请求失败时先换USB接口再换数据线；安装程序提示没有匹配的驱动时先在设备和打印机确认设备，已出现则手动安装。
- TH880仅支持USB连接Windows；TD630G多台Windows电脑安装驱动时选择Automatic，由安装程序自动识别IP端口。
- 所有发票税率统一为13%；增值税专票需一般纳税人资料并转人工财务。
- 证据不足或有多个处理分支时，每轮只问一个最能区分路径的问题。
- 考勤机自检中的“1号键”和“+增加键”指同一个实体按键。
- 09组最晚设为05:59；延后30分钟超过该上限时直接设05:59，并要求员工在05:59前打卡。
- 多团队真实班次重叠时先按交集计算共享班次；最终输入机器的自动班次仍不得重叠，且相邻班次至少间隔30分钟。
- 卡片吸入后退卡不打印时，使用原装卡并暂设15组00、09组00:00测试；09组只能在00:00–05:59之间，测试后按班次恢复。
- 5004是打印头卡住或不能移动的错误代码；通电只观察，清除内部异物前关机拔电。
- 同一印迹红黑混色属于异常；固定位置白线在原装卡自检后仍重复时可能需要维修打印头。
- 知识库没有对应信息、安全问题、明确退款、明确改变收货地址或排障完成仍未解决时，按统一规则转人工。
- `PACKAGE_MANIFEST.json` 记录每个有效载荷文件的相对路径、大小和SHA-256，可用于完整性复核。

有效载荷文件数：{manifest['file_count']}
有效载荷未压缩字节数：{manifest['uncompressed_size']}
"""


def build_package(root: Path, output_zip: Path, *, sync_metadata: bool = True) -> dict[str, object]:
    root = root.resolve()
    output_zip = output_zip.resolve()
    files = collect_package_files(root)
    if not files:
        raise ValueError(f"no package files found under {root}")

    entries = _manifest_entries(root, files)
    manifest: dict[str, object] = {
        "package_name": PACKAGE_ROOT,
        "created_on": date.today().isoformat(),
        "file_count": len(entries),
        "uncompressed_size": sum(int(item["size"]) for item in entries),
        "files": entries,
    }
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    readme_bytes = _readme_text(manifest).encode("utf-8")

    if sync_metadata:
        # Release builds synchronize the unpacked metadata. Unit tests can set
        # sync_metadata=False so constructing a temporary archive is read-only.
        (root / "PACKAGE_MANIFEST.json").write_bytes(manifest_bytes)
        (root / "README.md").write_bytes(readme_bytes)

    output_zip.parent.mkdir(parents=True, exist_ok=True)
    # Use stored entries for deterministic integrity on large mixed-media packages.
    # Deflated archives intermittently produced CRC readback errors on the local
    # synchronized workspace even though the source files and SHA-256 values were stable.
    with zipfile.ZipFile(output_zip, "w", compression=zipfile.ZIP_STORED) as archive:
        archive.writestr(f"{PACKAGE_ROOT}/README.md", readme_bytes)
        archive.writestr(f"{PACKAGE_ROOT}/PACKAGE_MANIFEST.json", manifest_bytes)
        for path in files:
            relative = path.relative_to(root).as_posix()
            archive.write(path, f"{PACKAGE_ROOT}/{relative}")

    report: dict[str, object] = {
        "output": str(output_zip),
        "file_count": len(entries),
        "uncompressed_size": manifest["uncompressed_size"],
        "zip_size": output_zip.stat().st_size,
        "zip_sha256": _sha256_file(output_zip),
        "asset_file_count": sum(item["path"].startswith("assets/") for item in entries),
        "source_file_count": sum(item["path"].startswith("sources/") for item in entries),
    }
    return report


def verify_package(package: Path) -> dict[str, object]:
    package = package.resolve()
    with zipfile.ZipFile(package) as archive:
        bad_file = archive.testzip()
        if bad_file is not None:
            raise ValueError(f"corrupt archive member: {bad_file}")
        manifest_name = f"{PACKAGE_ROOT}/PACKAGE_MANIFEST.json"
        manifest = json.loads(archive.read(manifest_name))
        for item in manifest["files"]:
            archive_name = f"{PACKAGE_ROOT}/{item['path']}"
            content = archive.read(archive_name)
            if len(content) != item["size"]:
                raise ValueError(f"size mismatch: {item['path']}")
            if hashlib.sha256(content).hexdigest() != item["sha256"]:
                raise ValueError(f"sha256 mismatch: {item['path']}")

    return {
        "verified": True,
        "file_count": manifest["file_count"],
        "uncompressed_size": manifest["uncompressed_size"],
        "zip_size": package.stat().st_size,
        "zip_sha256": _sha256_file(package),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--verify", action="store_true", help="verify every manifest hash after building")
    args = parser.parse_args()

    report = build_package(args.root, args.output)
    if args.verify:
        report["verification"] = verify_package(args.output)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
