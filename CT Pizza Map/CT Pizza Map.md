# CT Pizza map

## Goal

Some goals for this project include:
- Find the closest pizza trail pizza joint across the State
- Practice making a shiny app or leaflet map
- Practice network analysis


## Data

Data I'll need includes:
- [CT Pizza Trail](https://ctvisit.com/articles/connecticut-pizza-trail?utm_source=google&utm_medium=cpc&utm_campaign=COT-Fall-OutOfState-Tourism-Google-Conversions-PMAX-N/A-FALL-N/A&gad_source=1&gad_campaignid=22387171364&gbraid=0AAAAADxHotLC-_eSOf-TMFGBwltH8BO-o&gclid=CjwKCAjwpOfHBhAxEiwAm1SwEintkB3tituXmpisS2KHtUThWmDKbbdyqD2_adrxJ22S1vWxZkUhZhoC0IcQAvD_BwE), map of 100 pizza places in CT broken down by style
  - Will need to use Google Maps API or something similar to georeference them
- CT road network
  - Stumbling block: no *comprehensive* data source; solution
    - Use combo of [functional class dataset](https://connecticut-ctdot.opendata.arcgis.com/maps/CTDOT::ctdot-roadway-classification-and-characteristic-data/about), guide to speed limits, and personal experience
- CT census blocks? CT lots? What's my lowest level of geographic analysis
  - May be able to ghet away without this

## Procedure
1. Basic prep
  1. Used CT Pizza Map locations and designations to create table of pizza trail locations
  1. Used comparison of official speed limits for various roads sharing a class and personal experience driving around the state to decde on speed limits - not worth looking for individual roadway speed limits; importantly, operating under assumption of only two-lane roads

| Functional Class | Code | Speed (mph) |
|---|---|---|
| Interstate | 1 | 65 |
| Local | 7 | 25 |
| Major Collector | 5 | 30 |
| Minor Collector | 6 | 30 |
| Minor Arterial | 4 | 40 |
| Other Freeway and Expressway | 2 | 60 |
| Other Principal Arterial | 3 | 35 |

1. Geocode pizza spots
  1. Put all the pizza spots into a CSV for geocoding - include name, city, state, country (plus category for further analysis)
  1. Get Google Maps API key; tested with OSM geocoding, but didn't get the results without an address (and I don't want to search for 100 street addresses if I don't need to!)
  1. Use MMQGIS geocoding tool to obtain points for all 100 spots
  1. Clean out duplicate spots (two found for Jordan's, )
  1. Save out layer of pizza spots
1. Prepare pizza spots further - since I want to do separate maps as well for the various types of pizza, we'll want separate layers for each type as well (I think)
  1. Extract by attribute for each type
  1. Save results out
1. Load in and prepare road network
  1. Load in road network with functional class
  1. Assign speed by functional class
1. Perform network analysis by points to create isochrone for each point


## sources
- [CT Pizza Trail](https://ctvisit.com/articles/connecticut-pizza-trail)
- [CT Roads](https://magic.lib.uconn.edu/connecticut_data.html)
  - [Info about road classifications](https://www2.census.gov/geo/pdfs/reference/mtfccs.pdf)
- Urban areas and state boundaries were found through [TIGER/Line](https://www.census.gov/cgi-bin/geo/shapefiles/index.php)
- [Guidance around speed limits](https://portal.ct.gov/dot/-/media/dot/osta/guidelines-for-establishing-speed-limits-in-the-state-of-connecticut-102021.pdf)

## suggested claude approach:

Happy to dive deep into pgRouting. It's a powerful extension that handles the heavy lifting of topology building and routing algorithms entirely within PostgreSQL/PostGIS.

---

## The Full pgRouting Pipeline

### Prerequisites & Setup

```sql
-- Enable the required extensions
CREATE EXTENSION postgis;
CREATE EXTENSION pgrouting;

-- Verify versions
SELECT postgis_full_version();
SELECT pgr_version();
```

Load your shapefile using `shp2pgsql` (command line) or `ogr2ogr`:

```bash
# shp2pgsql approach — reprojects to WGS84, creates spatial index
shp2pgsql -I -s <source_srid>:4326 roads.shp public.roads | psql -d mydb

# ogr2ogr approach — more format flexibility
ogr2ogr -f "PostgreSQL" PG:"dbname=mydb" roads.shp \
  -nln roads -t_srs EPSG:4326 -lco GEOMETRY_NAME=geom
```

---

### Step 1 — Inspect & Prepare the Table

After loading, your table will look something like this:

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'roads';
```

You need at minimum: a geometry column, a speed/cost attribute, and (optionally) a one-way indicator. Add the topology columns pgRouting expects:

```sql
ALTER TABLE roads
  ADD COLUMN IF NOT EXISTS source INTEGER,
  ADD COLUMN IF NOT EXISTS target INTEGER,
  ADD COLUMN IF NOT EXISTS cost DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS reverse_cost DOUBLE PRECISION;
```

---

### Step 2 — Fix Geometry Issues First

Before building topology, clean up common geometry problems:

```sql
-- Check for invalid geometries
SELECT id, ST_IsValidReason(geom)
FROM roads
WHERE NOT ST_IsValid(geom);

-- Fix invalid geometries
UPDATE roads
SET geom = ST_MakeValid(geom)
WHERE NOT ST_IsValid(geom);

-- Remove Z/M coordinates if present (they can confuse topology)
UPDATE roads
SET geom = ST_Force2D(geom);

-- Ensure consistent SRID
UPDATE roads
SET geom = ST_SetSRID(geom, 4326)
WHERE ST_SRID(geom) != 4326;
```

---

### Step 3 — Handle Roads That Cross But Don't Split

Raw shapefiles often have roads that geometrically intersect (an overpass crosses a highway) but share no node — or conversely, roads that *should* share an endpoint but have a tiny gap. `pgr_nodeNetwork` fixes both:

```sql
-- This splits all crossing lines and outputs a new clean table
SELECT pgr_nodeNetwork(
  'roads',        -- input table
  0.5,            -- tolerance in CRS units (meters if projected, degrees if 4326)
  'id',           -- primary key column
  'geom'          -- geometry column
);
-- Creates: roads_noded (split segments) and roads_noded_vertices_pgr (nodes)
```

> **Important:** If your data is in EPSG:4326 (degrees), the tolerance `0.5` means 0.5 degrees — enormous. Either project first to a meter-based CRS (e.g., UTM), or use a very small tolerance like `0.000005`. Projecting first is strongly recommended.

```sql
-- Better: project to a meter-based CRS before noding
ALTER TABLE roads
  ALTER COLUMN geom TYPE geometry(LineString, 32618)
  USING ST_Transform(geom, 32618);  -- UTM zone 18N as example
```

---

### Step 4 — Build the Topology

`pgr_createTopology` is the core step. It walks every edge, finds shared endpoints within your tolerance, and assigns integer `source` and `target` node IDs:

```sql
SELECT pgr_createTopology(
  'roads_noded',   -- table name (use the noded version)
  0.5,             -- snapping tolerance in CRS units
  'geom',          -- geometry column
  'id'             -- primary key
);
```

This does two things:
1. Populates `source` and `target` on every row in `roads_noded`
2. Creates `roads_noded_vertices_pgr` — a point table of every node with its geometry

```sql
-- Inspect results
SELECT COUNT(*) FROM roads_noded;                    -- edge count
SELECT COUNT(*) FROM roads_noded_vertices_pgr;       -- node count

-- Peek at the node table
SELECT id, ST_AsText(the_geom) FROM roads_noded_vertices_pgr LIMIT 5;

-- Verify source/target populated
SELECT id, source, target FROM roads_noded LIMIT 10;
```

---

### Step 5 — Compute Edge Costs

Cost is what routing minimizes. The two most common are **distance** and **travel time**. You can store both:

```sql
-- Travel time in seconds (length in meters / speed in m/s)
UPDATE roads_noded SET
  cost = ST_Length(geom) / (speed_limit * 1000.0 / 3600.0),
  reverse_cost = CASE
    -- One-way roads: make reverse direction prohibitively expensive
    WHEN oneway = 'yes'  THEN 1e10
    WHEN oneway = '-1'   THEN ST_Length(geom) / (speed_limit * 1000.0 / 3600.0)
    ELSE ST_Length(geom) / (speed_limit * 1000.0 / 3600.0)
  END;
```

One-way handling logic:

| `oneway` value | `cost` (forward) | `reverse_cost` |
|---|---|---|
| `'yes'` | normal travel time | `1e10` (blocked) |
| `'-1'` (reverse only) | `1e10` | normal travel time |
| `'no'` or null | normal | normal |

---

### Step 6 — Analyze Topology Quality

Before routing, verify the network is well-connected:

```sql
-- Check for isolated nodes (connected to nothing)
SELECT pgr_analyzeGraph('roads_noded', 0.5, 'geom', 'id');
-- Outputs counts of OK/isolated nodes and dead ends to server log

-- Inspect node connectivity directly
SELECT cnt, COUNT(*) AS num_nodes
FROM (
  SELECT v.id, COUNT(e.id) AS cnt
  FROM roads_noded_vertices_pgr v
  LEFT JOIN roads_noded e ON v.id = e.source OR v.id = e.target
  GROUP BY v.id
) sub
GROUP BY cnt ORDER BY cnt;
-- cnt=1 means dead end, cnt=0 means isolated (problem!)

-- Find dead ends (useful for validating edge of network)
SELECT v.*
FROM roads_noded_vertices_pgr v
JOIN roads_noded e ON v.id = e.source OR v.id = e.target
GROUP BY v.id, v.the_geom
HAVING COUNT(e.id) = 1;
```

---

### Step 7 — Routing Algorithms

pgRouting provides several algorithms. Choose based on your needs:

#### Dijkstra — reliable, exact, single or many pairs
```sql
-- Single pair
SELECT seq, node, edge, cost, agg_cost
FROM pgr_dijkstra(
  'SELECT id, source, target, cost, reverse_cost FROM roads_noded',
  start_node_id,   -- integer
  end_node_id,     -- integer
  directed := true
);

-- Many-to-one (useful for nearest facility problems)
SELECT * FROM pgr_dijkstra(
  'SELECT id, source, target, cost, reverse_cost FROM roads_noded',
  ARRAY[1, 5, 12],   -- multiple sources
  42,                -- single target
  directed := true
);
```

#### A-star — faster than Dijkstra using geographic heuristic
```sql
-- Requires x1,y1,x2,y2 columns on edges (centroid coordinates of endpoints)
ALTER TABLE roads_noded
  ADD COLUMN x1 FLOAT, ADD COLUMN y1 FLOAT,
  ADD COLUMN x2 FLOAT, ADD COLUMN y2 FLOAT;

UPDATE roads_noded SET
  x1 = ST_X(ST_StartPoint(geom)),
  y1 = ST_Y(ST_StartPoint(geom)),
  x2 = ST_X(ST_EndPoint(geom)),
  y2 = ST_Y(ST_EndPoint(geom));

SELECT seq, node, edge, cost, agg_cost
FROM pgr_aStar(
  'SELECT id, source, target, cost, reverse_cost, x1, y1, x2, y2
   FROM roads_noded',
  start_node_id,
  end_node_id,
  directed := true,
  heuristic := 4   -- Haversine; good for geographic coordinates
);
```

#### Traveling Salesman (TSP) — visit multiple stops optimally
```sql
SELECT * FROM pgr_TSP(
  $$SELECT * FROM pgr_dijkstraCostMatrix(
      'SELECT id, source, target, cost, reverse_cost FROM roads_noded',
      ARRAY[1, 5, 12, 33, 87],
      directed := true
  )$$,
  start_id := 1
);
```

---

### Step 8 — Finding Nearest Nodes to Arbitrary Points

In practice, your start/end points are coordinates, not node IDs. Map them:

```sql
-- Find the nearest network node to a given lat/lon
SELECT id
FROM roads_noded_vertices_pgr
ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(-73.985, 40.748), 4326)
LIMIT 1;

-- Wrap in a function for convenience
CREATE OR REPLACE FUNCTION nearest_node(lon FLOAT, lat FLOAT)
RETURNS INTEGER AS $$
  SELECT id FROM roads_noded_vertices_pgr
  ORDER BY the_geom <-> ST_SetSRID(ST_MakePoint(lon, lat), 4326)
  LIMIT 1;
$$ LANGUAGE SQL STABLE;

-- Then use it in routing
SELECT * FROM pgr_dijkstra(
  'SELECT id, source, target, cost, reverse_cost FROM roads_noded',
  nearest_node(-73.985, 40.748),
  nearest_node(-73.960, 40.770),
  directed := true
);
```

---

### Step 9 — Reconstruct the Route Geometry

Dijkstra returns node/edge IDs, not geometries. Join back to get the actual path:

```sql
WITH route AS (
  SELECT edge
  FROM pgr_dijkstra(
    'SELECT id, source, target, cost, reverse_cost FROM roads_noded',
    nearest_node(-73.985, 40.748),
    nearest_node(-73.960, 40.770),
    directed := true
  )
  WHERE edge != -1  -- -1 is the terminal pseudo-edge
)
SELECT
  ST_Union(e.geom)          AS route_geom,       -- merged line
  SUM(e.cost)               AS total_time_sec,
  SUM(ST_Length(e.geom))    AS total_length_m
FROM route r
JOIN roads_noded e ON r.edge = e.id;
```

---

### Step 10 — Performance at Scale

For large networks (millions of edges), add indexes:

```sql
-- Spatial index on node table (usually auto-created)
CREATE INDEX ON roads_noded_vertices_pgr USING GIST(the_geom);

-- Index on source/target for fast edge lookups
CREATE INDEX ON roads_noded(source);
CREATE INDEX ON roads_noded(target);

-- Partial index if filtering by road type
CREATE INDEX ON roads_noded(cost) WHERE cost < 1e9;
```

Also consider restricting the routing query to a bounding box for long routes:

```sql
-- Only route through edges within a corridor
SELECT * FROM pgr_dijkstra(
  'SELECT id, source, target, cost, reverse_cost
   FROM roads_noded
   WHERE geom && ST_Expand(
     ST_Envelope(ST_Collect(
       ST_SetSRID(ST_MakePoint(-73.985, 40.748), 4326),
       ST_SetSRID(ST_MakePoint(-73.960, 40.770), 4326)
     )), 0.05
   )',
  start_id, end_id, directed := true
);
```

---

### The Full Mental Model

```
Raw shapefile
     │
     ▼
Load into PostGIS (shp2pgsql / ogr2ogr)
     │
     ▼
Fix geometries (ST_MakeValid, ST_Force2D, project CRS)
     │
     ▼
pgr_nodeNetwork   ← splits crossing roads, closes gaps
     │
     ▼
pgr_createTopology ← assigns source/target node IDs
     │
     ▼
Compute cost/reverse_cost ← travel time, distance, or custom
     │
     ▼
pgr_analyzeGraph  ← validate connectivity
     │
     ▼
pgr_dijkstra / pgr_aStar / pgr_TSP ← route!
     │
     ▼
Join to geometry → export or serve via API
```

The big advantage over the pure Python approach is that every step — noding, topology, routing, geometry reconstruction — happens inside the database with optimized C extensions, so it scales to continent-sized road networks without breaking a sweat.