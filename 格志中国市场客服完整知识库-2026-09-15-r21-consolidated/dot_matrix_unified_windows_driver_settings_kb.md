# 针式打印机统一 Windows 驱动设置知识库

更新时间：2026-09-08

## 1. 适用范围

- 适用于已经安装统一 Windows 针式打印机驱动的受支持机型。
- USB、Wi-Fi 和蓝牙版本使用相同的驱动设置功能；连接方式不会改变 Layout、Advanced 或 Configure 中的设置。
- 必须选择客户电脑上实际安装的正确打印机队列。示例中的 `TD630 SZ`、Configure 日期后缀和 `395092-20230106` 不是通用型号或客户设置，不得套用。
- 本文只记录视频、PDF或用户确认过的界面和值。没有展开的下拉菜单、标签页和范围不得猜测。

## 2. 打开统一驱动设置

1. 打开 Windows `控制面板`。
2. 进入 `硬件和声音 -> 设备和打印机`。
3. 找到实际安装的打印机队列并右击。
4. 选择 `打印首选项（Printing preferences）`。

`Printing preferences` 用于 Layout、纸张、DPI 和 Configure 设置。Windows 测试页与端口应在 `打印机属性（Printer properties）` 中处理，不要把两个窗口混为一谈。

## 3. Printing Preferences 标签页

已确认的标签页为：

- `Layout`
- `Paper/Quality`
- `Configure`

现有证据没有展开 `Paper/Quality` 的内部选项。客户询问该页具体设置时，应说明目前资料未记录，不能编造；需要具体选项时回复 `转人工`。

## 4. Layout

| 设置 | 已确认的值或选项 | 用途 |
|---|---|---|
| Orientation | `Portrait`、`Landscape` | 修正页面方向 |
| Page Order | 当前显示 `Front to Back`；其他选项未展示 | 控制页序 |
| Pages per Sheet | 当前显示 `1`；其他选项未展示 | 每张纸的文档页数 |
| Draw Borders | 已确认存在复选框 | 多页合并时绘制边框 |
| Advanced... | 已确认存在按钮 | 打开 Advanced Document Settings |

整页横着或方向错误时，先让软件页面方向和 Layout 中的 `Portrait/Landscape` 一致。仅在仍需要固定旋转时，才使用 Configure 的 `page rotation`。

## 5. Advanced Document Settings

入口：`Printing preferences -> Layout -> Advanced...`。

### 5.1 已确认的纸张菜单

- `A4: 240mm*297.4`
- `S1: 240mm*93.1mm`
- `S2: 240mm*139.7mm`
- `S3: 240mm*101.6mm`
- `S4: 240mm*279.4mm`

以上名称必须按驱动界面原样记录，不得把 A4 静默改写为标准 ISO A4 尺寸。

连续纸的物理宽度与驱动菜单不是同一参数。常见二等分连续纸实际约为 `241 × 139.7mm`，驱动选 `S2: 240mm*139.7mm`，固定页高选 `139.7mm(holes 11)`；三等分连续纸实际约为 `241 × 93.1mm`，驱动选 `S1: 240mm*93.1mm`，固定页高选 `93.1mm(holes 22/3)`。驱动中的 `240mm` 是原始纸型数值，必须保留，不能改成 `241mm`。

`Copy Count` 当前显示 `1 Copy`，其他选项未展示。

### 5.2 已确认的打印质量

- `DPI:720*720`：质量较高，速度较慢。
- `DPI:180*144`：分辨率较低，可在客户优先速度时使用。

### 5.3 其他可见高级设置

- ICM Method：`ICM Disabled`
- ICM Intent：`Pictures`
- Advanced Printing Features：`Enabled`
- Pages per Sheet Layout：`Right then Down`
- Print Optimizations：`Enabled`
- Advanced OEM UI Added Item：`0`

除纸张大小和 DPI 外，证据没有展开以上下拉菜单，不得编造其他候选值。

## 6. Configure

`Printing preferences` 中点击 `Configure` 后会打开一个独立的驱动设置窗口，这是正常界面行为，不是按钮失效。后续的位置、页高、旋转和单向打印均在该独立设置窗口内调整。

### 6.1 半色调模式

已确认的选项：`Dither`、`error diffusion`、`grayscale`。默认值为 `grayscale`。普通文字和表格不需要修改；只有图片、灰度或抖动问题才使用这一组设置。

### 6.2 参数、默认值与已确认范围

| 设置 | 默认/当前值 | 已确认范围或说明 |
|---|---|---|
| print head type | `DPIX180_DPIY_144_Needle_printer` | 字段禁用；未展示其他值，客户不要修改 |
| display language | `English` | 下拉菜单未展开 |
| Horizontal adjustment | `0mm` | 1mm 步进；画面至少显示 `-15mm` 到 `20mm`，完整下限未确认 |
| Vertical position adjustment | `0mm` | `-20mm` 到 `20mm`，1mm 步进 |
| density | `standard` | 下拉菜单未展开 |
| Fixed page height | `139.7mm(holes 11)` | 勾选 Fixed page height 后才生效 |
| speed | `standard` | 下拉菜单未展开，不得编造高速或草稿档位 |
| Halftone Density | `50` | 下拉菜单未展开 |
| grayscale threshold | `249` | 只确认画面显示过 `121` 到 `249`，完整下限未知 |
| page rotation | `0` | `0`、`90`、`180`、`270` |
| start print position | `0` | 菜单未展开，没有已验证操作流程，不得指导客户调整 |
| tear-off position | `0` | `0`、`+2mm` 到 `+20mm`、`-2mm` 到 `-20mm`，2mm 步进 |

### 6.3 Fixed page height 已确认选项

- `93.1mm(holes 22/3)`
- `101.6mm(holes 8)`
- `127mm(holes 10)`
- `139.7mm(holes 11)`
- `279.4mm(holes 22)`

`93.1mm(holes 22/3)` 是驱动界面的原始显示，其中 `22/3` 表示 22 除以 3，即每页约 `7⅓` 个孔距，不是 22 或 23 个孔。三等分纸连续打印参考：一页约 `7⅓` 个孔距，两页约 `14–15` 个孔距（图片实测约 14 个孔），三页约 `22` 个孔距。该数量只用于判断送纸是否明显异常，不能代替正确设置文档尺寸、驱动纸型和 `Fixed page height`。

### 6.4 默认 Configure 状态

- Halftone：`grayscale`
- Horizontal adjustment：`0mm`
- Vertical position adjustment：`0mm`
- density：`standard`
- Fixed page height 值：`139.7mm(holes 11)`
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

Fixed page height 的数值即使已经显示，也只有勾选该复选框后才生效。

## 7. 客服处理流程

### 7.1 整页左右偏移

1. 先确认源文档、驱动纸张大小和实体纸一致。
2. 打开 `Printing preferences -> Configure`。
3. 使用 `Horizontal adjustment`，每次按 1mm 小幅调整。
4. 每次只改一个方向，按第 8 节重新加载并测试一张。

### 7.2 整页过高或过低

1. 确认纸张起始装载位置正确。
2. 确认源文档与驱动纸张大小一致。
3. 打开 `Printing preferences -> Configure`。
4. 使用 `Vertical position adjustment`，每次按 1mm 小幅调整。
5. 每次只改一个方向，按第 8 节测试。

### 7.3 页面方向错误

1. 打开 `Printing preferences -> Layout`。
2. 先选择与文档一致的 `Portrait` 或 `Landscape`。
3. 只有还需要固定旋转时，才在 Configure 使用 `page rotation 0/90/180/270`。

旧 JM/JMS 驱动的方向选项属于其他驱动分支，不得与统一驱动步骤混用。

### 7.4 后进连续纸页长或停位错误

1. 测量或确认纸张高度与单边孔数。
2. 在 `Layout -> Advanced...` 选择对应的驱动 Paper Size。
3. 在 Configure 选择对应的 Fixed page height，并勾选 `Fixed page height`。
4. 在本流程中取消以下五项：
   - Remove white space at the bottom of the page
   - delete left blank page
   - Remove white space at the top of the page
   - Output bitmap image to computer
   - Paper edge hole length calculation
5. 除非同时排查打印速度，否则不要改变 One-way printing。
6. 按该版本界面点击 `import` 应用 Configure 设置。
7. 执行第 8 节保存后流程，只打印一张测试。

### 7.5 未停在撕纸线

1. 先让打印软件、驱动和实体纸的尺寸一致。
2. 后进连续纸先完成 Fixed page height 和重新装纸流程。
3. 尺寸和进纸正确时，纸张通常会自动到达撕纸位置；这不代表机器支持自动撕纸或自动退纸。
4. 仍只剩小幅误差时，使用 Configure 的 `tear-off position` 按 2mm 步进微调。
5. 每次修改后保存并只测试一张。

没有已验证的 `start print position` 操作流程，不得把它与已确认的 tear-off position 微调混在一起。

### 7.6 打印速度太慢

方法一：在 `Layout -> Advanced... -> Graphic -> Print Quality` 中，把 `DPI:720*720` 改为 `DPI:180*144`。速度可提高，但清晰度会降低。

方法二：在 Configure 取消 `One-way printing`，允许双向打印。速度可提高，但可能影响对位或打印质量。

可以分别或组合测试。如果清晰度或对位变差，恢复原设置。统一驱动的 speed 字段只确认当前值为 `standard`，未展开其他档位，不得编造高速或草稿档位。

### 7.7 不打印或连接错误

1. 打开 `设备和打印机 -> 右击打印机 -> 打印机属性 -> 端口`。
2. 确认勾选的端口与实际 USB、串口、网络、Wi-Fi 或蓝牙队列/连接一致。
3. 不得复制演示电脑或其他电脑的 IP 地址、端口或队列名。
4. 使用 Windows `打印测试页` 区分驱动/连接问题和打印软件/模板问题。

### 7.8 图片或灰度效果异常

1. 先确认普通文字是否正常。
2. 只在图片或灰度问题中比较 `Dither`、`error diffusion`、`grayscale`。
3. Halftone Density 或 grayscale threshold 每次只小幅修改一个值，并先记录原值。
4. 效果变差时恢复原值；不要声称完整范围已经确认。

## 8. 保存设置后的必做流程

每次保存驱动设置后：

1. 完全关闭当前打印软件并重新打开。
2. 将纸张从打印机中取出并重新正确装入。
3. 批量打印前先只打印一张测试。

## 9. 禁止编造的内容

- 不描述未展开的 `Paper/Quality` 内部设置。
- 不编造未展示的 speed、density、display language 或其他下拉选项。
- 不声称 Horizontal adjustment 的完整下限低于 `-15mm`。
- 不声称 grayscale threshold 的完整范围已经确认。
- 不把示例队列、模块编号或 Configure 日期后缀当成通用型号。
- 不复制演示电脑的 IP 或端口。
- 数据库没有明确记录的驱动设置、范围或步骤，统一说明资料未确认并回复 `转人工`。
