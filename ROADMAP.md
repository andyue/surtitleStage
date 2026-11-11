# SubtitleStage — 開發 Roadmap

## 開發策略

採取小型、可以驗證的 Milestone。

每一版都應保持：

- 可以 Build
- 可以 Run
- 核心功能可以操作

有 Critical Playback / Output Bug 時，不要急著進下一版。

開發優先：

Reliability
→ Core Workflow
→ Output Flexibility
→ Integration
→ Advanced Media

---

# 目前狀態與下一版 — 2026-10-21

目前 GitHub 已發布 **App v0.5.2（build 12）**，與本機版本一致。App 版本號與下方功能里程碑分開管理；V0.3 mapping 程式已納入，但 V0.2 仍有後續工具未完成，V0.3 已獲使用者確認實體多外接螢幕與電腦螢幕 Fade OK，其餘現場驗收仍待進行。

## 目前工作：v0.5.0 Inter-Application Video Output

使用者已授權 V0.5。本機版本 0.5.2（build 12），格式 11。

2026-10-21：依 QLab 反向畫面回報修正 Syphon 垂直座標轉換；新增方向回歸測試，修正後 QLab 人工驗收待確認。其後依使用者授權實作 NDI sender，採可選 runtime，詳見 NDI.md。

- [x] 每 Output 獨立 Syphon Server、名稱、透明／黑底、30／60 fps。
- [x] 沿用 Canvas／Output resolution、Layout、Region mapping，不要求實體顯示器。
- [x] 背景文字 raster、Metal Fade／Opacity／Blackout、有限排程與安全停止。
- [x] 官方固定版本 Universal framework、授權、來源及離線重建腳本。
- [x] 格式 1–9 遷移至 10；舊輸出預設不啟用 Syphon。
- [x] 真實 Syphon Client、多 Server、Alpha／Fade／Blackout 與回歸測試。
- [x] NDI sender：多來源、透明背景、Fade／Blackout、30／60 fps、可選動態 runtime；格式 1–10 遷移至 11。
- [ ] NDI 跨機器／實際接收軟體、斷網重連與長時間驗收。
- [ ] TouchDesigner／MadMapper 人工互通、多路 1080p／4K 長時間與接收端重啟驗收。

詳見 V0.5_VERIFICATION.md、NDI_EVALUATION.md。不提前實作 V0.6，既有現場驗收缺項跨版本保留。

## v0.4.0 已完成基礎：Structured Document Import

V0.4 完成時版本為 0.4.0（build 9），專案格式 9；GitHub 已發布仍為 v0.2.2。

- [x] File 選單集中 Import／Re-import；匯出目前 Cue Sheet 與含欄位說明的 XLSX 範本。
- [x] Merge by Cue Number：不同語言補入同一 Cue；只更新映射文字、保留 UUID，重複編號阻擋。
- [x] XLSX 欄位可直接 New Surtitle；預覽暫存，Apply 一次新增／合併，可 Undo。
- [x] XLSX 多工作表選擇、可修正的 Header 偵測、欄位映射與預覽。
- [x] 自訂文字欄位對應既有 Surtitle；Cue Number、Speaker、Notes 與 Target／Dialogue 路由。
- [x] 獨立 stable source ID 對應 Cue UUID；重新匯入列出 UNCHANGED／MODIFIED／NEW／DELETED。
- [x] 本機文字衝突與刪除預設不選；操作者逐項確認，保留既有 UUID、格式、配置及轉場。
- [x] DOCX 段落、角色／台詞、表格儲存格、標題辨識與整段一致的粗體／斜體／底線。
- [x] Import Workspace：預覽、編輯、Split／Merge、Ignore、Assign Speaker／Layer、Renumber、Validation。
- [x] 背景解析／比對、一次套用與 Undo；阻擋過期預覽及影響 Live Cue 的套用。
- [x] 格式 1–8 明確遷移至 9，儲存匯入來源與基準文字；複製 Cue 不複製來源綁定。
- [ ] 使用者實際 Excel／Word 文件與新版 IME 工作區人工驗收。

限制：Excel 使用已儲存的公式快取，不重新計算；數值日期不套用 Excel 顯示格式。DOCX 混合字元樣式會提示後攤平，沒有可靠來源鍵，因此本版不提供 DOCX re-import。匯入工作區 Split／Merge 不代表 production Cue List 的 Split／Merge 已完成。詳見 V0.4_VERIFICATION.md。

## v0.3.0 已完成基礎：Configurable Canvas & Multi-Output Mapping

使用者已明確要求實作 V0.3。本機版本為 0.3.0（build 6），格式 8；目前 GitHub 已發布仍為 v0.2.2。此進度不代表其餘 V0.2 缺項已完成。

- [x] Primary Canvas 自訂尺寸與 Presets。
- [x] 多 Output：enabled、display ID、signal resolution、assigned canvas、mapping。
- [x] Region UUID／命名／來源 crop／目的地 frame／可見性與存讀檔。
- [x] 來源與目的地 Visual Mapper、拖拉、縮放、數值 Apply。
- [x] Fit／Fill／Stretch／1:1 Pixel 與實際設備像素檢查。
- [x] 任意比例、邊界、遷移、獨立輸出 mapping、原生 raster 與桌面測試。
- [x] 實體多外接螢幕、Fade 在電腦螢幕：2026-10-19 使用者回報 OK。
- [ ] 拔插／重連、LED Processor／1:1 格線、長時間播放及不同更新率的實機驗收。

Multiple Canvas 評估：持續使用集合與穩定 Canvas UUID，Output／Region 可指派集合中的 Canvas，renderer 消費對應 Canvas；依 Roadmap 允許，本版 UI 只建立及編輯 Primary Canvas，不加入多 Canvas 管理工作區。

詳細操作、驗證證據與限制見 V0.3_VERIFICATION.md。未完成的現場驗收跨版本保留；目前依使用者要求進入 V0.5，不提前實作 V0.6。

## v0.2.x 已納入的基礎（歷史基線）

- Codable 專案格式 7、格式 1–6 遷移、New／Open／Save／Save As、背景 I/O、原子存檔及未儲存提示。
- 永久 Cue UUID、單列新增／刪除／重排、表格編輯、多 Surtitle 命名與複製、100 步 Undo／Redo。
- selectedCue／liveCue／blackout 分離，GO／Previous、雙擊 Cue 播放、Blackout／Restore、逐 Cue Fade In／Out。
- Text Modify 及逐屬性 Batch；Live Cue 的文字／格式及 Layout 修改立即更新輸出。
- 自訂 Canvas（整數 1–32768 pixels）、非標準比例預覽、多 Output slots、獨立字幕 Layout／可見性／旋轉、全螢幕輸出。實際仍使用主 Canvas 與 Fit。
- 剪貼簿逐行／逐段匯入、目標 Surtitle 選擇、預覽確認後插入。
- OSC 分頁、UDP 接收、GO／Previous、Blackout 明確開關或切換、依 UUID 跳 Cue。

## 已完成增量：Cue 編輯工作流（App v0.2.3）

v0.2.3 已完成以下程式與自動測試，尚待新版人工 UI 驗收及發布。GitHub 目前已發布版本仍為 v0.2.2。

- [x] 接回 Cue Details：編輯 displayNumber、名稱與備註，維持 UUID 不變。
- [x] Duplicate Cue：複製所有 Surtitle 文字、格式與轉場；副本取得新 UUID，插在來源後方，不自動播放。
- [x] 多選 Cue 與批次刪除：維持原順序，包含 Live Cue 時整批拒絕並說明原因，避免部分刪除。
- [x] 快速重新編號：依列表順序更新選取 Cue 的 displayNumber，提供起始值及預覽；不改 UUID／文字／Live。
- [x] 以上操作整合 Undo／Redo、未儲存狀態與存讀檔；一次批次操作為一步 Undo。

完成條件：修改前基線 Build／Tests、修改後 Build／相關測試通過；驗證 UUID、選取與 Live 分離、Undo／Redo、存讀檔、中文輸入。人工驗收與自動測試分別記錄。

Split／Merge 留在後續 Cue 編輯增量，先定義多語對齊、格式／轉場繼承及 Live Cue 保護規則，再實作。文字溢出／缺字警告為下一優先增量；Auto Fit、最大行數、Safe Area、中文斷行隨後處理。

本增量不包含 Scene、獨立 Layer 推進、Dissolve、Region Mapper、1:1 Pixel、Excel／Word、Syphon／NDI 或 Media Layers。下方長期里程碑保留，不因部分功能提前納入就視為完成。

## 驗收與發布限制

- 使用者於 2026-10-18 回報：繁中／簡中 IME、候選字、實體播放快捷鍵及 OSC 控制器／演出網路 OK；已試過的 Cue Sheet／舊專案存讀檔目前 OK。
- 使用者於 2026-10-19 回報實體多外接螢幕與電腦螢幕 Fade OK；拔插／重連、長時間播放、不同更新率及 LED 1:1 仍待驗證。這些待驗收項目需跨版本保留，不能宣稱已達完整現場可靠性驗收。
- 最近發布建置紀錄：Universal Release、簽名與 DMG 完整性檢查通過；41 項測試通過、4 項桌面測試跳過。不是本次文件更新重新執行的結果。
- 最新 V0.5 驗證見 V0.5_VERIFICATION.md；V0.4 驗證見 V0.4_VERIFICATION.md；V0.3 驗證見 V0.3_VERIFICATION.md；先前驗收狀態見 SURTITLE_WORKFLOW_VERIFICATION.md；操作與限制見 README.md／OSC.md。

---

# V0.1 — Core Subtitle Playback

目前 V0.1 依現場操作回饋擴充：多 Surtitle 表格、可預先建立及命名的 Output slots、每 Output 獨立即時 Layout、逐 Cue Text Modify／Fade，以及 100 步 Undo／Redo。另依使用者要求加入 OSC UDP 接收、GO／Previous、Blackout 明確開關及 UUID 跳 Cue（操作與範圍見 OSC.md）。這些是使用者明確要求的 V0.1 範圍；不代表下列 V0.2+ 其餘項目已開始。

目標：

完成最小但真的可以操作的字幕播放 App。

## Project

- 建立 macOS Native Swift Project
- Models / Stores / Playback / Output / Views 架構
- Codable Project Model
- New Project
- Save
- Save As
- Open

## Cue List

- Add Cue
- Delete Cue
- Reorder Cue
- Edit Cue
- Permanent UUID
- Display Number
- Cue Name
- Notes

## Playback

- selectedCue
- liveCue
- GO / Next
- Previous
- Blackout
- Blackout Restore

## Keyboard

- Space = GO
- Left Arrow = Previous
- B = Blackout Toggle
- Escape = Blackout
- 正確處理文字編輯 Focus
- 正確處理中文 IME

## Text

- 繁體中文
- 簡體中文
- English
- Unicode
- macOS Installed Fonts
- Font Size
- Alignment
- Character Spacing
- Line Spacing

## Canvas

預設：

1920 × 1080

但是 Canvas Width / Height 從第一版開始就必須是可設定資料。

任何 Renderer / Preview Code：

不得假設 1920 × 1080。

不得假設 16:9。

## Preview

- Scaled Canvas Preview
- 保留 Logical Pixel Coordinates
- 支援任意 Aspect Ratio

## Output

- 偵測 macOS Displays
- 選擇 External Display
- Borderless Output Window
- Fullscreen Output
- Blackout

## Import

Paste As Cues

支援：

- Line
- Paragraph

並提供 Import Preview。

## Tests

- Playback
- Cue Ordering
- Clipboard Importer
- Save / Load
- Canvas Coordinate Conversion

---

# V0.2 — Production Subtitle Workflow

目標：

從基本字幕播放器進入真正劇場可用的字幕 Workflow。

## Layers

- Multiple Text Layers
- Layer Visibility
- Layer Naming
- Layer Frame Editing

## Multilingual

典型配置：

surtitle1
surtitle2
surtitle3
可以點選編輯surtitle名稱

一個 Cue 可以同時更新多個 Layer。

## Scenes

加入 Scene Concept。

一個 Cue 可以 Atomic 地改變多個 Layer State。

## Text Tools

- Auto Fit
- Maximum Lines
- Overflow Warning
- Safe Area
- Missing Glyph Warning
- 更好的中文斷行

## Cue Editing

- Split Cue
- Merge Cue
- Duplicate Cue
- Multi-selection
- Fast Renumbering

## OSC

實作 OSC Receiver。

初期：

/subtitle/go

/subtitle/previous

/subtitle/blackout

/subtitle/cue/{id}

/layer/{name}/next

## Transitions

初期：

- Cut
- Fade / Dissolve

這個階段不要建立複雜 Animation System。

---

# V0.3 — Configurable Canvas & Multi-Output Mapping

程式已納入本機 v0.3.0；實體多外接螢幕與電腦螢幕 Fade 已由使用者確認，LED 等其餘驗收尚待完成。詳見上方目前狀態與 V0.3_VERIFICATION.md。

目標：

支援專業：

- LED Wall
- Projection
- Video Processor
- Multi-display

重要：

這一版不能稱為：

「4K Canvas」

正確概念是：

「Configurable Master Canvas」

3840 × 2160 只是一個 Preset。

## Canvas Configuration

允許：

- Width
- Height
- Custom Resolution
- Resolution Presets

Preset 可包含：

1920 × 1080

1920 × 1200

2560 × 1440

3840 × 1080

3840 × 2160

4096 × 2160

Custom

Custom 必須接受任意合理 Pixel Dimension。

不得假設 16:9。

## Multiple Canvases

評估 Project 內支援多個 Logical Canvas。

例如：

Main LED Canvas

Side Projection Canvas

Broadcast Canvas

即使 V0.3 UI 暫時只提供一個 Primary Canvas，Architecture 也不能阻止未來 Multiple Canvas。

## Multiple Physical Outputs

OutputManager 必須管理：

Collection of Outputs

每個 Output：

- Display ID
- Output Resolution
- Assigned Canvas
- Mapping Configuration
- Enabled State

## Output Mapper

建立 Visual Output Mapper。

顯示：

Canvas Boundary

允許建立 Region。

Region 可以：

- Drag
- Resize
- Numeric X
- Numeric Y
- Numeric Width
- Numeric Height

## Region Mapping

每個 Region：

- UUID
- Name
- Source
- Destination Frame
- Crop
- Scale
- Position

保留未來：

- Rotation
- Flip
- Mask

## Pixel Accuracy

所有 Region Coordinate 使用 Canvas Pixels。

例如：

Canvas：

5760 × 1080

Region A：

X 0
Y 0
1920 × 1080

Region B：

X 1920
Y 0
1920 × 1080

Region C：

X 3840
Y 0
1920 × 1080

Preview Scale 不得改變這些數值。

## LED Wall Workflow

支援一個大型 Physical Signal 內包含多個 Display Region。

例如：

Mac Output：

3840 × 2160

LED Processor 接收整個訊號。

裡面：

Region A
Region B
Region C

SubtitleStage 決定內容放在 Signal 的哪個 Pixel Region。

LED Processor 再將各區域 Mapping 到實際 LED。

## Crop / Scale / Position

必須是 Deterministic Mapping。

不要偷偷做 Aspect Ratio Correction。

提供：

- Fit
- Fill
- Stretch
- 1:1 Pixel

LED Workflow 中：

1:1 Pixel 非常重要。

## Tests

- Arbitrary Canvas Size
- Ultra-wide Canvas
- Non-16:9 Canvas
- Region Coordinate Conversion
- Region Boundary Validation
- Output Assignment
- Multiple Simultaneous Outputs

---

# V0.4 — Structured Document Import

目標：

整合正式製作使用的字幕文件。

## Excel

XLSX Import：

- Sheet Selection
- Header Detection
- Column Mapping
- Import Preview

Mapping：

Cue Number

Speaker

Chinese

English

Target

Notes

不得固定 Spreadsheet Schema。

## Excel Re-import

建立 Update Workflow。

比較新版資料與 Existing Project：

UNCHANGED

MODIFIED

NEW

DELETED

Operator 確認後才 Apply。

盡可能保留：

- Cue Formatting
- Layer Configuration
- Output Mapping
- Transition Configuration

## DOCX

Word Import：

解析：

- Paragraph
- Character Name
- Dialogue
- Basic Formatting
- Table
- Heading

建立 Import Workspace。

## Import Workspace

支援：

- Preview
- Split
- Merge
- Ignore
- Assign Speaker
- Assign Layer
- Renumber
- Validation

---

# V0.5 — Inter-Application Video Output

目標：

整合專業 Visual Workflow。

## Syphon

SubtitleStage
→ Syphon
→ TouchDesigner

或：

SubtitleStage
→ Syphon
→ MadMapper

盡可能支援 Alpha。

## NDI

評估 NDI Integration。

NDI 應為 Optional。

不能因為 NDI 不存在而導致 Core Application 無法啟動。

---

# V0.6 — Media Layers

## Image

- PNG
- JPEG
- Alpha
- Scale Modes

## Video

使用 AVFoundation。

初期：

- Load
- Play
- Stop
- Loop
- Basic Positioning

SubtitleStage 不需要變成完整 Media Server。

---

# V1.0 — Production Release Target

進入 1.0 前至少完成：

- Reliable Project Persistence
- Reliable Chinese Text Rendering
- Cue Playback
- Multiple Text Layers
- OSC
- Multiple Displays
- Configurable Canvas
- Output Mapping
- Region Mapping
- Excel Import
- Crash-resistant Live Playback
- 大量實際演出測試

Nice-to-have：

- DOCX
- Syphon
- NDI
- Media Layers

---

# Future Exploration

未來可研究：

- MIDI
- Stream Deck / Companion
- Web Remote
- ESP32 Remote
- Cue Groups
- Cue Sequences
- Auto-follow
- Timecode
- CSV
- Google Sheets
- SRT / VTT
- 中文直排
- Ruby Annotation
- Per-character Styling
- Advanced Transitions
- Backup Output Machine Synchronization

在實際 Production Requirement 尚未確認之前，不要讓這些功能過早影響 Core Architecture。

## 使用者要求增量：Glypheo 匯入（2026-11-11）

已接入 `.glypheo` 純文字多 Track 匯入、欄位映射、預覽、停用 Cue 保護及來源 ID re-import；沿用 V0.4 Import Workspace。不改變 V0.6 範圍或宣稱完成實機驗收。詳見 GLYPHEO_VERIFICATION.md。
