#!/bin/bash

# ==== CONFIGURATION ====
CLIENT_ID="0oa1jg4mt7iWfVpYc358"
CLIENT_SECRET="6f2n514tlRVhC7bGk1u4xKG8ksfSA1lh9XBF5Nsmnbq1Ptv6M7xg-1v25MRmEzZK"
INPUT_FILE="qkview_links.txt"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
OUTPUT_FILE="qkview_summary_${TIMESTAMP}.csv"
CPU_CMD_ID="81aab6fd832ed03b46618cc17c5ec6606eda26b5"
VERSION_CMD_ID="ab7a44c83cbb6c937f1405c611614902e77ab8ee"


# ==== ENCODE TO BASE64 ====
BASIC_AUTH=$(printf "%s:%s" "$CLIENT_ID" "$CLIENT_SECRET" | base64)

# ==== RETRIEVE ACCESS TOKEN ====
TOKEN_RESPONSE=$(curl -s --request POST "https://identity.account.f5.com/oauth2/ausp95ykc80HOU7SQ357/v1/token" \
  --header "accept: application/json" \
  --header "authorization: Basic $BASIC_AUTH" \
  --header "content-type: application/x-www-form-urlencoded" \
  --data "grant_type=client_credentials&scope=ihealth")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d':' -f2 | tr -d '"')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Failed to retrieve access token"
  exit 1
else
  echo "✅ Token acquired"
fi

# ==== FUNCTION: Decode Command Output ====
get_decoded_command_output() {
  local qkview_id=$1
  local command_id=$2

  local encoded_output
  encoded_output=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Accept: application/vnd.f5.ihealth.api" \
    -H "User-Agent: MyGreatiHealthClient" \
    "https://ihealth2-api.f5.com/qkview-analyzer/api/qkviews/${qkview_id}/commands/${command_id}" | \
    grep -oE "<output>.*</output>" | sed -E 's/<\/?output>//g')

  if [[ -n "$encoded_output" ]]; then
    echo "$encoded_output" | base64 -D
  else
    echo ""
  fi
}

# ==== FUNCTION: Extract Avg CPU ====

get_avg_cpu() {
  local qkview_id=$1
  local decoded
  decoded=$(get_decoded_command_output "$qkview_id" "$CPU_CMD_ID")

  if [[ -n "$decoded" ]]; then
    echo "$decoded" | awk '/System CPU Usage/ {getline; getline} /Utilization/ {print $(NF-1); exit}'
  else
    echo "N/A"
  fi
}

#=====GET VERSION =====

get_software_version() {
  local qkview_id=$1
  local decoded
  decoded=$(get_decoded_command_output "$qkview_id" "$VERSION_CMD_ID")

  if [[ -n "$decoded" ]]; then
    echo "$decoded" | awk '/^  Version/ { print $2; exit }'
  else
    echo "N/A"
  fi
}



# ==== WRITE CSV HEADER ====
echo "QKView ID,Hostname,Description,Status,Generation Date,File Size (bytes),Chassis Serial,Avg CPU (%),Software Version" > "$OUTPUT_FILE"


# ==== MAIN LOOP ====
while IFS= read -r line; do
  QKVIEW_ID=$(echo "$line" | sed -n 's|.*/qv/\([0-9]*\)/.*|\1|p')

  if [ -n "$QKVIEW_ID" ]; then
    echo "📡 Processing QKView ID: $QKVIEW_ID"

    RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Accept: application/vnd.f5.ihealth.api" \
         -H "User-Agent: MyGreatiHealthClient" \
         "https://ihealth2-api.f5.com/qkview-analyzer/api/qkviews/$QKVIEW_ID")

    HOSTNAME=$(echo "$RESPONSE" | xmllint --xpath 'string(//hostname)' - 2>/dev/null | xargs)
    DESCRIPTION=$(echo "$RESPONSE" | xmllint --xpath 'string(//description)' - 2>/dev/null | xargs)
    STATUS=$(echo "$RESPONSE" | xmllint --xpath 'string(//processing_status)' - 2>/dev/null | xargs)
    GEN_DATE=$(echo "$RESPONSE" | xmllint --xpath 'string(//generation_date)' - 2>/dev/null | xargs)
    FILE_SIZE=$(echo "$RESPONSE" | xmllint --xpath 'string(//file_size)' - 2>/dev/null | xargs)
    SERIAL_NUMBER=$(echo "$RESPONSE" | xmllint --xpath 'string(//chassis_serial)' - 2>/dev/null | xargs)
    HUMAN_DATE=$(date -r $((GEN_DATE / 1000)) "+%Y-%m-%d %H:%M:%S" 2>/dev/null)

    AVG_CPU=$(get_avg_cpu "$QKVIEW_ID")
    SOFTWARE_VERSION=$(get_software_version "$QKVIEW_ID")

    echo "$QKVIEW_ID,\"$HOSTNAME\",\"$DESCRIPTION\",$STATUS,\"$HUMAN_DATE\",$FILE_SIZE,\"$SERIAL_NUMBER\",$AVG_CPU,\"$SOFTWARE_VERSION\"" >> "$OUTPUT_FILE"
    echo "✅ Saved: $QKVIEW_ID"
  else
    echo "⚠️  Invalid QKView link: $line"
  fi
done < "$INPUT_FILE"
