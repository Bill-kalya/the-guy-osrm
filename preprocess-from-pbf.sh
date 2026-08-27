#!/bin/sh
#
# The Guy - OSRM graph build (maintenance, run OFF-production).
#
# Builds a Kenya MLD routing graph from the raw OpenStreetMap extract and packs
# it into the tarball that prepare.sh later pulls onto the /data volume.
#
# Run this on a beefy machine (4-8GB+ RAM, several GB disk) OR locally with
# Docker to regenerate the graph when you want a fresh map. It does NOT belong
# in the Railway runtime path (Railway egress may not reach Geofabrik, and the
# extract is memory/disk heavy). Run it as a one-off, then upload the tarball.

# Example (local Docker):
#   docker run --rm -v $PWD/data:/data \
#     ghcr.io/project-osrm/osrm-backend:v5.27.1 \
#     /bin/sh -c '/opt/preprocess-from-pbf.sh'
#
# Produces: /data/kenya-osrm-graph.tar.gz  (~470MB compressed)

set -eu

DATA_DIR="/data"
PBF_FILE="${DATA_DIR}/kenya.osm.pbf"
OSRM_FILE="${DATA_DIR}/kenya.osrm"
OSRM_PROFILE="${OSRM_PROFILE:-/opt/car.lua}"
PBF_URL="${PBF_URL:-https://download.openstreetmap.fr/extracts/africa/kenya-latest.osm.pbf}"

mkdir -p "${DATA_DIR}"

if [ ! -f "${PBF_FILE}" ]; then
    echo "[build] Downloading Kenya OSM data from ${PBF_URL} ..."
    curl -fL --retry 5 --retry-delay 5 -C - -o "${PBF_FILE}" "${PBF_URL}"
fi

echo "STEP 1/3: OSRM EXTRACT"
osrm-extract -p "${OSRM_PROFILE}" "${PBF_FILE}"

echo "STEP 2/3: OSRM PARTITION"
osrm-partition "${OSRM_FILE}"

echo "STEP 3/3: OSRM CUSTOMIZE"
osrm-customize "${OSRM_FILE}"

echo "Packing graph tarball ..."
tar czf "${DATA_DIR}/kenya-osrm-graph.tar.gz" "${OSRM_FILE}".*

echo "Removing intermediate PBF ..."
rm -f "${PBF_FILE}"

echo "[build] Graph tarball ready: ${DATA_DIR}/kenya-osrm-graph.tar.gz"
