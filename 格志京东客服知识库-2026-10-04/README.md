# 格志京东客服知识库（Flutter 数据包）

平台：京东（JD）　品牌：格志（Grozziie）　版本：2026-10-04-jd-grozziie-v1

本目录是纯知识/数据包，用于 Flutter 客服应用。不包含 Python 运行时、HTTP 服务、登录信息、真实消息发送、订单操作或人工转接适配器。

## Flutter 优先读取

1. `flutter_dataset_manifest.json`：Flutter 导入入口、文件角色和运行边界。
2. `jd_customer_service_rules.md`：必须全局载入的京东客服最高规则。
3. `rag_cards/customer_service_rag_cards.json`：Flutter 可直接 `jsonDecode` 的主卡片数组。
4. `rag_cards/high_frequency_queries.json`：高频问句到卡片 ID 的确定性路由。
5. `rag_cards/china_market_video_catalog.json`：仅保留 JD URL 的教程目录。
6. `product_model_feature_catalog_kb.md`：型号、连接、系统、纸张、包装和选型统一速查。

`rag_cards/customer_service_rag_cards.jsonl` 与 JSON 数组内容相同，保留给支持 JSONL 流式读取的工具。`rag_index/customer_service_rag_index.json` 是预生成的备用本地索引；Flutter 已有自己的 embedding/检索层时，应基于卡片重建本地索引，不要混用原平台缓存。

## 运行边界

- 只有 `status=active`、`platforms=["JD"]`、`current_platform="JD"` 的卡片可进入客服检索。
- `reply_template` 是回复建议；`actions` 是意图/工作流建议，不代表操作已执行。
- `risk_level=high/critical`、`auto_reply_allowed=false` 或需要人工/订单/财务的卡片不得被 Flutter 当作自动完成。
- 教程只能从 `platform_urls.JD` 选择，产品线、型号和问题必须匹配，每条回复最多一个链接。
- `sources/` 和 `assets/` 是技术证据，默认不直接发给客户。
- 京东手机 App 直打、价格、库存、开票、运费、退换、赠品和订单操作不得从技术资料推断。

详细接入说明见 `FLUTTER_INTEGRATION.md`。
