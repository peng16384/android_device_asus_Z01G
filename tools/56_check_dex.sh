#!/usr/bin/env bash
# 檢查安裝進去的 apk / jar 有沒有 classes.dex。
#
# 起因：AsusCamera.apk 在原廠是 odex 過的，extract_utils 的 '-' 前綴會走
# BUILD_PREBUILT 並試著用 oat2dex 從 oat/ 還原 dex，但這支失敗了。
# 失敗時它只印一行訊息，apk 照樣裝進 image，一啟動才炸：
#   java.lang.RuntimeException: Unable to instantiate application
#     com.asus.camera.CameraApplication: ClassNotFoundException
#
# 「沒有 classes.dex」本身不一定是錯 —— 純資源的 apk 本來就沒有：
#   RRO overlay（/vendor/overlay、主題與強調色）、framework-res.apk、
#   org.lineageos.platform-res.apk、CtsShim*。這些會被排除，
#   只列出「有程式碼卻抽不到 dex」的。
#
# 改完 blob 清單裡的 apk/jar 就跑一次這支。
O=${1:-$HOME/lineage-16.0/out/target/product/Z01G/system}
n=0
while IFS= read -r f; do
    case "$f" in
        */oat/*) continue;;                 # odex/vdex 本體
        */overlay/*) continue;;             # RRO 純資源
        *-res.apk) continue;;               # framework-res / platform-res
        */Lineage*Accent/*|*/Lineage*Theme/*) continue;;   # 主題 RRO
        */CtsShim*) continue;;              # 空殼
    esac
    unzip -l "$f" 2>/dev/null | grep -q 'classes.*\.dex' && continue
    echo "  [無 classes.dex] ${f#$O}"
    n=$((n+1))
done < <(find "$O" -name '*.apk' -o -name '*.jar' 2>/dev/null)
echo "共 $n 個有問題"
