#!/usr/bin/env bash
# Tạo keystore Release MỚI cho THBIKE (chạy MỘT LẦN, trên máy của bạn).
#   tool/make_release_keystore.sh [thư_mục_lưu]   (mặc định: ./secrets)
#
# Script KHÔNG ghi mật khẩu vào file nào. Nó in ra các giá trị để bạn dán vào
# GitHub → Settings → Secrets and variables → Actions. Thư mục secrets/ đã nằm
# trong .gitignore. HÃY SAO LƯU file .jks ở nơi an toàn: mất khóa = không thể
# cập nhật app đã cài.
set -euo pipefail
command -v keytool >/dev/null || { echo "✗ Cần JDK (keytool)." >&2; exit 1; }
OUT="${1:-secrets}"
ALIAS="thbike"
mkdir -p "$OUT"
JKS="$OUT/thbike-release.jks"
[[ -e "$JKS" ]] && { echo "✗ $JKS đã tồn tại — không ghi đè." >&2; exit 1; }

read -r -s -p "Mật khẩu keystore (>= 8 ký tự): " PASS; echo
read -r -s -p "Nhập lại: " PASS2; echo
[[ "$PASS" == "$PASS2" && ${#PASS} -ge 8 ]] || { echo "✗ Mật khẩu không khớp hoặc quá ngắn." >&2; exit 1; }

keytool -genkeypair -v -keystore "$JKS" -storetype PKCS12 -alias "$ALIAS" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass "$PASS" -keypass "$PASS" \
  -dname "CN=THBIKE, O=Vu Thai Hung, C=VN"

SHA=$(keytool -list -v -keystore "$JKS" -alias "$ALIAS" -storepass "$PASS" \
  | awk -F': ' '/SHA256:/{print $2; exit}' | tr -d ':' )
echo
echo "✓ Đã tạo $JKS"
echo "Thêm 5 Secret sau vào GitHub Actions:"
echo "  THBIKE_KEYSTORE_BASE64 = (nội dung lệnh:  base64 -w0 $JKS )"
echo "  THBIKE_STORE_PASSWORD  = (mật khẩu bạn vừa nhập)"
echo "  THBIKE_KEY_ALIAS       = $ALIAS"
echo "  THBIKE_KEY_PASSWORD    = (cùng mật khẩu trên)"
echo "  THBIKE_CERT_SHA256     = $SHA"
