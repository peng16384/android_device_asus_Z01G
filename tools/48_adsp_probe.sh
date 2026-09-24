#!/bin/bash
K=$HOME/zs551kl/kernel/msm-4.4
echo "=== scm.c 700-770（看 ret 是不是 remap 過的）==="
sed -n '690,770p' "$K/drivers/soc/qcom/scm.c"
