# SubtitleStage — 專案規格

## 文件定位與目前實作（2026-10-21）

本文件描述產品目標；未標示已實作的欄位或能力，不應解讀為目前都有提供。發布版本為 App v0.5.4（build 16，最低部署 macOS 13），專案格式為 12。已完成範圍及下一個開發增量以 ROADMAP.md「目前狀態與下一版」為準；操作以 README.md、OSC.md 為準；最新驗證以 V0.5_VERIFICATION.md 為準，先前人工驗收見 SURTITLE_WORKFLOW_VERIFICATION.md。V0.1_VERIFICATION.md、LAYOUT_VERIFICATION.md 是歷史紀錄。

目前行為約定：

- 選取不等於播放；編輯目前 Live Cue 的文字／格式，以及修改 Layout，會立即更新 Live。此為使用者要求的現行工作流，不能在下一版無意改回凍結快照。
- Blackout 保留 Live Cue；若黑場期間有編輯或明確播放操作，Restore 顯示更新後的 Live 內容。
- v0.5.4：Start Output 會先播放當下選取 Cue。預設 Show Controls 取得焦點時 Space 為 GO／Next、Esc 為 Stop Output，可自訂其他播放熱鍵；文字編輯與 IME 優先。輸出視窗保留 Esc 停止輸出，雙擊輸出畫面也可停止輸出並保留 Live／黑場狀態。
- 多 Surtitle／多 Output 已有實作，但正式 Scene／逐 Cue Layer 幾何及可見性狀態、獨立 Layer 推進未實作。
- Canvas 可自訂尺寸與 Presets；v0.3 已加入 Output signal resolution、Region source crop／destination、Fit／Fill／Stretch／1:1 Pixel。字幕 Layout 是來源內容配置，Region Mapper 是輸出訊號配置。UI 本版只建立／調整 Primary Canvas，資料與渲染仍支援 Canvas collection。
- Cue Fade 是依序淡出、切換、淡入，尚無新舊內容交疊的 Dissolve。
- v0.5.4 依使用者要求移除 Cue Details 畫面；保留既有檔案 metadata。Duplicate Cue、批次勾選刪除與編號預覽維持；批次勾選是暫態編輯狀態，與 selectedCue／liveCue 分離。Split／Merge 尚未實作。

## 1. 產品定位

SubtitleStage 是一套 macOS 原生的 Cue-based 字幕與文字播放軟體，主要使用情境包括：

- 劇場演出
- 現場活動
- 簡報
- 裝置藝術
- LED 電視牆
- 投影系統
- 多語字幕製作

第一階段優先解決中文與多語字幕的操作問題，同時從一開始就建立可以支援專業多輸出系統的架構。

概念上結合：

- Cue-based Playback
- 專業字幕編輯
- Scene / Layer 合成
- 可自訂解析度的 Pixel Canvas
- 多螢幕輸出
- Output Region Mapping
- OSC 現場控制

工作流程可以參考 Glypheo、QLab 等軟體，但不複製其 UI、內部架構或專有功能。

長期目標是：

> 建立一套可靠、快速、適合現場演出的文字與媒體輸出引擎。

---

# 2. 核心設計原則

優先順序：

1. 現場演出可靠性
2. Playback 行為必須可預測
3. 架構清楚
4. 操作速度
5. 中文與多語 Typography
6. 彈性的輸出 Mapping
7. 視覺效果

SubtitleStage 必須能在正式演出期間長時間穩定運作。

Playback 不應依賴：

- Internet
- Cloud Service
- 外部伺服器

---

# 3. 平台

目標：

- macOS
- Native Application

主要技術：

- Swift
- SwiftUI
- 必要時使用 AppKit
- CoreText / TextKit：進階文字排版
- Metal / MetalKit：未來 Renderer
- AVFoundation：未來影音播放

不要使用：

- Electron
- React
- WebView 作為主要 UI
- 依賴 Cloud 的 Renderer

---

# 4. 核心架構

基本階層：

Project
→ Canvas
→ Scene / Layer
→ Cue State
→ Output

這些概念必須彼此分離。

Cue 不等於 Output。

Layer 不等於實體 Display。

Canvas 解析度也不一定等於實體 Display 解析度。

---

# 5. Project

Project 包含：

- Project Metadata
- Canvas Definitions
- Layer Definitions
- Cue List
- Output Configuration
- Import Metadata
- 未來 OSC Configuration

Project Data 必須支援 Codable。

未來 Project File 可使用：

.substage

作為副檔名。

早期開發階段可直接使用 JSON。

---

# 6. Canvas

Canvas 代表 Renderer 使用的「邏輯 Pixel 座標系統」。

例如：

Canvas

Width = 3840
Height = 2160

但：

3840 × 2160 只是一個範例。

Canvas Resolution 必須可以自由設定。

程式絕對不能假設：

- 1920 × 1080
- 3840 × 2160
- 16:9
- 1080p
- 4K

實際現場可能出現：

1920 × 1080

3840 × 2160

3840 × 1080

4096 × 2160

5760 × 1080

2560 × 960

2688 × 768

或其他任意 Custom Resolution。

這對：

- LED Processor
- LED 電視牆
- Video Wall
- Projection System
- 特殊舞台螢幕

非常重要。

所有 Rendering Geometry 必須從：

canvas.width
canvas.height

取得。

禁止使用固定解析度常數。

---

# 7. Canvas 座標

所有 Layer 與 Region Geometry 使用：

Canvas Pixel Coordinates

例如：

Canvas：

5760 × 1080

Region A：

X = 0
Y = 0
W = 1920
H = 1080

Region B：

X = 1920
Y = 0
W = 1920
H = 1080

Region C：

X = 3840
Y = 0
W = 1920
H = 1080

Preview 可以縮小顯示 Canvas。

但是：

Preview Scale 絕對不能改變內部 Canvas Coordinates。

---

# 8. Layers

Renderer 採 Layer-based 架構。

第一階段 Layer：

TextLayer

未來：

- ImageLayer
- VideoLayer
- ShapeLayer
- GroupLayer

TextLayer 應包含：

- UUID
- Name
- Frame
- Font Family
- Font Weight
- Font Size
- Text Color
- Horizontal Alignment
- Vertical Alignment
- Character Spacing
- Line Spacing
- Maximum Lines
- Auto-fit Mode
- Background
- Outline
- Shadow
- Visibility

未來中文 Typography 可加入：

- 中文直排
- Ruby / 注音／標註
- Font Fallback
- 單字或單字元格式

---

# 9. Cue Model

每個 Cue 必須擁有永久 UUID。

例如：

Cue

- id: UUID
- displayNumber
- name
- note
- layerStates

重要：

displayNumber 不是 Identity Key。

Cue UUID 在以下操作後都必須維持不變：

- Reorder
- Renumber
- Edit
- Excel Re-import
- Project Save / Load

這是未來 Diff / Update Workflow 的基礎。

---

# 10. Playback State

必須分開管理：

selectedCue

liveCue

blackoutState

選取 Cue 不代表立即送出。

GO 才會改變 Live Output。

Blackout：

隱藏輸出，但不刪除目前 liveCue。

取消 Blackout：

恢復原本 Live Content。

---

# 11. Transport Controls

第一階段：

- GO / Next
- Previous
- Blackout

未來：

- Stop
- Fade
- Jump to Cue
- Load
- Auto-follow

---

# 12. Keyboard Control

初期快捷鍵：

Space
→ GO / Next

Left Arrow
→ Previous

B
→ Blackout Toggle

Escape
→ Blackout

Keyboard Shortcut 必須尊重文字編輯 Focus。

特別是中文 IME 輸入時，不得攔截：

- Space
- Enter
- Arrow Keys
- 一般字元

不能因為 Playback Shortcut 造成中文輸入法失效。

---

# 13. Preview

Operator UI 中央提供完整 Canvas Preview。

Preview 必須：

- 保持 Canvas Aspect Ratio
- 根據 UI 空間等比例縮放
- 保持 Pixel Coordinate Mapping
- 支援任意 Aspect Ratio

未來 Preview Overlay：

- Layer Bounds
- Region Boundaries
- Safe Area
- Pixel Coordinates
- Output Assignment

---

# 14. Physical Output

Output 與 Canvas 必須分離。

Physical Output 可能是：

- HDMI
- DisplayPort
- Thunderbolt
- LED Processor
- Projection Processor
- Video Wall Processor

App 必須取得 macOS 可用 Displays。

Output Window：

- Borderless
- 無 Toolbar
- 無 Operator UI
- 不應搶 Operator Focus
- 只 Render Output Content
- 支援 Blackout

禁止假設只有兩個 Display。

---

# 15. Output Mapping

未來 Output Mapper：

Canvas
→ Output
→ Region

一個實體 4K Output 可以包含多個獨立 Region。

例如：

3840 × 2160 HDMI

裡面可以配置：

- Chinese Subtitle
- English Subtitle
- Stage Right Screen
- Stage Left Screen

外部 LED Processor 再將這些區域分配給實際 LED。

---

# 16. Region Mapping

Region Properties：

- UUID
- Name
- X
- Y
- Width
- Height
- Crop
- Scale
- Position
- Optional Rotation
- Source Assignment

所有數值都必須可以精確輸入。

除了 Visual Drag / Resize 外，也必須提供 Numeric Input。

Pixel Accuracy 是必要條件。

---

# 17. Multiple Outputs

未來必須支援多組 Output 同時運作。

例如：

Operator Display

HDMI 1
→ Main LED

USB-C Display
→ Side Projection

Syphon
→ TouchDesigner

NDI
→ Broadcast

同一個 Canvas 可以送到多個 Output。

不同 Output 未來也可以使用不同 Canvas。

OutputManager 不得以「只有一個 External Display」為前提設計。

---

# 18. 中文與多語文字

中文是主要 Workflow。

至少支援：

- 繁體中文
- 簡體中文
- English
- Japanese
- Korean
- Mixed Language
- Unicode

文字輸入必須正確支援 macOS IME Composition。

未來 Text Validation：

- Overflow
- Missing Glyph
- 超過最大行數
- 超出 Safe Region

---

# 19. Clipboard Import

Paste As Cues 是核心功能。

初期支援：

- Split by Line
- Split by Paragraph

未來：

- 中文標點切割
- Maximum Character Count
- Maximum Line Count
- Automatic Subtitle Segmentation

Import 必須先 Preview，再真正建立 Cue。

---

# 20. Excel Import

Excel 定位為：

「結構化 Cue Sheet」

未來必須支援 Column Mapping。

例如：

Excel Cue No.
→ Display Number

Speaker
→ Speaker

Chinese
→ Chinese Text Layer

English
→ English Text Layer

Screen
→ Target

Note
→ Note

Excel Column Name 不得寫死。

因為不同製作單位的 Excel 格式一定不同。

---

# 21. Excel Re-import

未來支援從新版 Excel 更新既有 Project。

顯示：

UNCHANGED

MODIFIED

NEW

DELETED

Existing Formatting 與 Output Mapping 應盡可能保留。

Cue UUID 是穩定 Identity 的基礎。

---

# 22. Word Import

DOCX 主要定位為：

劇本／原始文本來源。

未來解析：

- Paragraph
- Character Name
- Dialogue
- Bold / Italic
- Heading
- Table
- Stage Direction

Import 必須經過 Import Workspace。

系統可以自動判斷，但不能直接偷偷修改正式 Cue List。

Operator 必須確認後才能 Import。

---

# 23. Import Architecture

所有 Import 最後都轉成相同 Internal Model。

DOCX
XLSX
Clipboard

↓

Parser

↓

Import Workspace

↓

Validation

↓

Cue / Layer Internal Model

Renderer 不應知道原始資料來自 Word、Excel 或 Clipboard。

---

# 24. Project Persistence

Save / Open 必須保留：

- Canvas Definitions
- Cue UUID
- Cue Ordering
- Layers
- Text Formatting
- Notes
- Output Mapping

Transient Playback State 不需要保存。

---

# 25. 外部控制

主要規劃：

OSC

目前已實作的字幕 OSC Address（詳見 OSC.md）：

/subtitle/go

/subtitle/previous

/subtitle/blackout

/subtitle/cue/{UUID}

尚未實作的獨立 Layer 指令：

/layer/A/next

/layer/B/next

未來：

- MIDI
- HTTP / WebSocket
- Companion
- ESP32 Hardware Controller

---

# 26. Video Interface

未來可能支援：

- Syphon
- NDI

Syphon 特別適合：

SubtitleStage
→ TouchDesigner

SubtitleStage
→ MadMapper

這些不是 V0.1 必要功能。

---

# 27. Reliability

Live Renderer 應盡可能與 Editing Operation 分離。

長期架構目標：

Operator UI 發生較重的 Editing Operation 時，不應不必要地中斷目前 Output。

避免加入不必要 Runtime Dependency。

---

# 28. Testing

至少測試：

- Cue Ordering
- Next
- Previous
- Blackout
- Project Serialization
- Project Deserialization
- Clipboard Parsing
- Canvas Coordinate Calculation

未來：

- Region Mapping
- Excel Parsing
- Re-import Diff
- Output Routing

---

# 29. Early Version 不做的事情

初期不要做：

- Full Video Editor
- 完整 Projection Mapping Software
- Timeline Editor
- Cloud Collaboration
- Web Application
- 複雜 Animation System

第一個目標是：

> 一套可靠、專業、Cue-based 的現場文字播放軟體。

## V0.4 實作邊界（2026-10-19）

XLSX／DOCX Parser 只產生 DocumentImportRow；Import Workspace 編輯中介資料，ImportDiff 產生逐項確認計畫，ProjectStore 檢查專案快照／session 與 Live Cue 後一次套用。檔案解析、欄位映射、差異計算與結果驗證於背景執行，不直接寫入 Production Cue。

CueImportOrigin 儲存獨立 source UUID、外部穩定 key 與最後接受的來源內容；不使用列號或 Cue displayNumber 猜配對。重新匯入保留既有 Cue 排序與製作設定，新增項目依來源順序插入目前選取 Cue 後方；缺少項目只在明確勾選後刪除。未映射的備註保留，已映射且有本機變更的欄位會標示衝突。無穩定鍵的 XLSX 與 DOCX 可初次匯入，但不提供 re-import。

DOCX 支援 body/table-cell 段落、Heading、Speaker/Character style 與冒號角色推斷；整段一致的粗體／斜體／底線可匯入。混合字元樣式、頁面版式、圖片、頁首頁尾等不屬本版文字渲染能力，預覽中會揭露限制。詳細操作與驗收見 README.md、V0.4_VERIFICATION.md。


### V0.4 File／Export 補充

依使用者要求，Import／Re-import 入口移至 File。新增 XLSX Cue Sheet 匯出與 Import Template 匯出，皆附 Import Guide；輸出為文字交換格式，保留每個 Surtitle 的文字、Cue Number、Speaker、Notes。Source ID 使用 Cue UUID，匯出不改變原專案及來源綁定；回匯可用 Merge by Cue Number 補入原 show，或首次匯入新專案後透過該來源 Re-import。完整製作設定仍由 .substage 保存。背景產生 XLSX，驗證容量／字元限制後原子寫入，不影響 Playback。


### V0.4 同 Cue 多 Surtitle 匯入

操作者可明確選 Merge by Cue Number，以本次預覽中的編號解析既有 Cue UUID；UUID 仍是永久身分，不改動既有來源綁定。配對成功只更新映射的字幕文字，未配對列可新增，不進行缺項刪除。空白／歧義編號阻擋，前導零不正規化，覆寫非空文字需確認。來源 ID 更新模式獨立保留。

XLSX 每欄的目的地選單提供 New Surtitle，工作區保存 draft LanguageLayer 與穩定 UUID，解析／預覽使用包含草稿的專案副本；Apply 檢查原始專案與 session 尚未改變後，一次寫入新字幕層、Output placement 與 Cue 文字。Cancel 不改專案，Undo 同時還原層與文字。沒有持久化模型改版。


### V0.5 Syphon／NDI 範圍（2026-10-20）

每個 Output 保存 SyphonSettings；不以 physical display ID 決定是否能啟動。訊號尺寸來自 Output resolution 或 assigned Canvas，實體輸出與 Syphon 生命週期分開。Start Syphon 不 GO、不修改 PlaybackState。共用 CanvasContentRenderer，背景合成 premultiplied RGBA8，Metal shader 套用 Opacity／Fade／Blackout，再透過官方 SyphonMetalServer 發送。

格式 10，1–9 遷移讓 Syphon 預設停用。未改 Cue UUID、Canvas pixel coordinate、Surtitle identity 或 import binding。texture／記憶體限制僅限制此輸出，不反向限制 Canvas 模型。最多一個 worker 工作，避免影格堆積。尺寸／server 設定變更會停止，文字與 Region 幾何可即時更新。

NDI 已於 v0.5.2 依使用者授權實作 sender；每個 Output 有獨立 NDISettings。格式 11 讀取 1–10，舊專案 NDI 預設停用。背景傳送採有限工作量與可選動態 runtime；無 NDI 時 App 仍可啟動。透明輸出轉成非預乘 Alpha，signal 寬度需為偶數。詳見 NDI.md。V0.6 圖片／影片不屬本次範圍。
