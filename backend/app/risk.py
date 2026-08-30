from __future__ import annotations

from dataclasses import dataclass


CRITICAL_TERMS = ("着火", "冒烟", "烧焦", "触电", "漏电")
HIGH_TERMS = (
    "退款", "退货", "退钱", "换货", "补发", "赔偿", "投诉", "差评", "12315",
    "平台介入", "小二", "发票", "税号", "改地址", "修改地址", "改电话", "维修费",
    "运费", "差价", "优惠券", "仅退款",
)
MEDIUM_TERMS = ("维修", "保修", "质保", "物流", "发货", "订单", "付款", "坏了")


@dataclass(frozen=True)
class RiskAssessment:
    level: str
    triggers: list[str]


def assess_risk(text: str) -> RiskAssessment:
    compact = text.lower().replace(" ", "")
    critical = [term for term in CRITICAL_TERMS if term in compact]
    if critical:
        return RiskAssessment("critical", critical)
    high = [term for term in HIGH_TERMS if term in compact]
    if high:
        return RiskAssessment("high", high)
    medium = [term for term in MEDIUM_TERMS if term in compact]
    if medium:
        return RiskAssessment("medium", medium)
    return RiskAssessment("low", [])
