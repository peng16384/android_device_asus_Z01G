/*
 * SPDX-FileCopyrightText: 2026 ZS551KL port
 * SPDX-License-Identifier: Apache-2.0
 */
#include "Vibrator.h"

#include <android-base/file.h>
#include <android-base/logging.h>

#include <chrono>
#include <thread>

namespace aidl::android::hardware::vibrator {

static constexpr char kEnable[] = "/sys/class/timed_output/vibrator/enable";

// 效果只能用「震多久」表達（timed_output 沒有波形）。長度照 AOSP 的 vibrator 預設實作的量級
static int32_t effectMs(Effect effect, EffectStrength strength) {
    int32_t ms;
    switch (effect) {
        case Effect::CLICK:        ms = 20; break;
        case Effect::TICK:         ms = 10; break;
        case Effect::TEXTURE_TICK: ms = 8;  break;
        case Effect::DOUBLE_CLICK: ms = 30; break;
        case Effect::HEAVY_CLICK:  ms = 35; break;
        default:                   return -1;
    }
    if (strength == EffectStrength::LIGHT) ms = ms * 3 / 4;
    if (strength == EffectStrength::STRONG) ms = ms * 5 / 4;
    return ms;
}

static ndk::ScopedAStatus unsupported() {
    return ndk::ScopedAStatus::fromExceptionCode(EX_UNSUPPORTED_OPERATION);
}

ndk::ScopedAStatus Vibrator::activate(int32_t timeoutMs,
                                      const std::shared_ptr<IVibratorCallback>& callback) {
    if (!::android::base::WriteStringToFile(std::to_string(timeoutMs), kEnable)) {
        PLOG(ERROR) << "寫 " << kEnable << " 失敗";
        return ndk::ScopedAStatus::fromExceptionCode(EX_SERVICE_SPECIFIC);
    }
    if (callback != nullptr && timeoutMs > 0) {
        std::thread([timeoutMs, callback] {
            std::this_thread::sleep_for(std::chrono::milliseconds(timeoutMs));
            callback->onComplete();
        }).detach();
    }
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::getCapabilities(int32_t* _aidl_return) {
    *_aidl_return = IVibrator::CAP_ON_CALLBACK | IVibrator::CAP_PERFORM_CALLBACK;
    return ndk::ScopedAStatus::ok();
}

ndk::ScopedAStatus Vibrator::off() {
    return activate(0, nullptr);
}

ndk::ScopedAStatus Vibrator::on(int32_t timeoutMs,
                                const std::shared_ptr<IVibratorCallback>& callback) {
    return activate(timeoutMs, callback);
}

ndk::ScopedAStatus Vibrator::perform(Effect effect, EffectStrength strength,
                                     const std::shared_ptr<IVibratorCallback>& callback,
                                     int32_t* _aidl_return) {
    int32_t ms = effectMs(effect, strength);
    if (ms < 0) return unsupported();
    *_aidl_return = ms;
    return activate(ms, callback);
}

ndk::ScopedAStatus Vibrator::getSupportedEffects(std::vector<Effect>* _aidl_return) {
    *_aidl_return = {Effect::CLICK, Effect::TICK, Effect::TEXTURE_TICK, Effect::DOUBLE_CLICK,
                     Effect::HEAVY_CLICK};
    return ndk::ScopedAStatus::ok();
}

// 以下是 timed_output 做不到的：回 UNSUPPORTED，框架會自己退回 on()/off()
ndk::ScopedAStatus Vibrator::setAmplitude(float) { return unsupported(); }
ndk::ScopedAStatus Vibrator::setExternalControl(bool) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getCompositionDelayMax(int32_t*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getCompositionSizeMax(int32_t*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getSupportedPrimitives(std::vector<CompositePrimitive>* supported) {
    supported->clear();
    return ndk::ScopedAStatus::ok();
}
ndk::ScopedAStatus Vibrator::getPrimitiveDuration(CompositePrimitive, int32_t*) {
    return unsupported();
}
ndk::ScopedAStatus Vibrator::compose(const std::vector<CompositeEffect>&,
                                     const std::shared_ptr<IVibratorCallback>&) {
    return unsupported();
}
ndk::ScopedAStatus Vibrator::getSupportedAlwaysOnEffects(std::vector<Effect>* _aidl_return) {
    _aidl_return->clear();
    return ndk::ScopedAStatus::ok();
}
ndk::ScopedAStatus Vibrator::alwaysOnEnable(int32_t, Effect, EffectStrength) {
    return unsupported();
}
ndk::ScopedAStatus Vibrator::alwaysOnDisable(int32_t) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getResonantFrequency(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getQFactor(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getFrequencyResolution(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getFrequencyMinimum(float*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getBandwidthAmplitudeMap(std::vector<float>*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getPwlePrimitiveDurationMax(int32_t*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getPwleCompositionSizeMax(int32_t*) { return unsupported(); }
ndk::ScopedAStatus Vibrator::getSupportedBraking(std::vector<Braking>* supported) {
    supported->clear();
    return ndk::ScopedAStatus::ok();
}
ndk::ScopedAStatus Vibrator::composePwle(const std::vector<PrimitivePwle>&,
                                         const std::shared_ptr<IVibratorCallback>&) {
    return unsupported();
}

}  // namespace aidl::android::hardware::vibrator
