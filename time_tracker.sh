#!/bin/bash

# JSON files to store logs
TIMESTAMP_FILE="$HOME/apps/time_tracker/timestamps.json"
TOTAL_FILE="$HOME/apps/time_tracker/totals.json"

# Function to show usage
usage() {
  echo "Usage: $0 [start|stop|status] [category]"
  echo "start   : Start tracking time for a category."
  echo "stop    : Stop tracking time for a category."
  echo "status  : Show total time spent on each category."
  exit 1
}

# Initialize JSON files if they don’t exist
init_files() {
  [ ! -f "$TIMESTAMP_FILE" ] && echo "[]" > "$TIMESTAMP_FILE"
  [ ! -f "$TOTAL_FILE" ] && echo "{}" > "$TOTAL_FILE"
}

# Function to validate category names
validate_category() {
  if [[ -z "$1" || ! "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: Invalid category name. Use alphanumeric characters, hyphens, or underscores."
    exit 1
  fi
}

# Read JSON file into a variable
read_json() {
  cat "$1"
}

# Write JSON to a file
write_json() {
  echo "$2" > "$1"
}

# Function to start tracking time for a category
start_timer() {
  category=$1
  validate_category "$category"
  init_files
  timestamp=$(date +%s)

  # Load existing timestamps
  timestamps=$(read_json "$TIMESTAMP_FILE")

  # Check if there’s an unmatched START for this category
  if echo "$timestamps" | jq -e ".[] | select(.category==\"$category\" and .event==\"START\" and .matched==false)" > /dev/null; then
    echo "Warning: There’s already an active timer for '$category'. Stop it before starting a new session."
    exit 1
  fi

  # Add a new START event directly to timestamps.json
  updated_timestamps=$(echo "$timestamps" | jq --arg cat "$category" --arg time "$timestamp" \
    '. + [{event: "START", category: $cat, timestamp: ($time | tonumber), matched: false}]')
  write_json "$TIMESTAMP_FILE" "$updated_timestamps"

  echo "Started tracking time for '$category'."
}

# Function to stop tracking time for a category
stop_timer() {
  category=$1
  validate_category "$category"
  init_files
  timestamp=$(date +%s)

  # Load timestamps
  timestamps=$(read_json "$TIMESTAMP_FILE")

  # Find the last unmatched START event for this category
  last_start=$(echo "$timestamps" | jq ". | map(select(.category==\"$category\" and .event==\"START\" and .matched==false)) | last")
  
  # Exit if no unmatched START found
  if [ "$last_start" = "null" ]; then
    echo "Error: No active timer for category '$category'."
    exit 1
  fi

  # Extract timestamp of last unmatched START event
  last_start_time=$(echo "$last_start" | jq -r '.timestamp')

  # Calculate duration and mark START as matched
  session_duration=$((timestamp - last_start_time))
  updated_timestamps=$(echo "$timestamps" | jq --arg cat "$category" --argjson last_start_time "$last_start_time" \
    '(.[] | select(.category==$cat and .timestamp==($last_start_time | tonumber)).matched) = true')

  # Append STOP event to timestamps.json
  updated_timestamps=$(echo "$updated_timestamps" | jq --arg cat "$category" --arg time "$timestamp" --arg dur "$session_duration" \
    '. + [{event: "STOP", category: $cat, timestamp: ($time | tonumber), duration: ($dur | tonumber)}]')
  write_json "$TIMESTAMP_FILE" "$updated_timestamps"

  # Update or add cumulative time and session count in totals.json
  totals=$(read_json "$TOTAL_FILE")
  total_time=$(echo "$totals" | jq -r --arg cat "$category" '.[$cat].time // 0')
  session_count=$(echo "$totals" | jq -r --arg cat "$category" '.[$cat].sessions // 0')
  new_total=$((total_time + session_duration))
  new_session_count=$((session_count + 1))
  updated_totals=$(echo "$totals" | jq --arg cat "$category" --argjson time "$new_total" --argjson sessions "$new_session_count" \
    '.[$cat] = {time: $time, sessions: $sessions}')
  write_json "$TOTAL_FILE" "$updated_totals"

  echo "Stopped tracking time for '$category'. Total time: $(format_time "$new_total")."
}

# Function to format time in human-readable format
format_time() {
  total_seconds=$1
  hours=$((total_seconds / 3600))
  minutes=$(( (total_seconds % 3600) / 60 ))
  seconds=$((total_seconds % 60))

  if [ "$hours" -gt 0 ]; then
    printf "%d hours, %d minutes, and %d seconds" "$hours" "$minutes" "$seconds"
  elif [ "$minutes" -gt 0 ]; then
    printf "%d minutes and %d seconds" "$minutes" "$seconds"
  else
    printf "%d seconds" "$seconds"
  fi
}

# Function to show status (total time spent on each category and session count)
show_status() {
  init_files
  totals=$(read_json "$TOTAL_FILE")
  if [ "$(echo "$totals" | jq length)" -eq 0 ]; then
    echo "No tracked categories yet."
    return
  fi

  echo "Category           | Sessions | Total Time"
  echo "-------------------|----------|-----------"
  echo "$totals" | jq -r 'to_entries[] | "\(.key):\(.value.sessions):\(.value.time)"' | while IFS=":" read -r category sessions seconds; do
    # Remove any leading/trailing whitespace from seconds
    seconds=$(echo "$seconds" | xargs)
    printf "%-18s| %-9s| %s\n" "$category" "$sessions" "$(format_time "$seconds")"
  done
}

# Ensure there is at least one argument
if [ $# -lt 2 ]; then
  usage
fi

# Command action
action=$1
category=$2

case $action in
  start)
    start_timer "$category"
    ;;
  stop)
    stop_timer "$category"
    ;;
  status)
    show_status
    ;;
  *)
    usage
    ;;
esac
