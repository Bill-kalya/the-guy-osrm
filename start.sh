#!/bin/sh
#
# The Guy - Kenya OSRM entrypoint.
#
# If an MLD routing graph already exists on the /data volume, it is served
# directly. Otherwise the Kenya PBF is preprocessed once (the expensive step)
# and the resulting graph persists on the volume for subsequent restarts.
#
# `exec` is intentional so OSRM becomes the container PID 1 and Railway can
# manage the process lifecycle correctly (signals, restart, logs).

set -eu

DATA_DIR="/data"
PBF_FILE="${DATA_DIR}/kenya.osm.pbf"
OSRM_FILE="${DATA_DIR}/kenya.osrm"
OSRM_PORT="${OSRM_PORT:-5000}"

echo "========================================"
echo " The Guy - Kenya OSRM"
echo "========================================"

mkdir -p "${DATA_DIR}"

if [ -f "${OSRM_FILE}.properties" ]; then
    echo "[start] Existing OSRM graph found; skipping preprocessing."
else
    echo "[start] No OSRM graph found; beginning Kenya map preprocessing..."
    /opt/prepare.sh
fi

echo "[start] Starting OSRM server on :${OSRM_PORT} ..."

exec osrm-routed \
    --algorithm mld \
    --port "${OSRM_PORT}" \
    --max-table-size 10000 \
    "${OSRM_FILE}"
