# The Guy - Kenya OSRM routing service
#
# Uses the official OSRM backend image. The Kenya OpenStreetMap extract is
# preprocessed (extract -> partition -> customize) into an MLD routing graph
# stored on a Railway Volume mounted at /data. osrm-routed then serves that
# prebuilt graph; the graph is NOT rebuilt on every deploy.
#
# Pin a known-good image digest/tag rather than :latest for reproducible builds.

FROM ghcr.io/project-osrm/osrm-backend:v5.27.1

# curl (for prepare.sh to download the prebuilt graph tarball) and
# ca-certificates (so curl can verify HTTPS to the GitHub release / Geofabrik)
# are not present in the base image.
#
# The image is Debian Bullseye, which reached EOL: deb.debian.org no longer
# serves it, and archive.debian.org's debian-security only hosts suites up to
# buster (no bullseye-security exists there), so apt is pointed at the plain
# bullseye main archive where curl and ca-certificates live. Archived releases
# keep the Release valid-until in the past, hence Acquire::Check-Valid-Until=false.
RUN set -eux; \
    rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true; \
    echo "deb http://archive.debian.org/debian bullseye main" > /etc/apt/sources.list; \
    apt-get -o Acquire::Check-Valid-Until=false update; \
    apt-get -o Acquire::Check-Valid-Until=false install -y --no-install-recommends curl ca-certificates; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /data

# Entrypoint/preparation scripts (they live under /opt in the image).
COPY start.sh /opt/start.sh
COPY prepare.sh /opt/prepare.sh
COPY preprocess-from-pbf.sh /opt/preprocess-from-pbf.sh
COPY healthcheck.sh /opt/healthcheck.sh

RUN chmod +x /opt/start.sh /opt/prepare.sh /opt/preprocess-from-pbf.sh /opt/healthcheck.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD /opt/healthcheck.sh || exit 1

ENTRYPOINT ["/opt/start.sh"]
