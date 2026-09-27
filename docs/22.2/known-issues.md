# 已知問題：LineageOS 22.2

> **English summary** — Known issues and limitations of the 22.2 build.
>
> - **User data (`/data`) is not encrypted** (the Trust page in Settings shows
>   "Encryption: Disabled"). A screen lock does not protect your
>   files if someone has the phone: with the unlocked bootloader they can boot a
>   recovery and read `/data` without your PIN. This is a known risk and is not
>   planned to change; turning encryption on later would require wiping data.
> - **Widevine is L3 only** (streaming apps limit you to SD). The device's
>   keybox is rejected by TrustZone even with every stock ASUS component; this is
>   not caused by the port.
> - FM radio and ANT+ are not included. (NFC works since `22.2-v1.1`.)
> - Without GApps there is no Wi-Fi/cell network location, only GPS.
> - No kernel module is loaded (`/proc/modules` is empty); everything needed is
>   built into the kernel.
> - This is a `userdebug` build (`ro.debuggable=1`), signed with this project's
>   own release keys.
> - On the first boot after installing, the fingerprint HAL may crash once
>   inside the ASUS blob and is restarted automatically; enrolling and
>   unlocking work.
> - A single SIM in **slot 2** has not been tested.
>
> The rest lists harmless messages developers will see in the logs.
> *The body is in Traditional Chinese.*

## 限制

### 使用者資料（`/data`）沒有加密

設定裡的「信任」頁面會顯示 **「加密：已停用」**。

意思是照片、App 資料、帳號登入資訊都以明文存在儲存空間裡。日常使用沒有差別，
但**螢幕鎖只擋得住操作手機，擋不住直接讀儲存空間**：這台的 bootloader 是解鎖的，
手機落到別人手上時，對方可以開進 recovery 或刷自己的映像，不需要你的密碼就能讀出 `/data`。

原因：原廠（Android 8）用的是整區加密（FDE），Android 13 起系統已經不支援；
新的以檔案為單位加密（FBE）在移植時沒有開。kernel 本身具備 FBE 需要的功能，
但開啟後**所有人都必須清除資料**才能改成加密，而且要重新驗證 TrustZone 那一段，
目前**不打算處理，列為已知風險**。

比較在意手機遺失風險的話：避免在這台上存放敏感資料，
並確認 Google 帳號等服務可以從別的裝置遠端登出。

### Widevine 只有 L3

DRM 服務正常，Widevine 內容播得了，但只到 **L3**：Netflix 之類的串流平台會限制在 SD 畫質。

這**不是移植造成的**。把 ASUS 原廠的整套元件（程式庫、TrustZone app、qseecomd）
換上去逐一測過，結果一樣：TrustZone 判定這台的 keybox 無效
（`/persist` 裡的 Widevine 資料與出廠時的備份逐檔相同，沒有被動過）。
推測是解鎖 bootloader 之後 TrustZone 就不再接受 keybox，但沒辦法在鎖定狀態下對照，未證實。
詳見 `lineage-22.2` 分支 `docs/bringup.md` 第 9 節。

### 沒有 FM、ANT+

建 blob 清單時刻意沒收（FM 收音機、ANT+）。

NFC 在 `22.2-v1.0` 也沒有，**`22.2-v1.1` 起可以用**（NXP PN548；悠遊卡這類 MIFARE Classic 卡也讀得到）。

### 沒裝 GApps 就只有 GPS 定位

GPS 可以用（衛星定位走 ASUS 原廠的定位堆疊）。Qualcomm 的網路定位（Izat）沒有收進來，
Wi-Fi／基地台定位要靠 GApps 提供。

### 不載入 kernel 模組

`/proc/modules` 是空的。需要的驅動（包含 Wi-Fi）都直接編進 kernel，不受影響。

### `userdebug` 版本，用本專案的私鑰簽名

- `ro.debuggable=1`（開發人員選項裡可以開 root 權限的 adb）。
- 簽名用的是本專案自己的金鑰，不是 AOSP 公開的 test-keys，
  所以系統設定裡不會出現「以測試金鑰簽署」的警告。
  之後的版本會沿用同一把金鑰，更新不用清資料。

### 安裝後第一次開機，指紋 HAL 可能崩潰一次

開機第 1 秒左右，ASUS 的 `fingerprint.gx5206.so` 裡的一個執行緒可能呼叫到空指標而崩潰，
系統會立刻把服務重新啟動。之後登錄指紋、解鎖、Home 鍵都正常，也不會再發生。
看起來是 blob 內部的啟動時序問題。

### 單一 SIM 插卡槽 2：沒有測過

16.0 版有「單一 SIM 要插卡槽 1」的限制，那是 16.0 改過的 ASUS IMS app 造成的。
22.2 換了一套 IMS（OnePlus 5 的 QTI IMS，未修改），那個限制應該不存在，但沒有實測。

---

## 開發者會在 log 裡看到、但無害的訊息

| 訊息 | 說明 |
|---|---|
| `WARNING ... enable_irq`（4 次，ASUS 音訊驅動）| 原廠驅動本來就有，16.0 時期就存在 |
| `proc_dir_entry 'driver/front_otp' already registered` | ASUS 相機驅動重複註冊同一個 proc 節點；合併 CIP 的修補之後 kernel 開始對這件事發出警告，功能不受影響 |
| 一般 App（`untrusted_app`）的 `avc: denied` | App 探測系統資訊被 SELinux 擋下，是 enforcing 的正常現象 |
