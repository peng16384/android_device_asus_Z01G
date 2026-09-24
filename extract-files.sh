#!/bin/bash
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
# 用法：
#   ./extract-files.sh <dump 目錄>     從離線 dump 抽（本專案的作法）
#   ./extract-files.sh                 從 adb 抽（需要 root）
#
# 本專案有 system 分割的完整 dd 映像，不必用 adb。
# 先用 device/asus/Z01G/extract-from-image.sh 把映像掛起來並呼叫本腳本。

set -e

DEVICE=Z01G
VENDOR=asus

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$MY_DIR" ]]; then MY_DIR="$PWD"; fi

ANDROID_ROOT="$MY_DIR"/../../..

HELPER="$ANDROID_ROOT"/vendor/lineage/build/tools/extract_utils.sh
if [ ! -f "$HELPER" ]; then
    echo "找不到 extract_utils.sh：$HELPER"
    echo "（需要先 repo sync 好 LineageOS 的 vendor/lineage）"
    exit 1
fi
. "$HELPER"

function blob_fixup() {
    case "${1}" in
    # TODO: 實際編出來、跑起來之後才會知道有哪些需要 patch。
    # 常見的是 Android 9 移除的 symbol，需要用 patchelf 加回 shim。
    esac
}

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

while [ "$1" != "" ]; do
    case $1 in
        -n | --no-cleanup )     CLEAN_VENDOR=false
                                ;;
        -s | --section )        shift
                                SECTION="$1"
                                CLEAN_VENDOR=false
                                ;;
        * )                     SRC="$1"
                                ;;
    esac
    shift
done

if [ -z "$SRC" ]; then
    SRC="adb"
fi

setup_vendor "$DEVICE" "$VENDOR" "$ANDROID_ROOT" false "$CLEAN_VENDOR"
extract "$MY_DIR"/proprietary-files.txt "$SRC" "$SECTION"

"$MY_DIR"/setup-makefiles.sh
