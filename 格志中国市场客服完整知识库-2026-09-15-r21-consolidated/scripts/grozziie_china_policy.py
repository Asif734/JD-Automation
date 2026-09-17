#!/usr/bin/env python3
"""Executable policy helpers for Grozziie China-market customer service."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


SAFETY_TERMS = ("着火", "冒烟", "焦味", "烧焦", "漏电", "电火花")
REFUND_TERMS = ("我要退款", "要求退款", "申请退款", "给我退款", "必须退款")
ADDRESS_CHANGE_TERMS = (
    "修改收货地址",
    "更改收货地址",
    "改收货地址",
    "换收货地址",
    "收货地址改",
    "收货地址换",
    "改地址",
)
SAFE_USER_ID = re.compile(r"^[\w.-]+$", re.UNICODE)


def route_customer_request(
    message: str,
    *,
    knowledge_found: bool,
    troubleshooting_exhausted: bool,
) -> dict[str, str | bool]:
    if any(term in message for term in SAFETY_TERMS):
        return {
            "handoff": True,
            "reason": "safety",
            "reply": "请立即停止使用并在确保安全的情况下断电，远离可燃物。转人工",
        }
    if any(term in message for term in REFUND_TERMS):
        return {"handoff": True, "reason": "refund", "reply": "转人工"}
    if any(term in message for term in ADDRESS_CHANGE_TERMS):
        return {"handoff": True, "reason": "address_change", "reply": "转人工"}
    if not knowledge_found:
        return {"handoff": True, "reason": "knowledge_missing", "reply": "转人工"}
    if troubleshooting_exhausted:
        return {"handoff": True, "reason": "troubleshooting_exhausted", "reply": "转人工"}
    return {"handoff": False, "reason": "continue", "reply": ""}


def validate_user_id(user_id: str) -> str:
    value = user_id.strip()
    if not value or value in {".", ".."} or not SAFE_USER_ID.fullmatch(value):
        raise ValueError("用户ID不能为空，且不能包含路径分隔符或其他不安全字符")
    return value


def append_customer_record(
    root: Path,
    user_id: str,
    customer_text: str,
    service_text: str,
) -> Path:
    safe_id = validate_user_id(user_id)
    root.mkdir(parents=True, exist_ok=True)
    path = root / f"{safe_id}.txt"
    with path.open("a", encoding="utf-8") as stream:
        stream.write(f"客户：{customer_text.strip()}\n客服：{service_text.strip()}\n")
    return path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    route = subparsers.add_parser("route")
    route.add_argument("--message", required=True)
    route.add_argument("--knowledge-found", action="store_true")
    route.add_argument("--troubleshooting-exhausted", action="store_true")

    record = subparsers.add_parser("append-record")
    record.add_argument("--root", type=Path, default=Path("/Users/dnying/Desktop/AI客服记录"))
    record.add_argument("--user-id", required=True)
    record.add_argument("--customer", required=True)
    record.add_argument("--service", required=True)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "route":
            result = route_customer_request(
                args.message,
                knowledge_found=args.knowledge_found,
                troubleshooting_exhausted=args.troubleshooting_exhausted,
            )
            print(json.dumps(result, ensure_ascii=False))
        else:
            path = append_customer_record(
                args.root,
                args.user_id,
                args.customer,
                args.service,
            )
            print(path)
    except ValueError as error:
        print(str(error))
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
