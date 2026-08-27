# The Guy - Kenya OSRM routing service
#
# Uses the official OSRM backend image. The Kenya OpenStreetMap extract is
# preprocessed (extract -> partition -> customize) into an MLD routing graph
# stored on a Railway Volume mounted at /data. osrm-routed then serves that
# prebuilt graph; the graph is NOT rebuilt on every deploy.
#
# Pin a known-good image digest/tag rather than :latest for reproducible builds.

FROM ghcr.io/project-osrm/osrm-backend:v5.27.1

# curl (for prepare.sh to download the Kenya PBF) and ca-certificates (so curl
# can verify the HTTPS connection to Geofabrik) are not present in the base
# image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /data

# Entrypoint/preparation scripts (they live under /opt in the image).
COPY start.sh /opt/start.sh
COPY prepare.sh /opt/prepare.sh
COPY healthcheck.sh /opt/healthcheck.sh

RUN chmod +x /opt/start.sh /opt/prepare.sh /opt/healthcheck.sh

EXPOSE 5000

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD /opt/healthcheck.sh || exit 1

ENTRYPOINT ["/opt/start.sh"]
