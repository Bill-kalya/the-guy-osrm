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

- The **volume** is critical: the Kenya PBF (~333 MB) is preprocessed once into
  an MLD graph. That graph persists on `/data`, so it is **not rebuilt on every
  deploy**.
- OSRM is reachable **only on Railway's private network** (`*.railway.internal`).
  It is never exposed to the public internet.

## Layout

```
├── Dockerfile          # ghcr.io/project-osrm/osrm-backend, pinned
├── start.sh            # serves graph if present, else preprocesses first
├── prepare.sh          # download Kenya PBF → extract → partition → customize
├── healthcheck.sh      # tiny route query to confirm daemon is healthy
└── README.md
```

## Prepipeline (MLD)

```
kenya.osm.pbf
   → osrm-extract     (car.lua profile)
   → osrm-partition
   → osrm-customize
   → kenya.osrm.*g    (MLD routing graph)
   → osrm-routed --algorithm mld
```

## Local development / validation

Prerelease validation is done locally so we confirm the image + Kenya graph are
good **before** spending Railway resources.

```bash
# 1. Build the image
docker build -t the-guy-osrm .

# 2. Run with a local volume bound to /data (downloads + preprocesses Kenya on first boot)
docker run -d \
  --name the-guy-osrm \
  -p 5000:5000 \
  -v the-guy-osrm-data:/data \
  the-guy-osrm

# 3. Watch the log until preprocessing completes and the server starts
docker logs -f the-guy-osrm

# 4. Route test (Nairobi)
curl "http://localhost:5000/route/v1/driving/36.8219,-1.2921;36.8850,-1.2195?overview=full&geometries=geojson"
```

You should get `"code": "Ok"` with `distance`/`duration` and a
`geometry.coordinates` array of `[longitude, latitude]` points following real
roads — **not a straight line**.

## Deploying to Railway

1. Create a new **GitHub repo** from this directory and push it.
2. On Railway, create a **new service from that repo** (it auto-detects the
   root-level `Dockerfile`).
3. Attach a **Volume**:
   - Mount path: `/data`
   - Size: start with **25 GB** (graph ≈ several GB, plus headroom for the
     source PBF during preprocessing; the PBF is deleted after extraction).
4. Set `OSRM_PORT=5000` (optional; defaults to 5000).
5. Deploy. Preprocessing takes a while on first boot — watch service logs.
   Subsequent deploys/restarts will boot almost instantly from the volume.
6. Note the private DNS name (e.g. `the-guy-osrm.railway.internal`).

> **Memory**: processing a Kenya extract can require several GB of RAM. If the
> preprocess step dies with exit code `137` (OOM-killed), raise the service
> memory limit (start at ~4–8 GB) and redeploy. `osrm-routed` itself needs far
> less after the graph is built.

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
