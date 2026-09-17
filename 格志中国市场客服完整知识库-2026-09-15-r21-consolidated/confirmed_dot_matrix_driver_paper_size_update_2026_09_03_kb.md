---
knowledge_base: confirmed_dot_matrix_driver_paper_size_update_2026_09_03
version: "2026-09-03"
language: zh-CN/en
status: confirmed
scope: "中国市场 Windows 针式打印机驱动纸张尺寸和固定页高设置"
source: "用户提供的 Windows 驱动设置视频及用户确认更正"
---

# Windows 针式打印机驱动纸张尺寸设置

## 中文客服知识

1. 打开 `开始 → 设置 → 设备 → 蓝牙和其他设备`，在相关设置中打开`设备和打印机`。
2. 找到正在使用的实体打印机，右击并选择`打印首选项/Printing Preferences`。
3. 点击`高级/Advanced`，在`纸张/输出`下打开`纸张规格`，选择与实际纸张匹配的纸型，点击`确定/OK`。
4. 返回打印首选项并进入 `Configure`。`Configure` 名称固定，不写成 `Configure-xxxx`。
5. 在固定页面高度中按实际撕线间距/驱动孔数选择：
   - 三等分：`93.1 mm（holes 22/3）`
   - 其他可选高度：`101.6 mm（holes 8）`、`127 mm（holes 10）`
   - 二等分：`139.7 mm（holes 11）`
   - 整张：`279.4 mm（holes 22）`
6. 后进连续纸时勾选`固定页面高度/Fixed page height`，并取消勾选`删除页面底部空白`、`删除左边空白页`、`删除页面顶部空白`、`将位图图像输出到计算机`和`纸边孔长计算`。`单向打印保持原设置`，除非另有速度或重影专项排查。点击`导入/Import`，再点击`确定/OK`保存。
7. 保存后必须完成两项操作：
   - 完全关闭并重新打开用于打印的软件。
   - 从打印机中取出纸张，按新规格正确重新装入，然后试打。

客服边界：

- 页高规格用“整张/二等分/三等分”表述；“二联/三联/六联”只表示复写纸层数。
- 不只按 `A4/S2/S3` 名称判断，应对照实际撕线间距、驱动显示的页高/孔数和纸张规格。
- 本统一驱动的标签页和本文列出的预设名称适用于当前支持的针式打印机型号，包括 Wi-Fi/蓝牙版本；但不能据此扩大各机型的物理进纸方式、纸宽和接口能力。
- 文档页面尺寸也必须与驱动设置一致，否则可能出现跨页、偏移或撕纸位置不正确。

## English customer-service knowledge

1. Open **Start → Settings → Devices → Bluetooth & other devices**, and then open **Devices and Printers** under Related Settings.
2. Right-click the physical printer currently in use and select **Printing Preferences**.
3. Select **Advanced**, open the paper specification under **Paper/Output**, choose the preset matching the actual paper, and click **OK**.
4. Return to Printing Preferences and open **Configure**. The tab is always named **Configure**; do not write `Configure-xxxx`.
5. Select the fixed page height according to the actual perforation interval/driver hole value: `93.1 mm (holes 22/3)`, `101.6 mm (holes 8)`, `127 mm (holes 10)`, `139.7 mm (holes 11)`, or `279.4 mm (holes 22)`.
6. For rear-fed continuous paper, select **Fixed page height**. Clear **Remove white space at the bottom of the page**, **delete left blank page**, **Remove white space at the top of the page**, **Output bitmap image to computer**, and **Paper edge hole length calculation**. Leave **One-way printing** unchanged unless speed or ghosting is being handled separately. Click **Import**, and then click **OK**.
7. After saving, completely close and reopen the software used for printing. Then remove the paper from the printer, reinsert it correctly according to the new setting, and perform a test print.
