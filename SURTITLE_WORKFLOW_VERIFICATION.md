# Surtitle 工作介面驗證 — v0.2.x 歷史紀錄

最新 v0.3.0 範圍與驗證見 V0.3_VERIFICATION.md。以下保留先前版本證據及使用者回報，不代表 v0.3 已經人工驗收。

## v0.2.3 開發驗證 — 2026-10-18（10-19 更新）

- 修改前 Universal 兩架構編譯成功；受限環境的圖示轉換失敗，且 OSC UDP 測試被作業系統拒絕開埠，不能視為功能通過。
- 修改後在允許本機 UDP 的環境執行完整測試：49 項中 45 項通過、4 項桌面測試跳過，0 失敗。仍有既存 ModuleCache 路徑警告。
- 新增測試涵蓋：完整多語／格式／轉場複製與新 UUID、Live／Blackout 保留、批次刪除原子拒絕、順序及勾選 Undo／Redo、重新編號預覽與整數溢位保護、Details 連續輸入 Undo、ProjectCodec 往返。
- 10-19 滿寬預覽修正後重新執行完整測試：45 項通過、4 項桌面測試跳過；Intel／Apple Silicon Release build、簽名與 DMG 封裝成功。
- 專案格式仍為 7。版本號更新為 0.2.3（build 5）；尚未上傳 GitHub。
- 2026-10-19 依使用者截圖修正 Playback 預覽為單欄滿寬（扣除操作欄既有邊界），維持 Canvas 比例；Layout 總覽仍為縮圖網格。
- 新版人工 UI 測試尚未執行；v0.2.2 的人工通過紀錄不自動視為新版已驗收。

待驗收：

- [ ] Cue Details 三欄繁中／簡中輸入、切換 Cue、Undo／Redo。
- [ ] Duplicate Cue 後檢查多語文字、格式、轉場與 Live 不變。
- [ ] 勾選、全選、清除、批次刪除 Live 保護及一次 Undo 還原。
- [ ] 重新編號預覽／Cancel／Apply，確認實際專案存檔重開。
- [ ] 新增工具列與分頁在操作螢幕上的可用性。
- [ ] 拖曳左右分隔線、縮放視窗、多 Output 與非標準 Canvas 比例，確認 Playback 預覽隨欄寬填滿且不變形。
- [ ] 延續多外接螢幕、拔插／重連、長時間播放及不同更新率 Fade 驗收。

## v0.2.2 發布紀錄 — 2026-10-18

- 已發布 GitHub Release v0.2.2，包含 SubtitleStage.dmg（Intel／Apple Silicon，macOS 14+）。
- 當次 Universal Release build、嚴格 ad-hoc 簽名及 DMG 完整性驗證通過；41 項測試通過、4 項桌面測試跳過。尚未 Apple notarize。
- SHA-256：`d45d30ee95aafd6d6fc99e6d7753512b30caa317692159f025838b9845ce5433`。
- 本紀錄沿用發布時證據；文件整理未重新 Build 或執行測試。
- 下一版範圍與完成條件見 ROADMAP.md；下方 2026-09-13 的檢查保留作為歷史證據。

## 已完成的檢查（2026-09-13）

- 修改前基線：20 個功能測試通過，當時存在的 3 個桌面測試預設略過。
- 新版功能測試：40 個通過；一般執行略過 4 個需桌面的測試。
- 桌面執行：畫面快照、選取效能、數字上下鍵／標記文字保護通過。本次測試 runner 無法取得 `NSScreen`，因此本機螢幕輸出／Esc 測試略過；先前版本曾在可用桌面環境通過。
- 先前桌面執行曾因自動審核使用額度耗盡被拒；2026-09-13 已重新獲准並成功執行，不再把該舊失敗當成未驗證的替代證據。
- 檢視表格、Text Modify、output 總覽及 detail 的原生離屏快照。列高正確由單行延伸至換行，工具列單行，Cue 格為綠底。AppKit 系統控制項在離屏快照中有外觀限制，完整互動外觀仍需實際使用確認。

- 最終 debug／release build、嚴格簽名與 ZIP 完整性檢查通過。Release 啟動測試維持運作五秒，無 stdout/stderr 診斷，測試實例已結束。

## 新功能測試覆蓋

- 每個 TextProperty 的 Batch 僅更新該屬性，不變更其他屬性或其他 Surtitle。
- Text Modify、Batch、文字與 Layout 修改會重建同一 liveCue 的 Live frame，立刻送到預覽與輸出。
- 顏色／斜體／底線／刪除線等屬性存檔往返。
- 舊 TextStyle 缺少新欄位時，採用白色、無裝飾預設；保留舊 output 未被覆寫的字體屬性。
- 單行、手動換行、長中文字自動折行、尾端換行的列高。
- 無效顏色拒絕存檔。
- 原生渲染的黑場、多語言分流與顏色像素檢查。
- 各 output 的位置／可見性互不影響，儲存還原完整。
- 各 output 的 Rotate X／Y／Z 互不影響，舊格式缺少旋轉時遷移為 0°。
- 每 Cue 自動 Fade In／Fade Out 與 Blackout／Restore 使用各自 0–10 秒設定；黑場不清除 liveCue。
- 100 步 Undo／Redo、連續儲存格輸入合併成一步、Cue 刪除與重排還原。
- 五個未指派 output slot 的建立／存檔／後續裝置指派與重複裝置防護。
- Duplicate Surtitle 完整複製台詞、格式及每個 output 的排列到來源右側。
- Paste As Cues 選擇目標 Surtitle 並插入游標 Cue 下方。
- Layout 選取 Surtitle 後的 Canvas pixel 方向鍵微調。
- Start Output 在建立輸出視窗前 take 當下選取的 Cue。
- Return 在目前列後插入新 Cue，保持既有 Cue UUID 與順序。
- 數值欄 ↑／↓ 加減 1，NSTextView 存在 marked text 時不攔截。
- 本機螢幕 output 視窗涵蓋完整 NSScreen.frame、位於選單列上方、不允許點擊穿透；模擬 Esc 關閉輸出、回到操作視窗，保留 Live／黑場狀態。

## 效能

相同機器的 200 Cue、20 次選取測試：

- 舊版：13.142 秒。
- 移除 801 個 SwiftUI 字型選項的重複建立後：0.713 秒。
- 最新空白 Output slots、Undo／Redo、逐 Cue fade 與工作頁：0.788 秒，平均約 39 毫秒／次。

這是受控測試的總經過時間，包含事件排程，不代表所有專案與硬體的保證。原生字型選單只建立一次；Live 無變更時不要求 renderer 重繪。

## 重跑

```sh
Scripts/test.sh
SUBTITLESTAGE_UI_CHECK=1 Scripts/test.sh --filter InterfaceTests
Scripts/build.sh
```

第二項需要可用的 macOS 桌面，會建立並關閉自己的測試視窗，其中含短暫的本機螢幕輸出測試。

## 使用者人工驗收回報 — 2026-10-18

針對目前 v0.2.2，由使用者回報以下結果；這是使用者實際操作的驗收紀錄，不是代理自行執行的 UI 測試。存讀檔結論限於目前已試過的 Cue Sheet 與舊專案，不代表所有歷史檔案皆已驗證。

- [x] 繁中／簡中 IME、實體鍵盤快捷鍵及候選字操作：OK。
- [x] 實際控制器的 OSC 操作與演出網路測試：OK。
- [x] 實際 Cue Sheet 與舊專案存讀檔：目前 OK。
- [ ] 多外接螢幕、拔插／重連、長時間播放：尚未驗證。
- [ ] 不同更新率螢幕上的 Fade 平順度：尚未驗證。

## 先前細項驗收清單

以下保留原有細項；未被本次回報明確涵蓋的操作仍待確認。

- [x] 繁中／簡中 IME 候選字操作（2026-10-18 使用者回報 OK）。
- [ ] 實際拖曳框與右下角，切換不同 output 後確認排列獨立。
- [ ] macOS 選色面板的手動操作、每種常用字型的斜體與字形。
- [ ] 實際硬體鍵盤確認儲存格 Return 新增 Cue、Shift+Return 換行、方向鍵換格及中文 IME 候選確認。
- [ ] 實際拖曳／方向鍵與 Rotate X／Y／Z，確認實體 output 即時同步。
- [ ] 字幕與 Blackout fade 在不同 refresh rate 顯示器上的視覺平順度。
- [x] 使用者自己的 Cue Sheet 與舊專案存讀檔（2026-10-18 使用者回報目前 OK）。
- [ ] 多外接顯示器的完整路由、長時間播放及斷線／重連。
- [x] 實體鍵盤播放快捷鍵（2026-10-18 使用者回報 OK；既有自動測試使用 AppKit 事件／命令）。
