# SubtitleStage — Surtitle 工作介面

原生 macOS 字幕播放工具，使用 SwiftUI / AppKit / Metal，v0.5 加入官方 Syphon framework。最低 macOS 14，建置需要 Swift 6 / Xcode。本版包含使用者指定的多 Surtitle 表格、獨立 output Layout、Text Modify 與逐項 Batch；包含 v0.4 文件匯入；各里程碑與實機驗收狀態見 ROADMAP.md。

## 版本與開發狀態

目前發布：**v0.2.2 — OSC Control**（2026-10-18）。

- [下載 DMG](https://github.com/andyue/surtitleStage/releases/download/v0.5.3/SubtitleStage-0.5.3-build13.dmg)
- [Release 說明](https://github.com/andyue/surtitleStage/releases/tag/v0.5.3)
- [目前進度與下一版範圍](ROADMAP.md)
- [最新 V0.5 驗證](V0.5_VERIFICATION.md)
- [OSC 指令與限制](OSC.md)

App 版本號不代表同號 Roadmap 里程碑已全部完成。最新版本為 **v0.5.3（build 13）**：新增 Glypheo 多 Track 純文字匯入與重新匯入，保留 Syphon、NDI、文件匯入、Cue 編輯與 Output Region Mapping。

## 建置與啟動

```sh
./Scripts/test.sh
./Scripts/build.sh
open "$(cat .build/app-path.txt)"
```

用 Xcode 開啟 `Package.swift`。腳本產生 Intel／Apple Silicon Universal 本機簽名開發版，將 app 放在非 iCloud 暫存目錄，路徑記錄在 `.build/app-path.txt`，另產生 `.build/SubtitleStage.zip` 與 `.build/SubtitleStage.dmg`。可將 ZIP 解壓至本機非 iCloud 資料夾長期保留，避免 iCloud metadata 使簽名失效。此開發版尚未 notarize。編譯快取留在 `.build`，腳本停用 SwiftPM 巢狀 sandbox 以相容受限開發環境。

## 左側表格

- 每列一個 Cue，每欄一個 Surtitle；直接編輯台詞。
- 預設單行高度；換行或文字自動折行時，以該列最長的儲存格自動增高。
- Live Cue 的編號格為綠底。一般選取與 Live 是分開的。
- 新欄名為 `Surtitle 1`、`Surtitle 2` 等，雙擊欄名可修改；舊專案已有名稱保留。
- Add Cue、Undo、Redo、+ Surtitle、Duplicate Surtitle、Paste As Cues… 在同一行；最多保留 100 個復原步驟。Duplicate Surtitle 選單會列出所有欄位，所選來源的完整副本插在來源右側。
- Cue 編號左側的 × 刪除整列；最右側拖曳把手調整 Cue 順序。刪除與拖曳都可 Undo／Redo。
- Cue UUID、文字與格式對應不因重排或改名而改變。
- 儲存格中 Return 在目前 Cue 後新增 Cue；Shift+Return 插入換行；方向鍵像試算表一樣選擇相鄰格。IME 組字期間不攔截 Return 或方向鍵。
- Paste As Cues 提供逐行／逐段預覽，可選目標 Surtitle，確認後插入目前 Cue 下方。

## 工作區配置

左側上半部固定為 Cue 表格，下半部是 Edit 區，可切換 Layout Setting／Text Modify／Cue Details／OSC／Video Output；窄欄位以選單切換。右側固定保留 Playback 預覽及 Show Controls，編輯排列或文字時仍可同時確認所有輸出。

### Playback

在右側獨立頁面顯示每個 output slot 的 Live 預覽，包括尚未指派顯示器的 slot。Playback 預覽採單欄垂直排列，每個畫面使用右側欄扣除既有左右邊界的完整寬度，高度依 Canvas 比例調整；超出可視高度時垂直捲動。Layout 總覽仍使用縮圖網格。底部固定 Start Output、Previous、GO / Next、Blackout／Restore、Stop Output；Blackout fade 可設定 0–10 秒。

### Layout Setting

第一層是各 output 的預覽總覽。可先建立任意數量的空白 output slot，再於個別頁面指派顯示器。Output 可改名；選取後用 Delete Output 並經確認刪除。顯示器選單會以 `[— Output 名稱]` 標示目前使用者，避免重複部署。

每個 output 都能分別選擇要顯示的 Surtitle，並保存各自的位置、寬、高與 Rotate X／Y／Z。拖曳字幕框移動，右下角縮放，也可輸入數值。點選 Surtitle 後，方向鍵每次移動 1 個 Canvas pixel。座標是 Canvas 像素，原點在左上角。Layout 沒有字體選項。

Canvas 的 Width／Height 可在 Layout Setting 設為 1–32,768 pixels。改變大小時，所有 Surtitle 與各 Output 的位置及尺寸會按比例縮放，並可 Undo。

新 output 會複製預設排列，之後獨立編輯。Layout 的拖曳、數值、可見性與旋轉會立即更新正在播放的實體 output。v0.3 的 Output Mapping 提供 signal resolution、來源 crop／目的地 Region 與四種 scale mode。預設無 Region 時維持完整 Canvas Fit。UI 仍只建立／編輯 Primary Canvas。

### Text Modify

選取左側儲存格，或在本頁選擇 Surtitle。每項一行，可編輯該 Cue／Surtitle 的：

- Font
- Size
- Character Spacing
- Line Spacing
- Color（macOS 原生選色介面，含透明度）
- Italic
- Underline
- Strikethrough
- Alignment

數值欄取得焦點後，可用 ↑／↓ 或滑鼠滾輪調整。IME 標記中的組字不會被數字調整攔截。Alignment 使用 Left／Center／Right 三段按鈕。

Cue Fade 可為每個 Cue 個別啟用 Fade In 與 Fade Out，並設定 0–10 秒。Cue 到達或離開時自動執行，無需演出時另外按淡入淡出按鈕。

每行右側的 **Batch** 只把該項目前的值套用到「同一 Surtitle 欄的所有現有 Cue」，不影響其他屬性、其他 Surtitle 欄、台詞、UUID 或 output 幾何。之後新增的 Cue 不自動繼承先前 Batch。

Text Modify 的逐項與 Batch 變更都會立即更新正在播放的畫面。

## 全畫面輸出與快捷鍵

可選擇本機螢幕，也可同時設定多個連接的顯示器。Start Output 會立即 take 當下選取的 Cue，並用黑底字幕覆蓋設定的整個螢幕。把操作螢幕本身設為 output 時，輸出視窗取得鍵盤焦點，操作介面被覆蓋。Esc 關閉所有輸出並回到操作介面，保留 Live Cue 與黑場狀態；再次 Start Output 會顯示當下選取的 Cue。

Space = GO、左箭頭 = Previous、B = 切換淡化黑場。進入 output 的 Layout Setting detail 並點選 Surtitle 後，方向鍵改為移動該 Surtitle。雙擊 Cue 編號會直接 take 該 Cue；Blackout 中 take 仍維持黑場，Restore 才顯示新 Live Cue。無輸出時，操作介面的 Esc 維持淡化黑場功能；有輸出且操作介面未編輯文字時，Esc 退出輸出。文字欄、IME、對話框與帶修飾鍵事件仍受焦點保護，不再需要 Arm Keyboard。按住播放鍵不會連續跳 Cue。

輸出中先 Stop Output 才能增刪 output slot。顯示器斷線時安全停止所有輸出，重連不自動重啟。

## Live 與檔案

首次 GO 從選取 Cue 開始，之後依 Live Cue 順序前進；末尾保持。Previous 在開頭保持。Blackout 不清除 Live；Restore 恢復目前 Live 內容（包含黑場期間的明確播放操作與即時編輯）。Live Cue 不可刪除。

正在播放的 Cue 文字、Text Modify、Batch 與 Layout Setting 編輯都立即更新 Live；選取其他 Cue 本身仍不會改變 Live，直到 GO、Previous、雙擊 Cue 編號或 Start Output。Opacity 以 5% 調整字幕總亮度，預設 100%。Blackout 位於輸出鏈最末端，只淡出畫面並保留 liveCue 與 Opacity；Restore 以設定時間淡回目前 Opacity 的內容。

New / Open / Save / Save As 保留未儲存提示、背景 I/O 與原子存檔。格式 11 讀取並遷移格式 1–10，保留 Cue UUID、排列、台詞、既有名稱、格式與 output 設定，並加入 output 名稱、空白裝置指派與逐 Cue transition。舊 app 無法讀取格式 11；若需留給舊版使用，以 Save As 保留原檔。

Canvas 預設 1920 × 1080；幾何從 Canvas 寬高推導，支援非標準比例。Canvas 設定 UI 與基本 OSC 已納入。Excel／Word 匯入已於 v0.4 納入；獨立 Layer 推進與影片尚未納入；Region Mapping 已於 v0.3 加入。

## 架構與驗證

- `CueTable.swift`：自動列高、欄名雙擊編輯、Live 格色。
- `OutputPreviews.swift` / `LayoutView.swift` / `LayoutCanvas.swift`：output 總覽與個別排列。
- `TextModifyView.swift` / `NumericField.swift` / `FontSelector.swift`：逐項調整、原生數值／字型控制。
- `TextFormatting.swift` / `TextEditing.swift`：顏色、裝飾、逐屬性 Batch。
- `CanvasView.swift` / `OutputManager.swift`：共用 renderer、全螢幕輸出與 Esc 退出。

最新結果與待驗收項目見 `V0.5_VERIFICATION.md`，先前人工驗收見 `SURTITLE_WORKFLOW_VERIFICATION.md`。早期記錄保留在 V0.1_VERIFICATION.md 和 LAYOUT_VERIFICATION.md。

## 現場驗收狀態（2026-10-18）

使用者回報 IME／候選字／實體播放快捷鍵、OSC 控制器及演出網路 OK；已測試的 Cue Sheet／舊專案存讀檔目前 OK。實體多外接螢幕與電腦螢幕 Fade 已由使用者確認 OK；拔插／重連、長時間播放及不同更新率 Fade 平順度仍待驗證。其他未明確回報的細項保留於驗證文件。

## v0.2.3 Cue 編輯

- 點選 Cue／儲存格後，左下 **Cue Details** 可編輯 Number、Name、Notes；編輯不觸發播放。
- **Duplicate Cue** 複製目前選取 Cue 的所有語言文字、格式、備註與轉場，插在來源後方，產生新 UUID 並選取副本；不改變 Live。Display Number 先保留來源值，可再重新編號。
- 每列左側新增批次勾選欄。勾選與一般選取／Live 各自獨立，不影響輸入焦點或播放。
- **Batch (數量)** 提供 Check All、Clear Checks、Delete Checked Cues、Renumber Checked Cues。
- 批次刪除若包含 Live Cue，整批拒絕並提示；其餘情況保留剩餘 Cue 順序。
- 重新編號先輸入非負整數起始值並預覽，按 Apply 才依目前列表順序套用；未勾選 Cue 保留編號，允許重複 displayNumber。UUID 始終是永久身份。
- 複製、批次刪除、重新編號各為一步 Undo／Redo；Cue Details 同欄位連續輸入合併為一步。批次勾選不寫入專案，Undo／Redo 會還原操作當時的勾選。
- v0.2.3 當時專案格式為 7；v0.3 Mapping 已升為格式 8。

## v0.3 Output Mapper

在 Layout Setting 選擇 Output，使用 **Output Mapping**：

1. 指派顯示器，設定 Enabled；選擇 **Use Display Pixels** 或輸入訊號寬高後 **Apply Size**。
2. 無 Region 時可直接選 **Fit／Fill／Stretch／1:1 Pixel**，映射完整 Canvas。
3. 按 **+ Region**，命名並選擇 Source crop 或 Destination signal 視圖；拖拉移動、右下角縮放，或填寫四個座標後 **Apply**。
4. 每個 Region 可設定 crop、destination、scale mode 及 enabled。Region 按清單順序疊放；最後一個刪除後會回到完整 Canvas 映射。
5. **Start Output** 會驗證所有已啟用且已指派的顯示器。明確訊號尺寸必須等於實際 backing pixels；1:1 另外要求 macOS 回報的 display pixels 相符，否則拒絕輸出並顯示原因。

所有座標都是像素：來源是 Canvas，目的地是輸出訊號。Fit／Fill 置中；1:1 以目的地左上角對齊並裁切。多 Region 可放在同一 HDMI 訊號內供 LED Processor 使用。縮小訊號導致 Region 越界時會拒絕，請先調整 Region。

播放時可即時調整 Region 幾何；裝置／訊號／模式／增刪需先 Stop Output。這些設定可存檔與 Undo／Redo，但播放中會阻止還原不同 output mapping。詳細限制與實機驗收見 V0.3_VERIFICATION.md。

### v0.3 人工驗收更新（2026-10-19）

使用者已確認實體多外接螢幕 OK、Fade 在電腦螢幕 OK。拔插／重連、長時間播放、不同更新率及 LED Processor 的 1:1 比對仍待驗證。詳細記錄見 [V0.3_VERIFICATION.md](V0.3_VERIFICATION.md)。


## v0.4 文件匯入

1. 在選單列 **File → Import Document…**，選 XLSX 或 DOCX。可先建立要使用的 Surtitle，或在 XLSX 欄位映射中選 New Surtitle… 新增。
2. XLSX：選工作表、確認 Header row（0 表示無標題），逐欄指定用途。中文／英文等欄名不固定，文字欄可對應任意現有 Surtitle，或選 **New Surtitle…** 建立新的字幕層；Target 必須精確對應 Surtitle 名稱或 UUID，並搭配 Dialogue 欄。按 **Build Preview**。
3. 預覽選列可修改文字、來源鍵、Cue 編號、Speaker、Notes 及 Ignore。勾選列可指定 Speaker／Layer、重新編號；Split Lines 依換行分割選取列，Merge Checked 合併相鄰勾選列。多語分割要求行數一致；多語列不允許直接合併到單一 Layer。
4. **Review Changes** 顯示目前與匯入內容；按 **Apply Checked Changes** 才修改專案。整批為一步 Undo，不自動 GO。預覽期間若專案已變更，需重新開啟匯入；會修改／刪除 Live Cue 時拒絕整批套用。

### Excel 重新匯入

初次匯入需把一欄指定為 **Stable source ID**：鍵必須非空、唯一，且在來源版本之間保持不變。Cue Number 只是顯示，不會自動拿來比對。無穩定鍵仍可初次匯入，但不會出現在 **Re-import…** 選單。

在 **File → Re-import** 選原來源，再選新版 XLSX；沿用工作表與映射設定。既有 Cue 保留 UUID、順序、格式、轉場與 Output 配置。新增 Cue 插在選取 Cue 後方；未映射的備註保持原樣。來源缺項標為 DELETED，預設保留；本機與來源都改過同一欄位時標示 OVERWRITE LOCAL EDITS，預設不勾選。選擇套用表示接受該列已映射的來源內容。Ignore 某來源列會保護其既有 Cue，不視為刪除。

Split 保留第一段來源鍵，後續加 #partN；Merge 保留第一列來源鍵。若重新匯入已分割／合併過的來源，必須檢查差異，必要時重做相同整理，不會猜測配對。Duplicate Cue 會解除副本來源綁定。

### 文件支援限制

- XLSX：最多 50 工作表、每表 10,000 列／256 欄、總計 200,000 儲存格。公式使用儲存快取，缺少快取或錯誤值會中止；請先在 Excel 重算存檔。日期與格式化數字使用原始值，需保留前導零的 ID 請存成文字。合併儲存格僅讀取左上角值。
- DOCX：body 與 table-cell 段落依文件順序匯入；Heading 預設 Ignore，Speaker／Character 段落可設定後續角色，冒號前文字可推斷角色，皆可在預覽修正。整段一致的粗體／斜體／底線可匯入，混合字元格式會警告後攤平。不匯入圖片、版式、頁首頁尾或註解。DOCX 無穩定鍵，本版不提供重新匯入比對。
- 檔案上限 50 MB、單一展開 XML 20 MB、讀取展開內容總計 100 MB。不支援加密檔及舊 XLS／DOC。
- Text Modify 新增 Bold；Cue Details 新增 Speaker。專案格式 9 保存來源與基準文字，舊版無法讀取，升版存檔建議用 Save As 保留原檔。


### File 選單與 Excel 匯出（v0.4.0 build 8）

匯入／重新匯入已移至 macOS 選單列 **File**，Cue 工具列不再重複放置。

- **File → Import Document…**：匯入 XLSX／DOCX。
- **File → Re-import**：選已建立穩定來源鍵的來源，再選更新檔。
- **File → Export Cue Sheet (.xlsx)…**：依目前 Cue 順序匯出 Source ID、Cue Number、Speaker、Notes，以及每個 Surtitle 的文字欄。
- **File → Export Import Template (.xlsx)…**：依目前 Surtitle 欄位產生一筆明確標記的範例列，空專案也可使用。

兩種匯出都有 **Cue Sheet** 與 **Import Guide** 工作表。初次使用先匯出範本，在 Excel 替換或刪除範例列；匯入時選 Cue Sheet、Header row = 1，再依 Import Guide 做欄位映射。每列 Source ID 應保持唯一且固定。

匯出現有 Cue 使用 Cue UUID 作為 Source ID；匯出不改專案、不建立或改寫來源綁定。回匯至原 show 時，可選 **Merge by Cue Number**，映射編號與目標字幕欄，直接補入同一列。新專案可選 Add New Cues；若映射了 Stable source ID，後續也可使用 File → Re-import。不要把此匯出檔當成原先另一個 Source ID 來源的更新檔。

XLSX 匯出只供文字交換，不含 Cue 名稱、格式、轉場、Canvas 或 Output 設定；完整專案請用 Save／Save As。所有儲存格明確寫成文字，保留前導零、換行及以等號開頭的台詞，不產生公式。超過 Excel 每格 32,767 UTF-16 字元、XML 不可表示的控制字元或本版匯入容量限制時，顯示錯誤且不覆寫目的檔案。檔案在背景產生並原子寫入。


### 同一 show 匯入不同 Surtitle（v0.4.0 build 9）

1. **File → Import Document…** 選 XLSX。
2. **Import mode → Merge by Cue Number**。show 已有 Cue 時，新的文件匯入預設使用此模式；空 show 預設 Add New Cues，原來源 Re-import 預設 Update by Source ID。
3. 編號欄映射 **Cue number**。語言文字欄選現有 Surtitle，或 **New Surtitle…**；新增名稱預填該欄標題，可自行修改。可同時建立多個 Surtitle，不需要退出匯入。
4. 不需要的欄位設 Ignore。按 **Build Preview → Review Changes**，核對每列對應與新增 Surtitle 名單，再 Apply。

例如 show 已有 Cue 1 的中文，把另一份 XLSX 的編號 1／英文映射到 English，會填入同一列的 English，不會多出第二個 Cue 1。再匯入另一語言也同理。

合併只更新映射的 Surtitle 文字，保留其他語言、Cue UUID、名稱、Speaker、Notes、格式、Output、轉場與既有來源綁定。缺少的編號列為 NEW，勾選才新增；不因來源缺項刪除 Cue。目標已有不同文字（包括清空）預設不勾選，需明確確認取代。相同文字為 UNCHANGED。

Cue Number 僅在本次預覽用於配對，再解析為既有 UUID，不作永久身分。比較會去除前後空白，但保留前導零，所以 001 與 1 不相同。來源或 show 對同一個待匯入編號有多筆時會阻擋，不猜測配對；可先 Undo 誤新增的列，或整理編號後重試。

New Surtitle 在 Apply 前只存在工作區，Cancel 不會留下空層。映射頁可按「Create on Apply」中的 × 移除預計新增的層。新字幕層使用預設位置，完成後到 Layout 調整，避免多層視覺重疊。新增字幕層與文字合併同屬一步 Undo，專案格式仍為 9。

Build 9 可見安裝檔副本：`dist/SubtitleStage-0.4.0-build9.dmg`（2026-10-20 已驗證）。打包腳本的原始輸出仍在 `.build/`。


## v0.5 Syphon 輸出

本機安裝檔：dist/SubtitleStage-0.5.3-build13.dmg。

1. 建立 Output slot，在 Layout Setting 設定字幕位置與 Region mapping；不需要指派實體螢幕。
2. **Edit → Video Output** 勾選 **Enable Syphon**；Output 本身也必須 enabled。
3. 設定 server 名稱、Transparent background、30／60 fps。解析度沿用 Output signal resolution；Automatic 使用該 Output 的 Canvas。
4. **Start Syphon**，再 GO；啟動不會自動播放選取列。
5. 在接收軟體選對應 server，以 premultiplied Alpha 合成。透明模式 Blackout 清成透明，關閉透明則為黑底。
6. 可同時啟用多個 Output，各自使用 Layout／Regions。實體輸出仍用 Start／Stop Output；Syphon 用 Stop Syphon 停止。

設定與尺寸改變會停止 Syphon，核對後重新啟動。字幕文字與 Layout／Region 幾何即時更新。30／60 是排程上限，實際幀率取決於負載。接收端可能在 Stop 後保留最後一幀；需要清畫面時先 Blackout，再確認斷線行為。

Syphon 單邊上限 16384 pixels，總 working-surface 預算 33,554,432 pixels；不改變 Canvas 支援範圍。目前格式為 11，舊版無法讀取，請 Save As 保留原檔。

NDI 已於 v0.5.2 提供 sender，runtime 可選且不隨 App 封裝。操作見 [NDI 輸出](NDI.md)。詳見 [NDI 評估](NDI_EVALUATION.md)、[V0.5 驗證](V0.5_VERIFICATION.md)。Syphon 來源／授權及離線重建見 [Vendor 說明](Vendor/README.md)。build.sh 會封裝並簽名 framework，並輸出可見 dist 安裝檔。

### v0.5.1：Syphon 方向修正（2026-10-21）

使用者回報 QLab 接收畫面反向。發送邊界現在將頂端起始的 bitmap 轉為 Syphon 接收端的垂直座標方向；不改 Canvas、Layout 或左右順序。新增非對稱文字逐像素方向回歸測試。此修正延續至 build 12；請重新啟動 Syphon，並在 QLab 以無翻轉／無旋轉設定驗收。實際 QLab 修正後畫面仍待使用者確認。

NDI 技術上可加入；v0.5.1 仍未實作 sender。正式整合應使用官方 SDK 與可選動態 runtime，並驗證 Alpha、發現／重連和網路負載；不直接重新散布其他 App 內附的 NDI library。

### v0.5.2：NDI® 網路輸出

Edit → Video Output 啟用 NDI；各 Output 可設定來源名稱、透明背景與 30／60 fps。按 Start NDI，再 GO；本機已安裝的官方 runtime 可自動載入，未安裝時提供下載／選擇入口。格式 11 可讀舊專案。完整限制與驗收見 [NDI.md](NDI.md)。NDI® is a registered trademark of Vizrt NDI AB. [NDI 官網](https://ndi.video/)

## Glypheo 匯入

File → Import 可選擇 `.glypheo`。所有 Group 按原順序轉成一份 Cue 表，各 Track 為獨立文字欄位。Source ID、Cue Number、Group / Status 預設分別映射來源鍵、順序編號與備註；將各 Track 映射到既有 Surtitle 或選 New Surtitle，接著 Preview → Review Changes → Apply Checked Changes。取消不修改專案，套用可 Undo。

保留 Unicode、原始換行與來源鍵，並可透過 File → Re-import 比對更新。Glypheo 停用的 Cue 與全空白 Cue 預設忽略，可在預覽中逐列啟用。原始群組名稱放入備註，Cue Number 依文件順序重新編號。

本次移轉為純文字：不移轉 Glypheo 字型、字元樣式、群組階層、轉場、Panel 或輸出設定。匯入後需檢查 SubtitleStage Layout 與輸出。尚未驗證所有 Glypheo 版本，無法辨識的檔案會報錯而不修改專案。

正式演出字幕與本機產物不納入 Git。可用 `GLYPHEO_TEST_FILE=/path/to/sample.glypheo zsh Scripts/test.sh --filter GlypheoTests` 驗證本機 Life of Pi 樣本；測試只讀取檔案，不上傳內容。
