# NDI® 輸出 — v0.5.2 / build 12

日期：2026-10-21。NDI® is a registered trademark of Vizrt NDI AB. [NDI 官方網站](https://ndi.video/)

## 操作

1. 建立 Output，設定其 Layout、Canvas 與 Region Mapping；不需要指派實體螢幕。
2. Edit → Video Output → NDI，勾選每個需要傳送的 Output。
3. 可設定來源名稱、透明背景、30／60 fps。不同 Output 使用不同來源名稱。
4. Start NDI 後按 GO；Start 本身不會變更 Live Cue。接收軟體選取電腦名稱下的 SubtitleStage 來源。
5. Blackout 在透明模式淡出至零 Alpha，在不透明模式淡出至黑色。Stop NDI 移除來源；接收端可能保留最後一幀，演出清場先 Blackout，再 Stop。
6. 若 macOS 詢問本機網路存取，允許才能供其他機器發現／接收。接收數量顯示為所有來源的連線總數。

## Runtime

安裝包不包含 NDI runtime，也沒有啟動時強制連結。啟動 NDI 才透過 `dlopen` 取得 `NDIlib_v5_load()`，檢查 API 並初始化。找不到、不相容或架構不符會顯示錯誤，其他播放功能繼續可用。

自動搜尋 `/usr/local/lib/libndi.dylib`、官方 Apple SDK 的 lib/macOS 路徑，以及本機已安裝的官方 NDI Scan Converter／Router 內 runtime。沒有安裝時可從介面前往 [官方 Runtime](https://ndi.link/NDIRedistV6Apple) 或 [NDI Tools](https://ndi.video/tools/)。也可在 NDI Runtime 展開項選擇官方 `libndi.dylib`。選擇記錄在本機偏好設定，不寫進 Show File。

成功載入的 runtime 保留至 App 結束，避免卸載時與 SDK 背景執行緒競爭。切換到另一 runtime 檔案需重啟 App。未複製、修改或重新散布其他應用程式的 runtime。

## 訊號與可靠性

- NDI High Bandwidth、progressive、RGBA（非預乘 Alpha），無音訊。共用 CanvasContentRenderer 與 VideoRasterizer；不使用 UI 截圖。
- Syphon 使用自己的垂直座標轉換；NDI buffer 保持 top-down，不沿用 Syphon 的 flip。
- 輸出尺寸取明確 Output signal resolution，否則取該 Output 的 Canvas。寬度必須為偶數；奇數寬度會拒絕啟動並提示明確設定 signal resolution，不更改 Canvas。
- 每邊最多 16384 pixels，NDI 全部輸出合計最多 16,777,216 pixels；這是此傳送器的資源上限，不限制專案 Canvas 模型。
- 30／60 fps 是目標上限；繁重渲染、網路或接收負載可能降低實際幀率。固定最多一個工作進行中，不累積待傳影格。
- 文字／Layout／Region 編輯可更新 Live；改尺寸、名稱、幀率、Alpha、啟用狀態或切換專案會停止 NDI，請檢查後重新 Start。
- 傳送、像素轉換、來源建立／銷毀皆在 NDI serial worker；同步 send 回傳後才重用 buffer。UI／GO 不等待網路傳送。
- 專案格式 11；讀取 1–10 時 NDI 預設停用，保留 UUID、Syphon 與原有設定。需要留給舊版使用時先 Save As 保留舊檔。

## 依賴來源與驗證範圍

Apple Frameworks 不提供 NDI 編碼／發現協定，因此需要 NDI runtime。此版使用公開 NDI v5 ABI，headers 每份均附 MIT notice；來源為本機 cyndilib 0.0.5 套件內 Vizrt 2023–2024 官方 headers，完整 notice 保留於 NDIBridge/SDK 並封裝 NDI-Headers-LICENSE.txt。官方 Apple SDK 下載在本次回傳 HTTP 403，沒有宣稱已取得最新完整 SDK，也沒有封裝 runtime。發布新版 SDK／runtime 前應重新確認採用版本條款。

自動測試使用本機官方 NDI Scan Converter 的 6.3.2.0 runtime，實際建立 sender、經 finder 發現、receiver 解碼並檢查方向、Alpha、Fade、Blackout、多來源、幀率與重新連接。這不等於人工 QLab／NDI Video Monitor 或跨機器網路驗收；長時間負載、斷網／重連、不同機器及接收軟體仍待確認。

官方參考：[動態載入](https://docs.ndi.video/all/developing-with-ndi/sdk/dynamic-loading-of-ndi-libraries)、[影格格式](https://docs.ndi.video/all/developing-with-ndi/sdk/frame-types)、[SDK 發布規範](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing)。
