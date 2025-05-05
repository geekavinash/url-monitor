#!/bin/bash

# Defaults
INTERVAL=10
MAX_REQUESTS=3
URLS=()
OUTPUT_FILE="url_monitoring_results.csv"

# Parse args
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --interval)
      raw_interval="$2"
      INTERVAL_NUM=$(echo "$raw_interval" | grep -o '^[0-9]\+')
      INTERVAL_UNIT=$(echo "$raw_interval" | grep -o '[smh]$')
      case $INTERVAL_UNIT in
        s) INTERVAL=$INTERVAL_NUM ;;
        m) INTERVAL=$((INTERVAL_NUM * 60)) ;;
        h) INTERVAL=$((INTERVAL_NUM * 3600)) ;;
        *) echo "Invalid interval unit"; exit 1 ;;
      esac
      shift 2
      ;;
    --maxrequests)
      MAX_REQUESTS="$2"
      shift 2
      ;;
    --urls)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        URLS+=("$1")
        shift
      done
      ;;
    *)
      echo "Unknown option: $1"; exit 1 ;;
  esac
done

[[ ${#URLS[@]} -eq 0 ]] && { echo "No URLs passed"; exit 1; }

# Only write header if file doesn't exist
if [ ! -f "$OUTPUT_FILE" ]; then
  header="Timestamp"
  for i in "${!URLS[@]}"; do
    idx=$((i+1))
    header="$header,URL$idx,Status$idx,ResponseHeader$idx"
  done
  echo "$header" > "$OUTPUT_FILE"
fi

get_headers() {
  local url=$1
  local tmp_file=$(mktemp)

  curl -s --connect-timeout 10 --max-time 10 \
       -o /dev/null -H "Range: bytes=0-100" -v "$url" 2> "$tmp_file"

  status_code=$(grep '^< HTTP' "$tmp_file" | head -n 1 | awk '{print $3}')
  [ -z "$status_code" ] && status_code="ERROR"

  response_headers=$(grep '^< ' "$tmp_file" |
                     sed 's/^< //' | tr -d '\r' | tr '\n' ' ' |
                     sed 's/"/\\"/g')

  rm "$tmp_file"
  echo "$status_code|$response_headers"
}

# Monitor loop
for ((i = 1; i <= MAX_REQUESTS; i++)); do
  echo "🔁 Iteration $i of $MAX_REQUESTS"
  timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  row="\"$timestamp\""

  for url in "${URLS[@]}"; do
    result=$(get_headers "$url")
    status=$(echo "$result" | cut -d'|' -f1)
    headers=$(echo "$result" | cut -d'|' -f2)
    row="$row,\"$url\",\"$status\",\"$headers\""
  done

  echo "$row" >> "$OUTPUT_FILE"
  [[ $i -lt $MAX_REQUESTS ]] && sleep "$INTERVAL"
done

echo "✅ Appended results to $OUTPUT_FILE"
