#!/bin/sh
#
# The Guy - Kenya OSRM graph provisioning.
#
# Downloads a PREBUILT MLD routing graph (a gzipped tarball of the kenya.osrm.*
# files) and unpacks it onto the /data volume. This avoids the expensive,
# memory-hungry extract/partition/customize step in production and, critically,
# avoids depending on Geofabrik's download server (which Railway's egress
# cannot always reach).
#
# The tarball is produced once by a maintenance job (see
# preprocess-from-pbf.sh) and hosted on a GitHub Release (or S3/R2/B2), then
# pointed at via GRAPH_URL.

set -eu

DATA_DIR="/data"
GRAPH_TARBALL="${DATA_DIR}/kenya-osrm-graph.tar.gz"
OSRM_FILE="${DATA_DIR}/kenya.osrm"

# URL of the prebuilt graph tarball. REQUIRED in production.
GRAPH_URL="${GRAPH_URL:-}"

mkdir -p "${DATA_DIR}"

if [ -z "${GRAPH_URL}" ]; then
    echo "[prepare] FATAL: GRAPH_URL is not set. "
    echo "[prepare] Point it at the hosted kenya-osrm-graph.tar.gz (GitHub Release / R2 / B2)."
    exit 1
fi

echo "[prepare] Downloading prebuilt Kenya OSRM graph from ${GRAPH_URL} ..."
# -f  fail on HTTP errors
# -L  follow redirects (GitHub Release assets redirect to a CDN)
# --retry / --retry-delay  resilient to transient failures
# -C -  resume a partial download across retries
curl -fL --retry 5 --retry-delay 5 -C - \
    -o "${GRAPH_TARBALL}" "${GRAPH_URL}"

echo "[prepare] Unpacking graph tarball ..."
tar xzf "${GRAPH_TARBALL}" -C "${DATA_DIR}"

# Reject a bad download (e.g. HTML error page saved as the tarball) before we
# tell the server it's ready.
if [ ! -f "${OSRM_FILE}.properties" ]; then
    echo "[prepare] FATAL: tarball did not contain a valid OSRM graph (no kenya.osrm.properties)."
    rm -f "${GRAPH_TARBALL}"
    exit 1
fi

echo "[prepare] Removing tarball to free volume space ..."
rm -f "${GRAPH_TARBALL}"

echo "[prepare] Kenya routing graph ready."
