#
# Copyright (C) 2026 The LineageOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# 把 fstab.qcom 安裝進 ramdisk 根目錄。
#
# 沒有這個檔的後果（我們踩過）：
#   Android 9 的 first-stage init 靠 /fstab.${ro.hardware}（= /fstab.qcom）
#   掛載 /system。ramdisk 裡沒有它 -> /system 永遠掛不起來 -> init 在極早期
#   就停住，連 USB gadget 都還沒設定，所以手機在 PC 上完全不會列舉。
#   症狀是「logo -> 黑屏 -> adb/fastboot 都看不到」，非常難從外部判斷。
#
#   device.mk 只寫 PRODUCT_PACKAGES += fstab.qcom 是不夠的 ——
#   那只是「要求安裝一個叫 fstab.qcom 的模組」，模組本身要在這裡定義，
#   而且 build 不會因為模組不存在而報錯。

LOCAL_PATH := $(call my-dir)

# /vendor/rfs 的目錄與 symlink（由 tools/52_gen_rfs_mk.py 產生）
include $(LOCAL_PATH)/rfs.mk

include $(CLEAR_VARS)
LOCAL_MODULE       := fstab.qcom
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := etc/fstab.qcom
# TARGET_ROOT_OUT = ramdisk 根目錄。非 Treble + A-only 的 Android 9
# first-stage init 只會在這裡找 fstab。
LOCAL_MODULE_PATH  := $(TARGET_ROOT_OUT)
# 順便把 /vendor/rfs 建出來。
# PRODUCT_COPY_FILES 沒辦法做 symlink，blob 清單也抽不到（產生器會跳過 symlink、
# 空目錄根本不在檔案清單裡），所以只能掛在某個模組的 post-install 指令上。
LOCAL_POST_INSTALL_CMD := $(z01g-make-rfs)
include $(BUILD_PREBUILT)
