#!/bin/bash

# === Config ===
LOCAL_BASE="$HOME/Onedrive"
TMP_CHANGES_FILE="/tmp/rclone_pending_changes.txt"
IDLE_SECONDS=300  # 5 minutes
NOTIFY_ENABLE=true
INTERRUPT_FLAG=false

# === Notify function ===
notify() {
    local msg="$1"
    if [ "$NOTIFY_ENABLE" = true ]; then
        notify-send "Rclone Sync" "$msg"
    fi
}

# === Compute common ancestor by path segments ===
common_prefix() {
    local paths=("$@")
    IFS='/' read -r -a ref_parts <<< "${paths[0]}"
    local prefix=""
    for ((i = 0; i < ${#ref_parts[@]}; i++)); do
        part="${ref_parts[i]}"
        for path in "${paths[@]}"; do
            IFS='/' read -r -a test_parts <<< "$path"
            if [[ "${test_parts[i]}" != "$part" ]]; then
                echo "$prefix"
                return
            fi
        done
        prefix+="$part/"
    done
    echo "$prefix"
}

# === Signal handler ===
trap 'INTERRUPT_FLAG=true' USR1

# === List mode ===
if [[ "$1" == "-l" ]]; then
    if [ ! -s "$TMP_CHANGES_FILE" ]; then
        echo "📭 No changes recorded yet."
        exit 0
    fi

    echo "📄 Files detected in pending changes:"
    mapfile -t changed_paths < "$TMP_CHANGES_FILE"
    for fullpath in "${changed_paths[@]}"; do
        echo " - ${fullpath}"
    done

    relative_paths=()
    for fullpath in "${changed_paths[@]}"; do
        rel="${fullpath#$LOCAL_BASE/}"
        relative_paths+=("$rel")
    done

    common_dir=$(common_prefix "${relative_paths[@]}")
    echo ""
    echo "📁 Minimal sync directory (relative): $common_dir"
    echo "📂 Full path: $LOCAL_BASE/$common_dir"
    exit 0
fi

# === Immediate sync mode ===
if [[ "$1" == "-y" ]]; then
    pkill -USR1 -f "$0"
    exit 0
fi

# === Main logic ===
echo "📡 Listening for changes under $LOCAL_BASE..."
> "$TMP_CHANGES_FILE"

while true; do
    event=$(inotifywait -r -e modify,create,delete,move --format '%w%f' "$LOCAL_BASE" 2>/dev/null)
    [ -n "$event" ] && echo "$event" >> "$TMP_CHANGES_FILE"
    notify "Change detected, entering sync preparation mode."

    last_event_time=$(date +%s)

    while true; do
        now=$(date +%s)
        elapsed=$((now - last_event_time))

        if [ "$INTERRUPT_FLAG" = true ]; then
            echo "⚡ Interrupt received. Forcing immediate sync."
            break
        fi

        if (( elapsed >= IDLE_SECONDS )); then
            break
        fi

        next_event=$(inotifywait -r -e modify,create,delete,move --timeout 1 --format '%w%f' "$LOCAL_BASE" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$next_event" ]; then
            echo "$next_event" >> "$TMP_CHANGES_FILE"
            last_event_time=$(date +%s)
        fi
    done

    mapfile -t changed_paths < "$TMP_CHANGES_FILE"
    relative_paths=()
    for fullpath in "${changed_paths[@]}"; do
        rel="${fullpath#$LOCAL_BASE/}"
        relative_paths+=("$rel")
    done

    common_dir=$(common_prefix "${relative_paths[@]}")
    [ -z "$common_dir" ] && continue

    SYNC_PATH="$LOCAL_BASE/$common_dir"
    if [ ! -d "$SYNC_PATH" ]; then
        # fallback one level up
        common_dir="${common_dir%/*}"
        SYNC_PATH="$LOCAL_BASE/$common_dir"
    fi

    if [ ! -d "$SYNC_PATH" ]; then
        notify "❌ Sync aborted: directory not found: $SYNC_PATH"
        echo "❌ Directory not found: $SYNC_PATH"
        > "$TMP_CHANGES_FILE"
        INTERRUPT_FLAG=false
        continue
    fi

    notify "Syncing directory: $common_dir"
    echo "🔄 Syncing $common_dir"

    (cd "$SYNC_PATH" && sync_to_onedrive)

    notify "✅ Sync complete: $common_dir"
    > "$TMP_CHANGES_FILE"
    INTERRUPT_FLAG=false

done
