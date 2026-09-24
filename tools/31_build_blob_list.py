#!/usr/bin/env python3
"""
重做 proprietary-files.txt —— 改用「全收再扣」而不是「猜著收」。

為什麼要重做：
    第一版用「參考機清單 ∩ 本機映像」+「檔名關鍵字」來挑 blob，
    結果在非 Treble 移植上嚴重不足。tools/30_gap_check_full.sh 實測：
        vendor/etc/init   缺 28/38   （含 init.qcom.rc、init.target.rc、rild.rc）
        vendor/etc        缺 231/444
        vendor/bin        缺 189/238
        vendor/firmware   缺 63/113
    少了 init.qcom.rc，就算 /system 掛起來也不會有任何 qcom HAL 啟動。

    非 Treble 的正確做法是反過來：
        /system/vendor 整個帶走，再扣掉 LineageOS 自己會從原始碼編的，
    而不是一項一項猜哪個需要。

做法：
    1. vendor/ 底下全收
    2. system 側（lib/lib64/bin/framework/app/priv-app/etc）沿用舊清單挑過的
    3. 扣掉 EXCLUDE：AOSP/LineageOS 自己會編、或已知會衝突的
    4. .apk / .jar 加 '-' 前綴走 BUILD_PREBUILT

輸出仍是 $DEVICE_PATH/proprietary-files.txt
"""
import os
import re
import sys

DEVICE_PATH = os.environ.get(
    'DEVICE_PATH',
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

MNT = '/mnt/zs_system'
OLD = os.path.join(DEVICE_PATH, 'proprietary-files.txt')
DST = OLD

# --- 扣掉：AOSP / LineageOS 會自己編出來的 ------------------------------
EXCLUDE_EXACT = {
    # ###################################################################
    # vendor/lib/modules/ —— kernel 建置自己會裝，原廠的留著會「搶目錄」
    #
    # 我們的 kernel 在建置時把自己編的模組裝進 vendor/lib/modules/，
    # 而這 4 個原廠檔也在同一個路徑。誰勝出看**建置順序**，每次可能不同：
    #   20:26 那次（增量）：原廠的蓋掉 kernel 的 —— 然後因為 modversions CRC
    #                       對不上我們的 kernel，init.qcom.rc:264 的
    #                       insmod msm_11ad_proxy.ko 一直失敗，lsmod 是空的
    #   22:22 那次（installclean）：kernel 的勝出，qca_cld3_wlan.ko 整個消失、
    #                       modules.dep 從 147 變 482 bytes
    # 是比對兩個 zip 的 system 映像（總區塊數差 1840）才發現的。
    #
    # 原廠這幾顆本來就不能用（CRC 不合，見 tools/71_ko_crc_check.py），
    # Wi-Fi 也早就編成 built-in（BoardConfig.mk 的 Wifi 段），
    # 所以一律讓 kernel 的版本勝出，結果才固定。
    #
    # ⚠ 我原本預測「msm_11ad_proxy.ko 會第一次真的載入」—— 錯的。實測：
    #     insmod ... failed: Required key not available
    # kernel 是 CONFIG_MODULE_SIG_FORCE=y，而 kernel 自己編的模組也過不了
    # 簽章檢查（大概是安裝時 strip 掉了附在檔尾的簽章）。
    # 所以行為與之前完全相同：**這台一個模組都載不起來**（/proc/modules 是空的）。
    # 對 Wi-Fi 沒影響（built-in），但 texfat.ko（exFAT）等也同樣載不起來。
    # ###################################################################
    'vendor/lib/modules/modules.dep',
    'vendor/lib/modules/msm_11ad_proxy.ko',
    'vendor/lib/modules/qca_cld3_wlan.ko',
    'vendor/lib/modules/wil6210.ko',

    # ###################################################################
    # audio_policy_configuration.xml —— 改由 device tree 提供補過
    # attachedDevices 的版本
    #
    # VoLTE 通話接通後擴音關不掉。Telecom 從開機就
    #     AUDIO_ROUTE (Entering state ActiveSpeakerRoute)
    # —— 它認為這台沒有聽筒。判斷依據是
    #     AudioManager.getDevices(GET_DEVICES_OUTPUTS) 有沒有 TYPE_BUILTIN_EARPIECE
    # 而那來自設定檔的 <attachedDevices>。
    #
    # 我們因為修藍牙而排除了 /vendor/etc/audio/ 那份（split-A2DP），
    # 退到 /vendor/etc/ 這份 —— 但它的 attachedDevices 與 AOSP 通用範本
    # **一字不差**（只有 Speaker + 兩個 mic）。也就是說它根本不是 ASUS 調過的檔案，
    # 而是留在樹裡從來沒被讀到過的樣板（/vendor/etc/audio/ 優先權比較高）。
    # ASUS 真正用的那份有 Earpiece / Telephony Tx / Telephony Rx / FM Tuner。
    #
    # 產生器：tools/104_patch_audio_policy.py（只加 3 行，會驗 XML 合法性）
    # ###################################################################
    'vendor/etc/audio_policy_configuration.xml',

    # ###################################################################
    # init.qcom.rc —— 改由 device tree 提供補過 group 的版本
    #
    # ASUS 這份是 Oreo 時代的，qcom-sh 與 qcom-post-boot 都只有 `user root`，
    # **沒有 group 行**。那兩支腳本要碰的檔案不是 root 的：
    #     /data/vendor/radio/copy_complete   660 radio:radio
    #     .../cpufreq/scaling_min_freq       664 system:system
    #     /sys/power/wake_lock               660 radio:wakelock
    # -> 每次都要 CAP_DAC_OVERRIDE，而 enforcing 下 qti_init_shell 沒有那個權限
    #    （AOSP domain.te:1385 的 dac_override_allowed 不含它，上游 qcom 也沒加）。
    #
    # 實測後果：copy_complete 停在 init 寫的初始值 0，而
    # libril-qc-qmi-1.so 裡有這個字串 —— 那是 QCRIL modem config 模組等的旗標。
    #
    # LineageOS 16.0 的 OnePlus msm8998 樹（同 SoC）兩行都有：
    #     service qcom-sh         group root system radio
    #     service qcom-post-boot  group root system wakelock graphics
    #
    # 產生器：tools/97_patch_qcom_init_rc.py（只加 3 行，diff 會驗）
    # ###################################################################
    'vendor/etc/init/hw/init.qcom.rc',

    # ###################################################################
    # ASUS 的 split-A2DP 音訊政策 —— 藍牙沒聲音的根因（2026-09-24 實測）
    #
    # Android 9 找 audio_policy_configuration.xml 的順序是
    #     /odm/etc  ->  **/vendor/etc/audio**  ->  /vendor/etc  ->  /system/etc
    # 也就是 `/vendor/etc/audio/` 這一層**優先權比 `/vendor/etc/` 高**。
    # ASUS 在那裡放了一份 30 KB 的 split-A2DP 版本，內容是：
    #     primary 模組自己宣告 BT A2DP Out / Headphones / Speaker 並建立 route
    #     a2dp 模組 inline 宣告，而且**只有 a2dp input**
    # 那是 QTI 的 offload 設計：A2DP 音訊走 primary HAL -> SLIMBUS_7_RX -> BT 晶片。
    #
    # 但那條路需要 android.hardware.bluetooth.a2dp@1.0::IBluetoothAudioOffload，
    # 那顆 HAL 在 LineageOS 上不存在（hwservicemanager: Cannot find entry ...），
    # 所以音訊寫進去就沒有下文 —— btsnoop 在播放時 12 秒成長 0 bytes。
    #
    # 症狀極具迷惑性：配對正常、編碼協商正常、mAudioState=PLAYING、
    # 音訊路由顯示 BLUETOOTH_A2DP、輸出執行緒也在寫，就是沒聲音。
    # 而且因為這份的優先權最高，**改 /vendor/etc/audio_policy_configuration.xml
    # 完全沒有效果**，一度讓我誤判成「不是設定檔的問題」。
    #
    # 排除之後會退回 /vendor/etc/audio_policy_configuration.xml（ASUS 自己那份
    # 203 行的非 split 版本），它的 primary 沒有 A2DP，a2dp 模組就能正常提供
    # 輸出，走 AOSP 的軟體 A2DP 路徑。實測有聲音。
    #
    # 這是「原廠設定檔不見得能被 AOSP 堆疊正確解讀」的第三次：
    #     audio_policy_volumes.xml      -> 音量完全調不動
    #     media_profiles_vendor.xml     -> zygote SIGABRT 開不了機
    #     audio/audio_policy_configuration.xml -> 藍牙沒聲音
    # ###################################################################
    'vendor/etc/audio/audio_policy_configuration.xml',
    'vendor/etc/audio/audio_policy_configuration_24bit.xml',
    # ###################################################################

    # ###################################################################
    # 對著 Qualcomm 改過的 framework 編譯的 App —— 在 AOSP/LineageOS 的
    # framework.jar 上會 NoSuchMethodError 無限重啟（2026-09-24 實測）：
    #     java.lang.NoSuchMethodError: No static method getIntWithSubId(
    #       Landroid/content/ContentResolver;Ljava/lang/String;I)I
    #       in class Landroid/telephony/TelephonyManager;
    #     at com.quicinc.cne.CNE.isDataRoamingEnabledonUI(CNE.java:397)
    # 參考樹 oneplus_common / dumpling（lineage-16.0, msm8998）都沒有裝這三支。
    # 相關的 framework jar（cneapiclient / com.quicinc.cne* / qcrilhook /
    # org.simalliance.openmobileapi）刻意保留 —— 是 uses-library，
    # 沒有 App 宣告就不會被載入；原生的 cnd daemon 也保留。
    # 之後要測 RIL 的 OEM 功能，正解是移植 QTI 的 framework 補丁，
    # 不是把這幾支裝回來。
    'priv-app/CNEService/CNEService.apk',
    'priv-app/qcrilmsgtunnel/qcrilmsgtunnel.apk',
    'vendor/app/SmartcardService/SmartcardService.apk',
    # ###################################################################

    # 關鍵字誤判（ASUS_HINTS 的 'fingerprint' 過度匹配）
    'lib/android.hardware.biometrics.fingerprint@2.1.so',
    'lib64/android.hardware.biometrics.fingerprint@2.1.so',
    # 模組名稱與 hardware/lineage/telephony 衝突
    'framework/qti-telephony-common.jar',
    # 路徑與原始碼衝突（m nothing 會警告 overriding commands）
    'lib64/libldacBT_abr.so',
    'lib64/libldacBT_enc.so',
    'vendor/lib/libwifi-hal-qcom.so',
    'vendor/lib64/libwifi-hal-qcom.so',
    'vendor/lib64/libwifi-hal.so',

    # AOSP / LineageOS 會自己編進 vendor 的基本工具。
    # 特別是 toybox_vendor —— 它的模組會自動建立 vendor/bin 底下
    # 148 個指向自己的 symlink（cat / chmod / grep ...），
    # 我們不該再收一份 Oreo 的。
    'vendor/bin/toybox_vendor',
    'vendor/bin/sh',
    'vendor/bin/dd',
    'vendor/bin/getprop',
    'vendor/bin/grep',
    'vendor/bin/egrep',
    'vendor/bin/fgrep',
    'vendor/bin/vndservice',
    'vendor/bin/vndservicemanager',
    'vendor/bin/hostapd_cli',
    'vendor/etc/mkshrc',
    # vendor/qcom/opensource/data-ipa-cfg-mgr 會編
    'vendor/bin/ipacm',
    'vendor/etc/IPACM_cfg.xml',

    # fstab 由 device tree 自己提供（device.mk 的 PRODUCT_COPY_FILES）。
    # ASUS 的 init.target.rc 第 50 行是 mount_all /vendor/etc/fstab.qcom，
    # /data /cache /persist 全看這一份。收原廠的 blob 會蓋掉我們的版本，
    # 導致 /data 仍用 forceencrypt=footer 進入加密流程而卡住開機。
    'vendor/etc/fstab.qcom',

    # 原廠的 /vendor/manifest.xml（Treble 之前的舊路徑）。
    # 我們自己的 manifest 由 BoardConfig 的 DEVICE_MANIFEST_FILE 經 assemble_vintf
    # 裝到 /vendor/etc/vintf/manifest.xml；libvintf 在 Android 9 是先讀那一份，
    # 找不到才 fallback 到 /vendor/manifest.xml，所以原廠這份理論上不會被用到。
    # 但它宣告的 HAL 集合跟我們的不一致（例如仍宣告 android.hardware.gnss，
    # 而我們刻意拿掉以改走 passthrough），留著只會在除錯時誤導，直接排除。
    'vendor/manifest.xml',

    # 原廠的音量曲線表：ASUS 自己擴充了 AOSP 的 deviceCategory 列舉，加了
    # 第 5 種 DEVICE_CATEGORY_HEADSET_nonEU（13 條曲線）。他們的 framework
    # 有對應修改，AOSP 9 的解析器沒有：
    #   E APM::Serializer: Invalid deviceCategory=DEVICE_CATEGORY_HEADSET_nonEU
    #   E APM::VolumeCurve: Invalid device category 1 for Volume Curve （×N）
    # 整組音量曲線註冊失敗 -> STREAM_MUSIC 的 speaker 索引卡在 0 且 Muted:true
    # -> 音量鍵完全調不動。改由 device tree 提供剔除 nonEU 的版本
    # （configs/audio/audio_policy_volumes.xml，PRODUCT_COPY_FILES 裝上去）。
    'vendor/etc/audio_policy_volumes.xml',

    # 原廠的 media profiles：用了 8 個 Qualcomm 擴充、AOSP 9 沒定義的
    # camcorder quality（vga / 2k / 4kdci / qhd 與 timelapse 版本）。
    # MediaProfiles 的解析跑在 zygote 的 preload 階段，遇到不認識的名稱
    # 是 CHECK() 直接 abort：
    #   F MediaProfiles: MediaProfiles.cpp:329 CHECK(quality != -1) failed.
    #   F libc: Fatal signal 6 (SIGABRT) -> init: Service 'zygote' received signal 6
    # 整個系統起不來。改由 device tree 提供剔除過的版本
    # （configs/media/media_profiles_vendor.xml，tools/93 產生）。
    'vendor/etc/media_profiles_vendor.xml',

    # 模組名稱與 AOSP 撞：
    #   base_rules.mk:260: error: vendor/asus/Z01G:
    #     MODULE.TARGET.JAVA_LIBRARIES.com.android.nfc_extras already defined
    #     by frameworks/base/nfc-extras.
    # AOSP Pie 自己有這個模組（只是沒進 PRODUCT_PACKAGES 所以沒被安裝）。
    # 真要補應該是 PRODUCT_PACKAGES += com.android.nfc_extras，不是收 blob。
    # NFC 在 bring-up 期間整組停用，懸空宣告沒有實際影響，先不處理。
    #
    # 注意：光是從 EXTRA_SYSTEM_LIBS 拿掉**沒有用** —— system 側是用
    # load_old() 沿用上一份 proprietary-files.txt，進過清單就會一直被帶下去。
    # 要移除 system 側的東西，一定要放進這個 EXCLUDE_EXACT。
    'framework/com.android.nfc_extras.jar',

    # 指紋 HAL 的 rc 由 device tree 提供（補了 interface 宣告、拿掉 disabled）。
    # 原廠那份在 Pie 上等於死的：disabled 但沒有 interface 宣告，
    # 而且原廠所有 rc 裡再也沒有第二處提到 fps_hal，永遠不會被啟動。
    # 連帶 Home 鍵不會動 —— 這台的 Home 鍵就是指紋辨識器，
    # goodix 驅動要等指紋 daemon 切到按鍵模式才會回報 KEY_HOME。
    'vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc',

    # QTI 的網路定位（Izat）—— 必須拿掉，它會把 system_server 打死。
    #
    # com.qualcomm.location 的 NetworkLocationService 在它自己的 manifest 裡是
    # android:process="system"，也就是**跑在 system_server 行程內**。
    # 它的 static initializer 呼叫 System.loadLibrary 去載
    # /system/lib64/vendor.qti.gnss@1.0.so，而那支需要
    #   android::hardware::gnss::V1_0::toString<IGnssNiCallback::GnssNiNotifyFlags>(uint32_t)
    # —— Oreo 的 android.hardware.gnss@1.0.so 有匯出，Pie 改成 header inline 之後不再匯出。
    # dlopen 失敗丟 UnsatisfiedLinkError，沒人接，system_server 就死：
    #   FATAL EXCEPTION IN SYSTEM PROCESS: main
    #     at IzatProvider.<clinit>(IzatProvider.java:591)
    #     at NetworkLocationService.onCreate(NetworkLocationService.java:42)
    #     at com.android.server.SystemServer.run(SystemServer.java:476)
    # 實測：開機是完成了（sys.boot_completed=1），兩分鐘後才被這個打掉。
    #
    # 不影響 GPS 本身 —— 衛星定位走 framework 的 GnssLocationProvider 直接對
    # android.hardware.gnss@1.0-impl-qti.so（passthrough），跟 Izat 無關。
    # Izat 是 QTI 的網路／融合定位擴充，Android 自己也有一套。
    'priv-app/com.qualcomm.location/com.qualcomm.location.apk',

    # ASUS 原廠相機 —— 抽出來的 apk 裡沒有 classes.dex。
    # 原廠是 odex 過的（dex 在 vendor/app/AsusCamera/oat/ 裡），
    # extract_utils 的 '-' 前綴會試著用 oat2dex 還原，但這支失敗了，
    # 結果 apk 裝進去卻一啟動就：
    #   java.lang.RuntimeException: Unable to instantiate application
    #     com.asus.camera.CameraApplication: ClassNotFoundException
    # 開機後會跳「com.asus.camera keeps stopping」。
    #
    # 不值得修：這支 app 依賴一整套 ASUS 的 framework 擴充（ASUS 的
    # android.jar 擴充、libasuscameraext_* 等），在 Pie 上本來就跑不起來。
    # LineageOS 的 Snap 已經在 PRODUCT_PACKAGES 裡了。
    # （tools/56_check_dex.sh 會檢查還有沒有別的 apk 缺 classes.dex ——
    #   實測只有這一支。）
    'vendor/app/AsusCamera/AsusCamera.apk',
    'etc/permissions/com.qualcomm.location.xml',
    'framework/izat.xt.srv.jar',
    'etc/permissions/izat.xt.srv.xml',

    # -----------------------------------------------------------------
    # 改用 AOSP 9 自己編的 HAL，不收 Oreo blob。
    # 這些都是「Oreo 執行檔 + Pie 函式庫」的 symbol 不相容，
    # 症狀是 init 無限 restart（實測各 325 次）而不是編譯錯誤：
    #
    #   wifi@1.0-service       缺 android::wifi_system::InterfaceTool 的 vtable
    #                          （Pie 的 libwifi-system.so 版面已不同）
    #   media.omx@1.0-service  缺 OmxStore 的無參數建構子（Pie 改成有參數）
    #   keymaster@3.0          impl.so 要 Oreo 版的
    #                          SoftKeymasterContext::ParseKeyBlob，
    #                          但 libsoftkeymasterdevice.so 不能換成 Oreo 的
    #                          —— Pie 的 /system/bin/keystore 也連著它
    #   audio@2.0              原廠 service/impl 的 DT_NEEDED 全是 AOSP 函式庫，
    #                          沒有 QTI 擴充，等於 AOSP 版；真正的硬體實作是
    #                          vendor/lib*/hw/audio.primary.msm8998.so（照收）
    #
    # 拿掉 blob 之後，對應的 AOSP 模組要在 device.mk 的 PRODUCT_PACKAGES 裡
    # 明確列出來，否則會變成「.rc 在、執行檔不在」的另一種錯位。
    'vendor/bin/hw/android.hardware.wifi@1.0-service',
    'vendor/bin/hw/android.hardware.media.omx@1.0-service',
    'vendor/bin/hw/android.hardware.keymaster@3.0-service',
    'vendor/lib/hw/android.hardware.keymaster@3.0-impl.so',
    'vendor/lib64/hw/android.hardware.keymaster@3.0-impl.so',
    'vendor/bin/hw/android.hardware.audio@2.0-service',
    'vendor/lib/hw/android.hardware.audio@2.0-impl.so',
    'vendor/lib64/hw/android.hardware.audio@2.0-impl.so',
    'vendor/lib/hw/android.hardware.audio.effect@2.0-impl.so',
    'vendor/lib64/hw/android.hardware.audio.effect@2.0-impl.so',

    # -----------------------------------------------------------------
    # bring-up 期間先關掉：會 crash loop、且都不是開機必要功能。
    #   qti_gnss    vendor.qti.gnss@1.0_vendor.so 需要 Oreo HIDL 產生的
    #               gnss@1.0 toString<GnssNiNotifyFlags> 模板實體，Pie 沒有
    #   nqnfc       passthrough 找不到 android.hardware.nfc@1.0-impl，
    #               abort：'Error while registering nfc AOSP service: 1'
    #   wfdservice  需要 libskia.so，Pie 不再把它安裝成共享函式庫
    # 這三個的 .rc 也要一起排掉，否則就變成「服務在、執行檔不在」。
    'vendor/bin/hw/vendor.qti.gnss@1.0-service',
    'vendor/etc/init/vendor.qti.gnss@1.0-service.rc',
    'vendor/bin/hw/vendor.nxp.hardware.nfc@1.0-service',
    'vendor/etc/init/vendor.nxp.hardware.nfc@1.0-service.rc',
    'bin/wfdservice',
    'etc/init/wfdservice.rc',
    'vendor/etc/init/com.qualcomm.qti.wifidisplayhal@1.0-service.rc',
}

# 這些 .rc 對應的 HAL service 我們在 device.mk 裡是用 AOSP 版，
# AOSP 的模組自己會帶 .rc，收 blob 版會衝突。
#
# ###########################################################################
# 這個清單「只能」列出真的改用 AOSP 模組的那幾個。
#
# 原本這裡還排掉 gatekeeper / graphics.* / health / light / memtrack / power /
# sensors / thermal / usb / vibrator / vr，理由是「AOSP 會自己編、會自帶 .rc」。
# 但 tools/32_prune_device_mk.py 後來把那些 AOSP 套件從 device.mk 移除了
# （對這種舊機移植，原廠 vendor HAL 才跟硬體對得上），兩邊就對不起來：
# 執行檔是原廠 blob，.rc 卻兩邊都沒有 -> init 根本不會啟動這些 HAL。
#
# 這個錯誤被 out/ 的殘留檔遮了好幾輪 —— 增量編譯不會刪掉上一次產生的 .rc，
# 所以前幾次開機其實是靠「device.mk 還沒 prune 之前留下來的 AOSP .rc」在跑。
# 跑了 make installclean 之後才暴露出來（tools/44、tools/45）。
#
# 現在的規則：blob 給執行檔，就要配 blob 的 .rc；只有下面這四個
# 在 device.mk 裡明確用 PRODUCT_PACKAGES 指定 AOSP 模組，才排掉原廠 .rc。
# configstore 也排掉，因為 AOSP 9 用的是 @1.1，原廠只有 @1.0。
# ###########################################################################
EXCLUDE_PATTERNS = [
    # 只有這幾個改用 AOSP 模組（見 device.mk 的 Audio 與「其他改用 AOSP 版的 HAL」段）
    r'^vendor/etc/init/android\.hardware\.(audio|keymaster|media\.omx|wifi)@',
    r'^vendor/etc/init/android\.hardware\.configstore@',
    # 工廠測試用，一般開機不需要
    r'^vendor/etc/init/hw/init\.qcom\.factory\.rc$',
    # AOSP 自己有
    r'^vendor/etc/init/vndservicemanager\.rc$',
    # odex/vdex 是原廠針對 Oreo 預編的，對 Pie 無效且會佔空間
    r'/oat/',
    r'\.(odex|vdex|art)$',
]

# --- 額外補進來的 system 側函式庫 -------------------------------------
# 來源：tools/36_check_blob_deps.py 的 DT_NEEDED 分析。
# 第一次開到 zygote 之後，所有 vendor HAL 都 exit(1)，logcat 顯示
#   F linker: CANNOT LINK EXECUTABLE "...": library "xxx.so" not found
# 這些是「blob 需要、AOSP 9 不會建、而原廠映像有」的函式庫。
#
# 刻意「不」補的：
#   libskia.so      Pie 有自己的版本，塞 Oreo 的會蓋掉 framework 在用的。
#                   只有 ASUS 工廠測試程式（libmmi / vendor/bin/mmi）需要它，
#                   開機不會啟動，失敗無害。
#   libgcc.so       需要它的是 vendor/lib/rfsa/adsp/* —— 跑在 aDSP 上的
#                   二進位檔，不經過 Android 的 linker。
#
# 關於 android.hidl.base@1.0 / android.hidl.manager@1.0：
#   一開始想用 PRODUCT_PACKAGES 從 AOSP 原始碼建，但建不出來也不報錯。
#   查 system/libhidl/transport/base/1.0/Android.bp：
#       hidl_interface { name: "android.hidl.base@1.0", core_interface: true, ... }
#   core_interface: true 表示 Android 9 已經把它「併進 libhidlbase」，
#   不再產生獨立的 .so —— 這正是 Oreo blob 找不到它的根本原因。
#   所以只能收原廠的（LineageOS 各家舊機 device tree 也是這樣做）。
EXTRA_SYSTEM_LIBS = [
    # HIDL base/manager —— 被 144 個 blob 需要，缺了所有 vendor HAL 都起不來
    'lib/android.hidl.base@1.0.so', 'lib64/android.hidl.base@1.0.so',
    'lib/android.hidl.manager@1.0.so', 'lib64/android.hidl.manager@1.0.so',
    # keymaster / 指紋
    'lib/libkeymaster1.so', 'lib64/libkeymaster1.so', 'lib64/libsoftkeymaster.so',
    # 相機（ASUS PreISP / TrueSight）
    'lib/libpreisp_camera.so', 'lib/libpreisp_shimlayer.so',
    'lib/libjpegHWCompress.so', 'lib/libtrueportrait.so',
    # 顯示
    'lib/libdisplayconfig.so',
    # media.omx service
    'lib/libmediacodecservice.so', 'lib/libavservices_minijail.so',
    # IMS（VoLTE）—— org.codeaurora.ims 這顆 apk 要的 system 側庫。
    # 那顆 apk 本身不從 blob 清單來：它是 odex 的，由
    # tools/101_build_ims_apk.sh 從映像重做（deodex + 改 API 位置 + 重簽）。
    # imscamera_jni / imsmedia_jni 是 com.qualcomm.ims.vt.{ImsCamera,ImsMedia}
    # 的靜態初始化區塊 System.loadLibrary 的對象 —— 只有視訊通話會碰到，
    # 語音通話不需要，但缺了的話一開視訊就 UnsatisfiedLinkError。
    'lib/libimscamera_jni.so', 'lib64/libimscamera_jni.so',
    'lib/libimsmedia_jni.so', 'lib64/libimsmedia_jni.so',
    'lib/lib-imsvt.so', 'lib64/lib-imsvt.so',
    'lib/lib-imsvtutils.so', 'lib64/lib-imsvtutils.so',
    'lib/lib-imsvtextutils.so', 'lib64/lib-imsvtextutils.so',
    'lib/lib-imsvideocodec.so', 'lib64/lib-imsvideocodec.so',
    'lib/com.qualcomm.qti.imscmservice@1.0.so',
    'lib64/com.qualcomm.qti.imscmservice@1.0.so',
    # NFC（NXP）—— 先前誤以為 vendor/nxp/opensource 會建，實測沒有
    'lib64/libnqnfc-nci.so', 'lib64/libp61-jcop-kit.so',
    # 其他
    'lib/libsparse.so', 'lib/libandroid_net.so', 'lib64/libandroid_net.so',
    'lib64/libwfdservice.so',
    'lib/android.hardware.tests.libhwbinder@1.0.so',
    'lib64/android.hardware.tests.libhwbinder@1.0.so',

    # --- system 側的 framework jar 與 permissions xml ---------------------
    # 來源：tools/54_system_side_gap.sh（哪些 system 側檔案沒被收）
    #      與 tools/55_dangling_libs.sh（已安裝的 xml 宣告了不存在的 jar）
    #
    # 這一類是 system 側特有的漏法：vendor/ 是整個收進來的，
    # 但 system 側只沿用早期那份人工挑過的清單，所以「vendor 的 app
    # 依賴 system 的 jar」這種組合會斷掉，而且編譯期完全不會發現。
    #
    # SmartcardService.apk 在 vendor/app 所以被收了，但它 uses-library 的
    # org.simalliance.openmobileapi 整組都在 /system：
    #   java.lang.NoClassDefFoundError:
    #     Lorg/simalliance/openmobileapi/service/ISmartcardService$Stub;
    #   -> 開機後跳「SmartcardService keeps stopping」對話框
    'framework/org.simalliance.openmobileapi.jar',
    'etc/permissions/org.simalliance.openmobileapi.xml',
    # 這兩個的 permissions xml 已經裝了，但 jar 沒收 -> 懸空宣告，
    # 任何 <uses-library> 它們的 app 一啟動就 ClassNotFoundException
    'framework/com.qualcomm.qti.imscmservice@1.0-java.jar',
    # Qualcomm 的 AT（Adaptive Thermal / App Tuning）函式庫。
    # system.prop 的 ro.vendor.at_library=libqti-at.so 指向它，
    # 而它在 system 側（/system/lib{,64}）不在 vendor/，所以整包掃 vendor/
    # 的邏輯抓不到 —— 又是同一類死角。
    # ※ 原廠同時設了 ro.vendor.gt_library=libqti-gt.so，但那支**原廠映像裡
    #   根本不存在**（只有 libqti-gt-prop.so），所以我們不跟進那條屬性。
    'lib/libqti-at.so', 'lib64/libqti-at.so',
    # 觸控的輸入裝置設定與字元對應表。
    # 這兩種檔案沒有 keycode 標籤，可以直接用原廠的
    # （.kl 就不行 —— 見 device.mk 的 keylayout 段與 tools/58_gen_keylayout.py）。
    'usr/idc/focal-touchscreen.idc',
    'usr/keychars/focal-touchscreen.kcm',
    # com.android.nfc_extras.jar 刻意不收 —— 模組名稱與 AOSP 撞：
    #   base_rules.mk:260: error: vendor/asus/Z01G:
    #     MODULE.TARGET.JAVA_LIBRARIES.com.android.nfc_extras already defined
    #     by frameworks/base/nfc-extras.
    # AOSP Pie 自己有這個模組（只是沒進 PRODUCT_PACKAGES 所以沒被安裝）。
    # 要補的話應該是 PRODUCT_PACKAGES += com.android.nfc_extras，不是收 blob。
    # 但 NFC 整組在 bring-up 期間是停用的，懸空宣告沒有實際影響，先不處理。
]

# system 側要沿用舊清單的前綴（vendor/ 以外）
SYSTEM_PREFIXES = ('lib/', 'lib64/', 'bin/', 'framework/', 'app/', 'priv-app/',
                   'etc/permissions/', 'etc/init/', 'etc/firmware/', 'etc/')


# ######################################################################
# system 側的「直接掃映像」清單
#
# ############ 為什麼要有這一段（2026-09-23 的教訓）##################
# 在這之前，main() 對 vendor/ 是**完整掃描映像**，對 system 側卻只沿用
# load_old() 讀到的舊條目 + EXTRA_SYSTEM_LIBS 手動補的。
# 結果是：任何沒被人工加過的 ASUS system 側檔案，永遠不會進清單，
# 而且編譯期完全不會發現。一次踩到三個：
#
#   etc/firmware/adsp.*          ADSP 根本載不起來
#     ueventd 找韌體的順序是 /etc/firmware → /odm/firmware →
#     /vendor/firmware → /firmware/image。ASUS 那份不在，就退到 modem
#     分割那份**測試金鑰簽章、OEM_ID=0000** 的通用映像，而本機
#     androidboot.fused=1、OEM 熔絲是 0x0029 / MODEL 0x0022，
#     TZ 的 PAS_INIT_IMAGE 直接回 -60 拒絕。
#     連帶：沒有音效卡（q6afe/q6asm 靠 ADSP）、相機 SOF Freeze。
#
#   etc/mixer_paths_ZS551KL.xml  audio HAL 的 platform_init 直接中止
#     -> AudioPolicy 開不了 primary output -> 完全沒有音訊輸出
#
#   etc/preisp_profiles.xml      相機 Rockchip pre-ISP 取不到解析度設定
#
# 這三個都不是「參考機也有的檔案」，所以交集法抓不到；也不含 asus
# 字樣，所以關鍵字法抓不到；又不是 .so，所以 DT_NEEDED 分析抓不到。
#
# 判準：**會被驅動 request_firmware()、或被 blob 以絕對路徑開啟的資料檔**
# 一律要收。AOSP 自己會建的（etc/init/*.rc、cacerts、fonts.xml、
# ld.config.txt …）一律不收，收了就是模組/路徑衝突。
# ######################################################################

# 整個目錄收下來
SYSTEM_SCAN_DIRS = [
    'etc/firmware',   # ADSP 映像、TAS2557 功放韌體、面板色溫 LUT（phone_ct）、true2life
    'etc/dts',        # DTS Eagle 音效後處理設定與授權金鑰
    'etc/hostapd',    # Wi-Fi AP
    'etc/cne',        # Qualcomm Connectivity Engine
    'etc/dpm',        # Qualcomm Data Port Mapper
    'etc/perf',       # Qualcomm perf HAL 白名單
    'etc/scve',       # Qualcomm SCVE 人臉模型（相機的 libscve*_skel 會用）
]

# etc/ 頂層：只挑硬體相關的，其餘（ASUS 工廠測試與 log 腳本、
# nand_sd_mmc_* 測試圖樣、AOSP 自己的 fonts.xml/ld.config.txt…）不收
SYSTEM_SCAN_FILES = [
    # --- 音效：這台專屬的 mixer 路徑 --------------------------------
    # audio.primary.msm8998.so 裡寫死的搜尋順序（strings 可見）：
    #   /asusfw/audio/mixer_paths_ZS551KL{,_EU,_leak}.xml   優先
    #   /system/etc/mixer_paths_ZS551KL{,_leak}.xml         備援
    # 缺了會 platform_init: Failed to init audio route controls, aborting.
    'etc/mixer_paths_ZS551KL.xml',
    'etc/mixer_paths_ZS551KL_EU.xml',
    'etc/mixer_paths_ZS551KL_leak.xml',
    # --- 音效：TI TAS2557 智慧功放的校正與相關腳本 ------------------
    'etc/speaker_l.ftcfg',
    'etc/speaker_r.ftcfg',
    'etc/silence.wav',                      # 功放校正用的靜音訊號源
    'etc/init.asus.asus_amp_cal.sh',
    'etc/init.asus.asus_nonmp_amp_cal.sh',
    'etc/spkampcal.sh', 'etc/rcvampcal.sh',
    'etc/readSPKCal.sh', 'etc/readRCVCal.sh',
    'etc/audio_codec_status.sh', 'etc/headset_status.sh',
    'etc/select_mic.sh', 'etc/select_output.sh',
    'etc/init.asus.dts.sh',                 # 搭配 etc/dts/
    # --- 3.5mm 耳機孔：把它從 UART 除錯序列埠切回音訊 ----------------
    #
    # ⚠ 名字看起來像 debug 腳本，第一輪分類時被我歸到「工廠測試與 log
    #   腳本 -> 跳過」，結果就是插耳機完全沒反應。audbg = audio debug。
    #
    # ASUS 把 3.5mm 孔設計成兩用：預設是 UART 除錯序列埠，音訊關閉。
    # kernel 端 sound/soc/codecs/wcd9335.c:164 是 `int g_DebugMode = 1;`
    # —— 編譯預設就是 debug 模式。而 wcd-mbhc-v2.c 的插拔中斷處理有
    # ASUS 加的一行：
    #       if (g_DebugMode)
    #               goto exit;
    # 於是機械插拔中斷照常觸發、detection_type 也正確，但完全不做
    # 插頭類型偵測就離開（實測 log 就是 enter -> cancel -> leave）。
    #
    # 切換方式：寫 0 到 /proc/driver/audio_debug
    #   0 -> gpio_direction_output(AUDIO_DEBUG_GPIO, 1)  關 uart、開音訊
    #   1 -> gpio_direction_output(AUDIO_DEBUG_GPIO, 0)  開 uart、關音訊
    # 讀這個節點在非 debug 模式下回傳的是插頭類型（1=HEADSET、2=HEADPHONE…）。
    #
    # checkaudbg.sh 等 /proc/driver/audio_codec_status 就緒（最多 120 秒）
    # 後依 ro.boot.pre-ftm 決定 persist.asus.audbg 的預設值（非工廠模式 = 0），
    # audbg.sh 再把該值寫進 proc 節點。啟動由 rootdir/etc/init.z01g.rc 接上。
    #
    # 保留這條路徑而不是在 init 裡直接 write 0，是因為它同時是
    # 「把耳機孔變回序列埠主控台」的逃生門：setprop persist.asus.audbg 1。
    'etc/init.asus.audbg.sh',
    'etc/init.asus.checkaudbg.sh',
    # --- 相機 -------------------------------------------------------
    'etc/preisp_profiles.xml',              # Rockchip pre-ISP 解析度設定
    # --- 感測器 -----------------------------------------------------
    'etc/sensors_init.sh',
    'etc/rgb_sensor_init.sh',
    'etc/init.asus.slpi_ssr.sh',
    # --- NFC（NXP）存取控制，bring-up 期間雖停用但先收齊 ------------
    'etc/nqnfcee_access.xml',
    'etc/nqnfcse_access.xml',
]

# 需要「換個名字再裝一份」的檔案：src:dst（extract_utils.sh 的語法）
#
# ACDB 音效校正的目錄名是 libacdbloader.so 用 ro.build.product 組出來的
# （strings 可見 "%s/%s"、"%s/%s_MP"、"ro.build.product"、"ro.boot.id.stage"）。
# 原廠 ro.build.product=ZS551KL，我們是 Z01G（＝TARGET_DEVICE），
# 而 ro.* 屬性先設先贏、用 PRODUCT_PROPERTY_OVERRIDES 蓋不掉，
# 所以改成把同一份資料再以 Z01G 的名字裝一份。
# 不這樣做的話 loader 找不到就退回 /vendor/etc/acdbdata/MTP/ —— 那是
# 高通參考板的校正表，症狀是「音質像通話」而且音量曲線不對。
# 本機 ro.boot.id.stage=7 會選到 _MP 那組，兩組都放以防萬一。
_ACDB_TYPES = ['Bluetooth_cal.acdb', 'General_cal.acdb', 'Global_cal.acdb',
               'Handset_cal.acdb', 'Hdmi_cal.acdb', 'Headset_cal.acdb',
               'Speaker_cal.acdb', 'workspaceFile.qwsp']
EXTRA_RENAMED = [
    (f'vendor/etc/acdbdata/ZS551KL{sfx}/ZS551KL_{t}',
     f'vendor/etc/acdbdata/Z01G{sfx}/Z01G_{t}')
    for sfx in ('', '_MP') for t in _ACDB_TYPES
]


def excluded(rel):
    if rel in EXCLUDE_EXACT:
        return True
    return any(re.search(p, rel) for p in EXCLUDE_PATTERNS)


def load_old():
    """讀上一份 proprietary-files.txt，用來沿用 system 側挑過的條目。

    ⚠ 這讓 system 側的條目是「黏著」的：一旦某個檔案進過清單，
    之後就算把它從 EXTRA_SYSTEM_LIBS 拿掉也還是會被帶下去。
    要真的移除，必須放進 EXCLUDE_EXACT（excluded() 是在合併之後才套用）。
    實例：framework/com.android.nfc_extras.jar 從 EXTRA_SYSTEM_LIBS 移除後
    仍然留在清單裡，害編譯一直炸模組名稱衝突。
    """
    out = set()
    with open(OLD, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith('#'):
                out.add(line.lstrip('-').split('|', 1)[0].split(':', 1)[0].strip())
    return out


def main():
    if not os.path.ismount(MNT):
        sys.exit(f'!!! {MNT} 沒掛載，先跑 tools/07_mount_system.sh')

    old = load_old()

    # 1. vendor/ 全收（但排除 symlink）
    #
    # 注意 os.walk 的行為：「指向檔案的 symlink」會被放進 files 清單，
    # 不像 find -type f 會排除它們。第一版沒濾掉，結果清單多了 199 條
    # symlink（148 個是 vendor/bin/* -> toybox_vendor），
    # extract-files.sh 抽不到它們但只印訊息不會失敗，
    # 一直到編譯才炸：
    #   ninja: error: '...proprietary/vendor/etc/firmware/wcd9320/wcd9320_anc.bin',
    #          needed by ..., missing and no known rule to make it
    #
    # 這些 symlink 本來就不該當 blob：toybox_vendor 的模組會自己建，
    # vendor/rfs/* 則是 init 在執行期建的。
    vendor, skipped_links = [], 0
    for dirpath, _d, files in os.walk(os.path.join(MNT, 'vendor')):
        for fn in files:
            full = os.path.join(dirpath, fn)
            if os.path.islink(full):
                skipped_links += 1
                continue
            vendor.append(os.path.relpath(full, MNT))

    # 2. system 側沿用舊清單挑過的，再加上 DT_NEEDED 分析補出來的
    system_side = [p for p in old if not p.startswith('vendor/')
                   and p.startswith(SYSTEM_PREFIXES)]
    n_extra = 0
    for e in EXTRA_SYSTEM_LIBS:
        if os.path.exists(os.path.join(MNT, e)):
            if e not in system_side:
                system_side.append(e)
                n_extra += 1
        else:
            print(f'  !!! 原廠映像裡找不到 {e}')
    print(f'DT_NEEDED 補入      {n_extra} 條')

    # 2b. system 側：直接掃映像（見 SYSTEM_SCAN_DIRS 上方的長註解）
    #
    # 這一段才是 system 側唯一「不依賴人工記得加」的來源。
    # 沿用舊清單 + EXTRA_SYSTEM_LIBS 是黏著且被動的，掃描是主動的。
    n_scan_dir = 0
    for d in SYSTEM_SCAN_DIRS:
        root = os.path.join(MNT, d)
        if not os.path.isdir(root):
            print(f'  !!! 原廠映像裡找不到目錄 {d}')
            continue
        for dirpath, _d, files in os.walk(root):
            for fn in files:
                full = os.path.join(dirpath, fn)
                if os.path.islink(full):
                    continue
                rel = os.path.relpath(full, MNT)
                if rel not in system_side:
                    system_side.append(rel)
                    n_scan_dir += 1
    n_scan_file = 0
    for f in SYSTEM_SCAN_FILES:
        if not os.path.isfile(os.path.join(MNT, f)):
            print(f'  !!! 原廠映像裡找不到 {f}')
            continue
        if f not in system_side:
            system_side.append(f)
            n_scan_file += 1
    print(f'system 掃描補入    {n_scan_dir} 條（目錄）+ {n_scan_file} 條（頂層挑選）')

    allfiles = sorted(set(vendor) | set(system_side))
    kept = [p for p in allfiles if not excluded(p)]
    dropped = [p for p in allfiles if excluded(p)]

    # 分段
    def sect(p):
        if p.startswith('vendor/etc/init'):
            return '1. vendor init rc（沒有這些 HAL 不會啟動）'
        if p.startswith('vendor/firmware') or p.startswith('etc/firmware'):
            return '2. 韌體'
        if p.startswith('vendor/etc'):
            return '3. vendor 設定檔'
        if p.startswith('vendor/bin'):
            return '4. vendor 執行檔'
        if p.startswith('vendor/lib64'):
            return '5. vendor lib64'
        if p.startswith('vendor/lib'):
            return '6. vendor lib'
        if p.startswith('vendor/'):
            return '7. vendor 其他'
        return '8. system 側'

    buckets = {}
    for p in kept:
        buckets.setdefault(sect(p), []).append(p)

    n_pkg = 0
    with open(DST, 'w', encoding='utf-8') as fh:
        fh.write('# Proprietary files for ASUS ZenFone 4 Pro (ZS551KL / Z01G)\n#\n')
        fh.write('# 來源：原廠 15.0410.1911.117 的 /system 分割 dd 映像\n')
        fh.write('# 產生：tools/31_build_blob_list.py\n#\n')
        fh.write('# 非 Treble 移植：/system/vendor 全收，再扣掉 LineageOS 自己會編的。\n')
        fh.write('# 第一版用「參考機交集 + 關鍵字」挑，漏掉 init.qcom.rc 等關鍵檔案\n')
        fh.write('# （vendor/etc/init 缺 28/38、vendor/bin 缺 189/238），已改為此法。\n')
        fh.write('# system 側原本只沿用舊清單，漏掉 etc/firmware/adsp.*（ADSP 載不起來）\n')
        fh.write('# 等關鍵檔案，已改為掃描 SYSTEM_SCAN_DIRS / SYSTEM_SCAN_FILES。\n#\n')
        fh.write(f'# 共 {len(kept)} 條（vendor/ {len(vendor)} 條全收，'
                 f'扣除 {len(dropped)} 條）+ {len(EXTRA_RENAMED)} 條改名安裝\n\n')
        for name in sorted(buckets):
            items = buckets[name]
            fh.write(f'# --- {name} ({len(items)}) ---\n')
            for p in sorted(items):
                if p.endswith(('.apk', '.jar')):
                    fh.write(f'-{p}\n')
                    n_pkg += 1
                else:
                    fh.write(f'{p}\n')
            fh.write('\n')

        # 改名安裝（src:dst）—— 見 EXTRA_RENAMED 的註解
        fh.write(f'# --- 9. 同一份檔案再以 Z01G 的名字裝一份 '
                 f'({len(EXTRA_RENAMED)}) ---\n')
        fh.write('#     ACDB loader 用 ro.build.product 當目錄名，原廠是 ZS551KL，\n')
        fh.write('#     我們是 Z01G；ro.* 蓋不掉，所以改名再裝一份。\n')
        for src, dst in EXTRA_RENAMED:
            if not os.path.isfile(os.path.join(MNT, src)):
                print(f'  !!! 改名來源不存在 {src}')
                continue
            fh.write(f'{src}:{dst}\n')
        fh.write('\n')

    print(f'vendor/ 全部       {len(vendor)} 條（另排除 {skipped_links} 個 symlink）')
    print(f'system 側沿用      {len(system_side)} 條')
    print(f'扣除               {len(dropped)} 條')
    for p in dropped[:25]:
        print(f'    - {p}')
    if len(dropped) > 25:
        print(f'    ... 另外 {len(dropped)-25} 條')
    print(f'最終               {len(kept)} 條（{n_pkg} 條 .apk/.jar 走 BUILD_PREBUILT）')
    print()
    for name in sorted(buckets):
        print(f'  {name:<42} {len(buckets[name]):>5}')
    print()
    print(f'輸出：{DST}')


if __name__ == '__main__':
    main()
