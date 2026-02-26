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

# Create TXT record
# Strip wildcard prefix so *.hcpss.org is treated the same as hcpss.org
EFFECTIVE_DOMAIN="$CERTBOT_DOMAIN"
test "${CERTBOT_DOMAIN:0:2}" == "*." && \
  EFFECTIVE_DOMAIN="${CERTBOT_DOMAIN:2}"
DOMAIN_HOST=$(echo "$EFFECTIVE_DOMAIN" | sed "s/$DOMAIN$//" | sed 's/\.$//')
CREATE_DOMAIN="_acme-challenge.$DOMAIN_HOST"
# Check if we are validating a wildcard or top level domain
test -z "$DOMAIN_HOST" && \
  CREATE_DOMAIN="_acme-challenge"

# Always POST a new record - when both a base domain and its wildcard are in
# the same cert request, both tokens must coexist at the same DNS hostname
RECORD_ID=""
METHOD="POST"

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

# Make sure the change propagates over DNS
wait_for_dns_propagation() {
  local fqdn="$1"
  local expected="$2"
  local acme_record="_acme-challenge.${fqdn}"

  if [[ -z "$fqdn" || -z "$expected" ]]; then
    echo "Usage: wait_for_dns_propagation <hostname> <expected_txt_value>" >&2
    return 1
  fi

  # Extract the base domain (last two labels)
  local domain
  domain=$(echo "$fqdn" | awk -F. '{print $(NF-1)"."$NF}')

  echo "Waiting for TXT record at ${acme_record} to propagate..."
  echo "Expected value: ${expected}"
  echo "Looking up NS records for ${domain}..."

  # Get the list of nameservers
  local nameservers
  nameservers=$(dig +short NS "$domain" @8.8.8.8 | sed 's/\.$//')

  if [[ -z "$nameservers" ]]; then
    echo "ERROR: No NS records found for ${domain}" >&2
    return 1
  fi

  echo "Found nameservers:"
  echo "$nameservers" | sed 's/^/  /'
  echo ""

  for ns in $nameservers; do
    echo "Checking ${ns}..."
    while true; do
      local found=false

      # dig returns one TXT record per line, each wrapped in quotes
      while IFS= read -r line; do
        local value
        value=$(echo "$line" | tr -d '"')
        if [[ "$value" == "$expected" ]]; then
          found=true
          break
        fi
      done < <(dig +short TXT "${acme_record}" "@${ns}" 2>/dev/null)

      if [[ "$found" == true ]]; then
        echo "  ✔ ${ns} returned matching record"
        break
      else
        echo "  ✘ No matching TXT record on ${ns}, retrying in 5s..."
        sleep 5
      fi
    done
  done

  echo ""
  echo "DNS propagation complete for ${acme_record}"
}

if [ "$CREATE_DOMAIN" == "_acme-challenge" ]; then
  wait_for_dns_propagation "$DOMAIN" "$CERTBOT_VALIDATION"
else
  wait_for_dns_propagation "$DOMAIN_HOST.$DOMAIN" "$CERTBOT_VALIDATION"
fi
