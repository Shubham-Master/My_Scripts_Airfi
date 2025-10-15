#!/bin/bash
# -------------------------------------------------------------------
# AirFi Log Processor - Targeted Boxes
# Description:
#   Processes logs only for specified box serials (passed as args)
#   Applies same logic as main script but limited scope.
# -------------------------------------------------------------------

# ---------------- CONFIGURATION ----------------
SRC_BUCKET="airserver-logs-backups"
DST_BUCKET="airserver-logs-processed"
BASE_TMP="/tmp/s3_targeted_processing"
mkdir -p "$BASE_TMP"

SKIPPED_BOXES_FILE="$BASE_TMP/skipped_boxes.txt"
touch "$SKIPPED_BOXES_FILE"

CUTOFF_DATE=$(date -d '365 days ago' +%s)

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

# ---------------- MAIN ----------------
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <box_id_1> [box_id_2] ..."
    exit 1
fi

for BOX_ID in "$@"; do
    log "==============================="
    log "Processing box: $BOX_ID"
    log "==============================="

    BOX_DIR="$BASE_TMP/$BOX_ID"
    mkdir -p "$BOX_DIR"

    aws s3api list-objects-v2 \
        --bucket "$SRC_BUCKET" \
        --prefix "logs/$BOX_ID/" \
        --query 'Contents[?contains(Key, `logfile-maintenance-`) == `true`].[Key, LastModified, StorageClass]' \
        --output text | while read -r KEY DATE STORAGE; do

        # Skip non-standard storage
        [[ "$STORAGE" != "STANDARD" ]] && continue

        # Skip old logs
        MOD_TS=$(date -d "$DATE" +%s)
        (( MOD_TS < CUTOFF_DATE )) && continue

        TMP_FILE="$BOX_DIR/$(basename "$KEY")"
        OUT_FILE="$BOX_DIR/$(basename "${KEY%.gz}_STM_LOG.txt")"

        log "[$BOX_ID] Downloading $KEY"
        aws s3 cp "s3://$SRC_BUCKET/$KEY" "$TMP_FILE" --quiet || { log "[$BOX_ID] Download failed"; continue; }

        # Skip FASE logs
        if zcat "$TMP_FILE" | grep -q "airfi-cmd\.sh --list: FASE='on'"; then
            log "[$BOX_ID] Skipped (FASE=on)"
            if ! grep -q "^$BOX_ID$" "$SKIPPED_BOXES_FILE"; then
                echo "$BOX_ID" >> "$SKIPPED_BOXES_FILE"
            fi
            rm -f "$TMP_FILE"
            continue
        fi

        # Skip logs containing LTC4156 in the first log
        if zcat "$TMP_FILE" | grep -m 1 "LTC4156" >/dev/null; then
            log "[$BOX_ID] Skipped (LTC4156 found in first log)"
            if ! grep -q "^$BOX_ID$" "$SKIPPED_BOXES_FILE"; then
                echo "$BOX_ID" >> "$SKIPPED_BOXES_FILE"
            fi
            rm -f "$TMP_FILE"
            continue
        fi

        log "[$BOX_ID] Parsing log"
        extract_stm_log "$TMP_FILE" "$OUT_FILE"

        DST_KEY="${KEY%.gz}_STM_LOG.txt"
        log "[$BOX_ID] Uploading processed log"
        aws s3 cp "$OUT_FILE" "s3://$DST_BUCKET/$DST_KEY" --quiet

        rm -f "$TMP_FILE" "$OUT_FILE"
        log "[$BOX_ID] ✅ Completed $KEY"

    done
done

log "All selected boxes processed successfully."
