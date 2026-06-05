import Foundation

enum SelfUpdateInstallScript {
    static let content = """
    #!/bin/zsh
    set -euo pipefail
    APP_PID="$1"
    DEST_APP="$2"
    NEW_APP="$3"
    WORK_DIR="$4"
    LOG_PATH="$5"
    {
      echo "[system] $(date -u +%FT%TZ) installing update"
      for i in {1..80}; do
        /bin/kill -0 "$APP_PID" 2>/dev/null || break
        /bin/sleep 0.25
      done
      if /bin/kill -0 "$APP_PID" 2>/dev/null; then
        echo "[system] old app still running, terminating $APP_PID"
        /bin/kill -TERM "$APP_PID" 2>/dev/null || true
        for i in {1..20}; do
          /bin/kill -0 "$APP_PID" 2>/dev/null || break
          /bin/sleep 0.25
        done
      fi
      if /bin/kill -0 "$APP_PID" 2>/dev/null; then
        echo "[system] old app still running after TERM, force killing $APP_PID"
        /bin/kill -KILL "$APP_PID" 2>/dev/null || true
        /bin/sleep 0.25
      fi
      /bin/mkdir -p "$(/usr/bin/dirname "$DEST_APP")"
      /bin/rm -rf "$DEST_APP"
      /usr/bin/ditto "$NEW_APP" "$DEST_APP"
      /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
      /usr/bin/open -n "$DEST_APP"
      rm -rf "$WORK_DIR"
      echo "[system] update installed to $DEST_APP"
    } >> "$LOG_PATH" 2>&1
    """
}
