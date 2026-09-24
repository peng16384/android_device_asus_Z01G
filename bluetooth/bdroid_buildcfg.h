/*
 * Copyright (C) 2012 The Android Open Source Project
 * Copyright (C) 2026 The LineageOS Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/*
 * ASUS ZenFone 4 Pro (ZS551KL / Z01G)
 *
 * BoardConfig.mk 的 BOARD_BLUETOOTH_BDROID_BUILDCFG_INCLUDE_DIR 指向這個目錄。
 * 少了這個檔，system/bt 會在編到 avrcp-target-service 時
 *   fatal error: 'bdroid_buildcfg.h' file not found
 *
 * 內容以 LineageOS xiaomi/msm8998-common 為底，改成本機參數：
 *   原廠 build.prop: qcom.bluetooth.soc=cherokee（WCN3990）
 *                    persist.vendor.bt.a2dp_offload_cap=sbc-aptx-aptxhd-aac
 */

#ifndef _BDROID_BUILDCFG_H
#define _BDROID_BUILDCFG_H

#define BTM_DEF_LOCAL_NAME "ASUS ZenFone 4 Pro"

/* 高通自家的藍牙軟體堆疊（cherokee / WCN3990） */
#define BLUETOOTH_QTI_SW TRUE

#define MAX_ACL_CONNECTIONS 16
#define MAX_L2CAP_CHANNELS  16

#define BLE_VND_INCLUDED TRUE

/* 連線建立後跳過 connection update，避免部分裝置配對時斷線 */
#define BT_CLEAN_TURN_ON_DISABLED 1

#endif
