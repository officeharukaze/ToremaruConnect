#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[watch_and_build] Starting watcher in $ROOT"

if ! command -v shasum >/dev/null 2>&1; then
  echo "[watch_and_build] Error: 'shasum' command not found. Install it (should exist on macOS) or adjust script." >&2
  exit 1
fi

compute_sig(){
  # Compute signature of tracked files to detect changes
  git ls-files -z | xargs -0 shasum 2>/dev/null | shasum 2>/dev/null || echo ""
}

prev_sig=$(compute_sig)
echo "[watch_and_build] initial signature: ${prev_sig%% *}"

while true; do
  sleep 2
  cur_sig=$(compute_sig)
  if [ -z "$cur_sig" ]; then
    echo "[watch_and_build] No git-tracked files or shasum failed; sleeping..."
    sleep 5
    continue
  fi
  if [ "$cur_sig" != "$prev_sig" ]; then
    echo "[watch_and_build] Change detected. Running build loop..."
    prev_sig="$cur_sig"
    # Keep trying builds until success
    attempt=1
    while true; do
      echo "[watch_and_build] Build attempt #$attempt"
      if ./scripts/install_and_run.sh; then
        echo "[watch_and_build] Build succeeded"
        break
      else
        echo "[watch_and_build] Build failed. Saving logs to build_failures.log and retrying in 5s..."
        ./gradlew assembleDebug --stacktrace > build_failures.log 2>&1 || true
        tail -n 200 build_failures.log | sed -n '1,200p'
        attempt=$((attempt+1))
        sleep 5
      fi
    done
    echo "[watch_and_build] Build loop finished; continuing to watch for new changes."
  fi
done
