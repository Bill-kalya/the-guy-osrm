#!/bin/sh
#
# The Guy - Kenya OSRM preprocessing (MLD pipeline).
#
# Downloads the Kenya OpenStreetMap extract from Geofabrik (if not already
# present) and builds an MLD routing graph. This is memory/disk intensive and
# should only run once; the resulting graph persists on the /data volume.

set -eu

DATA_DIR="/data"
PBF_FILE="${DATA_DIR}/kenya.osm.pbf"
OSRM_FILE="${DATA_DIR}/kenya.osrm"
OSRM_PROFILE="${OSRM_PROFILE:-/opt/car.lua}"

# Geofabrik Kenya extract. Use the dated snapshot filename if you want a
# specific release; kenya-latest.osm.pbf always points at the newest one.
PBF_URL="${PBF_URL:-https://download.geofabrik.de/africa/kenya-latest.osm.pbf}"

mkdir -p "${DATA_DIR}"

if [ ! -f "${PBF_FILE}" ]; then
    echo "[prepare] Downloading Kenya OSM data from ${PBF_URL} ..."
    # Follow redirects (Geofabrik redirects kenya-latest to a dated file) and
    # resume partial downloads across retries.
    curl -fL --retry 3 --retry-delay 5 -C - \
        -o "${PBF_FILE}" "${PBF_URL}"
else
    echo "[prepare] Using existing PBF: ${PBF_FILE}"
fi

echo "========================================"
echo "STEP 1/3: OSRM EXTRACT"
echo "========================================"
osrm-extract -p "${OSRM_PROFILE}" "${PBF_FILE}"

echo "========================================"
echo "STEP 2/3: OSRM PARTITION"
echo "========================================"
osrm-partition "${OSRM_FILE}"

echo "========================================"
echo "STEP 3/3: OSRM CUSTOMIZE"
echo "========================================"
osrm-customize "${OSRM_FILE}"

echo "========================================"
echo "OSRM PREPROCESSING COMPLETE"
echo "========================================"

# Remove the source PBF to free disk on the volume.
rm -f "${PBF_FILE}"

echo "[prepare] Kenya routing graph ready."
