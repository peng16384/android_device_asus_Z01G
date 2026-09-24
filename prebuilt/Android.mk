#
# IMS（VoLTE）的 org.codeaurora.ims
#
# 這顆 apk 不是從 blob 清單來的。原廠 /system/app/ims/ims.apk 是 odex 的
# （apk 內沒有 classes.dex），而且是對 Oreo 的 IMS API 編的，
# Pie 把那套整組搬到了 android.telephony.ims.compat.*。
# 由 tools/101_build_ims_apk.sh 從原廠映像重做，詳見那支腳本的檔頭。
#
# 為什麼是 BUILD_PREBUILT 而不是 PRODUCT_COPY_FILES：
#     build/make/core/Makefile:28
#     error: Prebuilt apk found in PRODUCT_COPY_FILES ... use BUILD_PREBUILT instead!
# AOSP 明文擋掉 apk 走 PRODUCT_COPY_FILES（那條路不會處理簽章與 dexpreopt）。
#
# LOCAL_CERTIFICATE := PRESIGNED
#     tools/101 已經用 platform key 簽過了（sharedUserId=android.uid.phone，
#     簽名要跟 com.android.phone 相符才裝得起來）。這裡不要再簽一次。
#
# LOCAL_DEX_PREOPT := false
#     這顆的 dex 是我們改過再組回去的，讓它在裝置上第一次跑時自己編就好，
#     免得 build 期的 dex2oat 對一個「非本樹編出來」的 dex 出狀況。
#
LOCAL_PATH := $(call my-dir)

ifneq ($(wildcard $(LOCAL_PATH)/ims/ims.apk),)

include $(CLEAR_VARS)
LOCAL_MODULE := ims
LOCAL_MODULE_OWNER := qcom
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := ims/ims.apk
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_DEX_PREOPT := false
include $(BUILD_PREBUILT)

else
$(warning ####################################################################)
$(warning # 找不到 device/asus/Z01G/prebuilt/ims/ims.apk                      )
$(warning # 先跑：sudo bash tools/07_mount_system.sh                          )
$(warning #       bash tools/101_build_ims_apk.sh                             )
$(warning # 不跑的話編出來的 ROM 沒有 ImsService，撥號會停在「撥號中」然後掛斷 )
$(warning ####################################################################)
endif
