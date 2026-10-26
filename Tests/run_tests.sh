#!/bin/zsh
# 장치 판별·전환 규칙 단위 테스트 실행 (Xcode 테스트 타깃 없이 swiftc로 빌드)
set -e
ROOT="${0:A:h}/.."
OUT="${TMPDIR:-/tmp}/magictrack_logic_tests"
xcrun swiftc -O -o "$OUT" \
  "$ROOT/Tests/LogicTests/main.swift" \
  "$ROOT/MagicTrack/Core/DeviceClassifier.swift" \
  "$ROOT/MagicTrack/Core/SwitchCoordinator.swift" \
  "$ROOT/MagicTrack/Core/TrackpadDevice.swift" \
  "$ROOT/MagicTrack/Core/SensitivityController.swift"
"$OUT"
