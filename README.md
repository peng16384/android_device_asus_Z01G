# device/asus/Z01G — LineageOS 16.0 for ASUS ZenFone 4 Pro (ZS551KL)

Device tree for LineageOS 16.0 (Android 9).
Clone this branch straight into an AOSP checkout:

```bash
git clone -b lineage-16.0 <this repo> device/asus/Z01G
```

Project overview, status, build and flashing guides are on the **`main`**
branch (`README.md` and `docs/`).

---

## 這棵樹的形狀與取捨

以 `LineageOS/android_device_xiaomi_msm8998-common`（lineage-16.0）為骨架，
理由是它的 `proprietary-files.txt` 對本機 `system.img` 的命中率最高
（458/570 = 80.4 %）。板級參數以
[`shakalaca/android_device_asus_Z01G`](https://github.com/shakalaca/android_device_asus_Z01G)
為準，並與實機拆出來的 boot header 交叉驗證過
（`kernel_offset 0x8000`、`ramdisk_offset 0x1000000`、`tags_offset 0x100` 逐項吻合）。

**刻意做成單一 device tree，沒有拆 `msm8998-common`。**
Xiaomi/OnePlus 拆 common 是因為一個平台有多支機器；這裡只有一支，
拆開只是增加一層間接。

**這台不是 Treble。** 沒有獨立的 vendor 分割，blob 放在 `/system/vendor`：

```make
TARGET_COPY_OUT_VENDOR := system/vendor
# 不設 BOARD_VENDORIMAGE_*
# 不設 PRODUCT_FULL_TREBLE_OVERRIDE
# 不設 BOARD_PROPERTY_OVERRIDES_SPLIT_ENABLED
```

---

## 目錄

| | |
|---|---|
| `configs/` | 從原廠映像改過的設定檔（audio policy、media profiles）|
| `keylayout/` | `goodixfp.kl` —— 指紋感測器當 Home 鍵用 |
| `overlay/` | framework 資源覆蓋（耳機偵測、實體按鍵、IMS 套件名）|
| `prebuilt/` | IMS 的 `BUILD_PREBUILT` 定義（apk 本身不在 git 裡，見下）|
| `rootdir/` | fstab、init rc、補過 group 的 `init.qcom.rc` |
| `sepolicy/` | SELinux 政策（public / private / vendor 三側）|
| `tools/` | 建置與診斷工具 |
| `docs/` | 三份工程紀錄，見下 |

## 要先跑工具才能編

`proprietary-files.txt`、`configs/` 底下的設定檔、以及
`prebuilt/ims/ims.apk` **都是從你自己手機的原廠映像產生的**，不在這個 repo 裡。
步驟見 `main` 分支的 `docs/building.md`。

缺 `prebuilt/ims/ims.apk` 時編譯會直接失敗 —— 這是刻意的，
寧可大聲壞掉，也不要靜靜編出一個沒有通話功能的 ROM。

> **`proprietary-files.txt` 是產生出來的，手改會被蓋掉。**
> 要增減請改 `tools/31_build_blob_list.py`。

## 工程紀錄

`docs/` 底下三份，記的不只是「怎麼做成的」，還有走過的彎路與下錯的判斷：

| | |
|---|---|
| [`kernel.md`](docs/kernel.md) | 從原廠原始碼編出可開機的 kernel，與原廠逐項比對的驗證 |
| [`bringup.md`](docs/bringup.md) | 建置與開機除錯，含七次編譯失敗與六輪開機失敗的根因 |
| [`volte.md`](docs/volte.md) | VoLTE：把 Oreo 的 IMS app 改到 Pie 的 API 位置（**英文**）|
| [`volte.zh-TW.md`](docs/volte.zh-TW.md) | 同上，中文版 |

`volte.md` 大概是**最有轉移價值**的一份（所以寫了英文版） —— 任何要把 OEM 的舊 IMS apk
搬到新版 Android 的人都會碰到同樣的問題。

`docs/reference/` 是從實機抓的原廠資料（分割表、fstab、cmdline、defconfig、
getprop）。**`getprop_full.txt` 裡的 IMEI、序號與 MAC 位址已經遮蔽**，
其餘保持原樣。
