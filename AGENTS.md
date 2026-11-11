# SubtitleStage — Codex 開發規則

## 1. 修改程式前必讀

進行重大修改前先閱讀：

- PROJECT_SPEC.md
- ROADMAP.md
- AGENTS.md

先理解目前 Milestone。

除非使用者明確要求，否則不要提前實作後面版本的功能。

---

# 2. 最高優先原則

SubtitleStage 是 Live Production Software。

開發優先順序：

1. Reliability
2. Deterministic Behavior
3. Data Integrity
4. Clear Architecture
5. Operator Speed
6. Performance
7. Visual Polish

不得為了 UI 特效犧牲 Playback Reliability。

---

# 3. Current Milestone

根據：

ROADMAP.md

以及 User Request 判斷目前工作範圍。

只實作 Requested Scope。

不要因為新增一個功能就順便重寫其他無關系統。

---

# 4. 修改前先 Build

修改 Architecture 前：

1. Inspect Repository
2. 理解 Existing Models
3. 理解 State Flow
4. Build Current Project
5. Run Existing Tests

修改後：

1. Build
2. Run Relevant Tests
3. 修正 Compile Errors
4. 回報 Warning / Failure

如果環境允許 Build，就不能在沒有 Build 的情況下宣稱功能正常。

---

# 5. 保護既有功能

新增功能不能破壞：

- Cue Ordering
- Cue UUID
- Project Loading
- Project Saving
- Playback State
- GO
- Previous
- Blackout
- Output Selection
- External Output Rendering
- Chinese Text Input

修改 Shared Model 時，必須檢查所有 Call Sites。

---

# 6. Architecture Rules

禁止把整個 App 都塞進：

ContentView.swift

維持 Separation of Concerns。

建議：

App/

Models/

Stores/

Playback/

Rendering/

Output/

Importers/

Views/

Utilities/

Tests/

Folder 名稱可以調整，但 Responsibility 必須清楚。

---

# 7. Data Model Rules

Persistent Model 不應依賴 SwiftUI View Implementation。

Project Persistence 使用 Codable。

每個 Persistent Cue 必須有 UUID。

永遠不要使用：

displayNumber

array index

visible row number

作為永久 Cue Identity。

Reorder 不得改變 Cue Identity。

---

# 8. Canvas Rules — CRITICAL

Canvas Resolution 是 Configurable。

永遠不能假設：

1920 × 1080

3840 × 2160

16:9

1080p

4K

所有 Canvas Geometry 必須從：

CanvasDefinition

取得。

正確：

canvas.width

canvas.height

錯誤：

hard-coded 1920

hard-coded 1080

hard-coded 3840

hard-coded 2160

除非這些值只是 User-selectable Preset。

3840 × 2160 是 Preset。

不是 Architecture Constant。

---

# 9. Arbitrary Resolution Support

必須支援非標準 Resolution。

例如：

3840 × 1080

5760 × 1080

2688 × 768

2560 × 960

4096 × 2160

不能因為不是標準 Video Resolution 就拒絕 Canvas。

只根據實際 Rendering / System Limit 做合理 Validation。

---

# 10. Coordinate System

Layer 與 Region Position：

儲存在 Canvas Pixel Coordinates。

Preview Coordinates：

只是 UI Presentation Coordinates。

永遠不要把 Preview-space Coordinate 存進 Project Model。

必須存在：

Canvas Coordinates
↔
Preview Coordinates

的明確轉換。

Canvas Coordinates 永遠是 Authoritative Data。

---

# 11. Output Rules

Canvas 與 Physical Output 是不同概念。

禁止假設：

Canvas Resolution == Display Resolution

禁止假設：

One Canvas == One Display

禁止假設：

One Region == One Display

禁止假設：

Only One External Display

Output Architecture 必須以 Collection 為基礎。

---

# 12. LED / Video Wall Rules

一個 Physical Output 可能包含多個 Logical Region。

例如：

3840 × 2160 HDMI Signal

裡面包含：

LED Left

LED Right

Subtitle Strip

Auxiliary Screen

不要自動把所有 Content Scale 到填滿 Physical Output。

Mapping 必須 Explicit。

未來至少：

- 1:1 Pixel
- Fit
- Fill
- Stretch

LED Workflow 必須保留真正 1:1 Pixel Output 的能力。

---

# 13. Text Editing Rules

Chinese IME Correctness 是 Mandatory。

當：

TextField
TextEditor
NSTextView

正在編輯時，不得讓 Global Keyboard Handler 錯誤吃掉輸入。

特別注意：

Space

Enter

Arrow Keys

Escape

B

Playback Shortcut 不得干擾 IME Composition。

---

# 14. Playback State Rules

以下概念必須分開：

selectedCue

liveCue

blackoutState

Selecting != Playing

Editing != Playing

Blackout != Delete liveCue

解除 Blackout 後，除非中間有其他明確 Playback Operation，否則應恢復原本 Live Content。

---

# 15. Rendering Rules

Renderer Consume：

Project State
+
Playback State

Renderer 不應負責 Project Editing Logic。

Rendering 不得與 SwiftUI View Dimensions 緊密綁定。

未來換成 Metal Renderer 時，不應需要重寫整個 Project Model。

---

# 16. Importer Rules

Importer 先把 External Data 轉換成 Intermediate Import Model。

禁止：

XLSX / DOCX / Clipboard Parser

在 Parsing 過程直接修改 Production Cue Data。

正確流程：

External Source

↓

Parser

↓

Import Model

↓

Preview / Validation

↓

User Confirmation

↓

Project Mutation

---

# 17. Excel Rules

不能假設固定 Column Name。

必須使用 Column Mapping。

例如可能收到：

Chinese

中文

中文字幕

Translation

Subtitle ZH

Column Mapping 是 Import Configuration。

不是 Core Cue Identity。

---

# 18. Re-import Rules

未來 Re-import 應盡可能保留 Existing Production Configuration。

Text Change 不應不必要地破壞：

- Cue UUID
- Formatting
- Layer Assignment
- Output Mapping
- Transition
- Local Notes

需要 Diff / Update Workflow 時，禁止直接做 Destructive Replacement。

---

# 19. Dependencies

優先：

Apple Frameworks

以及必要、成熟、維護良好的第三方 Dependency。

加入第三方 Dependency 前：

1. 先判斷 Apple Framework 是否能合理完成
2. 說明為什麼需要 Dependency
3. 不要為了簡單 Utility 引入大型 Library

Live Production Reliability 高於少寫一些 Code。

---

# 20. Threading / Performance

禁止在 Main UI Thread 執行：

- Large File Parsing
- Heavy Rendering
- Network Operations
- Expensive Media Decoding

Playback Command 必須保持 Responsive。

不要 Premature Optimization，但也不要建立明顯會 Block UI 的 Architecture。

---

# 21. Error Handling

重要 Error 不得 Silent Ignore。

User-facing Error 必須可理解。

例如：

Project cannot be opened.

Output display disappeared.

Imported spreadsheet is invalid.

Font is unavailable.

Canvas size is invalid.

Development Diagnostic 則要保留足夠 Technical Detail。

---

# 22. Output Disconnect Handling

External Display 在演出中可能消失。

未來必須處理：

- Display Disconnect
- Display Reconnect
- Display ID Change
- Output Reassignment

Display 消失不能造成 App Crash。

Early Version 至少必須：

安全退回 Operator-only Mode。

---

# 23. Project Migration

Project Format 未來一定會改變。

不能隨便修改 Codable Model 造成舊 Project 無法讀取。

Model 開始穩定後加入：

projectFormatVersion

例如：

{
  "projectFormatVersion": 1
}

未來 Schema Change 必須使用 Explicit Migration。

---

# 24. Testing Requirements

Business Logic 必須可以不啟動完整 UI 就進行測試。

至少測試：

- Cue Navigation
- Blackout
- Canvas Coordinate Conversion
- Region Mapping
- Clipboard Parsing
- Project Serialization
- Import Diff

不要把 Business Logic 全部寫在 SwiftUI View Body。

---

# 25. 禁止 Placeholder Completion

不能因為建立了：

TODO

Empty View

Stub Service

Hard-coded Demo Data

Placeholder Button

就宣稱 Feature Complete。

如果功能沒有完成，要明確說明剩下什麼。

---

# 26. Avoid Overengineering

不要為幾個版本以後的功能建立過度複雜 Framework。

保留 Clean Extension Point 即可。

例如：

V0.1 不需要完整 Media Abstraction。

V0.1 不需要 NDI。

V0.1 不需要完整 Metal Compositor。

但是：

V0.1 的 Canvas Model 從第一天就不能假設 1080p。

---

# 27. Refactoring

以下情況可以 Refactor：

- Remove Duplication
- Clarify Ownership
- Enable Required Feature
- Fix Unsafe State Flow

新增 Feature 時不要順便做大型無關 Refactor。

如果大型 Refactor 是必要的，Completion Report 必須解釋原因。

---

# 28. Git Discipline

重大修改前：

檢查 git status。

不能覆蓋 User 的其他修改。

不能因為某個 File 與預期不同就自行 Revert。

Change Scope 必須符合目前 Task。

除非 User 明確要求：

不要自行 Commit。

---

# 29. Completion Report

每次完成 Development Task 後回報：

## Changed

修改了哪些 File / Component。

## Implemented

目前實際可以使用的功能。

## Architecture

重要 Architecture Decision。

## Verification

Build Result

Test Result

需要 Manual Verification 的項目。

## Known Issues

尚未完成或不確定的地方。

## Next Step

建議下一個 Logical Development Step。

如果沒有真的進行 Manual UI Test，就不能宣稱 UI 已經實測正常。

---

# 30. Decision Rule

遇到 Requirement 不明確時，優先選擇最符合：

Live Theatre Reliability

+

Fast Operator Workflow

+

Configurable Professional Video Output

的方案。

但不要因此增加不必要 Complexity。

如果某個 Architecture Decision 可能永久限制以下能力：

- Canvas Resolution
- Output Count
- Cue Identity
- Multilingual Text
- Future Rendering

則不要只因目前版本需求簡單而把架構寫死。

應優先採用較通用、但仍保持清楚簡單的 Data Model。