#!/usr/bin/env bash
# Build release APK universal DUY NHẤT và bàn giao thành THBIKE-vX.Y.Z.apk
# (X.Y.Z lấy từ `version:` trong pubspec.yaml).
#
#   tool/build_release_apk.sh            # build + chép + kiểm tra
#   tool/build_release_apk.sh --install  # thêm: adb install -r nếu có thiết bị
#
# Thư mục bàn giao: $TH_BIKE_DELIVERY_DIR (mặc định: <repo>/dist).
# Không đổi package ID, chữ ký, phiên bản. Build lỗi => thoát mã != 0 và KHÔNG
# tạo file bàn giao (không đổi tên file lỗi/cũ thành file hoàn chỉnh).
set -euo pipefail

EXPECTED_PKG="vn.mybike.mybike_app"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER_NAME="$(grep -m1 '^version:' "$ROOT/pubspec.yaml" | awk '{print $2}' | cut -d+ -f1)"
[[ "$VER_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ LỖI: version trong pubspec không đúng dạng X.Y.Z: '$VER_NAME'" >&2; exit 1; }
OUT_NAME="THBIKE-v${VER_NAME}.apk"
DELIVERY="${TH_BIKE_DELIVERY_DIR:-$ROOT/dist}"
SRC="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
DO_INSTALL=0
[[ "${1:-}" == "--install" ]] && DO_INSTALL=1

fail() { echo "✗ LỖI: $*" >&2; exit 1; }
skip() { echo "• BỎ QUA (chưa kiểm tra): $*"; }
ok()   { echo "✓ $*"; }

cd "$ROOT"
command -v flutter >/dev/null || fail "không tìm thấy lệnh flutter trong PATH"

# 1. Build universal (KHÔNG --split-per-abi, KHÔNG --target-platform tách).
rm -f "$SRC"
flutter build apk --release
[[ -f "$SRC" ]] || fail "build xong nhưng thiếu $SRC"

# 2. Bàn giao đúng 1 file: xóa mọi APK cũ trong thư mục bàn giao.
mkdir -p "$DELIVERY"
find "$DELIVERY" -maxdepth 1 -type f -name '*.apk' -delete
TMP="$DELIVERY/.${OUT_NAME}.tmp"
cp "$SRC" "$TMP"
mv -f "$TMP" "$DELIVERY/$OUT_NAME"
APK="$DELIVERY/$OUT_NAME"
echo "== Kiểm tra $APK"

# 3. Tồn tại + dung lượng + toàn vẹn zip.
[[ -f "$APK" ]] || fail "file không tồn tại"
SIZE=$(stat -c%s "$APK")
(( SIZE > 0 )) || fail "dung lượng 0 byte"
ok "tồn tại, dung lượng $SIZE byte ($(numfmt --to=iec "$SIZE"))"
if command -v unzip >/dev/null; then
  unzip -tq "$APK" >/dev/null || fail "APK không phải zip hợp lệ"
  ok "cấu trúc zip hợp lệ"
  ABIS=$(unzip -Z1 "$APK" | grep -o '^lib/[^/]*/' | sort -u | tr '\n' ' ' || true)
  echo "  ABI trong APK: ${ABIS:-không có lib native}"
fi
ok "sha256: $(sha256sum "$APK" | cut -d' ' -f1)"

# 4. Tìm công cụ Android SDK.
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
BT=""
if [[ -n "$SDK" && -d "$SDK/build-tools" ]]; then
  BT="$SDK/build-tools/$(ls "$SDK/build-tools" | sort -V | tail -1)"
fi
tool() { # tool <name>: ưu tiên build-tools, sau đó PATH
  if [[ -n "$BT" && -x "$BT/$1" ]]; then echo "$BT/$1"; elif command -v "$1" >/dev/null; then command -v "$1"; fi
}

# 5. Package ID + phiên bản.
AAPT="$(tool aapt2 || true)"; [[ -z "$AAPT" ]] && AAPT="$(tool aapt || true)"
PUBVER=$(grep -m1 '^version:' pubspec.yaml | awk '{print $2}')
if [[ -n "$AAPT" ]]; then
  BADGE=$("$AAPT" dump badging "$APK" 2>/dev/null | grep -m1 '^package:' || true)
  [[ -n "$BADGE" ]] || fail "aapt không đọc được manifest APK"
  PKG=$(sed -n "s/.*name='\([^']*\)'.*/\1/p" <<<"$BADGE")
  VN=$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$BADGE")
  VC=$(sed -n "s/.*versionCode='\([^']*\)'.*/\1/p" <<<"$BADGE")
  [[ "$PKG" == "$EXPECTED_PKG" ]] || fail "package ID là '$PKG', mong đợi '$EXPECTED_PKG'"
  ok "package ID: $PKG; version: $VN (code $VC); pubspec: $PUBVER"
else
  skip "package ID/phiên bản — không có aapt/aapt2 (pubspec: $PUBVER)"
fi

# 6. Chữ ký.
APKSIGNER="$(tool apksigner || true)"
if [[ -n "$APKSIGNER" ]]; then
  CERT=$("$APKSIGNER" verify --verbose --print-certs "$APK" 2>&1) \
    || fail "apksigner verify thất bại: $CERT"
  ok "chữ ký hợp lệ ($(grep -m1 -o 'v[0-9]* scheme[^:]*: true' <<<"$CERT" | tr '\n' ' '))"
  echo "$CERT" | grep -E 'certificate (DN|SHA-256)' | head -2 | sed 's/^/  /'
  if grep -qi 'Android Debug' <<<"$CERT"; then
    echo "! CẢNH BÁO: APK đang ký bằng khóa DEBUG (build.gradle.kts dùng signingConfigs.debug)."
    echo "  Không phải khóa release riêng. Cài đè lên bản đã ký khóa khác sẽ báo INSTALL_FAILED_UPDATE_INCOMPATIBLE."
  fi
else
  skip "chữ ký — không có apksigner"
fi

# 7. Cài đặt thật qua adb (chỉ khi có thiết bị).
ADB="$(command -v adb || { [[ -n "$SDK" && -x "$SDK/platform-tools/adb" ]] && echo "$SDK/platform-tools/adb"; } || true)"
if (( DO_INSTALL )); then
  [[ -n "$ADB" ]] || fail "--install nhưng không có adb"
  DEV=$("$ADB" devices | awk 'NR>1 && $2=="device"{print $1}' | head -1)
  [[ -n "$DEV" ]] || fail "--install nhưng không có thiết bị nối qua adb"
  "$ADB" -s "$DEV" install -r "$APK" || fail "adb install -r thất bại"
  ok "adb install -r thành công trên $DEV ($("$ADB" -s "$DEV" shell getprop ro.product.model | tr -d '\r'))"
else
  skip "cài đặt — chưa chạy adb install (dùng --install khi cắm Xiaomi 15T Pro)"
fi

# 8. Chỉ đúng 1 file bàn giao.
N=$(find "$DELIVERY" -maxdepth 1 -type f | wc -l)
(( N == 1 )) || fail "thư mục bàn giao có $N file, mong đợi đúng 1"
ok "bàn giao: $APK"
