#!/bin/bash

# Configuration
GOAL_HOURS=${1:-4}
MODE=${2:-daily} # New argument: daily or weekly
WEEKLY_GOAL_HOURS=$(( GOAL_HOURS * 5 ))
API_URL="http://localhost:5600/api/0"
START_TIME_STR="07:30:00"

# Goal in seconds
GOAL_SEC=$(( GOAL_HOURS * 3600 ))
WEEK_GOAL_SEC=$(( WEEKLY_GOAL_HOURS * 3600 ))

# Fetch Bucket Name
BUCKET_NAME=$(curl -s "$API_URL/buckets" | jq -r 'keys[] | select(contains("aw-watcher-afk"))' | head -n 1)

if [ -z "$BUCKET_NAME" ]; then
    echo "{\"state\": \"Critical\", \"text\": \"AW Offline\"}"
    exit 1
fi

# Date & Expected Calculations
NOW=$(date +%s)
START_DAY_S=$(date -d "$START_TIME_STR" +%s)
EXPECTED_DAY_SEC=$(( NOW - START_DAY_S ))

[ $EXPECTED_DAY_SEC -lt 0 ] && EXPECTED_DAY_SEC=0
[ $EXPECTED_DAY_SEC -gt $GOAL_SEC ] && EXPECTED_DAY_SEC=$GOAL_SEC

DOW=$(date +%u)
DAYS_PASSED=$(( DOW - 1 ))
[ $DAYS_PASSED -gt 5 ] && DAYS_PASSED=5

if [ $DOW -ge 6 ]; then
    EXPECTED_WEEK_SEC=$(( DAYS_PASSED * GOAL_SEC ))
else
    EXPECTED_WEEK_SEC=$(( (DAYS_PASSED * GOAL_SEC) + EXPECTED_DAY_SEC ))
fi

# Fetch ActivityWatch Data
START_ISO=$(date -d "00:00:00" --iso-8601=seconds)
if [ $DOW -eq 1 ]; then
    START_WEEK_ISO=$(date -d "00:00:00" --iso-8601=seconds)
else
    START_WEEK_ISO=$(date -d "last monday 00:00:00" --iso-8601=seconds)
fi

# Helper function to format duration to HhMm
format_hm() {
    local total_sec=$1
    local h=$(( total_sec / 3600 ))
    local m=$(( (total_sec % 3600) / 60 ))
    echo "${h}h${m}m"
}

# FIXED: Wrapped format_hm inside standard command substitution $(...)
output_json() {
    local expected=$1 actual=$2 label=$3
    local diff state text

    if [ $actual -lt $expected ]; then
        diff=$(( expected - actual ))
        state="Warning"
        text="$label -$(format_hm $diff)"
    else
        diff=$(( actual - expected ))
        state="Good"
        text="$label +$(format_hm $diff)"
    fi

    echo "{\"state\": \"$state\", \"text\": \"$text\"}"
}

# Execute based on requested block mode
if [ "$MODE" = "weekly" ]; then
    WEEK_DATA=$(curl -s "$API_URL/buckets/$BUCKET_NAME/events?start=$START_WEEK_ISO")
    WEEK_SEC=$(echo "$WEEK_DATA" | jq '[.[] | select(.data.status == "not-afk") | .duration] | add // 0' | cut -d. -f1)
    output_json $EXPECTED_WEEK_SEC $WEEK_SEC "WEEK"
else
    # Hide daily metric entirely on weekends
    if [ $DOW -ge 6 ]; then
        echo "{}"
    else
        DAY_DATA=$(curl -s "$API_URL/buckets/$BUCKET_NAME/events?start=$START_ISO")
        DAY_SEC=$(echo "$DAY_DATA" | jq '[.[] | select(.data.status == "not-afk") | .duration] | add // 0' | cut -d. -f1)
        output_json $EXPECTED_DAY_SEC $DAY_SEC "DAY"
    fi
fi

