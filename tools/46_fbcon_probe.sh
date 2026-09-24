#!/bin/bash
K=$HOME/zs551kl/kernel/msm-4.4
echo "=== mdss_fb 有沒有 deferred_io（command mode 面板要靠它才會把 fbcon 的內容推上去）==="
grep -n 'deferred_io\|fb_deferred' "$K/drivers/video/fbdev/msm/mdss_fb.c" | head
echo
echo "=== mdss_fb 的 fb_ops ==="
sed -n '/static struct fb_ops mdss_fb_ops/,/};/p' "$K/drivers/video/fbdev/msm/mdss_fb.c"
echo
echo "=== CONFIG_FB_DEFERRED_IO 在 defconfig? ==="
grep -n 'DEFERRED_IO' "$K/arch/arm64/configs/zs551kl-perf_defconfig" || echo "  沒有"
