// Z01G keymaster shim
//
// 補一個符號給 Oreo 的 libkeymaster1.so。
//
// 注意：這個檔案刻意用 // 行註解而不是區塊註解 ——
// 註解裡要寫 /vendor/lib64/hw 這類路徑，一不小心打出 star-slash
// 就會把區塊註解提前關掉，後面整段被當成程式碼解析（踩過一次）。
//
// 問題：
//     /vendor/bin/gxFpDaemon（指紋 daemon，也是 Home 鍵的來源）與
//     /vendor/lib64/hw/fingerprint.gx5206.so（以及 gx5216）
//     都連結 libkeymaster1.so。那支是 Oreo 的 blob
//     （AOSP 9 沒有這個模組，只能收原廠的），
//     而它需要的符號由 libkeymaster_messages.so 提供 —— 那支是 AOSP 9 編的。
//     執行時：
//         CANNOT LINK EXECUTABLE "/vendor/bin/gxFpDaemon": cannot locate symbol
//           "_ZN9keymaster27copy_size_and_data_from_bufEPPKhS1_PmP9UniquePtrIA_h13DefaultDeleteIS5_EE"
//           referenced by "/system/lib64/libkeymaster1.so"
//
// 差在哪：
//     Android 9 把 UniquePtr / DefaultDelete 從全域搬進 keymaster 命名空間，
//     所以 mangled name 變了，但函式本身與 ABI 完全相同（參數只是指標）：
//       Oreo  keymaster::copy_size_and_data_from_buf(
//                 const uint8_t**, const uint8_t*, size_t*,
//                 UniquePtr<uint8_t[], DefaultDelete<uint8_t[]>>*)
//       Pie   keymaster::copy_size_and_data_from_buf(
//                 const uint8_t**, const uint8_t*, size_t*,
//                 keymaster::UniquePtr<uint8_t[], keymaster::DefaultDelete<uint8_t[]>>*)
//     所以只要用舊的 mangled name 再導一次就好。
//
// 為什麼不直接換成 Oreo 的 libkeymaster_messages.so：
//     它是系統層的函式庫，/system/bin/keystore、libsoftkeymasterdevice.so、
//     libpuresoftkeymasterdevice.so、libkeymaster3device.so 全都連著它
//     （tools/67_km_probe.sh 列得出來）。換成 Oreo 版會把 keystore 和
//     我們正在用的 AOSP keymaster@3.0 一起弄壞。非 Treble 只有一個
//     linker namespace，也沒辦法讓 vendor 那邊看到不同版本。
//
// 掛法：BoardConfig.mk 的 TARGET_LD_SHIM_LIBS
//     —— LineageOS 在 bionic linker 裡加的機制（linker.cpp 的
//        parse_LD_SHIM_LIBS / g_ld_all_shim_libs）：
//        指定「載入某個函式庫時，順便把這個 shim 一起載進同一個查找群組」。
//     我們掛在 libkeymaster1.so 上，所以只有指紋那條鏈會受影響。
//
// 實測缺的符號只有這一個（tools/67_km_probe.sh 比對過完整的 U 清單）。

#include <stddef.h>
#include <stdint.h>

// size_t* 在 32 位元 mangle 成 Pj、64 位元成 Pm，所以兩種位元的名字不一樣。
// 兩邊的實際字串都是從建出來的 .so 上 nm -D 抄下來的，不是手推的。
#if defined(__LP64__)
#define KM_PIE_SYM \
    _ZN9keymaster27copy_size_and_data_from_bufEPPKhS1_PmPNS_9UniquePtrIA_hNS_13DefaultDeleteIS5_EEEE
#define KM_OREO_SYM \
    _ZN9keymaster27copy_size_and_data_from_bufEPPKhS1_PmP9UniquePtrIA_h13DefaultDeleteIS5_EE
#else
#define KM_PIE_SYM \
    _ZN9keymaster27copy_size_and_data_from_bufEPPKhS1_PjPNS_9UniquePtrIA_hNS_13DefaultDeleteIS5_EEEE
#define KM_OREO_SYM \
    _ZN9keymaster27copy_size_and_data_from_bufEPPKhS1_PjP9UniquePtrIA_h13DefaultDeleteIS5_EE
#endif

extern "C" {

// Pie 版，由 libkeymaster_messages.so 提供
bool KM_PIE_SYM(const uint8_t** buf_ptr, const uint8_t* end, size_t* size, void* dest);

// Oreo 版，由這裡補上
bool KM_OREO_SYM(const uint8_t** buf_ptr, const uint8_t* end, size_t* size, void* dest);

bool KM_OREO_SYM(const uint8_t** buf_ptr, const uint8_t* end, size_t* size, void* dest) {
    return KM_PIE_SYM(buf_ptr, end, size, dest);
}

}  // extern "C"
