/* 1 Isolate residences */

create table res_osm as
select "IDK WHAT COLUMNS I WANT YET"
from "GOD KNOWS WHERE"
where building = 'yes' or building = 'residential'

--------------------------------------------------------------------------------

/* 2 Isolate transit stops */

create table sholm_tram as
select "COLUMN"
from "GOD KNOWS WHERE"
where railway = 'tram_stop'

create table sholm_rail_transit_node as
select "column"
from "GNW"
where railway = 'station' and type = 'node'

create table sholm_rail_transit_area as
select "column"
from "GNW"
where railway = 'station' and type = 'area'
-- option for breaking apart

create table sholm_rail_transit as
select "column"
from "GNW"
where railway = 'tram_stop' or railway = 'station'
-- option for keeping together

create table sholm_transit as
select osm_id, building, way
from "GOD KNOWS WHERE"
where public_transport = 'stop_position'

--------------------------------------------------------------------------------

/* 3 Isolate stockholm neighborhoods */

create table sholm_hoods as
select geom, "OTHER COLUMNS"
from "GNW"

-- i know neighborhoods are admin level 10
-- imma use Stockholms kommun (admin level 7) as my boundaries
-- i wanna find all the polygons within this so I have stockholm subdivisions

--------------------------------------------------------------------------------

/* 4 convert polygons to centroids */

/* Convert residence polygons to centroids */
create table res_osm_pt as
select osm_id, building, ST_CENTROID(way) as geom
from res_osm

/* Convert stations to centroids */
create table sholm_rail_centroids as
  select osm_id, building, ST_CENTROID(way) as geom
  from sholm_rail_transit

create table sholm_transit_centroids as
  select osm_id, building, ST_CENTROID(way) as geom
  from sholm_transit

--------------------------------------------------------------------------------

/* 5 count residences within each district */

create table res_hood as
  select
  res_osm_pt.building as building,
  res_osm_pt.osm_id as osm_id,
  res_osm_pt.geom as point_geom,
  sholm_hoods."column" as "?????"
  from res_osm_pt
  join sholm_hoods
  on st_intersects(sholm_hoods.geom, res_osm_pt.geom)
  -- creating a table that joins ward id to each residence points

 create table reshood_cnt as
   select "?????", count(osm_id)
   from res_hood
   group by "?????"
  -- creating a table that groups and counts residences in each ward

create table hood_w_res_cnt as
  select
  reshood_cnt.count as count
  reshood_cnt."column" as "????"
  sholm_hoods.name as hood_name
  sholm_hoods.geom as geom
  from resward_cnt
  inner join wards
  on reshood_cnt."???" = sholm_hoods."???"
-- joining resward_cnt w ward geometries to get a map of wards with counts of residences

--------------------------------------------------------------------------------

/* 6 count how many residences are within 1mi of a clinic */
SELECT addgeometrycolumn('evan','res_osm_pt','utmgeom',32737,'POINT',2);
UPDATE res_osm_pt
SET utmgeom = ST_Transform(geom, 32737);
--prepare residences for analysis

SELECT addgeometrycolumn('evan','sholm_rail_centroids','utmgeom',32737,'POINT',2);
UPDATE sholm_rail_centroids
SET utmgeom = ST_Transform(geom, 32737);
-- prepare clinics for Analysis

SELECT addgeometrycolumn('evan','hood_w_res_cnt','utmgeom',32737,'POLYGON',2);
UPDATE hood_w_res_cnt
SET utmgeom = ST_Transform(geom, 32737);
-- prepare wards for analysis


ALTER TABLE res_osm_pt ADD COLUMN res_access_rail INTEGER;
ALTER TABLE res_osm_pt ADD COLUMN res_access_all INTEGER;
-- add access to residential table

UPDATE res_osm_pt
SET res_access_rail = 1
FROM sholm_rail_centroids
WHERE ST_DWITHIN(res_osm_pt.utmgeom, sholm_rail_centroids.utmgeom, "1609.34");
-- make access equal one when residence is within 1mi/1609.34m of rail transit

UPDATE res_osm_pt
SET res_access_all = 1
FROM sholm_transit_centroids
WHERE ST_DWITHIN(res_osm_pt.utmgeom, sholm_transit_centroids.utmgeom, "1609.34");
-- make access equal one when residence is within 1mi/1609.34m of any transit

select *
from res_osm_pt
where res_access_rail is null
limit 1000;
-- lets check

select *
from res_osm_pt
where res_access_all is null
limit 1000;
-- lets check

CREATE TABLE res_within_rail AS
SELECT *
FROM res_osm_pt
WHERE res_access_rail = 1
-- table with only residences within buffer

CREATE TABLE res_within_all AS
SELECT *
FROM res_osm_pt
WHERE res_access_all = 1
-- table with only residences within buffer

--------------------------------------------------------------------------------

/* 7 join residential points within buffer zone to wards with count, count total
number of residences within buffer, and calc percentage */

create table hoods_w_rail_access as
  select
  a."column", count(b.res_access_rail) as rail_access
  from hood_w_res_cnt a
  join res_within_rail b
  on st_intersects(a.geom, b.geom)
  group by a."column"
-- count residences with access in each ward

create table hoods_w_transit_access as
  select
  a."column", count(b.res_access_all) as transit_access
  from hood_w_res_cnt a
  join res_within_all b
  on st_intersects(a.geom, b.geom)
  group by a."column"
-- how do i do the second join/count???


create table hoods_1 as
    select
    hood_w_res_cnt."column" as "???",
    hood_w_res_cnt.name as name,
    hood_w_res_cnt.count as total_count,
    hoods_w_rail_access.rail_access as rail_access,
    hood_w_res_cnt.geom as geom
    from wards_w_res_cnt
    full outer join wards_w_access
    on hood_w_res_cnt."column" = hoods_w_rail_access."column"
-- join the wards with number with access to the table with the names,
-- total count, and geom

create table hoods_final as
    select
    hoods_1."column" as "???",
    hoods_1.name as name,
    hoods_1.total_count as total_count,
    hoods_1.rail_access as rail_access,
    hoods_w_transit_access.transit_access as transit_access
    hoods_1.geom as geom
    from hoods_1
    full outer join hoods_w_transit_access
    on hoods_1."column" = hoods_w_transit_access."column"

update hoods_final
  set rail_access = 0
  where rail_access is null;
update hoods_final
  set transit_access = 0
  where transit_access is null
-- make it 0 instead of null

ALTER TABLE hoods_final
ADD COLUMN pct_rail float(8);
UPDATE hoods_final
SET pct_rail = rail_access*1.0/total_count*1.0;
ALTER TABLE hoods_final
ADD COLUMN pct_transit float(8);
UPDATE hoods_final
SET pct_transit = transit_access*1.0/total_count*1.0;
-- calculate percentage
