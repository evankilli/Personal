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
  resward_cnt.count as count
  resward_cnt.fid as fid
  wards.ward_name as ward_name
  wards.geom as geom
  from resward_cnt
  inner join wards
  on resward_cnt.fid = wards.fid
-- joining resward_cnt w ward geometries to get a map of wards with counts of residences
