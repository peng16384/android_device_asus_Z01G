#!/usr/bin/env bash
# 查一個 SELinux 型別是 public / private / vendor 的哪一邊。
#
# 為什麼需要：Treble 把政策切三塊分別編譯，vendor 的 .te 看不到 private 的
# 型別、private 的看不到 vendor 的。規則放錯邊 → `ERROR 'unknown type xxx'`。
# 而錯誤訊息只會報第一個，一次只能修一條，很耗時。
#
# ⚠ 不要用「有沒有出現在 plat_pub_policy.cil」來判斷 —— 那只能分出
#   public 與「其他」，會把 vendor 型別誤判成 private（實測踩過）。
#   唯一可靠的是看宣告寫在哪個目錄。
#
# 用法：bash tools/96_sepolicy_side.sh <型別名> [型別名...]
# 建置身分與 WSL distro：需要時用環境變數覆蓋
#   BUILD_USER=alice WSL_DISTRO=ubuntu2004 bash tools/xxx.sh
BUILD_USER="${BUILD_USER:-${SUDO_USER:-$(id -un)}}"
WSL_DISTRO="${WSL_DISTRO:-ubuntu2004}"

set -u
[ $# -ge 1 ] || { echo "用法: $0 <型別名> [型別名...]"; exit 1; }
cat > /tmp/_ss.sh <<INNER
R=$HOME/lineage-16.0
for t in $*; do
  # 排除被註解掉的宣告（qcom 的 file.te 裡有好幾個 #type ...）
  hit=\$(grep -rn "^[[:space:]]*type[[:space:]]\+\$t[,;]" \$R/system/sepolicy \$R/device/qcom/sepolicy \$R/device/lineage/sepolicy \$R/device/asus/Z01G/sepolicy --include='*.te' 2>/dev/null \
         | grep -av 'sepolicy-legacy' | grep -av '/prebuilts/' | head -1)
  if [ -z "\$hit" ]; then printf '  %-26s \033[31m找不到宣告\033[0m\n' "\$t"; continue; fi
  f=\${hit%%:*}; f=\${f#\$R/}
  case "\$f" in
    */public/*)  side='public  （兩邊都看得到）';;
    */private/*) side='private （只有 sepolicy/private/ 能用）';;
    device/asus/Z01G/sepolicy/vendor/*)  side='vendor  （我們自己的）';;
    device/asus/Z01G/sepolicy/private/*) side='private （我們自己的）';;
    */vendor/*)  side='vendor  （只有 sepolicy/vendor/ 能用）';;
    *)           side='?';;
  esac
  printf '  %-26s %-36s %s\n' "\$t" "\$side" "\$f"
done
INNER
MSYS_NO_PATHCONV=1 wsl -d "$WSL_DISTRO" -u "$BUILD_USER" -- bash /tmp/_ss.sh
