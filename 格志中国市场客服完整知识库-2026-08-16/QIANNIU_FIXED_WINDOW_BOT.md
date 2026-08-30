# 千牛固定窗口自动回复 MVP

本项目已经有一个可运行的自动化内核：

- 只扫描固定区域，不扫全屏。
- `4区`：当前客户聊天内容，有变化才 OCR。
- `1区`：左侧正在接待列表，可选低频监控新客户。
- `5区`：右侧订单/客户信息区，只读订单状态，不操作订单。
- `2区`：回复输入区。
- `3区`：发送按钮。
- 回复优先从本项目 RAG 卡片库检索。
- 当前运行策略只认窗口标题包含 `接待中心` 的客服窗口，并按配置固定在附屏坐标；找不到该窗口时只等待，不会把 `千牛工作台` 当成目标窗口。

## 文件

- 配置：`qianniu_ui_regions.json`
- 主脚本：`scripts/qianniu_fixed_window_bot.py`
- 本地中文 OCR：`.venv-ocr` + `scripts/ocr_rapid.py`
- 备用 OCR：`scripts/ocr_image.swift`，编译后为 `bin/ocr_image`
- 启动器：`/Applications/QianNiuRAGBot.app`
- 后台打开千牛：若千牛未运行，启动脚本只会用后台方式打开 `/Applications/Aliworkbench.app`，随后仍只等待标题包含 `接待中心` 的窗口；不会把 `千牛工作台` 当成客服窗口操作。

## 权限

真实运行需要给启动脚本的终端/App 授权：

- 屏幕录制：用于截取固定区域。
- 辅助功能：用于激活千牛、读取窗口位置、点击输入框/发送按钮。
- 剪贴板：用于快速粘贴回复。

当前自动发送模式不启用“固定坐标兜底”。也就是说，辅助功能必须能读到 `接待中心` 窗口，程序才会截图、填入和发送；这样可以避免误操作主屏幕或千牛主界面。

## 只读测试

不输入、不发送，只验证截图、OCR、RAG：

```bash
.venv-ocr/bin/python scripts/qianniu_fixed_window_bot.py --once --verbose --window-relative --pin-reception-window --no-activate-before-scan
```

## 持续监控

每 5 秒扫描一次当前聊天区：

```bash
.venv-ocr/bin/python scripts/qianniu_fixed_window_bot.py --interval 5 --window-relative --pin-reception-window --no-activate-before-scan
```

同时低频检查左侧会话列表：

```bash
.venv-ocr/bin/python scripts/qianniu_fixed_window_bot.py --interval 5 --watch-list --window-relative --pin-reception-window --open-qianniu-if-missing --no-activate-before-scan
```

## 填入回复但不发送

```bash
.venv-ocr/bin/python scripts/qianniu_fixed_window_bot.py --interval 5 --fill --window-relative --pin-reception-window --no-activate-before-scan
```

## 自动发送低风险回复

只会自动发送 RAG 标记为 `auto_reply_allowed=true` 的回复。退款、退货、换货、赔偿、差价、发票、投诉、差评、平台介入、维修收费、地址、电话等高风险场景不会自动承诺。

```bash
.venv-ocr/bin/python scripts/qianniu_fixed_window_bot.py --interval 5 --auto-send --window-relative --pin-reception-window --open-qianniu-if-missing --no-activate-before-scan
```

## 当前已验证

RapidOCR 已接入并可识别当前千牛聊天截图中的客户消息：

```text
可以优惠吗
打卡机多重
```

主解析逻辑可从截图 OCR 结果中提取出：

```text
打卡机多重
```

## 重要限制

- OCR 已从 macOS Vision 切换为本地 RapidOCR；如果 `.venv-ocr` 不存在，会回退备用 OCR。
- 截图权限仍取决于启动进程的“屏幕录制”授权；若从 Terminal 启动，需要给 Terminal 授权。
- 区域坐标基于当前固定窗口，窗口移动或缩放后要重新标定。
- 订单区 `5区` 只读，不做退款、改价、发票、设置等操作。
