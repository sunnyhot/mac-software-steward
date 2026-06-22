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
    TEMP_APP="$DEST_APP.updating.$$"
    BACKUP_APP="$DEST_APP.previous.$$"
    RESTORE_NEEDED=0
    restore_backup() {
      local code="$?"
      if [ "$RESTORE_NEEDED" = "1" ] && [ -d "$BACKUP_APP" ]; then
        echo "[system] install failed, restoring backup from $BACKUP_APP"
        /bin/rm -rf -- "$DEST_APP"
        /bin/mv "$BACKUP_APP" "$DEST_APP"
      fi
      /bin/rm -rf "$TEMP_APP"
      exit "$code"
    }
    trap 'restore_backup' ERR
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
      /bin/rm -rf "$TEMP_APP" "$BACKUP_APP"
      /usr/bin/ditto "$NEW_APP" "$TEMP_APP"
      /bin/test -d "$TEMP_APP/Contents/MacOS"
      EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$TEMP_APP/Contents/Info.plist")"
      /bin/test -x "$TEMP_APP/Contents/MacOS/$EXECUTABLE_NAME"
      if [ -e "$DEST_APP" ]; then
        /bin/mv "$DEST_APP" "$BACKUP_APP"
        RESTORE_NEEDED=1
      fi
      /bin/mv "$TEMP_APP" "$DEST_APP"
      /usr/bin/xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true
      /usr/bin/open -n "$DEST_APP"
      RESTORE_NEEDED=0
      /bin/rm -rf "$BACKUP_APP" "$WORK_DIR"
      echo "[system] update installed to $DEST_APP"
    } >> "$LOG_PATH" 2>&1
    """
}
