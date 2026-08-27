# The Guy — Kenya OSRM Routing

Self-hosted [OSRM](https://github.com/Project-OSRM/osrm-backend) routing engine
for **The Guy**, preprocessed against the Kenya OpenStreetMap extract and served
over Railway's private network.

## Why this exists

The Guy's Spring Boot backend (`OsrmRoutingService`) needs real road routes. It
currently defaults to the public `router.project-osrm.org` demo server, which is
fine for launch but rate-limits at scale. This service hosts our own instance so
routing is unlimited, free, and backed by Kenyan road data.

## Architecture

```
Flutter (The Guy)
   │
   ▼
Spring Boot API
   │  ROUTING_PROVIDER_URL=http://the-guy-osrm.railway.internal:5000
   ▼
OSRM (this service) ── serves MLD graph
   │
   ▼
Railway Volume (/data) ── Kenya routing graph (persistent)
```

- The **volume** is critical: it holds the prebuilt MLD routing graph on `/data`,
  so it is **not rebuilt on every deploy** — the service boots instantly.
- OSRM is reachable **only on Railway's private network** (`*.railway.internal`).
  It is never exposed to the public internet.
- A **prebuilt graph tarball is pulled at first boot** (from a GitHub Release/S3/
  R2/B2 via `GRAPH_URL`) and unpacked onto the volume. The runtime never
  downloads a raw PBF or runs the memory-heavy extract — it only needs the
  already-processed graph.

## How the graph gets onto the volume

We do the expensive work **once, off-production**, then ship the result:

```
[maintenance]                      [Railway first boot]
kenya.osm.pbf                          GRAPH_URL
   → osrm-extract                          │
   → osrm-partition                        ▼
   → osrm-customize                prepare.sh downloads prebuilt
   → kenya.osrm.*g                  kenya-osrm-graph.tar.gz
   → tar czf → tarball (~470MB)        │ unpack onto /data
   → upload to GitHub Release           ▼
                                       serve via osrm-routed
```

Using a prebuilt tarball (rather than preprocessing on Railway) avoids two
problems: Railway's egress may not reach `download.geofabrik.de`, and extract/
partition/customize needs several GB of RAM.

## Layout

```
├── Dockerfile                  # ghcr.io/project-osrm/osrm-backend, pinned + curl
├── start.sh                    # serves graph if present, else provisions once
├── prepare.sh                  # pull + unpack prebuilt graph tarball (GRAPH_URL)
├── preprocess-from-pbf.sh      # maintenance: build graph from PBF + pack tarball
├── healthcheck.sh              # tiny route query to confirm daemon is healthy
└── README.md
```

## Prepipeline (MLD) — maintenance only

Build the graph fresh and pack it (run off-production, e.g. locally with Docker):

```
kenya.osm.pbf
   → osrm-extract     (car.lua profile)
   → osrm-partition
   → osrm-customize
   → kenya.osrm.*g    (MLD routing graph)
   → tar czf kenya-osrm-graph.tar.gz kenya.osrm.*
   → osrm-routed --algorithm mld
```

## Local development / validation

Prerelease validation is done locally so we confirm the image + Kenya graph are
good **before** spending Railway resources.

```bash
# 1. Build the image
docker build -t the-guy-osrm .

# 2a. Serve a prebuilt graph tarball locally (or set GRAPH_URL to a hosted one)
#     e.g. python -m http.server 8899  (serving kenya-osrm-graph.tar.gz)

# 2b. Run with a local volume; supplies the prebuilt tarball on first boot
docker run -d \
  --name the-guy-osrm \
  -p 5000:5000 \
  -e GRAPH_URL=http://host.docker.internal:8899/kenya-osrm-graph.tar.gz \
  -v the-guy-osrm-data:/data \
  the-guy-osrm

# 3. Watch the log until the graph is pulled + unpacked and the server starts
docker logs -f the-guy-osrm

# 4. Route test (Nairobi)
curl "http://localhost:5000/route/v1/driving/36.8219,-1.2921;36.8850,-1.2195?overview=full&geometries=geojson"
```

Building the graph fresh (maintenance only):

```bash
docker run --rm -v $PWD/data:/data the-guy-osrm /bin/sh -c '/opt/preprocess-from-pbf.sh'
```

You should get `"code": "Ok"` with `distance`/`duration` and a
`geometry.coordinates` array of `[longitude, latitude]` points following real
roads — **not a straight line**.

## Deploying to Railway

1. Create a new **GitHub repo** from this directory and push it.
2. Upload `kenya-osrm-graph.tar.gz` (~470 MB) as an asset of a **GitHub Release**
   on that repo (or to S3/R2/B2), and copy its direct download URL.
3. On Railway, create a **new service from that repo** (it auto-detects the
   root-level `Dockerfile`).
4. Attach a **Volume**:
   - Mount path: `/data`
   - Size: start with **25 GB** (graph ≈ 1.1 GB uncompressed, with headroom).
5. Set environment variables:
   - `GRAPH_URL=https://github.com/<you>/the-guy-osrm/releases/download/v1/kenya-osrm-graph.tar.gz`
   - `OSRM_PORT=5000` (optional; defaults to 5000).
6. Deploy. On first boot `prepare.sh` downloads + unpacks the graph onto the
   volume (a few minutes). Subsequent deploys/restarts boot almost instantly
   from the volume, **no re-download and no preprocessing**.
7. Note the private DNS name (e.g. `the-guy-osrm.railway.internal`).

> **Memory**: because we ship a prebuilt graph, the Railway service only runs
> `osrm-routed`, which needs modest RAM (~1–2 GB is plenty). If you ever run
> `preprocess-from-pbf.sh` on a Railway service it needs several GB, but you
> should not — build the tarball locally/off-production instead.

## Connecting The Guy's backend

Set the backend environment variable and redeploy:

```yaml
ROUTING_PROVIDER_URL=http://the-guy-osrm.railway.internal:5000
```

The backend keeps its existing Redis route cache in front of this service, so a
60-second TTL absorbs repeat queries.

## Test before switching traffic

```http
GET /route/v1/driving/36.8219,-1.2921;36.8850,-1.2195?overview=full&geometries=geojson
```

Expect:

```json
{
  "code": "Ok",
  "routes": [
    {
      "distance": 12345.6,
      "duration": 987.4,
      "geometry": { "coordinates": [ [36.8219, -1.2921], ... ], "type": "LineString" }
    }
  ]
}
```

## Roadmap / future

- **Traffic-aware ETAs**: OSRM's `osrm-customize` accepts segment-speed and
  turn-penalty updates. The Guy can later feed live provider speeds back in to
  make ETAs reflect real conditions ("Ngong Road is moving at 11 km/h today").
- **Alternative routes** and provider navigation via OSRM's other algorithms.
