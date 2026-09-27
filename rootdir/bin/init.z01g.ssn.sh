#!/vendor/bin/sh
# ZS551KL：裝置序號（SSN）寫進 USB 描述元與 ro.serialno（init.qcom.usb.rc 的 on boot 用 exec 呼叫）
#
# ASUS 的 bootloader 不傳 androidboot.serialno -> ro.serialno 是空的 -> USB 沒有 iSerialNumber ->
# Windows 的 adb 取不到序號就略過這台。序號在 factory 分割的 /factory/SSN（原廠
# vendor/bin/init.asus.usb_ssn.sh 也讀這個）。
# 不用 init 的 copy：/factory 的檔案是 0666，init 會以 "Skipping insecure file" 拒讀（2026-09-25 實測），
# 而 /factory 依安全規則唯讀掛載、不能改權限。
#
# 只負責讀檔、交給 init：寫 configfs 與設 ro.serialno 由 init.qcom.usb.rc 做（SELinux：serialno_prop 只有
# init 能寫，這支跑在 qti_init_shell）。exec 是同步的，回到 init 時 vendor.asus.ssn 已經設好
ssn=$(cat /factory/SSN 2>/dev/null)
[ -n "$ssn" ] || exit 0
setprop vendor.asus.ssn "$ssn"
