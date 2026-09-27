# 已知問題：Evolution X（vic）

> **English summary** — Everything listed for the LineageOS 22.2 build applies
> here too (same device tree, kernel and vendor files): see
> [`../22.2/known-issues.md`](../22.2/known-issues.md) — notably Widevine L3 and
> no NFC. Specific to Evolution X:
>
> - Google apps are the **mini** set: Google Photos, Recorder, ARCore, Pixel live
>   wallpapers and a few other Pixel extras are not included (most can be
>   installed from the Play Store). The full set would not fit GitHub's 2 GiB
>   file limit.
> - The GNSS service crashes once shortly after every boot, inside ASUS's
>   location library, and is restarted automatically; GPS works afterwards.
> - "Network location without GApps" from the LineageOS list does not apply:
>   Google services are built in.
>
> *The body is in Traditional Chinese.*

**LineageOS 22.2 版的已知問題這裡全部適用**（同一棵 device tree、同一顆 kernel、同一批 vendor 檔）：
見 [`../22.2/known-issues.md`](../22.2/known-issues.md)，主要是 Widevine 只有 L3、沒有 NFC。

其中「沒裝 GApps 就只有 GPS 定位」這一條**不適用**：Evolution X 內建 Google 服務，網路定位由它提供。

## Evolution X 特有的

### Google App 是精簡版（mini）

內建的是 Evolution X 的 **mini** GApps。和完整版相比少了：
Google 相簿、錄音機、ARCore、Pixel 動態桌布與桌布、Google Fi、聲音放大器、
Voice Access、切換控制、天氣等 Pixel 附加 App（多數可以從 Play 商店裝回來）；
Android System Intelligence 是較小的舊版。
Google Play 服務、Play 商店、Google App、Google 訊息、日曆、Files 都在。

原因：完整版的 zip 是 2.44 GiB，超過 GitHub Release 單檔 2 GiB 的上限。
mini 版 zip 1.9 GiB，system 用掉 4.1 GB（分割 5 GB）。

### 每次開機，GNSS 服務會當機一次

開機後不久，`android.hardware.gnss@1.0-service` 會在 ASUS 原廠的定位程式庫
（`libdataitems.so`，處理網路狀態通知時）因記憶體配置失敗而中止，系統隨即自動重啟它，
之後 GPS 正常。LineageOS 與 Evolution X 用的是同一套程式與設定，
但目前只在 Evolution X 上觀察到；觸發它的那一次呼叫還沒有抓到。

---

## 開發者會在 log 裡看到、但無害的訊息

除了 22.2 版列的那些之外：

| 訊息 | 說明 |
|---|---|
| 第一次開機時 `init-radio-sh` 的 `avc: denied { chown }`（數百筆）| `init.radio.sh` 把 modem 裡的電信商設定檔複製到 `/data/vendor/modem_config` 後想逐一改擁有者，SELinux 沒給這個權限。上游 LineageOS 的 OnePlus 5 樹是同一套政策、同樣的訊息；實測 VoLTE 與行動數據都正常 |
| `ro.build.host` 是 `r-<一串亂數>-<四個字元>` | Evolution X 每次建置都以亂數產生 Google 建置伺服器格式的主機名稱，與建置者的電腦無關 |
