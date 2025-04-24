#!/bin/bash

# ==== CONFIGURATION ====
CLIENT_ID="0oa1jg4mt7iWfVpYc358"
CLIENT_SECRET="6f2n514tlRVhC7bGk1u4xKG8ksfSA1lh9XBF5Nsmnbq1Ptv6M7xg-1v25MRmEzZK"
INPUT_FILE="qkview_links.txt"
TIMESTAMP=$(date "+%Y%m%d_%H%M%S")
OUTPUT_FILE="qkview_summary_${TIMESTAMP}.csv"

# ==== ENCODE TO BASE64 ====
BASIC_AUTH=$(printf "%s:%s" "$CLIENT_ID" "$CLIENT_SECRET" | base64)

# ==== RETRIEVE ACCESS TOKEN ====
TOKEN_RESPONSE=$(curl -s --request POST "https://identity.account.f5.com/oauth2/ausp95ykc80HOU7SQ357/v1/token" \
  --header "accept: application/json" \
  --header "authorization: Basic $BASIC_AUTH" \
  --header "cache-control: no-cache" \
  --header "content-type: application/x-www-form-urlencoded" \
  --data "grant_type=client_credentials&scope=ihealth")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d':' -f2 | tr -d '"')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ Failed to retrieve access token"
  exit 1
fi

# ==== PREPARE CSV OUTPUT ====
if [ ! -f "$OUTPUT_FILE" ]; then
  echo "QKView ID,Hostname,Description,Status,Generation Date,File Size (bytes),Chassis Serial" > "$OUTPUT_FILE"
fi

# ==== PROCESS EACH QKVIEW LINK ====
while IFS= read -r line; do
  QKVIEW_ID=$(echo "$line" | sed -n 's|.*/qv/\([0-9]*\)/.*|\1|p')

  if [ -n "$QKVIEW_ID" ]; then
    echo "📡 Fetching QKView ID: $QKVIEW_ID"

    RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" \
         -H "Accept: application/vnd.f5.ihealth.api" \
         -H "User-Agent: MyGreatiHealthClient" \
         "https://ihealth2-api.f5.com/qkview-analyzer/api/qkviews/$QKVIEW_ID")

    # Extract XML fields
    HOSTNAME=$(echo "$RESPONSE" | xmllint --xpath 'string(//hostname)' - 2>/dev/null | xargs)
    DESCRIPTION=$(echo "$RESPONSE" | xmllint --xpath 'string(//description)' - 2>/dev/null | xargs)
    STATUS=$(echo "$RESPONSE" | xmllint --xpath 'string(//processing_status)' - 2>/dev/null | xargs)
    GEN_DATE=$(echo "$RESPONSE" | xmllint --xpath 'string(//generation_date)' - 2>/dev/null | xargs)
    FILE_SIZE=$(echo "$RESPONSE" | xmllint --xpath 'string(//file_size)' - 2>/dev/null | xargs)
    SERIAL_NUMBER=$(echo "$RESPONSE" | xmllint --xpath 'string(//chassis_serial)' - 2>/dev/null | xargs)
    GEN_DATE=$(echo "$RESPONSE" | xmllint --xpath 'string(//generation_date)' - 2>/dev/null | xargs)
    HUMAN_DATE=$(date -r $((GEN_DATE / 1000)) "+%Y-%m-%d %H:%M:%S" 2>/dev/null)

    # Append to CSV
    echo "$QKVIEW_ID,\"$HOSTNAME\",\"$DESCRIPTION\",$STATUS,\"$HUMAN_DATE\",$FILE_SIZE,\"$SERIAL_NUMBER\"" >> "$OUTPUT_FILE"
    echo "✅ Saved!"
  else
    echo "⚠️  Invalid QKView link: $line"
  fi
done < "$INPUT_FILE"
