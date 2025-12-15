#!/bin/bash

set -euo pipefail

# 프로젝트 루트 기준으로 실행되도록 설정
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

FLUTTER_BIN="${FLUTTER_BIN:-flutter}"

echo ">>> 프로젝트 경로: $PROJECT_ROOT"

FLUTTER_SDK="/Users/yoojaekwon/development/flutter"
if [ -d "$FLUTTER_SDK" ]; then
  if [ ! -w "$FLUTTER_SDK/bin/cache" ]; then
    echo ">>> Flutter SDK 권한을 사용자 계정으로 수정합니다 (비밀번호 필요)"
    sudo chown -R "$USER" "$FLUTTER_SDK"
  fi
fi

echo ">>> flutter clean"
"$FLUTTER_BIN" clean >/dev/null

if [ ! -d "macos" ]; then
  echo ">>> macOS 폴더가 없어 새로 생성합니다."
  "$FLUTTER_BIN" create --platforms=macos . >/dev/null
fi

add_entitlement() {
  local file="$1"
  local key="com.apple.security.network.client"

  if [ ! -f "$file" ]; then
    echo "warning: $file 파일이 없어 건너뜁니다."
    return
  fi

  python3 - "$file" "$key" <<'PY'
import plistlib, pathlib, sys
path = pathlib.Path(sys.argv[1])
key = sys.argv[2]
data = plistlib.loads(path.read_bytes())
if data.get(key) is True:
    sys.exit(0)
data[key] = True
path.write_bytes(plistlib.dumps(data))
print(f">>> {path} 에 {key} 권한 추가")
PY
}

add_entitlement "macos/Runner/DebugProfile.entitlements"
add_entitlement "macos/Runner/Release.entitlements"

echo ">>> flutter pub get"
"$FLUTTER_BIN" pub get >/dev/null

echo ">>> CocoaPods 설치"
pushd macos >/dev/null
pod install >/dev/null
popd >/dev/null

echo ">>> flutter doctor -v"
"$FLUTTER_BIN" doctor -v

echo ">>> 준비 완료! 이제 'flutter run -d macos' 를 실행하세요."
