#!/usr/bin/env python3
"""Local HTTP API for the客服 RAG knowledge base.

This intentionally uses only the Python standard library so it can run on a
fresh Mac without installing FastAPI/Uvicorn first.
"""

from __future__ import annotations

import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from scripts.search_rag import search
from video_materials import PlatformRequiredError, VideoMaterialError, match_video_material


ROOT = Path(__file__).resolve().parent
INDEX_PATH = ROOT / "rag_index/customer_service_rag_index.json"
INDEX = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
MIN_AUTO_REPLY_SCORE = 60


def normalize_text(text: str) -> str:
    return re.sub(r"\s+", "", text.lower())


def quick_result(card_id: str, reply: str, *, risk_level: str = "low", auto_reply_allowed: bool = True) -> dict:
    return {
        "reply": reply,
        "risk_level": risk_level,
        "auto_reply_allowed": auto_reply_allowed,
        "confidence": "high",
        "score": 999,
        "actions": [],
        "sources": ["quick_answer"],
        "matches": [{"id": card_id, "type": "quick_answer"}],
    }


def has_attendance_context(message: str, product: str | None = None) -> bool:
    text = normalize_text(" ".join(part for part in [product or "", message] if part))
    return any(term in text for term in ["考勤", "打卡", "m880", "纸卡", "上下班", "班次", "响铃", "工时", "挂墙", "壁挂"])


def quick_answer(message: str, product: str | None = None) -> dict | None:
    compact = normalize_text(message)
    attendance = has_attendance_context(message, product)

    if re.search(r"^(ok|okay|好的|好|可以|行|谢谢|感谢|很棒|不错|收到|明白)$", compact, re.I):
        return quick_result("quick_answer_ack", "亲，不客气哈，有问题随时发我，我这边继续帮您看。")

    if any(term in compact for term in ["看不懂", "不会弄", "不会设置", "不明白", "看不明白"]):
        return quick_result("quick_answer_need_step", "亲，没关系哈。您把机器型号和现在卡在哪一步拍给我，我按步骤带您看。")

    if any(term in compact for term in ["转人工", "转人", "人工", "主账号", "转到主账号"]):
        return quick_result("quick_answer_handoff", "亲，可以的，我这边先帮您记录，稍后让对应同事继续跟进。", risk_level="medium", auto_reply_allowed=False)

    if any(term in compact for term in ["看的是考勤机", "是考勤机", "考勤机哦"]):
        return quick_result("quick_answer_attendance_context_confirm", "亲，好的，我按考勤机给您看哈。您现在主要想确认色带、纸卡、时间设置还是班次？")

    if attendance and any(term in compact for term in ["多少个人", "多少人", "支持几个人", "几个人用", "几人用", "员工数量", "人数"]):
        return quick_result("quick_answer_attendance_user_capacity", "亲，这款纸卡考勤机一般支持 50 人左右使用哈，适合小店、办公室日常打卡。")

    if attendance and any(term in compact for term in ["只能用你们的卡纸", "只能用原装卡", "必须用你们的卡", "必须原装卡", "其他卡纸", "外面的卡纸", "外购卡"]):
        return quick_result("quick_answer_attendance_card_compatibility", "亲，不一定非要用我们家的卡纸哈。只要尺寸、厚度和卡位一致就可以用；不一致的话可能会打印位置不准或卡纸。")

    if attendance and any(term in compact for term in ["计算工时", "算工时", "统计工时", "总工时"]):
        return quick_result("quick_answer_attendance_work_hours", "亲，普通纸卡考勤机主要是在卡上打印上下班时间，月底按卡上记录核对；是否自动统计/计算工时要看具体版本和软件功能。")

    if attendance and any(term in compact for term in ["卡纸多宽", "纸卡多宽", "考勤卡多宽", "卡纸尺寸", "纸卡尺寸", "考勤卡尺寸"]):
        return quick_result("quick_answer_attendance_card_size", "亲，原装考勤卡规格参考是高约 18.5cm、宽约 8.5cm。外购卡也要尺寸一致，不然可能识别或打印位置不准哈。")

    if attendance and any(term in compact for term in ["能挂着", "可以挂", "挂墙", "壁挂", "上墙", "挂起来", "挂着吗"]):
        return quick_result("quick_answer_attendance_wall_mount", "亲，可以的，这款考勤机可以放桌面，也可以挂墙使用。挂墙时注意电源线和插卡位置留好空间就行哈。")

    if any(term in compact for term in ["都打黑色", "全部黑色", "全打黑色", "只打黑色", "不打红色", "不要红色", "可以黑色"]) or ("打黑" in compact):
        return quick_result("quick_answer_attendance_black_print", "亲，可以尽量设置成黑色。一般手动选择打卡列时是黑色；如果用自动判断迟到/早退，异常打卡可能会显示红色哈。")

    if any(term in compact for term in ["打红色", "红色打印", "打印红色", "什么情况红色", "什么情况可以打红色"]):
        return quick_result("quick_answer_attendance_red_print", "亲，红色一般是迟到、早退这类异常打卡会显示，正常上下班通常是黑色。具体要看您设置的上下班时间和迟到早退规则哈。")

    if attendance and any(term in compact for term in ["一天可以打几次", "一天打几次", "打几次卡", "几次卡"]):
        return quick_result("quick_answer_attendance_punch_times", "亲，最多可以设置 3 组班次，也就是一天最多 6 次打卡（3 次上班+3 次下班）。如果班次很重合，建议用手动打卡更稳。")

    if attendance and any(term in compact for term in ["夜班", "晚上8点到早上8点", "20点到8点", "20:00到08:00", "20:00-08:00", "跨天"]):
        return quick_result(
            "quick_answer_attendance_night_shift",
            "亲，可以设置哈。两班可按 08:00-20:00、20:00-08:00 来排；夜班跨天时，09组换行时间要设在最晚下班之后，比如 08:30 或 09:00，避免打到前一天。",
            risk_level="medium",
            auto_reply_allowed=True,
        )

    if attendance and "色带" in compact and any(term in compact for term in ["多久", "多长", "多少字符", "多少次", "打卡多少", "打多少", "能用"]):
        return quick_result("quick_answer_attendance_ribbon_life", "亲，考勤机色带能用多久和打卡人数、每天打卡次数、打印浓度有关，没有固定字符数哈。打印变淡或断线时更换色带就可以。")

    if "色带" in compact and any(term in compact for term in ["多久", "多长", "多少字符", "多少次", "打卡多少", "打多少", "能用"]):
        return quick_result("quick_answer_ribbon_life_need_model", "亲，您问的是考勤机色带还是针式打印机色带呀？两种不一样。发下机器型号，我按对应型号给您确认。", auto_reply_allowed=False)

    if attendance and "纸卡" in compact and any(term in compact for term in ["多久", "能用多久", "用多久", "50张", "50張"]):
        return quick_result("quick_answer_attendance_card_duration", "亲，50 张卡一般按员工人数来算，每个员工通常一张卡。比如 10 个员工大概能先用 5 个月左右，中途补卡会用得快一些。")

    if any(term in compact for term in ["哪里修", "在哪修", "怎么修", "维修", "坏了"]):
        return quick_result(
            "quick_answer_repair_collect_info",
            "亲，我先帮您核实售后。麻烦发一下机器型号、订单状态、故障现象和图片/视频，维修或寄修地址需要按订单和检测情况确认。",
            risk_level="high",
            auto_reply_allowed=False,
        )

    if any(term in compact for term in ["保修多久", "质保多久", "保多久", "保修多长", "机器保修"]):
        return quick_result(
            "quick_answer_warranty_collect_info",
            "亲，保修要以商品页和订单售后规则为准哈。您发下订单和机器型号，我帮您按订单情况确认更准确。",
            risk_level="high",
            auto_reply_allowed=False,
        )

    if re.search(r"(100|110|220)\s*[vV伏]|电压|电源适配器|适配器", compact):
        return quick_result("quick_answer_voltage", "亲，可以的，一般配的是宽电压电源，100-240V 范围内可以用哈。您也可以看下适配器标签，如果写着 100-240V 就没问题；插头不匹配的话配个转换头就行。")

    return None


def is_customer_reply_card(result: dict) -> bool:
    if result.get("type") != "card":
        return False
    reply = str(result.get("reply_template") or "").strip()
    if not reply:
        return False
    unsafe_bits = [
        "---",
        "knowledge_base:",
        "source_boundary:",
        "截图/后台",
        "查询入口：",
        "客服口径：",
        "| 客户表达 |",
        "典型信号：",
        "必须优先",
        "do_not_say",
        "src_",
    ]
    return not any(bit in reply for bit in unsafe_bits)


def has_intent_match(result: dict) -> bool:
    reasons = result.get("reasons") or []
    return any(
        reason == "high_frequency_exact"
        or str(reason).startswith("keyword:")
        or str(reason).startswith("high_risk:")
        for reason in reasons
    )


def is_confident_result(result: dict) -> bool:
    reasons = [str(reason) for reason in (result.get("reasons") or [])]
    if any(reason.startswith("product_mismatch:") for reason in reasons):
        return False
    return result.get("type") == "card" and has_intent_match(result) and float(result.get("score") or 0) >= MIN_AUTO_REPLY_SCORE


def is_relevant_card_for_message(result: dict, message: str) -> bool:
    """Reject locally known false-positive cards before they can be sent."""
    card_id = str(result.get("id") or "")
    compact = normalize_text(message)
    if "manual_punch_columns" in card_id and not any(
        term in compact for term in ["手动", "打卡列", "第几列", "按键", "按钮", "选择列", "列"]
    ):
        return False
    if "warranty" in card_id and not any(term in compact for term in ["保修", "质保", "保多久", "坏", "维修", "售后"]):
        return False
    if "ribbon_install" in card_id and any(term in compact for term in ["多久", "多长", "多少字符", "打多少", "能用"]):
        return False
    if "price_coupon_difference" in card_id and not any(
        term in compact for term in ["差价", "优惠", "优惠券", "券", "便宜", "降价", "价格", "活动"]
    ):
        return False
    if "selling_points" in card_id and any(
        term in compact for term in ["色带", "多少次", "打卡多少", "保修", "维修", "卡纸", "怎么", "故障", "不清楚"]
    ):
        return False
    return True


def build_reply(
    message: str,
    product: str | None = None,
    shop: str | None = None,
    context: str | None = None,
    platform: str | None = None,
) -> dict:
    attendance_context = has_attendance_context(message, product)
    if attendance_context and not platform:
        return quick_result(
            "video_platform_required",
            "亲，为避免发错视频链接，请先确认您咨询的平台是天猫、京东还是拼多多。",
            risk_level="unknown",
            auto_reply_allowed=False,
        )

    if platform:
        try:
            video_result = match_video_material(message, platform)
        except (PlatformRequiredError, VideoMaterialError):
            return quick_result(
                "video_platform_or_asset_unavailable",
                "亲，当前平台的视频素材暂时无法安全确认，我先为您转人工核实。",
                risk_level="unknown",
                auto_reply_allowed=False,
            )
        if video_result:
            return video_result

    compact = normalize_text(message)
    if attendance_context and any(term in compact for term in ["不会用", "不会操作", "怎么用", "不懂用"]):
        return quick_result(
            "video_attendance_topic_clarification",
            "亲，您具体想看哪一项：时间/日期、班次、纸卡、色带、打印位置、响铃，还是密码设置？确认后我只发最相关的一段。",
            auto_reply_allowed=True,
        )

    quick_reply = quick_answer(message, product)
    if quick_reply:
        return quick_reply

    query = " ".join(part for part in [product, shop, context or message] if part)
    raw_results = search(INDEX, query or message, top_k=8)
    results = [
        result
        for result in raw_results
        if is_customer_reply_card(result)
        and is_relevant_card_for_message(result, message)
        and is_confident_result(result)
    ]
    top = results[0] if results else None

    if not top:
        return {
            "reply": "亲，我这边需要再确认一下。麻烦您补充机器型号或问题截图，我按情况帮您看。",
            "risk_level": "unknown",
            "auto_reply_allowed": False,
            "confidence": "low",
            "score": 0,
            "actions": [],
            "sources": [],
            "matches": raw_results[:3],
        }

    return {
        "reply": top.get("reply_template") or "亲，您这个问题我帮您确认一下哈。",
        "risk_level": top.get("risk_level"),
        "auto_reply_allowed": bool(top.get("auto_reply_allowed", False)),
        "confidence": "high",
        "score": top.get("score"),
        "actions": top.get("actions", []),
        "sources": [item.get("source_file") for item in results if item.get("source_file")],
        "matches": results,
    }


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html: str, status: int = 200) -> None:
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path in {"/", "/customer-reply"}:
            params = parse_qs(parsed.query)
            message = params.get("message", ["色带怎么安装"])[0]
            result = build_reply(message)
            self._send_html(
                f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <title>客服 RAG API Preview</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 32px; line-height: 1.5; }}
    input {{ width: 420px; max-width: 90vw; padding: 8px; }}
    button {{ padding: 8px 14px; }}
    pre {{ background: #f6f8fa; padding: 16px; border-radius: 8px; white-space: pre-wrap; }}
  </style>
</head>
<body>
  <h1>客服 RAG API Preview</h1>
  <form method="get" action="/customer-reply">
    <input name="message" value="{message}" />
    <button type="submit">测试</button>
  </form>
  <h2>返回结果</h2>
  <pre>{json.dumps(result, ensure_ascii=False, indent=2)}</pre>
  <p>程序调用请 POST JSON 到 <code>/customer-reply</code>，字段：<code>message</code>、<code>product</code>、<code>shop</code>。</p>
</body>
</html>"""
            )
            return
        self._send_json({"error": "not found"}, status=404)

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path != "/customer-reply":
            self._send_json({"error": "not found"}, status=404)
            return

        length = int(self.headers.get("Content-Length", "0") or 0)
        raw_body = self.rfile.read(length).decode("utf-8") if length else "{}"
        try:
            payload = json.loads(raw_body)
        except json.JSONDecodeError:
            self._send_json({"error": "invalid json"}, status=400)
            return

        message = str(payload.get("message", "")).strip()
        if not message:
            self._send_json({"error": "message is required"}, status=400)
            return
        self._send_json(
            build_reply(
                message=message,
                product=payload.get("product"),
                shop=payload.get("shop"),
                platform=payload.get("platform"),
            )
        )

    def log_message(self, format: str, *args: object) -> None:
        return


def main() -> None:
    server = ThreadingHTTPServer(("127.0.0.1", 8000), Handler)
    print("RAG API server running at http://127.0.0.1:8000/customer-reply")
    server.serve_forever()


if __name__ == "__main__":
    main()
