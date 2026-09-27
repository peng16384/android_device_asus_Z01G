# 刷機：LineageOS 22.2

> **English summary** — How to install the LineageOS 22.2 build. Read
> [`../flashing.md`](../flashing.md) first: its prerequisites, the list of
> partitions you must never write, and the rescue section all still apply.
> What is different for 22.2:
>
> - **Use the LineageOS Recovery from the release, not TWRP.** The zip is signed
>   with this project's own release key; the recovery verifies it, can format
>   `/data`, and installs future OTA updates. TWRP cannot mount `/data` after
>   LineageOS has booted once, and rejects this zip's device check (`ERROR: 7`).
> - **Coming from anything else — stock, the 16.0 build, any other ROM — you must
>   Format data.** Updates of this 22.2 build (the in-system Updater, or
>   sideloading a newer release zip) keep your data.
> - Steps: `fastboot flash recovery recovery.img` → `fastboot oem reboot-recovery`
>   → Factory reset → Format data → Apply update → Apply from ADB →
>   `adb sideload <zip>` → Reboot system now.
> - Updates arrive in **Settings → System → Updater**.
>
> *The body is in Traditional Chinese.*

**先讀 [`../flashing.md`](../flashing.md)**：前提條件、**絕對不能寫入的分割區**、
出事怎麼救，全部照舊適用。這份只寫 22.2 不一樣的地方。

---

## 1. 要下載的東西

Releases 裡 22.2 的那一版：

| 檔案 | 用途 |
|---|---|
| `lineage-22.2-<日期>-UNOFFICIAL-Z01G.zip` | ROM 本體 |
| `recovery.img` | LineageOS Recovery（驗證簽章、安裝、之後的 OTA 更新都靠它）|
| `SHA256SUMS` | 先核對再刷 |

```bash
sha256sum -c SHA256SUMS
```

## 2. 為什麼換成 LineageOS Recovery

| | TWRP 3.7.0 | LineageOS Recovery |
|---|---|---|
| 裝這個 zip | ✗ 裝置檢查失敗（`ERROR: 7`：這台的 TWRP 沒設 `ro.product.device`）| ✓ |
| 驗證 zip 的簽章 | 不驗 | ✓ 用 ROM 內建的憑證驗 |
| LineageOS 開過機之後的 `/data` | ✗ 掛不動（`quota`，見 `../flashing.md`）| ✓ |
| 系統內的 OTA 更新 | ✗ | ✓ |

這個 ROM 用**本專案自己的私鑰**簽名（不是 AOSP 公開的 test-keys），
LineageOS Recovery 只接受用這把金鑰（或 LineageOS 官方金鑰）簽的更新。

要換回 TWRP 隨時可以：`fastboot flash recovery <twrp 映像>`。

## 3. 安裝

⚠ **第一次安裝一定要 Format data**，內部儲存空間（照片、下載、App 資料）會全部清空，
外接 SD 卡不受影響。從原廠、16.0、或任何別的 ROM 過來都一樣——
簽章不同的系統 App 碰到舊資料會開不了機。

1. 手機進 bootloader（關機後按住 **電源 + 音量上**，或 `adb reboot bootloader`）
2. 刷 recovery，然後進去：
   ```bash
   fastboot flash recovery recovery.img
   fastboot oem reboot-recovery
   ```
   （`fastboot reboot recovery` 在這台不可靠。刷的時候出現
   `skip copying recovery image avb footer` 的警告是正常的。）
3. **Factory reset → Format data/factory reset**，確認
4. 回主選單 → **Apply update → Apply from ADB**
5. 電腦上：
   ```bash
   adb sideload lineage-22.2-<日期>-UNOFFICIAL-Z01G.zip
   ```
   電腦端的進度停在 47% 左右、最後印出 `Total xfer: 1.00x` 是正常的；
   手機畫面顯示 `Install completed with status 0` 才是成功。
6. 需要 Google 服務的話，**在重開機之前**同樣用 Apply from ADB 裝 GApps
   （arm64 / Android 15）。GApps 不是用本專案的金鑰簽的，recovery 會問
   「Signature verification failed, install anyway?」——那是預期的，選 Yes。
   本專案沒有實測過特定哪一套 GApps。
7. **Reboot system now**

電腦看不到手機時：在 recovery 的 **Advanced → Enable ADB** 打開 adb
（一般模式預設是關的），必要時拔插一次 USB 線。

## 4. 之後的更新

**設定 → 系統 → Updater**。有新版時會列出來，下載後由 LineageOS Recovery
驗證簽章並安裝，資料保留。

也可以手動：下載新版 zip，照上面第 4–5 步 sideload（**不用** Format data）。

## 5. 裝了之後

- SELinux 是 enforcing，adb 需要在手機上授權（`ro.adb.secure=1`）。
- 已知問題見 [`known-issues.md`](known-issues.md)。
