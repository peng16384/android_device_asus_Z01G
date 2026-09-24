# 刷機：前提條件、安全規則、出事怎麼救

> **English summary** — Prerequisites, safety rules, and recovery. This document
> deliberately does not give step-by-step instructions: if any prerequisite is
> unclear to you, do not flash. There is no free 9008/EDL rescue package for this
> device.
>
> **The safety rules, in full, because getting these wrong is unrecoverable:**
>
> - **Never write to** `xbl`, `abl`, `tz`, `rpm`, `hyp`, `pmic`, `keymaster`,
>   `devcfg`, `gpt`, `persist`, `modemst1`, `modemst2`, `fsg`, or any `*bak`
>   partition. Damaging these means 9008/EDL, and the factory package for this
>   device is only available from paid sources.
> - **Only** `boot`, `recovery`, `system`, `userdata` and `cache` are safe.
> - Back up `persist` before anything else — it holds per-device sensor
>   calibration and the Wi-Fi/BT MAC addresses, and **cannot be recreated**.
> - `fastboot boot <img>` (boot without flashing) **does not work** on this
>   device, so there is no "try it first" option.
> - TWRP cannot mount `/data` once LineageOS has booted (ext4 `quota` feature vs.
>   a TWRP kernel without `CONFIG_QUOTA`). Wipe operations **fail silently**; use
>   Format Data instead.
> - Inside TWRP, `/vendor` is a real empty directory, not a symlink. Pushing
>   there writes to a tmpfs that vanishes on reboot — and `adb push` reports
>   success. Use `/system/vendor/...` instead.
> - The release ROM zip has a **widened device check**. This device's TWRP
>   does not set `ro.product.device` or `ro.build.product`, so a stock
>   LineageOS zip always aborts with `ERROR: 7`. The check now also accepts
>   `ro.omni.device == "Z01G"` / `ro.product.name == "omni_Z01G"`, which this
>   TWRP does set, and still rejects other devices.
>
> *The body is in Traditional Chinese and covers the same ground in more detail,
> plus how to recover when the device will not boot.*

> **這份文件刻意不寫「逐步手把手」。**
> 如果下面的前提條件你有任何一項看不懂或做不到，請不要刷。
> 這台機器沒有免費的 9008/EDL 救援包 —— 刷壞某些分割區就是變磚，
> 而且工廠包只有付費來源。

---

## 1. 前提條件

刷之前，下面每一項都要成立：

### 你必須已經會的

- 用 `fastboot` 與 `adb`，知道兩者差別，知道怎麼確認裝置有被認到
- 進入 bootloader 與 recovery，知道刷錯時怎麼再進去
- 看懂 `logcat` 與 `dmesg` 的大致意思（出事時這是唯一的線索）

### 裝置狀態

| | |
|---|---|
| 機型 | ASUS ZenFone 4 Pro **ZS551KL**（Z01G / Z01GD）。其他型號**不要**刷 |
| Bootloader | 已解鎖（`fastboot getvar unlocked` 回 `yes`）|
| Recovery | TWRP 已安裝（本專案用 3.7.0_9-0 測試）|
| 原廠版本 | 建議先更新到最後一版官方韌體（15.0410.1911.117）再刷 |

### 你必須先備份的

**在動任何東西之前**，至少要有這些，而且要確認**存在電腦上**不是只在手機裡：

- `boot` 分割區的原廠映像
- `persist` 分割區（裡面有感測器校正、Wi-Fi/BT MAC —— **弄丟就回不來了**）
- TWRP 的完整備份（boot / system / data）
- `/data` 裡你在乎的所有東西

> `/data` 會被清空。LineageOS 的 FDE 與原廠的加密不相容，
> 第一次刷一定要 Format Data（不是 Wipe，見第 3 節）。

---

## 2. 安全規則

### 絕對不要寫入這些分割區

```
xbl  abl  tz  rpm  hyp  pmic  keymaster  devcfg  gpt
persist  modemst1  modemst2  fsg  以及任何 *bak
```

這些壞掉會變 9008/EDL，**而這台的工廠包只有付費來源**。
沒有任何一個正常的刷機流程需要碰它們。看到任何教學叫你刷這些，停下來。

### 可以寫入的只有

```
boot  recovery  system  userdata  cache
```

### 其他

- **每次刷之前先確認還原檔在手邊**，而不是「應該還在吧」
- 一次只改一件事。同時換 kernel 又換 ROM，出事時分不出是哪個
- `fastboot boot xxx.img`（只開不刷）**這台不支援** —— 任何版本的 TWRP 都會退回
  fastboot 畫面。所以沒有「先試試看」這個選項，只能真的刷進去
- 進 recovery 用 `fastboot oem reboot-recovery`，`fastboot reboot recovery` 不可靠

---

## 3. 刷機

大致順序（細節看 TWRP 的操作說明，這裡只寫這台特有的部分）：

1. `fastboot oem reboot-recovery` 進 TWRP
2. **Format Data**（不是 Wipe → Data）
3. sideload 或從 SD 卡安裝 ROM zip（Releases 裡的那個，原因見下面「裝置檢查」）
4. 需要 Google 服務的話接著刷 GApps（**arm64 / 9.0 / nano** 或更小）
5. 重開機。第一次開機會跑 dexopt，在這顆 835 上可能要 20–40 分鐘

### 裝置檢查

一般的 LineageOS zip 開頭會檢查 `ro.product.device` 或 `ro.build.product`
是不是 `Z01G`。但這台的 TWRP **兩個都沒有設**（只有 `ro.omni.device=Z01G`
與 `ro.product.name=omni_Z01G`），所以自己編、沒改過的 zip **一定會失敗**：

```
E3004: This package is for device: Z01G; this device is .
updater process ended with ERROR: 7
```

Releases 的 zip 把這個檢查**放寬**成也認 `ro.omni.device` / `ro.product.name`，
不是拿掉——別的機型照樣會被擋下。實機上測過三種情況：原本的檢查失敗、
放寬後通過、裝置名稱不對時仍然失敗。

自己編的話，用 `lineage-16.0` 分支的 `tools/28_widen_device_assert.sh`
處理編出來的 zip。

### 這台特有的兩個坑

**TWRP 掛不動 `/data`。** 只要 LineageOS 開機過一次，`/data` 就會被加上
ext4 的 `quota` feature，而這台 TWRP 的 kernel 沒有
`CONFIG_QUOTA` —— 於是 `Wipe → Data`、`Wipe Dalvik` 都會**靜靜失敗**
（只印一行 `Failed to mount '/data'` 然後繼續，看起來像成功了）。

要清 `/data` 只能用不經過掛載的路徑：GUI 的 **Format Data**，或

```bash
make_ext4fs /dev/block/bootdevice/by-name/userdata
```

⚠ **不要加 `-l`**。給錯大小會做出比分割區小的檔案系統。不給它會自己讀
block device 的大小。

**TWRP 裡的 `/vendor` 不是 symlink。** 開機後的系統上
`/vendor -> /system/vendor`，但 TWRP 有自己的 ramdisk root，
`/vendor` 是一個真實的空目錄。所以在 TWRP 裡 `adb push ... /vendor/etc/xxx`
會寫進 TWRP 的記憶體檔案系統，重開機就蒸發 —— 而且 **push 會回報成功**。
在 TWRP 裡要動 vendor 的東西，一律用 `/system/vendor/...`。

---

## 4. 出事怎麼救

### 開不了機（卡在開機動畫或黑屏）

**先確認 adb 通不通。** 這個 ROM 的 adb 在開機第 14 秒左右就會上線，
開機動畫還在跑就能用：

```bash
adb logcat -b all > boot.log
adb shell dmesg > kmsg.txt
```

有 log 就有救。沒有 adb 的話進 TWRP，唯讀掛 `/data` 撈：

```bash
mount -o ro -t ext4 /dev/block/bootdevice/by-name/userdata /tmp/d
```

（唯讀是因為上面說的 quota 問題。）

Java 層的例外**不會**留 tombstone，要看 `/data/system/dropbox/`；
原生崩潰才在 `/data/tombstones/`。

### 刷回原廠 boot

```bash
fastboot flash boot <你備份的原廠 boot.img>
```

### 完全刷回原廠

下載 ASUS 官方韌體（WW_ZS551KL 的 `UL-ASUS_Z01GD_*-user.zip`），
放到 SD 卡根目錄，用原廠 recovery 或 TWRP 安裝。

⚠ 刷回原廠 system 之後，`/system/recovery-from-boot.p` 會被還原，
下次開機就會**把 TWRP 蓋回原廠 recovery**。要保住 TWRP 的話，
開機前先把那個檔改名（原廠出貨狀態下它本來就被改名成 `.bak` 停用了）。

### 沒有 adb、也進不了 recovery

這台的 3.5mm 耳機孔預設是 **UART kernel console**（ASUS 把它設計成兩用）。
如果你有 UART 轉接線：

```
setprop persist.asus.audbg 1     # 下次開機把耳機孔切回 console
```

cmdline 本來就有 `androidboot.console=ttyMSM0`，115200 8N1。
—— 但這招需要你還能下 `setprop`，所以它是「預防」不是「救援」。
真的兩者皆無時，只剩 9008/EDL，而那需要付費的工廠包。

---

## 5. 什麼情況下不要來問

- 刷了別的機型 → 沒有人幫得上
- 刷了教學沒提到的分割區 → 同上
- 沒有備份 `persist` 就清掉它 → 校正資料是每台獨有的，沒得抄

刷機的風險是你自己承擔的。這份文件已經把這台特有的坑寫出來了，
剩下的是你要不要在還沒準備好的時候動手。
