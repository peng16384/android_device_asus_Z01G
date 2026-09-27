# 已知問題：Evolution X（vic）

> **English summary** — Everything listed for the LineageOS 22.2 build applies
> here too (same device tree, kernel and vendor files): see
> [`../22.2/known-issues.md`](../22.2/known-issues.md) — notably Widevine L3 and
> no NFC. Specific to Evolution X:
>
> - The system partition is 5 GB and the build with full Google apps uses
>   4.8 GB of it. If future Google apps grow past that, the build will switch to
>   a smaller Google apps set.
> - "Network location without GApps" from the LineageOS list does not apply:
>   Google services are built in.
>
> *The body is in Traditional Chinese.*

**LineageOS 22.2 版的已知問題這裡全部適用**（同一棵 device tree、同一顆 kernel、同一批 vendor 檔）：
見 [`../22.2/known-issues.md`](../22.2/known-issues.md)，主要是 Widevine 只有 L3、沒有 NFC。

其中「沒裝 GApps 就只有 GPS 定位」這一條**不適用**：Evolution X 內建 Google 服務，網路定位由它提供。

## Evolution X 特有的

### system 分割快滿了

這台的 system 分割只有 5 GB，內建完整 Google 服務的 Evolution X 用掉 4.8 GB
（LineageOS 版是 2.4 GB）。system 是唯讀的，剩多少不影響使用；
但如果之後的 Google App 再變大、放不下，會改用 Evolution X 的精簡版 GApps
（到時候會在 release 說明裡寫明少了哪些 Google App）。

---

## 開發者會在 log 裡看到、但無害的訊息

除了 22.2 版列的那些之外：

| 訊息 | 說明 |
|---|---|
| 第一次開機時 `init-radio-sh` 的 `avc: denied { chown }`（數百筆）| `init.radio.sh` 把 modem 裡的電信商設定檔複製到 `/data/vendor/modem_config` 後想逐一改擁有者，SELinux 沒給這個權限。上游 LineageOS 的 OnePlus 5 樹是同一套政策、同樣的訊息；實測 VoLTE 與行動數據都正常 |
| `ro.build.host` 是 `r-<一串亂數>-<四個字元>` | Evolution X 每次建置都以亂數產生 Google 建置伺服器格式的主機名稱，與建置者的電腦無關 |
