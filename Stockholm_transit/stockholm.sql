/* 1 Isolate Stockholms kommun */

create table sholm as
  select osm_id, name, way as geom
  from se_polygon
  where admin_level = '7' and name = 'Stockholms kommun'

--------------------------------------------------------------------------------

/* 2 Isolate residences */

create table res_osm as
select osm_id, building, way as geom
from se_polygon
where building = 'yes' or building = 'residential'
-- SELECT

alter table res_osm
add column within_sholm INTEGER
-- create column so we can set at 1 when within city

update res_osm
  set within_sholm = 1
  from sholm
  where st_within(res_osm.geom, sholm.geom)
  -- give value of 1 where within sholm_tram

select within_sholm, count(osm_id)
from res_osm
group by within_sholm
-- check

delete from res_osm
  where within_sholm is null
  -- only sholm now!

--------------------------------------------------------------------------------

/* 3 Isolate transit stops */

/* create table sholm_tram as
select osm_id
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
-- option for breaking apart */

create table sholm_rail_transit as
select osm_id, name, railway, public_transport, way as geom
from se_point
where railway = 'tram_stop' or railway = 'station'
-- option for keeping together

alter table sholm_rail_transit
add column within_sholm INTEGER
-- create column so we can set at 1 when within city

update sholm_rail_transit
  set within_sholm = 1
  from sholm
  where st_within(sholm_rail_transit.geom, sholm.geom)
  -- give value of 1 where within sholm_tram

select within_sholm, count(osm_id)
from sholm_rail_transit
group by within_sholm
-- check

delete from sholm_rail_transit
  where within_sholm is null

----------- now for all transit ------------------------------------------------

create table sholm_transit as
select osm_id, name, railway, public_transport, highway, way as geom
from se_point
where public_transport = 'stop_position' or public_transport = 'station' or highway = 'bus_stop'

alter table sholm_transit
add column within_sholm INTEGER
-- create column so we can set at 1 when within city

update sholm_transit
  set within_sholm = 1
  from sholm
  where st_within(sholm_transit.geom, sholm.geom)
  -- give value of 1 where within sholm_tram

select within_sholm, count(osm_id)
from sholm_transit
group by within_sholm
-- check

delete from sholm_transit
  where within_sholm is null

select railway, count(osm_id)
  from sholm_transit
  group by railway
--------------------------------------------------------------------------------

/* 4 Isolate stockholm neighborhoods */

create table sholm_hoods as
select osm_id, name, population, way as geom
from se_polygon
where admin_level = '9'
except
select osm_id, name, population, way as geom
from se_polygon
where name = 'Gustavsberg'
-- one admin_levl 9 showed up outside city, this deletes it

-- i know neighborhoods are admin level 10
-- imma use Stockholms kommun (admin level 7) as my boundaries
-- i wanna find all the polygons within this so I have stockholm subdivisions
-- looks like admin level 10 only exists within a subset of cities so I should be fine?

--------------------------------------------------------------------------------

/* 5 convert polygons to centroids */

/* Convert residence polygons to centroids */
create table res_osm_pt as
select osm_id, building, ST_CENTROID(geom) as geom
from res_osm

--------------------------------------------------------------------------------

/* 6 count residences within each district */

create table res_hood as
  select
  res_osm_pt.building as building,
  res_osm_pt.osm_id as osm_id,
  res_osm_pt.geom as point_geom,
  sholm_hoods.name as name
  from res_osm_pt
  join sholm_hoods
  on st_intersects(sholm_hoods.geom, res_osm_pt.geom)
  -- creating a table that joins ward id to each residence points

 create table reshood_cnt as
   select name, count(osm_id)
   from res_hood
   group by name
  -- creating a table that groups and counts residences in each ward

create table hood_w_res_cnt as
  select
  sholm_hoods.name as hood_name,
  reshood_cnt.count as count,
  sholm_hoods.geom as geom
  from reshood_cnt
  join sholm_hoods
  on reshood_cnt.name = sholm_hoods.name
-- joining resward_cnt w ward geometries to get a map of wards with counts of residences

--------------------------------------------------------------------------------

/* 7 count how many residences are within 1mi of a rail stop */
SELECT addgeometrycolumn('evan','res_osm_pt','utmgeom',32737,'POINT',2);
UPDATE res_osm_pt
SET utmgeom = ST_Transform(geom, 32737);
--prepare residences for analysis

SELECT addgeometrycolumn('evan','sholm_rail_transit','utmgeom',32737,'POINT',2);
UPDATE sholm_rail_transit
SET utmgeom = ST_Transform(geom, 32737);
-- prepare rail for Analysis


SELECT addgeometrycolumn('evan','sholm_transit','utmgeom',32737,'POINT',2);
UPDATE sholm_transit
SET utmgeom = ST_Transform(geom, 32737);
-- prepare all transit for Analysis


SELECT addgeometrycolumn('evan','hood_w_res_cnt','utmgeom',32737,'POLYGON',2);
UPDATE hood_w_res_cnt
SET utmgeom = ST_Transform(geom, 32737);
-- prepare hoods for analysis


ALTER TABLE res_osm_pt ADD COLUMN access_rail INTEGER;
ALTER TABLE res_osm_pt ADD COLUMN access_all INTEGER;
-- add access to residential table

UPDATE res_osm_pt
SET access_rail = 1
FROM sholm_rail_transit
WHERE ST_DWITHIN(res_osm_pt.utmgeom, sholm_rail_transit.utmgeom, 402.34);
-- make access equal one when residence is within 1mi/1609.34m of rail transit

UPDATE res_osm_pt
SET access_all = 1
FROM sholm_transit
WHERE ST_DWITHIN(res_osm_pt.utmgeom, sholm_transit.utmgeom, 402.34);
-- make access equal one when residence is within 1mi/1609.34m of any transit

select *
from res_osm_pt
where access_rail is null
limit 1000;
select access_rail, count(osm_id)
from res_osm_pt
group by access_rail
-- lets check

select *
from res_osm_pt
where access_all is null
limit 1000;
select access_all, count(osm_id)
from res_osm_pt
group by access_all
-- lets check

CREATE TABLE res_within_rail AS
SELECT *
FROM res_osm_pt
WHERE access_rail = 1
-- table with only residences within buffer

CREATE TABLE res_within_all AS
SELECT *
FROM res_osm_pt
WHERE access_all = 1
-- table with only residences within buffer

--------------------------------------------------------------------------------

/* 8 join residential points within buffer zone to wards with count, count total
number of residences within buffer, and calc percentage */

create table hoods_w_rail_access as
  select
  a.hood_name as name , count(b.access_rail) as rail_access
  from hood_w_res_cnt a
  join res_within_rail b
  on st_intersects(a.geom, b.geom)
  group by a.hood_name
-- count residences with access in each ward

create table hoods_w_transit_access as
  select
  a.hood_name as name , count(b.access_all) as transit_access
  from hood_w_res_cnt a
  join res_within_all b
  on st_intersects(a.geom, b.geom)
  group by a.hood_name
-- how do i do the second join/count???


create table hoods_1 as
    select
    hood_w_res_cnt.hood_name as name,
    hood_w_res_cnt.count as total_count,
    hoods_w_rail_access.rail_access as rail_count,
    hood_w_res_cnt.geom as geom
    from hood_w_res_cnt
    full outer join hoods_w_rail_access
    on hood_w_res_cnt.hood_name = hoods_w_rail_access.name
-- join the wards with number with access to the table with the names,
-- total count, and geom

create table hoods_final as
    select
    hoods_1.name as name,
    hoods_1.total_count as total_count,
    hoods_1.rail_count as rail_count,
    hoods_w_transit_access.transit_access as transit_count,
    hoods_1.geom as geom
    from hoods_1
    join hoods_w_transit_access
    on hoods_1.name = hoods_w_transit_access.name

update hoods_final
  set rail_access = 0
  where rail_access is null;
update hoods_final
  set transit_access = 0
  where transit_access is null
-- make it 0 instead of null
-- not needed

ALTER TABLE hoods_final
ADD COLUMN pct_rail float(8);
UPDATE hoods_final
SET pct_rail = rail_count*1.0/total_count*1.0;
ALTER TABLE hoods_final
ADD COLUMN pct_transit float(8);
UPDATE hoods_final
SET pct_transit = transit_count*1.0/total_count*1.0;
-- calculate percentage
