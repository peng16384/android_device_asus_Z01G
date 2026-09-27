# 刷機：Evolution X（vic，Android 15）

> **English summary** — Evolution X for this device is built from the same device
> tree, kernel and vendor files as the LineageOS 22.2 build, and installs the
> same way: read [`../22.2/flashing.md`](../22.2/flashing.md) and
> [`../flashing.md`](../flashing.md) first. Differences:
>
> - **Google apps are built in** — do not flash a separate GApps package.
> - **Coming from anything else, including this project's LineageOS 22.2 build,
>   you must Format data.** Updates of Evolution X keep your data.
> - Either recovery works: the `recovery.img` from this release or from the
>   LineageOS 22.2 release. Both carry this project's release key.
> - The first boot takes several minutes longer (Google apps are optimised).
> - USB debugging is off after installation; enable it in Developer options if
>   you need adb.
> - Updates arrive in the Evolution X **Updater** (Settings → System).
>
> *The body is in Traditional Chinese.*

**先讀 [`../22.2/flashing.md`](../22.2/flashing.md) 與 [`../flashing.md`](../flashing.md)**。
Evolution X 用的是同一棵 device tree、同一顆 kernel、同一批 vendor 檔，
安裝流程、安全規則、出事怎麼救都一樣。這份只寫不一樣的地方。

## 1. 要下載的東西

Releases 裡 Evolution X 的那一版：

| 檔案 | 用途 |
|---|---|
| `EvolutionX-15.0-<日期>-Z01G-<版本>-Unofficial.zip` | ROM 本體（**已內建 Google 服務**，mini 版，見 known-issues）|
| `recovery.img` | LineageOS Recovery（Evolution X 沿用）|
| `SHA256SUMS` | 先核對再刷 |

## 2. 與 LineageOS 22.2 版不同的地方

| | |
|---|---|
| GApps | **已內建**，不要再刷另外的 GApps 套件 |
| 從別的 ROM 換過來 | **一定要 Format data** —— 包括從本專案的 LineageOS 22.2 換過來（系統 App 與 Google 服務都不同）|
| recovery | 這個 release 的 `recovery.img` 或 LineageOS 22.2 release 的都可以：兩者都認得本專案的私鑰。<br>手機上已經是 LineageOS 22.2 那顆 recovery 的話，**不用換** |
| 第一次開機 | 比 LineageOS 久幾分鐘（要最佳化一大堆 Google 的 App），開機動畫停久一點是正常的 |
| USB 偵錯 | 裝好之後是**關的**；要用 adb 請到開發人員選項打開 |
| 更新 | **設定 → 系統 → Updater**（Evolution X 自己的更新程式，讀本專案的清單）|

## 3. 安裝

和 22.2 版相同（[`../22.2/flashing.md`](../22.2/flashing.md) 的第 3 節），只是 sideload 的是
Evolution X 的 zip，而且**第 6 步（GApps）跳過**：

```bash
adb sideload EvolutionX-15.0-<日期>-Z01G-<版本>-Unofficial.zip
```

zip 比 LineageOS 的大（約 1.9 GB），傳輸久一點。

## 4. 已知問題

見 [`known-issues.md`](known-issues.md)。
