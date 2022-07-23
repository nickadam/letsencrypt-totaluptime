#!/bin/bash

TU_USERNAME=""
TU_PASSWORD=""
API_URL="https://api.totaluptime.com"

# Check vars
test -z "$TU_USERNAME" && \
  echo "ERROR: TU_USERNAME must be set" && exit 1
test -z "$TU_PASSWORD" && \
  echo "ERROR: TU_PASSWORD must be set" && exit 1

# Check deps
if ! which jq >/dev/null; then
  echo "ERROR: jq is required, https://stedolan.github.io/jq/" && exit 1
fi
if ! which curl >/dev/null; then
  echo "ERROR: curl is required, https://curl.se/" && exit 1
fi

# Get zone and record ids
ZONE_ID=$(cat "/tmp/CERTBOT_$CERTBOT_DOMAIN/ZONE_ID")
RECORD_ID=$(cat "/tmp/CERTBOT_$CERTBOT_DOMAIN/RECORD_ID")
test -z "$ZONE_ID" && \
  echo "ERROR: Failed to get ZONE_ID" 1>&2 && exit 1
test -z "$RECORD_ID" && \
  echo "ERROR: Failed to get RECORD_ID" 1>&2 && exit 1

# Delete the TXT record
RESPONSE=$(curl -s -u "$TU_USERNAME:$TU_PASSWORD" -X "DELETE" \
  -H "Accept: application/json" \
  "$API_URL/CloudDNS/Domain/$ZONE_ID/TXTRecord/$RECORD_ID")
