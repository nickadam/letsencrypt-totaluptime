#!/bin/bash

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

# Strip only the top domain to get the zone id
DOMAIN=$(expr match "$CERTBOT_DOMAIN" '.*\.\(.*\..*\)')

# This must be a wildcard or top level domain
test -z "$DOMAIN" && \
  DOMAIN="$CERTBOT_DOMAIN"

# Get the Total Uptime domain id
QUERY_PARAMS="?searchField=domainName&searchString=$DOMAIN&searchOper=eq"
ZONE_ID=$(curl -s -u "$TU_USERNAME:$TU_PASSWORD" -X GET \
  -H "Accept: application/json" \
  "$API_URL/CloudDNS/Domain/All$QUERY_PARAMS" | jq -r '.rows[0].id')
test "$ZONE_ID" == "null" && \
  echo "ERROR: Failed to retrieve domain id from Total Uptime API" && exit 1

test -z "$ZONE_ID" && \
  echo "ERROR: Failed to get ZONE_ID" 1>&2 && exit 1

# Get TXT record
# Strip wildcard prefix so *.hcpss.org is treated the same as hcpss.org
EFFECTIVE_DOMAIN="$CERTBOT_DOMAIN"
test "${CERTBOT_DOMAIN:0:2}" == "*." && \
  EFFECTIVE_DOMAIN="${CERTBOT_DOMAIN:2}"
DOMAIN_HOST=$(echo "$EFFECTIVE_DOMAIN" | sed "s/$DOMAIN$//" | sed 's/\.$//')
DELETE_DOMAIN="_acme-challenge.$DOMAIN_HOST"
# Check if we are validating a wildcard or top level domain
test -z "$DOMAIN_HOST" && \
  DELETE_DOMAIN="_acme-challenge"

# Get all TXT records for the domain
RECORD_IDS=$(curl -s -u "$TU_USERNAME:$TU_PASSWORD" -X "GET" \
  -H "Accept: application/json" \
  "$API_URL/CloudDNS/Domain/$ZONE_ID/TXTRecord/All" | jq -r '.rows[] | select(.txtHostName == "'$DELETE_DOMAIN'") | .id')

test -z "$RECORD_IDS" && \
  echo "ERROR: Failed to get RECORD_IDS" 1>&2 && exit 1

for RECORD_ID in $RECORD_IDS; do
  # Delete the TXT record
  RESPONSE=$(curl -s -u "$TU_USERNAME:$TU_PASSWORD" -X "DELETE" \
    -H "Accept: application/json" \
    "$API_URL/CloudDNS/Domain/$ZONE_ID/TXTRecord/$RECORD_ID")
done
