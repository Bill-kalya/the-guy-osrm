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
OSRM_FILE="${DATA_DIR}/kenya.osrm"

# Download the tarball to a scratch location so the 466MB archive is NOT
# written next to the ~1.1GB unpacked graph on the /data volume at the same
# time. /tmp is in-memory (tmpfs) on most container platforms, which both keeps
# peak volume usage down to just the unpacked graph and avoids the
# "curl: (23) Failure writing output to destination" seen when the volume runs
# out of space mid-download. We do NOT use `-C -` (resume) here precisely
# because resuming into a stale partial file wedged the volume before.
GRAPH_TARBALL="/tmp/kenya-osrm-graph.tar.gz"

# URL of the prebuilt graph tarball. REQUIRED in production.
GRAPH_URL="${GRAPH_URL:-}"

# If the value was pasted as a full "GRAPH_URL=https://..." line (or any KEY=URL
# form) instead of just the URL, strip the "KEY=" prefix so curl gets a clean
# URL. This makes the container tolerant of how the env var is configured.
case "${GRAPH_URL}" in
    http*) : ;;
    *=*)   GRAPH_URL="${GRAPH_URL#*=}" ;;
esac

mkdir -p "${DATA_DIR}"
rm -f "${GRAPH_TARBALL}"

if [ -z "${GRAPH_URL}" ]; then
    echo "[prepare] FATAL: GRAPH_URL is not set. "
    echo "[prepare] Point it at the hosted kenya-osrm-graph.tar.gz (GitHub Release / R2 / B2)."
    exit 1
fi

echo "[prepare] Downloading prebuilt Kenya OSRM graph from ${GRAPH_URL} ..."
# -f  fail on HTTP errors
# -L  follow redirects (GitHub Release assets redirect to a CDN)
# --retry / --retry-delay  resilient to transient failures
curl -fL --retry 3 --retry-delay 3 -o "${GRAPH_TARBALL}" "${GRAPH_URL}"

echo "[prepare] Unpacking graph tarball ..."
# Tolerate archives wrapped in a single top-level directory (e.g. one created
# from a Docker volume as `tar czf graph.tar.gz data/...`). Detect a shared
# top-level component and strip it so the kenya.osrm.* files land directly in
# ${DATA_DIR}; already-flat archives are unpacked unchanged.
FIRST_ENTRY=$(tar tzf "${GRAPH_TARBALL}" 2>/dev/null | head -n1)
case "${FIRST_ENTRY}" in
    */*) STRIP_COMPONENTS="--strip-components=1" ;;
    *)   STRIP_COMPONENTS="" ;;
esac

tar xzf ${STRIP_COMPONENTS} "${GRAPH_TARBALL}" -C "${DATA_DIR}"
rm -f "${GRAPH_TARBALL}"

# Reject a bad download (e.g. an HTML error page saved as the tarball, or a
# truncated archive) before advertising readiness. These are the files
# osrm-routed --algorithm mld opens at startup (storage/io_config.hpp).
for REQUIRED_FILE in \
        "${OSRM_FILE}.properties" \
        "${OSRM_FILE}.mldgr" \
        "${OSRM_FILE}.partition" \
        "${OSRM_FILE}.cells"; do
    if [ ! -f "${REQUIRED_FILE}" ]; then
        echo "[prepare] FATAL: tarball did not contain a valid OSRM MLD graph (missing ${REQUIRED_FILE})."
        exit 1
    fi
done

echo "[prepare] Kenya routing graph ready."
