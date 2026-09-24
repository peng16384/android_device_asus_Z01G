# 自己編

> **English summary** — How to build this ROM yourself. The unusual part: this
> project distributes no proprietary files, so vendor blobs, several config files
> and the patched `ims.apk` are all regenerated from **your own device's stock
> image** using the scripts in `tools/`. Requires Ubuntu 20.04 (LineageOS 16.0
> needs python2, openjdk-8 and lib32 packages that newer releases dropped),
> `git-lfs`, and `python` pointing at python2. The build fails loudly if the IMS
> APK has not been rebuilt — deliberately, so nobody ships a ROM that silently
> cannot make calls.
>
> *The body is in Traditional Chinese.*

這個專案**不散布任何專有檔案**。vendor blob 與改過的 `ims.apk` 都是從
**你自己手機的原廠映像**抽出來重建的，所以編譯流程比一般的 device tree
多一個「先從手機取得原始素材」的步驟。

---

## 1. 環境

實測過的組合（其他組合沒試過）：

| | |
|---|---|
| OS | Ubuntu 20.04.6 LTS（WSL2 也可以，本專案就是在 WSL2 上做的）|
| 為什麼是 20.04 | LineageOS 16.0 是 2018–2019 年的樹，需要 python2.7、openjdk-8<br>與一堆 lib32 舊套件，新版 Ubuntu 早就沒有了 |
| 磁碟 | 至少 300 GB（AOSP 樹 + out/）|
| RAM | 建議 16 GB 以上 |

⚠ **`python` 必須指向 python2**。AOSP 9 的建置腳本是 Python 2 寫的，
指向 python3 會編到一半失敗，而且留下 0 byte 的中間檔讓 ninja 誤判為最新，
根因修好之後症狀還會復發（要手動清 `out/target/common/obj/.../＊_intermediates`）。

⚠ **一定要裝 git-lfs**。缺了它 `repo sync` 會報
`Cannot initialize work tree`，而且 prebuilt 的 APK 會變成 134 bytes 的
LFS 指標檔 —— `repo sync` 成功不等於內容到位。

```bash
sudo apt install git-lfs && git lfs install
```

---

## 2. 取得 LineageOS 16.0 原始碼

```bash
mkdir ~/lineage-16.0 && cd ~/lineage-16.0
repo init -u https://github.com/LineageOS/android.git -b lineage-16.0
repo sync -j8
```

## 3. 放入這棵 device tree

```bash
git clone -b lineage-16.0 <this repo> device/asus/Z01G
```

## 4. 從你自己的手機取得素材

這一步是本專案與一般 device tree 最不一樣的地方。

### 4.1 取得原廠 system 分割區

**要用 `dd` 整個分割區，不要用 `adb pull /system`** —— 後者會丟失權限、
symlink 與 SELinux context。手機需要 root（Magisk 即可）。

```bash
bash device/asus/Z01G/tools/06_dump_system.sh     # root dd -> system.img（5 GiB，約 8 分鐘）
sudo bash device/asus/Z01G/tools/07_mount_system.sh   # 唯讀掛到 /mnt/zs_system
```

⚠ Android 8 的 toybox `dd` **不吃 `bs=1M`**，要寫 `bs=1048576`；
而且要用 `adb exec-out` 不是 `adb shell`，否則二進位會被 CRLF 轉換弄壞。
上面的腳本已經處理好了。

### 4.2 產生 blob 清單並抽取

```bash
bash device/asus/Z01G/tools/42_refresh_blobs.sh
```

這支會重新掃描映像產生 `proprietary-files.txt`（約 3600 條），
再跑 `extract-from-image.sh` 產生 `vendor/asus/Z01G/`。

> **`proprietary-files.txt` 是產生出來的，手改會被蓋掉。**
> 要增減請改 `tools/31_build_blob_list.py`。

### 4.3 重建 IMS（VoLTE 要用）

```bash
# 需要 vdexExtractor：https://github.com/anestisb/vdexExtractor
# 以及 baksmali/smali 2.5.2 放在 ~/imswork/tools/
bash device/asus/Z01G/tools/101_build_ims_apk.sh
```

這支會從原廠映像取出 `ims.apk`，還原被 quicken 過的 dex、把 Oreo 的 IMS API
參照改成 Pie 的位置、換掉 manifest 的 intent action、用 platform key 重簽，
最後對著**實際編出來的 framework** 驗證每一個類別、方法與欄位都找得到。

背景與每一步的理由見 `lineage-16.0` 分支的 `docs/volte.md`。

⚠ 沒跑這支的話編譯會**直接失敗**（找不到 `prebuilt/ims/ims.apk`）。
這是刻意的 —— 寧可大聲壞掉，也不要靜靜編出一個沒有通話功能的 ROM。

### 4.4 其他從原廠映像產生的檔案

```bash
sudo bash tools/07_mount_system.sh                    # 確認有掛載
python3 device/asus/Z01G/tools/97_patch_qcom_init_rc.py    # init.qcom.rc 補 group
python3 device/asus/Z01G/tools/104_patch_audio_policy.py   # audio policy 補 attachedDevices / BT SCO
python3 device/asus/Z01G/tools/93_sanitize_media_profiles.py  # 剔除 AOSP 9 不接受的錄影規格
```

每一支都會先驗證「原樣確實存在」，對不上就中止不寫檔。

## 5. 編譯

```bash
source build/envsetup.sh
lunch lineage_Z01G-userdebug
mka bacon
```

⚠ **`mka bacon 2>&1 | tail -30` 會吃掉失敗** —— 管線的結束碼是 `tail` 的，
`set -e` 攔不到。寫腳本時要加 `set -o pipefail`。

⚠ **`out/` 是增量的。** 從 blob 清單移除一條**不會**讓已經安裝的檔案消失。
改過清單之後要 `m installclean`（`tools/44_installclean_build.sh` 會處理）。

### 5.1 要公開發布的話

照上面的方式編，產物裡會帶著**你的帳號與電腦名稱**：

| 出現在 | 內容 |
|---|---|
| `build.prop`、zip 的 metadata | `ro.build.user`、`ro.build.host`、`eng.<帳號>.<日期>` |
| kernel 版本字串 | `Linux version ... (<帳號>@<電腦名稱>)`，任何人 `cat /proc/version` 都看得到 |
| 36 個 `.oat` / `.odex`、`libart.so` 等 | dex2oat 記下的 `/home/<帳號>/...` 建置路徑 |

要發布的 ROM 請改用：

```bash
bash device/asus/Z01G/tools/106_release_build.sh
```

它在私有的 UTS namespace 裡以 `android-build@localhost` 的身分，
從 bind mount 的中性路徑 `/src/lineage-16.0` 編，輸出放在另一個目錄
（平常開發用的 `out/` 不受影響；路徑一換等於從頭編，第一次要一個多小時）。

編完用 `tools/107` 掃一次，確認沒有個資：

```bash
bash device/asus/Z01G/tools/107_scan_rom_pii.sh <zip> <樣式檔> [<只列檔名的樣式檔>]
```

樣式檔一行一個字串（帳號、電腦名稱、email 帳號…），**放在 repo 以外**。
門號這類連前後文都不該出現在畫面上的，放第三個參數，只會列出檔名。

---

## 6. 驗證

編完之後值得跑的檢查：

```bash
bash device/asus/Z01G/tools/45_preflight.sh        # 刷機前的綜合檢查
bash device/asus/Z01G/tools/40_check_services.sh   # .rc 與執行檔有沒有錯位
bash device/asus/Z01G/tools/37_shadow_check.sh     # blob 與 AOSP 模組互相覆蓋
```

`.rc` 指向不存在的執行檔在編譯期**完全無聲**，開機才會發現 —— 所以這類
檢查比看編譯輸出有用。

---

## 7. 工具總覽

`tools/` 裡的腳本大致分三類：

| 編號 | 用途 |
|---|---|
| 01–25 | kernel 與第一次建置的流程 |
| 31–56 | blob 清單、抽取、各種「編譯期無聲」的檢查 |
| 93–104 | 從原廠映像產生設定檔、SELinux、IMS |
| 105–107 | 比對兩個 ROM zip 的內容、發布用建置、個資掃描 |

其中 **98–104 是這個專案比較有轉移價值的部分**，與機型無關：

| | |
|---|---|
| `98_vdex_extract.py` | 解析 vdex，判斷 dex 有沒有被 quicken |
| `99_patch_ims_smali.py` | Oreo 的 IMS app 搬到 Pie 的 API 位置 |
| `100_patch_axml_string.py` | 只重建 binary XML 的字串池（不用 apktool 重編整包資源）|
| `102_check_dex_refs.py` | 對著實際的 framework 檢查 dex 的**類別**參照 |
| `103_check_dex_methods.py` | 同上，檢查**方法與欄位** |
| `104_patch_audio_policy.py` | audio policy 的 attachedDevices 與 BT SCO route |

102/103 是從失敗學到的：類別層、方法層、欄位層各自會產生
`NoClassDefFoundError`、`NoSuchMethodError`、`NoSuchFieldError`，
而且都只在執行到那一行才爆。一輪「改→編→刷→測」要 20 分鐘，
所以值得一次掃完而不是一次抓一個。
