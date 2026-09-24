# config.fs for ASUS ZenFone 4 Pro (ZS551KL / Z01G)
#
# 以 LineageOS xiaomi/msm8998-common 的 config.fs 為底，
# 只保留 proprietary-files.txt 真的有收的執行檔。
# 產生：tools/21_gen_config_fs.py
#
# 注意：本機是非 Treble，vendor 實際落在 /system/vendor，
# 但 config.fs 的路徑仍寫 vendor/...（TARGET_COPY_OUT_VENDOR 會處理）。

[AID_VENDOR_QTI_DIAG]
value:2901

[vendor/bin/pm-service]
mode: 0755
user: AID_SYSTEM
group: AID_SYSTEM
caps: NET_BIND_SERVICE

[vendor/bin/pd-mapper]
mode: 0755
user: AID_SYSTEM
group: AID_SYSTEM
caps: NET_BIND_SERVICE

[vendor/bin/imsdatadaemon]
mode: 0755
user: AID_SYSTEM
group: AID_SYSTEM
caps: NET_BIND_SERVICE

[vendor/bin/ims_rtp_daemon]
mode: 0755
user: AID_SYSTEM
group: AID_RADIO
caps: NET_BIND_SERVICE

[vendor/bin/imsrcsd]
mode: 0755
user: AID_SYSTEM
group: AID_RADIO
caps: NET_BIND_SERVICE BLOCK_SUSPEND WAKE_ALARM

[vendor/bin/cnd]
mode: 0755
user: AID_SYSTEM
group: AID_SYSTEM
caps: NET_BIND_SERVICE BLOCK_SUSPEND NET_ADMIN

[vendor/bin/loc_launcher]
mode: 0755
user:  AID_GPS
group: AID_GPS
caps: SETUID SETGID

