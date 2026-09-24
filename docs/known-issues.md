# 已知問題

> **English summary** — Known issues and limitations.
>
> **Limitations**
>
> - A single SIM must go in **slot 1**; in slot 2, IMS binds the wrong stack
>   and there is no VoLTE.
> - NFC, Miracast and VR are disabled.
> - Without GApps there is no Wi-Fi/cell network location, only GPS.
> - The built-in camera app (Snap) only switches between the main and front
>   cameras. The telephoto camera works in apps that list every camera, such as
>   Open Camera.
> - No kernel module can be loaded (`CONFIG_MODULE_SIG_FORCE=y` rejects even the
>   kernel's own modules). Wi-Fi is built in and unaffected; `texfat.ko`
>   (exFAT) is affected.
> - This is a `userdebug` build (`ro.debuggable=1`).
>
> **If calls do not go out** (dialer sits at "Dialing", then hangs up): check
> `adb logcat -b all | grep -E "isVolteEnabled|Z01G-IMS"`. `true` is good. The
> ROM retries a failed IMS start for up to three minutes after boot; if it is
> still `false` after that, reboot.
>
> The rest lists harmless log messages that developers will see, and what has
> not been tested. *The body is in Traditional Chinese.*

## 限制

### 單一 SIM 請插卡槽 1

IMS 綁定哪一個協定堆疊的判斷有一段時序競態（詳見
`lineage-16.0` 分支 `docs/volte.md` 的 G 段）：`SubscriptionManager.getPhoneId()`
在 IMS 查詢的當下可能還沒就緒，而 app 之後只等一個
`ACTION_DDS_SWITCH_DONE` 廣播——那是 QTI 自家 telephony 擴充發的，
這個建置上沒有那個擴充，所以永遠不會再重新評估。

我們的處理是「解析不到就退回 phone 0」。**所以唯一的 SIM 請插卡槽 1。**
插在卡槽 2 的話 IMS 會綁到錯的堆疊，VoLTE 不會運作。

（這台的卡槽 2 與 microSD 共用，多數人本來就插記憶卡。）

### NFC、Miracast、VR 沒有啟用

bring-up 期間關掉之後沒有回頭處理：

- NFC（NXP，HAL 有但服務停用）
- Miracast / WFD
- VR

要啟用的話得同步改 `manifest.xml` —— **manifest 宣告了但服務沒註冊，
客戶端會無限等待**（Watchdog 會把 system_server 打死）。

### 沒裝 GApps 就只有 GPS 定位

GPS 本身可以用（GPS / GLONASS / 北斗 / Galileo / QZSS 都收得到）。
但 Qualcomm 的網路定位（Izat）在 Pie 上會把 system_server 打死，所以停用了；
Wi-Fi／基地台定位因此要靠 GApps 提供。

### 內建相機只切換主鏡頭與前鏡頭

三顆鏡頭（IMX362 主 / IMX319 前 / IMX351 望遠）都可以用，
但內建的 Snap 切換鈕只在第一顆後鏡頭與第一顆前鏡頭之間跳，這是 App 本身的行為。

要用望遠鏡頭，請換成會列出所有鏡頭的 App，例如 **Open Camera**
（實測切換鈕會輪到第三顆，能拍全解析度照片）。

### kernel 模組一個都載不起來

kernel 設了 `CONFIG_MODULE_SIG_FORCE=y`，連 kernel 自己編出來的模組也被拒絕
（`Required key not available`）。Wi-Fi 驅動是直接編進 kernel 的，不受影響；
但 `texfat.ko`（exFAT）這類模組也載不起來。

### 這是 `userdebug` 版本

`ro.debuggable=1`，`adb root` 要靠它。要完全收掉得改編 `user` 變體，
會失去部分除錯能力。

---

## 打不出電話時

症狀：撥號顯示「撥號中」，然後自己掛斷。

在 3G 已關台的地區，語音只能走 VoLTE；VoLTE 沒起來時撥號會退回 3G，
就會是這個樣子。開機時 modem 的 IMS 偶爾還沒準備好（實測是刷機後的第一次開機），
ROM 會自動重試，最多 3 分鐘。

**怎麼判斷**：

```bash
adb logcat -b all | grep -E "isVolteEnabled|Z01G-IMS"
```

`isVolteEnabled=true` 才是好的；有重試的話會看到 `Z01G-IMS` 的紀錄。
開機 3 分鐘後還是沒起來，就重開機。

細節見 `lineage-16.0` 分支 `docs/volte.md` 的「Boot timing」一節。

---

## log 裡看得到、但無害的訊息

給會看 log 的人：下面這些看起來像錯誤，但都查過，不影響功能。

| | |
|---|---|
| `GnssLocationProvider: Unable to initialize GNSS Xtra interface` | Qualcomm 的 GPS 驅動本來就沒實作這個介面，衛星星曆由 `xtra-daemon` 自己下載 |
| `dumpsys location` 的衛星表全部是「未知」 | 驅動的除錯資料只回傳空白樣板，不代表沒有星曆 |
| `QtiImsExtManager` 的三個方法 | `getImsServiceStatus` / `isConnected` / `isOpened` 在 Pie 的<br>`ImsManager` 不存在。那是給 QTI/ASUS 自家 App 的擴充 API，<br>這個建置沒有裝會呼叫它的東西。若有 App 踩到會明確報 `NoSuchMethodError` |
| `ro.sf.lcd_density` 的 SELinux denial | `init.qcom.post_boot.sh` 想設一個早就設好的唯讀屬性，本來就會失敗。<br>**刻意不 dontaudit** —— 免得連帶蓋掉別的訊息 |
| `dpmd` 的 DAC denial | 查過：用真實身分算過每個 `openat` 都通過，7596 行 strace 裡零個<br>`EACCES`。沒查出是哪個 syscall 觸發的，但也沒有任何呼叫失敗。<br>同樣刻意留著可見 |
| GApps 的亮度 NPE | `com.google.android.apps.turbo` 開機時碰 `AutomaticBrightnessController`<br>會 NPE。LineageOS 既有問題，與本移植無關 |
| `lineageparts` 偶發當機 | 開機初期第一次開 Trust 頁面時，之後正常。LineageOS 自己的競態 |

---

## 沒測過的

- 藍牙以外的通話音訊路徑（有線耳機通話、車用免持）
- 雙卡同時使用
- Widevine DRM 的實際播放（服務有起來）
- 快充的實際功率
