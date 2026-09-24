# 由 tools/52_gen_rfs_mk.py 從原廠映像產生，不要手改。
#
# /vendor/rfs 是純目錄 + symlink 的樹（24 個目錄、45 條 symlink，沒有一般檔案），
# blob 清單抽不到它 —— 產生器會跳過 symlink，空目錄也不會出現在檔案清單裡。
# 缺了之後 tftp_server 會一直刷：
#   tftp-server : mkdir failed: [/vendor/rfs/msm/mpss/readwrite] [No such file or directory]
# 而 rfs 是 modem / adsp / slpi 讀寫 EFS 類檔案的路徑，RIL 會用到。

TARGET_RFS_DIR := $(TARGET_OUT_VENDOR)/rfs

define z01g-make-rfs
	mkdir -p $(TARGET_RFS_DIR)/apq $(TARGET_RFS_DIR)/apq/gnss $(TARGET_RFS_DIR)/apq/gnss/readonly $(TARGET_RFS_DIR)/apq/gnss/readonly/vendor $(TARGET_RFS_DIR)/mdm $(TARGET_RFS_DIR)/mdm/adsp $(TARGET_RFS_DIR)/mdm/adsp/readonly $(TARGET_RFS_DIR)/mdm/adsp/readonly/vendor $(TARGET_RFS_DIR)/mdm/mpss $(TARGET_RFS_DIR)/mdm/mpss/readonly $(TARGET_RFS_DIR)/mdm/mpss/readonly/vendor $(TARGET_RFS_DIR)/mdm/slpi $(TARGET_RFS_DIR)/mdm/slpi/readonly $(TARGET_RFS_DIR)/mdm/tn $(TARGET_RFS_DIR)/mdm/tn/readonly $(TARGET_RFS_DIR)/msm $(TARGET_RFS_DIR)/msm/adsp $(TARGET_RFS_DIR)/msm/adsp/readonly $(TARGET_RFS_DIR)/msm/adsp/readonly/vendor $(TARGET_RFS_DIR)/msm/mpss $(TARGET_RFS_DIR)/msm/mpss/readonly $(TARGET_RFS_DIR)/msm/mpss/readonly/vendor $(TARGET_RFS_DIR)/msm/slpi $(TARGET_RFS_DIR)/msm/slpi/readonly
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/apq/gnss/hlos
	ln -sf /data/vendor/tombstones/rfs/modem $(TARGET_RFS_DIR)/apq/gnss/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/apq/gnss/readonly/firmware
	ln -sf /vendor/firmware $(TARGET_RFS_DIR)/apq/gnss/readonly/vendor/firmware
	ln -sf /persist/rfs/apq/gnss $(TARGET_RFS_DIR)/apq/gnss/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/apq/gnss/shared
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/mdm/adsp/hlos
	ln -sf /data/vendor/tombstones/rfs/lpass $(TARGET_RFS_DIR)/mdm/adsp/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/mdm/adsp/readonly/firmware
	ln -sf /vendor/firmware $(TARGET_RFS_DIR)/mdm/adsp/readonly/vendor/firmware
	ln -sf /persist/rfs/mdm/adsp $(TARGET_RFS_DIR)/mdm/adsp/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/mdm/adsp/shared
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/mdm/mpss/hlos
	ln -sf /data/vendor/tombstones/rfs/modem $(TARGET_RFS_DIR)/mdm/mpss/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/mdm/mpss/readonly/firmware
	ln -sf /vendor/firmware $(TARGET_RFS_DIR)/mdm/mpss/readonly/vendor/firmware
	ln -sf /persist/rfs/mdm/mpss $(TARGET_RFS_DIR)/mdm/mpss/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/mdm/mpss/shared
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/mdm/slpi/hlos
	ln -sf /data/vendor/tombstones/rfs/slpi $(TARGET_RFS_DIR)/mdm/slpi/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/mdm/slpi/readonly/firmware
	ln -sf /persist/rfs/mdm/slpi $(TARGET_RFS_DIR)/mdm/slpi/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/mdm/slpi/shared
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/mdm/tn/hlos
	ln -sf /data/vendor/tombstones/rfs/tn $(TARGET_RFS_DIR)/mdm/tn/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/mdm/tn/readonly/firmware
	ln -sf /persist/rfs/mdm/tn $(TARGET_RFS_DIR)/mdm/tn/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/mdm/tn/shared
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/msm/adsp/hlos
	ln -sf /data/vendor/tombstones/rfs/lpass $(TARGET_RFS_DIR)/msm/adsp/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/msm/adsp/readonly/firmware
	ln -sf /vendor/firmware $(TARGET_RFS_DIR)/msm/adsp/readonly/vendor/firmware
	ln -sf /persist/rfs/msm/adsp $(TARGET_RFS_DIR)/msm/adsp/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/msm/adsp/shared
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/msm/mpss/hlos
	ln -sf /data/vendor/tombstones/rfs/modem $(TARGET_RFS_DIR)/msm/mpss/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/msm/mpss/readonly/firmware
	ln -sf /vendor/firmware $(TARGET_RFS_DIR)/msm/mpss/readonly/vendor/firmware
	ln -sf /persist/rfs/msm/mpss $(TARGET_RFS_DIR)/msm/mpss/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/msm/mpss/shared
	ln -sf /persist/hlos_rfs/shared $(TARGET_RFS_DIR)/msm/slpi/hlos
	ln -sf /data/vendor/tombstones/rfs/slpi $(TARGET_RFS_DIR)/msm/slpi/ramdumps
	ln -sf /firmware $(TARGET_RFS_DIR)/msm/slpi/readonly/firmware
	ln -sf /persist/rfs/msm/slpi $(TARGET_RFS_DIR)/msm/slpi/readwrite
	ln -sf /persist/rfs/shared $(TARGET_RFS_DIR)/msm/slpi/shared
endef
