#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"
GRADLE="$ROOT/gradlew"
ADB=${ADB:-adb}

# Print java version for easier diagnosis
echo "[install_and_run] java version:" $(java -version 2>&1 | head -n 1 | sed 's/^/ /') || true
JAVA_MAJOR=$(java -XshowSettings:properties -version 2>&1 | awk -F' ' '/java.version =/ {print $3}' | sed -E 's/[^0-9].*//') || true
if [ -n "${JAVA_MAJOR:-}" ] && [ "${JAVA_MAJOR}" -ge 22 ] 2>/dev/null; then
  echo "[install_and_run] WARNING: Detected java major version ${JAVA_MAJOR}. If Gradle/Kotlin fails to parse this, set JAVA_HOME to a supported JDK (11 or 17) or install a compatible JDK."
fi

function build_and_install() {
  echo "[install_and_run] Building APK..."
  "$GRADLE" :app:assembleDebug --no-daemon
  if [ ! -f "$APK" ]; then echo "[install_and_run] APK not found: $APK"; return 1; fi
  DEVICES=$($ADB devices | awk 'NR>1 && $2=="device" {print $1}')
  if [ -z "$DEVICES" ]; then echo "[install_and_run] No devices connected."; $ADB devices; return 2; fi
  for d in $DEVICES; do
    echo "--- Device: $d ---"
    # echo "[install_and_run] Uninstalling existing package (if any)..."
    # $ADB -s "$d" uninstall net.harukaze.app.toremaruappinfo >/dev/null 2>&1 || true
    echo "[install_and_run] Installing $APK to $d..."
    $ADB -s "$d" install -r "$APK"
    echo "[install_and_run] Starting app on $d..."
    $ADB -s "$d" shell am start -S -n net.harukaze.app.toremaruappinfo/.MainActivity
    echo "[install_and_run] Started on $d"
    echo "[install_and_run] ToremaruDebug log (last 50 lines):"
    $ADB -s "$d" logcat -d -s ToremaruDebug | tail -n 50 || true
  done
}

if [ "${1:-}" = "--loop" ] || [ "${1:-}" = "-l" ]; then
  echo "[install_and_run] Loop mode: will rebuild & install repeatedly. Ctrl-C to stop."
  while true; do
    if build_and_install; then
      echo "[install_and_run] Success. Sleeping 2s before next run..."
      sleep 2
    else
      echo "[install_and_run] Failed. Sleeping 5s then retry..."
      sleep 5
    fi
  done
else
  build_and_install
fi
