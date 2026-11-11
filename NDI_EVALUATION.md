# NDI® 整合評估 — v0.5

歷史評估；2026-10-21 已依使用者授權於 v0.5.2 實作 sender，現況請見 [NDI.md](NDI.md)。

日期：2026-10-20。結論：本次完成 Roadmap 所列的評估；App 0.5.0 沒有 NDI sender、SDK 或 runtime 依賴。缺少 NDI 不會阻止 App、實體 Output 或 Syphon 啟動。

NDI® is a registered trademark of Vizrt NDI AB. [NDI 官方網站](https://ndi.video/)

## 建議後續整合

官方提供動態載入方式，可在使用者啟動 NDI 時取得 runtime 入口；找不到 library 時僅回報該輸出不可用，不在 App 啟動時強制連結。macOS 路徑與 runtime 入口以採用版本 SDK 為準。[Dynamic Loading](https://docs.ndi.video/all/developing-with-ndi/sdk/dynamic-loading-of-ndi-libraries)

建議初期僅做 video sender，消費現有 LiveFrame 與共用 CanvasContentRenderer，不加入音訊、receiver 或媒體播放。每個 Output 保持自己的傳送設定。傳送與轉換使用獨立 worker 與有限緩衝，網路背壓不得阻塞 GO／Previous。

## 像素與 Alpha

官方 RGBA／BGRA 是未預乘 Alpha，本版 Syphon 則是預乘 Alpha；NDI sender 需要轉換，Alpha=0 時 RGB=0，並測試半透明字緣。官方提醒影像寬度應能被 2 整除。奇數 Canvas 應採顯式 signal padding 或回報輸出限制，不能偷偷改 Canvas。幀率使用分子／分母。[Frame Types](https://docs.ndi.video/all/developing-with-ndi/sdk/frame-types)

## SDK／發布條件

後續需取得採用版本的官方 SDK，確認其隨附 License Agreement 與 redistribution 條件；依規範加入連結、商標聲明與發行資訊。本版沒有包入 NDI runtime。[SDK Licensing](https://docs.ndi.video/all/developing-with-ndi/sdk/licensing)、[SDK 入口](https://ndi.video/for-developers/)

## 尚需驗證

- runtime 存在／缺少／架構不符，不影響其他輸出與專案開啟。
- 真實接收端的發現、重新連線、多來源、Alpha、Fade／Blackout。
- 網路負載、封包丟失、接收端重啟、長時間傳送；操作延遲、CPU、記憶體與幀率。
- 不同解析度／奇數尺寸策略、保存／遷移／Undo、停止生命週期與當版 SDK 發行條件。

以上是後續 sender 整合驗收項目，不是本版已實作功能。
