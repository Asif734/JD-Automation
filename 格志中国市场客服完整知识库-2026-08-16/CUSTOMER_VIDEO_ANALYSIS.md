# 客户视频快速分析工具

该工具把客户视频转换成本地、可核对的证据包。它负责解码、抽帧、联系表、音轨和可选 OCR，不会自动判断故障，也不会自动把案例加入知识库。

## 首次安装

```bash
scripts/install_video_tools.sh
```

安装内容位于项目 `.venv-video`，包含 PyAV/FFmpeg、Pillow 和本地 FFmpeg 可执行文件，不修改 macOS 系统组件。安装后离线也能处理本地视频。

## 单个视频

```bash
.venv-video/bin/python scripts/prepare_customer_videos.py /absolute/path/to/video.mp4
```

10 秒以内默认每 0.25 秒抽帧，10–30 秒每 0.5 秒，30 秒–5 分钟每 1 秒，更长视频先按 2–5 秒生成概览。

## 批量目录

```bash
.venv-video/bin/python scripts/prepare_customer_videos.py /absolute/path/to/folder --recursive
```

支持 MP4、MOV、MKV、AVI、WebM 和 3GP。单个文件损坏只计入失败摘要，不中断其他视频。

## 常用参数

```bash
.venv-video/bin/python scripts/prepare_customer_videos.py /absolute/path/to/video.mp4 --dense --force
.venv-video/bin/python scripts/prepare_customer_videos.py /absolute/path/to/video.mp4 --interval 0.5
.venv-video/bin/python scripts/prepare_customer_videos.py /absolute/path/to/video.mp4 --no-audio --no-ocr
```

- `--dense`：强制每 0.25 秒抽帧。
- `--interval`：指定抽帧秒数。
- `--no-audio`：不提取音轨。
- `--no-ocr`：跳过代表帧 OCR，适合只需快速看动作的批量任务。
- `--force`：重新生成该视频 SHA-256 对应的证据目录；不会改动原视频。
- `--output`：修改输出根目录，默认是 `outputs/customer_video_analysis`。

## 输出内容

每个视频生成独立目录：

- `metadata.json`：SHA-256、时长、尺寸、帧率、容器、视频/音频编码和处理策略。
- `frames/`：按时间顺序命名的原始抽帧。
- `contact_sheets/`：每帧带可读秒数的联系表。
- `audio.wav`：存在音轨且未禁用时生成的单声道审核音频。
- `evidence.json`：时间戳、实际解码帧时间、OCR 状态和知识库确认状态。
- `analysis_draft.md`：客服助手填写的固定诊断结构，初始状态为“待用户确认”。

相同 SHA-256 的视频默认复用完整缓存；若之前未运行 OCR，而本次命令要求 OCR，则会补做完整证据包。

## 备用阅读

主解码失败时，记录原错误，再用 macOS QuickTime/AVFoundation 只读检查。能播放不代表已完整阅读，仍须核对开头、中间、结尾和关键动作。扩展名与真实容器不一致时以解码结果为准。

## 知识库确认门

工具生成的结果不得自动写入正式知识库。客服助手先展示可见事实、未知项、可能分支和关键时间点；只有用户明确确认结论并要求加入知识库后，才更新知识源、RAG 卡、证据索引和回归查询。
