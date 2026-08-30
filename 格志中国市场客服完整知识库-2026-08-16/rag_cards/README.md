# 客服 RAG 卡片库

本目录是客服自动回复的结构化 RAG 数据层。长 Markdown 知识库仍作为原始资料保留，实时客服回复优先走这里的卡片库和索引。

## 文件

- `customer_service_rag_card_schema.json`：单张卡片字段定义。
- `customer_service_rag_cards.jsonl`：主卡片库，每行一张卡片。
- `high_frequency_queries.json`：高频客户问题缓存，命中后直接定位卡片。
- `source_chunks.jsonl`：由现有 Markdown 知识库自动切分的全量兜底知识块。
- `../rag_index/customer_service_rag_index.json`：由脚本生成的本地检索索引。

## 构建索引

```bash
python3 scripts/build_source_chunks.py
python3 scripts/build_rag_index.py
```

输出：

```text
rag_index/customer_service_rag_index.json
```

当前第一版索引包含：

- 关键词索引
- 同义词索引
- 高频问题缓存
- 字符 n-gram TF-IDF 向量兜底
- 风险规则置顶字段
- 全量 Markdown 章节块兜底检索

生产环境如果已有 embedding/向量库，可以把 `scripts/search_rag.py` 里的本地 n-gram 向量替换成真实向量检索；卡片结构不需要改。

## 两层 RAG 策略

当前已经把已有知识库做成两层：

1. **Curated Cards**
   - 文件：`customer_service_rag_cards.jsonl`
   - 用途：高频问题、风险规则、视频素材、可直接回复话术。
   - 优先级：最高。

2. **Source Chunks**
   - 文件：`source_chunks.jsonl`
   - 来源：项目根目录下现有 Markdown 知识库。
   - 用途：卡片命不中时做兜底，保留所有原始知识覆盖面。
   - 优先级：低于 curated cards，避免长文档冲掉高频短回复。

实时客服回复建议顺序：

```text
客户问题 -> 高频缓存/高风险规则 -> Curated Card -> Source Chunk 兜底 -> 原始 Markdown 人工查阅
```

如果命中的是 `source_chunk`，不要直接把整段内容发给客户。应先提炼为短回复，必要时再新增一张正式 curated card。

## 搜索测试

```bash
python3 scripts/search_rag.py 日期怎么调
python3 scripts/search_rag.py 色带怎么装
python3 scripts/search_rag.py 端口怎么改
python3 scripts/search_rag.py 可以退货吗
```

输出会显示：

- 命中的卡片 id
- 分数
- 风险等级
- 可否自动回复
- 话术模板
- 需要执行的动作，比如发送千牛视频卡片

## 新增卡片原则

新增资料时优先新增一条卡片，而不是继续把内容堆进长文档。

每张卡片必须明确：

- 产品线：考勤机、热敏机、针打、WiFi/蓝牙、售后等。
- 问题：例如“设置日期”“色带安装”“端口修改”。
- 关键词和同义词。
- 风险等级：`low`、`medium`、`high`。
- 是否允许自动回复。
- 短回复模板。
- 动作：发送视频、要求截图、转人工、收集信息等。

## 风险规则

高风险问题必须优先于普通卡片：

- 退款、退货、换货、补发、赔偿。
- 差价、优惠券、运费。
- 发票。
- 投诉、差评、平台介入。
- 维修收费、过保、检测结论。
- 地址、电话等隐私信息。

高风险卡片通常设置：

```json
"risk_level": "high",
"auto_reply_allowed": false
```

自动客服只能安抚和收集信息，不承诺最终结果。

## 千牛视频规则

千牛素材中心视频多数没有客户可直接打开的公开视频链接。卡片里的 `location` 是给客服/自动化操作用的后台位置，不应直接发给客户。

正确动作：

```json
{
  "type": "send_qianniu_video_card",
  "location": "千牛 > 商品 > 素材中心 > 我的图片/视频 > 视频 > Attendance Machine > 11.set date",
  "url": null
}
```

客户话术只说“我发您对应视频”，不要说后台路径，也不要编造链接。
