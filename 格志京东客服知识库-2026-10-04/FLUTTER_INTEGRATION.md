# Flutter 接入说明

## 1. 建议的 assets 配置

把下列数据文件复制到 Flutter 项目的知识库 assets 目录，并在 `pubspec.yaml` 声明：

- `flutter_dataset_manifest.json`
- `handover/capabilities.json`
- `jd_customer_service_rules.md`
- `product_model_feature_catalog_kb.md`
- `rag_cards/customer_service_rag_cards.json`
- `rag_cards/high_frequency_queries.json`
- `rag_cards/china_market_video_catalog.json`
- `rag_cards/customer_service_rag_card_schema.json`

如果 Flutter 端已有向量库，可另外导入顶层技术 Markdown 和 `rag_cards/source_chunks.jsonl` 重建 embedding。不建议把 `sources/` 与 `assets/` 全量建立客户回复索引。

## 2. 加载顺序

1. 读取 `flutter_dataset_manifest.json` 并检查 `platform == "JD"`。
2. 读取 `handover/capabilities.json`，关闭未实现的商品卡、邀单、订单卡、发票卡、邮件和人工转接动作。
3. 把 `jd_customer_service_rules.md` 作为全局提示词/规则加载，不要只依赖检索命中。
4. `jsonDecode` 读取 `customer_service_rag_cards.json`，按 `id` 建立映射。
5. 对 `high_frequency_queries.json` 中的 `query` 做小写化和去空白后建立精确路由。
6. 再建立关键词/语义检索；确定性高频路由应优先于普通语义排序。

## 3. 返回对象建议

Flutter 内部可把命中卡片映射为：

```text
cardId
reply
riskLevel
autoReplyAllowed
requiredSlots
actions
sourceFiles
tutorial
requiresHuman
```

`requiresHuman` 在下列任一情况为 `true`：

- `risk_level` 为 `high` 或 `critical`；
- `auto_reply_allowed` 为 `false`；
- action type 包含 `human`、`handoff`、`transfer`、`finance`、`order_check` 或 `manual_email`。

未接入真实人工转接适配器时，Flutter 只能把会话进入“人工待处理”状态，不得向客户显示“已转人工”。

## 4. 教程匹配

- 卡片 `tutorial_refs` 只包含字符串：具体 `content_id` 或 `catalog:<product_line>`。
- 具体 `content_id` 优先；目录范围需再按标题、关键词、型号和产品线排序。
- 只读取 `platform_urls.JD`；为空或无精确匹配时不发链接。
- 链接只能附在已完整回答的文字之后，不能代替文字答案。

## 5. 上线前最低检查

- 卡片 ID 无重复，所有 `source_files` 存在。
- 所有活动卡片都是 `platforms=["JD"]` 和 `current_platform="JD"`。
- 所有高频路由的 `card_id` 都存在。
- 所有教程只有 JD URL，不使用其他平台备用链接。
- 至少测试：TD630/TD630G电脑Wi-Fi边界、TP876PLUS纸宽购买选项、M880D备用电池、当前型号目录、发票/退换/转人工的禁止自动承诺。
