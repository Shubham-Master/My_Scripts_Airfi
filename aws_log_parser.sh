#!/bin/bash
# -------------------------------------------------------------------
# AirFi Log Processor (Enhanced Checkpointing)
# Description:
#   - Streams maintenance logs (.gz) from S3
#   - Skips FASE='on' logs
#   - Extracts STM32/STC3115/PMIC/version info
#   - Writes cleaned logs to another S3 bucket preserving folder structure
#   - Maintains per-box checkpoints + global completed-box list
# -------------------------------------------------------------------

# ---------------- CONFIGURATION ----------------
SRC_BUCKET="airserver-backups"
DST_BUCKET="airserver-logs-processed"
BASE_TMP="/tmp/s3_processing"
mkdir -p "$BASE_TMP"
SOURCE_MOUNTED="/home/ubuntu/airserver_backup"
DEST_MOUNTED="/home/ubuntu/airserver-processed"
LOG_LIST="/home/ubuntu/logs-list.txt"


GLOBAL_COMPLETED="$BASE_TMP/completed_boxes.txt"
SKIPPED_FILE="$BASE_TMP/skipped_fase.txt"

CUTOFF_DATE=$(date -d '365 days ago' +%s)

# ---------------- LOG FUNCTION ----------------
log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# ---------------- PARSER ----------------
extract_stm_log() {
    local input="$1"
    local output="$2"

    zcat "$input" \
    | grep -E "init: (SWver|HWver|HWrev|powman-ver)|STM32\[BQ24620\[status=|STC3115\[chg=|airfi-cmd\.sh: --(shutdown|reboot)" \
    | sed -E 's/^([0-9TZ:+-]+|[0-9TZ:+-]+\s+[0-9.-]+)\s+[0-9.-]+\s+//g' \
    | sed -E 's/\/usr\/bin\/powman\[.*\]:\s*//g' \
    | sed -E 's/^.*init: /init: /' \
    | sed -E '/^init: Box power-(up|down) Battery status:?$/d' \
    | sed -E 's/BQ24620\[status=([0-9]+)[^S]*STC3115/BQ24620[status=\1 STC3115/g' \
    | sed -E 's/[[:space:]]\+/ /g' \
    | awk '!seen[$0]++' > "$output"
}

# ---------------- HELPERS ----------------
is_processed() {
    grep -Fxq "$1" "$2" 2>/dev/null
}

mark_processed() {
    echo "$1" >> "$2"
}

# ---------------- MAIN LOOP ----------------
log "Starting log processing with structured checkpoints..."

grep -E "logfile-maintenance*." $LOG_LIST | while read -r LOG_FILE; do
    KEY=$LOG_FILE
    BOX_ID=$(echo "$LOG_FILE" | awk -F'/' '{print $(NF-1)}')
    BOX_DIR="$BASE_TMP/$BOX_ID"
    mkdir -p "$BOX_DIR"
    BOX_CHECKPOINT="$BOX_DIR/checkpoint.txt"
    FILE_PATH=$SOURCE_MOUNTED/$LOG_FILE
    FILE_MOD=$(stat -c %y "$FILE_PATH")
    FILE_MOD_TS=$(date -d "$FILE_MOD" +%s)
    # Skip if older than 365 days
    if (( FILE_MOD_TS < CUTOFF_DATE )); then
        continue
    fi
    #  Get StorageClass of a Specific File
    STORAGE_CLASS=$(aws s3api head-object --bucket "$SRC_BUCKET" --key "$KEY"  --query "StorageClass || 'STANDARD'" --output text)
    echo "StorageClass of $KEY: $STORAGE_CLASS"
    if [[ "$STORAGE_CLASS" != "STANDARD" ]]; then
        continue
    fi
    # Skip if already processed this object
    if is_processed "$KEY" "$BOX_CHECKPOINT"; then
        continue
    fi

    # Skip FASE logs
    if zcat "$FILE_PATH" | grep -q "airfi-cmd\.sh --list: FASE='on'"; then
        log "[$BOX_ID] Skipped (FASE=on)"
        if ! grep -q "^$BOX_ID$" "$SKIPPED_FILE"; then
            echo "$BOX_ID" >> "$SKIPPED_FILE"
        fi
        mark_processed "$KEY" "$BOX_CHECKPOINT"
        continue
    fi

    # Skip logs containing LTC4156 in the first log
    if zcat "$FILE_PATH" | grep -m 1 "LTC4156" >/dev/null; then
        log "[$BOX_ID] Skipped (LTC4156 found in first log)"
        if ! grep -q "^$BOX_ID$" "$SKIPPED_FILE"; then
            echo "$BOX_ID" >> "$SKIPPED_FILE"
        fi
        mark_processed "$KEY" "$BOX_CHECKPOINT"
        continue
    fi

    # Parse & upload
    log "[$BOX_ID] Processing"
    OUT_FILE=$(mktemp)
    extract_stm_log "$FILE_PATH" "$OUT_FILE"

    DST_KEY="${KEY%.gz}_STM_LOG.txt"
    log "[$BOX_ID] Uploading result"
    aws s3 cp "$OUT_FILE" "s3://$DST_BUCKET/$DST_KEY" --quiet

    mark_processed "$KEY" "$BOX_CHECKPOINT"

    # If all logs for this box processed, mark box as completed
    TOTAL=$(aws s3api list-objects-v2 --bucket "$SRC_BUCKET" --prefix "$(dirname "$KEY")/" --query 'length(Contents[])' --output text)
    DONE=$(wc -l < "$BOX_CHECKPOINT")
    if [[ "$DONE" -eq "$TOTAL" ]]; then
        if ! grep -Fxq "$BOX_ID" "$GLOBAL_COMPLETED" 2>/dev/null; then
            echo "$BOX_ID" >> "$GLOBAL_COMPLETED"
            log "[$BOX_ID] ✅ Box completed and added to $GLOBAL_COMPLETED"
        fi
    fi
done

log "Processing complete."
