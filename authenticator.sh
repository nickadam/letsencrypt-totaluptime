#!/bin/bash

API_URL="https://api.totaluptime.com"

# Check env vars
test -z "$TU_USERNAME" && \
  echo "ERROR: Environment variable TU_USERNAME must be set" && exit 1
test -z "$TU_PASSWORD" && \
  echo "ERROR: Environment variable TU_PASSWORD must be set" && exit 1

# Check deps
if ! which jq >/dev/null; then
  echo "ERROR: jq is required, https://stedolan.github.io/jq/" && exit 1
fi
if ! which curl >/dev/null; then
  echo "ERROR: curl is required, https://curl.se/" && exit 1
fi

# Strip only the top domain to get the zone id
DOMAIN=$(expr match "$CERTBOT_DOMAIN" '.*\.\(.*\..*\)')

# Must be a wildcard
test -z "$DOMAIN" && \
  DOMAIN="$CERTBOT_DOMAIN"

# Get the Total Uptime domain id
QUERY_PARAMS="?searchField=domainName&searchString=$DOMAIN&searchOper=eq"
ZONE_ID=$(curl -s -u "$TU_USERNAME:$TU_PASSWORD" -X GET \
  -H "Accept: application/json" \
  "$API_URL/CloudDNS/Domain/All$QUERY_PARAMS" | jq -r '.rows[0].id')
test "$ZONE_ID" == "null" && \
  echo "ERROR: Failed to retrieve domain id from Total Uptime API" && exit 1

# Create TXT record
DOMAIN_HOST=$(echo "$CERTBOT_DOMAIN" | sed "s/$CERTBOT_DOMAIN$//" | sed 's/\.$//')
CREATE_DOMAIN="_acme-challenge.$DOMAIN_HOST"
# Check if we are validating a wildcard domain
test -z "$DOMAIN_HOST" && \
  CREATE_DOMAIN="_acme-challenge"

# Check if TXT record already exists
QUERY_PARAMS="?searchField=txtHostName&searchString=$CREATE_DOMAIN&searchOper=eq"
RECORD_ID=$(curl -s -u "$TU_USERNAME:$TU_PASSWORD" -X GET \
  -H "Accept: application/json" \
  "$API_URL/CloudDNS/Domain/$ZONE_ID/TXTRecord/All$QUERY_PARAMS" | jq -r '.rows[0].id')
METHOD="PUT"
test "$RECORD_ID" != "null" && \
  RECORD_ID="/$RECORD_ID"
test "$RECORD_ID" == "null" && \
  RECORD_ID="" METHOD="POST"

# Create or update the TXT record
DATA="{\"txtHostName\":\"$CREATE_DOMAIN\",\"txtText\":\"$CERTBOT_VALIDATION\",\"txtTTL\":\"60\"}"
REQUEST_URI="$API_URL/CloudDNS/Domain/$ZONE_ID/TXTRecord$RECORD_ID"
RESPONSE=$(curl -s -u "$TU_USERNAME:$TU_PASSWORD" -X "$METHOD" \
  -H "Accept: application/json" "$REQUEST_URI" -d "$DATA")
RESPONSE_STATUS=$(echo "$RESPONSE" | jq -r '.status')
test "$RESPONSE_STATUS" != "Success" &&
  echo "ERROR: Failed to set TXT record using Total Uptime API, $REQUEST_URI, $DATA, $RESPONSE" && exit 1

# Set TXT record id
RECORD_ID=$(echo "$RESPONSE" | jq -r '.id')
test "$RECORD_ID" == "null" && \
  echo "ERROR: Failed to get record id after setting TXT record $CREATE_DOMAIN" && exit 1

# Save info for cleanup
test ! -d /tmp/CERTBOT_$CERTBOT_DOMAIN && \
  mkdir -m 0700 /tmp/CERTBOT_$CERTBOT_DOMAIN

echo $ZONE_ID > /tmp/CERTBOT_$CERTBOT_DOMAIN/ZONE_ID
echo $RECORD_ID > /tmp/CERTBOT_$CERTBOT_DOMAIN/RECORD_ID

# Sleep to make sure the change has time to propagate over to DNS
sleep 120
