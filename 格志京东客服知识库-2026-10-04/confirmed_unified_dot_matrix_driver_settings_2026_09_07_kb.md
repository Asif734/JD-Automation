---
knowledge_base: confirmed_unified_dot_matrix_driver_settings_2026_09_07
version: "2026-09-07-r10"
language: zh-CN/en
status: confirmed
scope: "统一版 Windows 针式打印机驱动设置；适用于支持的 USB、Wi-Fi、蓝牙针式打印机型号"
sources:
  - "sources/user_uploads/dot_matrix_driver_settings/unified_dot_matrix_driver_settings_screen_recording_2026_09_07.mp4"
  - "sources/user_uploads/dot_matrix_driver_settings/unified_dot_matrix_driver_settings_2026_09_07.pdf"
---

# 统一版 Windows 针式打印机驱动设置（已确认）

## 1. 适用范围与客服边界

- 本文所述统一驱动界面适用于当前支持的 Windows 针式打印机型号，包括 USB、Wi-Fi 和蓝牙版本。连接方式不改变本文列出的驱动设置。
- 统一驱动不改变机型本身的进纸能力、纸宽、接口或系统兼容性。后进连续纸步骤只能发给确认支持后进纸的型号：`TD630`、`TD630G`、`AK915`、`TG890`；`AK910`、`AK890` 不支持后进连续纸。
- 客户界面可能显示 `Configure-日期`，客服统一称为 **Configure**。Configure 窗口标题中的编号是驱动构建标识，不是打印机型号。
- 只能使用本文或其他已确认知识中明确记录的设置。不得编造 Paper/Quality 内部选项、未展开的下拉选项、未展示的范围或不存在的 High Speed/Draft 模式。

## 2. 打开驱动设置

标准入口：`控制面板 → 硬件和声音 → 设备和打印机 → 右击已安装的打印机 → 打印首选项`。

也可使用：`开始 → 设置 → 设备 → 蓝牙和其他设备 → 相关设置 → 设备和打印机 → 右击打印机 → 打印首选项`。

- **打印首选项**：用于 Layout、纸张规格、DPI 和 Configure 设置。
- **打印机属性**：用于端口检查和 Windows `打印测试页`。

打印首选项中已确认的标签页为：`Layout`、`Paper/Quality`、`Configure`。视频和 PDF 没有打开 `Paper/Quality` 的内部内容，因此不得编造 Paper/Quality 中的设置。

## 3. Layout 标签页

- Orientation：`Portrait`、`Landscape`。
- Page Order：画面当前显示 `Front to Back`，其他选项未展开。
- Pages per Sheet：画面当前显示 `1`，其他选项未展开。
- `Draw Borders`：可见复选框。
- `Advanced...`：打开高级文档设置。

打印方向默认使用 `Portrait`（纵向）。只有客户明确需要横向，或原文档/打印预览确实为横向时，才选择 `Landscape`。只有需要固定旋转 90°、180° 或 270° 时，才使用 Configure 的 `page rotation`。

## 4. Layout → Advanced... 高级设置

### 4.1 Paper/Output → Paper Size

驱动中已确认的纸张规格名称如下，必须按界面原文保留：

- `A4: 240mm*297.4`
- `S1: 240mm*93.1mm`
- `S2: 240mm*139.7mm`
- `S3: 240mm*101.6mm`
- `S4: 240mm*279.4mm`

`Copy Count` 当前显示 `1 Copy`，其他数量选项未展开。

### 4.2 Graphic → Print Quality

已确认的 DPI 只有：

- `DPI:720*720`：质量较高。
- `DPI:180*144`：速度较快，但打印质量降低。

### 4.3 其他已显示的高级项目

- ICM Method：`ICM Disabled`
- ICM Intent：`Pictures`
- Advanced Printing Features：`Enabled`
- Pages per Sheet Layout：`Right then Down`
- Print Optimizations：`Enabled`
- Advanced OEM UI Added Item：`0`

除纸张规格和 DPI 外，上述下拉框未展开，不得自行补充其他可选值。

## 5. Configure 标签页

### 5.1 Halftone

已确认选项：`Dither`、`error diffusion`、`grayscale`。PDF 记录的默认值为 `grayscale`。

### 5.2 参数、范围与默认值

| 项目 | 默认/当前值 | 已确认范围或选项 | 用途 |
|---|---|---|---|
| print head type | `DPIX180_DPIY_144_Needle_printer` | 禁用字段，未显示其他值 | 硬件配置，不指导客户修改 |
| display language | `English` | 未展开 | 配置界面语言 |
| Horizontal adjustment | `0mm` | 每次 1mm；视频可见至少 -15mm 至 +20mm，不能把下限写死 | 整体左右移动 |
| Vertical position adjustment | `0mm` | -20mm 至 +20mm，每次 1mm | 整体上下移动 |
| density | `standard` | 未展开 | 打印浓度 |
| Fixed page height | `139.7mm(holes 11)` | 见下表 | 连续纸固定页长 |
| speed | `standard` | 未展开 | 驱动速度模式 |
| Halftone Density | `50` | 未展开 | 图像网点浓度 |
| grayscale threshold | `249` | 视频可见 121–249；完整下限未展示 | 灰度转点阵阈值 |
| page rotation | `0` | `0`、`90`、`180`、`270` | 输出旋转 |
| start print position | `0` | 未展开 | 只在另有确认流程时使用 |
| tear-off position | `0` | `0`、+2mm 至 +20mm、-2mm 至 -20mm，每次 2mm | 纸型正确后的撕纸位置微调 |

### 5.3 Fixed page height 固定页高

- `93.1mm(holes 22/3)`
- `101.6mm(holes 8)`
- `127mm(holes 10)`
- `139.7mm(holes 11)`
- `279.4mm(holes 22)`

`93.1mm(holes 22/3)` 是驱动画面原文，不自行改写。选中固定页高数值后，只有勾选 **Fixed page height**，该数值才生效。

纸张实物和驱动预设要分开表述：常见连续纸实际纸宽约 `241mm`，而对应的驱动预设宽度是 `240mm`。`holes 22/3` 表示 `22除以3`，约 `7⅓` 个孔位间隔，不是22或23孔。

后进连续纸的诊断基准：三等分打印1页约 `7⅓`、2页约 `14–15`、3页约 `22` 个孔位间隔；二等分打印1页约 `11` 个孔位间隔。数值仅作为是否多走纸的辅助判断，软件页面大小、驱动纸张大小和固定页高仍必须一致。

### 5.4 PDF 已确认的 Configure 默认状态

- Halftone：`grayscale`
- Horizontal adjustment：`0mm`
- Vertical position adjustment：`0mm`
- density：`standard`
- Fixed page height 数值：`139.7mm(holes 11)`
- speed：`standard`
- Halftone Density：`50`
- grayscale threshold：`249`
- page rotation：`0`
- start print position：`0`
- tear-off position：`0`
- Fixed page height：未勾选
- Remove white space at the bottom of the page：已勾选
- delete left blank page：已勾选
- Remove white space at the top of the page：未勾选
- Output bitmap image to computer：未勾选
- Paper edge hole length calculation：已勾选
- One-way printing：已勾选

## 6. 客服排查流程

### 6.1 整体左右偏移

1. 先确认打印软件模板、驱动纸张规格和实物纸张一致。
2. 打开 `打印首选项 → Configure`。
3. 使用 **Horizontal adjustment**，每次按 1mm 小幅调整。
4. 保存后执行第 7 节的必做步骤。

只有内容压到左侧拖纸孔、涉及左侧空白页处理时，才检查 `delete left blank page/删除左边空白页`；它不是整页左右偏移的通用调节项。

### 6.2 整体上下偏移

1. 检查初始装纸位置、模板尺寸和驱动纸张规格。
2. 打开 `打印首选项 → Configure`。
3. 使用 **Vertical position adjustment**，每次按 1mm 小幅调整。
4. 保存后执行第 7 节的必做步骤。

### 6.3 后进连续纸页长或停止位置不正确

仅用于支持后进连续纸的型号：`TD630`、`TD630G`、`AK915`、`TG890`。

1. 确认实物纸张高度、撕线间距和孔数。
2. 在 `Layout → Advanced... → Paper/Output → Paper Size` 选择匹配规格。
3. 在 `Configure` 选择匹配的 **Fixed page height**。
4. 勾选 **Fixed page height**。
5. 取消勾选以下五项：
   - `Remove white space at the bottom of the page/删除页面底部空白`
   - `delete left blank page/删除左边空白页`
   - `Remove white space at the top of the page/删除页面顶部空白`
   - `Output bitmap image to computer/将位图图像输出到计算机`
   - `Paper edge hole length calculation/纸边孔长计算`
6. **One-way printing/单向打印保持原设置**，除非同时在做速度或重影的专项排查。
7. 点击驱动中显示的 `Import/导入`，再按页面可见按钮点击 `OK/确定` 或 `Apply/应用`。
8. 执行第 7 节的必做步骤，再先打印一份样张。

### 6.4 撕纸位置不正确

1. 先匹配打印软件页面尺寸、驱动 Paper Size、连续纸 Fixed page height 和实际装纸方式。
2. 设置和进纸正确后，打印机会自动把连续纸带到正确撕纸位置；不要编造或寻找独立的“自动撕纸模式”。
3. 如果只剩少量偏差，再进入 `Configure → tear-off position`，按 2mm 逐步微调。
4. 每次改变后保存、重启软件、重新装纸并试打一份。

第一份正确但第二份标题落在撕纸线时，按实际撕纸线间距设置固定页高，完成保存后的必做步骤，并连续打印两份客户表单检查累计误差；此专项不需要另外打印 Windows `打印测试页`。

### 6.5 打印速度慢

方法一：`打印首选项 → Layout → Advanced... → Graphic → Print Quality`，选择 `DPI:180*144`。较低 DPI 能提高速度，但打印质量会降低。

方法二：`打印首选项 → Configure`，取消勾选 **One-way printing/单向打印**，即启用双向打印。双向打印不是双面打印。

保存后执行第 7 节必做步骤。客户只问速度时，不主动追加重影警告；不得编造单独的 High Speed 或 Draft 模式。

### 6.6 横向重影或竖线不直

需要强制单向打印时，在 `Configure` **勾选 One-way printing/单向打印**。不得告诉客户去关闭不存在的 High Speed 设置。若同时出现固定且连续的横向黑线，按打印头硬件故障处理并转人工维修。

### 6.7 端口或连接异常

1. 打开 `设备和打印机 → 右击打印机 → 打印机属性 → 端口`。
2. 勾选端口必须与实际 USB、串口、网络、Wi-Fi 或蓝牙打印队列/连接一致。
3. 界面中可见的示例类型包括 COM、FILE、WSD、USB001、Standard TCP/IP、PORTPROMPT；不得照抄视频中的 IP 或端口号。
4. Windows `打印测试页`可用于区分驱动/连接问题和打印软件/模板问题。

### 6.8 图像或灰度效果不理想

先确认普通文字是否正常，再按需要检查 `Dither`、`error diffusion`、`grayscale`。Halftone Density 或 grayscale threshold 只做小幅调整，并先记录原值；效果变差时恢复。

## 7. 保存设置后的必做步骤

每次保存驱动设置后必须完成：

1. 完全关闭当前用于打印的软件，再重新打开。
2. 从打印机中取出纸张，并按新设置正确重新装入。
3. 批量打印前先打印一份样张；累计页长问题连续打印两份客户表单。

## 8. 客服回复防编造规则

- `Paper/Quality` 内部内容没有展示，不得编造。
- 下拉框没有展开时，只能说当前值或“未确认其他选项”，不得自创选项。
- Horizontal adjustment 的视频仅确认至少 -15mm 至 +20mm，不能把下限写死。
- grayscale threshold 只确认画面可见 121–249，不能声称这是完整范围。
- 不把队列名、驱动构建号、视频中的 IP/端口、General 页硬件参数当作所有型号的通用值。
- 不支持后进纸的型号不得发送后进连续纸步骤。

## English support summary

Use **Control Panel → Hardware and Sound → Devices and Printers → right-click the installed printer → Printing preferences**. The confirmed tabs are Layout, Paper/Quality, and Configure. Do not invent settings that were not shown.

- Paper Size: `A4: 240mm*297.4`, `S1: 240mm*93.1mm`, `S2: 240mm*139.7mm`, `S3: 240mm*101.6mm`, `S4: 240mm*279.4mm`.
- Print Quality: `DPI:720*720` or `DPI:180*144`.
- Whole-page offset: Configure → Horizontal adjustment or Vertical position adjustment, in 1mm steps.
- Residual tear-off offset: Configure → tear-off position, from -20mm to +20mm in 2mm steps.
- Faster printing: select `DPI:180*144` and/or clear **One-way printing** to allow bidirectional printing.
- Rear-fed continuous paper: only use the fixed-page-height workflow on `TD630`, `TD630G`, `AK915`, and `TG890`; preserve One-way printing unless speed/ghosting is being handled separately.
- After saving: completely close and reopen the printing software, remove and correctly reload the paper, then print a sample before a batch.
