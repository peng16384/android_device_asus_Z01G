#!/bin/bash
S=$HOME/lineage-16.0
F=$(ls $S/frameworks/native/include/input/InputEventLabels.h \
       $S/frameworks/native/libs/input/InputEventLabels.cpp 2>/dev/null | head -1)
echo "標籤表：$F"
echo
for k in APP_SWITCH HOME BACK FOCUS CAMERA VOLUME_UP \
         GESTURE_DOUBLE_CLICK GESTURE_SWIPE_UP GESTURE_W GESTURE_S \
         GESTURE_E GESTURE_C GESTURE_Z GESTURE_V FINGERPRINT_EARLYWAKEUP; do
  if grep -q "DEFINE_KEYCODE($k)" "$F" 2>/dev/null; then r="認得"; else r="不認得"; fi
  printf "  %-28s %s\n" "$k" "$r"
done
