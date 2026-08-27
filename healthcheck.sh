#!/bin/sh
#
# Health check for the OSRM service. Performs a tiny route query against a
# downtown Nairobi point to confirm the daemon responds with code "Ok".
# Used by both the Docker HEALTHCHECK and Railway's TCP/HTTP checks.

set -eu

# Nairobi CBD self-route (start == end => trivial but valid query).
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    --max-time 10 \
    "http://127.0.0.1:${OSRM_PORT:-5000}/route/v1/driving/36.8219,-1.2921;36.8219,-1.2921?overview=false" \
    2>/dev/null || echo 000)

if [ "${STATUS}" = "200" ]; then
    echo "[health] OSRM OK (HTTP ${STATUS})"
    exit 0
fi

echo "[health] OSRM unhealthy (HTTP ${STATUS})"
exit 1
