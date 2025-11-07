/* 1 Isolate Stockholms kommun */

create table sholm as
  select osm_id, name, way as geom
  from se_polygon
  where admin_level = '7' and name = 'Stockholms kommun'
-- we need to make sure we're only looking at Stockholm and not adjacent suburbs

--------------------------------------------------------------------------------

/* 2 Isolate residences */

create table res_osm as
select osm_id, building, way as geom
from se_polygon
where building = 'yes' or building = 'residential'
-- select residences and unclassified buildings. Some mixed use buildings in dense areas are unclassified, and classification of buildings in particular on OpenStreetMap is imperfect, so a decision was made to err on the side of too many rather than too few residences

alter table res_osm
add column within_sholm INTEGER
-- create column so we can set at 1 when within city

update res_osm
  set within_sholm = 1
  from sholm
  where st_within(res_osm.geom, sholm.geom)
  -- give value of 1 where within Stockholm

select within_sholm, count(osm_id)
from res_osm
group by within_sholm
-- check, works!

delete from res_osm
  where within_sholm is null
  -- only Stockholm now!

--------------------------------------------------------------------------------

/* 3 Isolate transit stops */

create table sholm_rail_transit as
select osm_id, name, railway, public_transport, way as geom
from se_point
where railway = 'tram_stop' or railway = 'station'
-- Create table of tram stop and railway station points

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
-- check, all good!

delete from sholm_rail_transit
  where within_sholm is null
  -- delete where outside of Stockholm


----------- now for all transit ------------------------------------------------

create table sholm_transit as
select osm_id, name, railway, public_transport, highway, way as geom
from se_point
where public_transport = 'stop_position' or public_transport = 'station' or highway = 'bus_stop'
-- repeat process of creating table of transit stops using expanded parameters

alter table sholm_transit
add column within_sholm INTEGER
-- create column so we can set at 1 when within city

update sholm_transit
  set within_sholm = 1
  from sholm
  where st_within(sholm_transit.geom, sholm.geom)
  -- give value of 1 where within Stockholm

select within_sholm, count(osm_id)
from sholm_transit
group by within_sholm
-- check

delete from sholm_transit
  where within_sholm is null
  -- delete transit stops outside of Stockholm


select railway, count(osm_id)
  from sholm_transit
  group by railway
  -- Validate number of railway stops
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
-- Gustavsberg was the only borough/Stadsdelsområde outside of Stockholm which showed up when admin_level 9 was queried, and so needed to be excluded. admin_level 9 is not universal, so admin_level 9 was not assigned to administrative divisions within most areas.
-- i know neighborhoods are admin level 9
-- i will use Stockholms kommun (admin level 7) as my boundaries
-- i want to find all the polygons within this so I have stockholm subdivisions
-- looks like admin level 9 only exists within a subset of cities so I should be fine

--------------------------------------------------------------------------------

/* 5 convert polygons to centroids */

/* Convert residence polygons to centroids */
create table res_osm_pt as
select osm_id, building, ST_CENTROID(geom) as geom
from res_osm
-- all transit stops were classified as points


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
  -- creating a table that joins neighborhood id to each residence points

 create table reshood_cnt as
   select name, count(osm_id)
   from res_hood
   group by name
  -- creating a table that groups and counts residences in each neighborhood

create table hood_w_res_cnt as
  select
  sholm_hoods.name as hood_name,
  reshood_cnt.count as count,
  sholm_hoods.geom as geom
  from reshood_cnt
  join sholm_hoods
  on reshood_cnt.name = sholm_hoods.name
-- joining reshood_cnt w neighborhood geometries to get a map of neighborhoods with counts of residences

--------------------------------------------------------------------------------

/* 7 count how many residences are within 1mi of a rail stop */
SELECT addgeometrycolumn('evan','res_osm_pt','utmgeom',32737,'POINT',2);
UPDATE res_osm_pt
SET utmgeom = ST_Transform(geom, 32737);
--prepare residences for geographic analysis

SELECT addgeometrycolumn('evan','sholm_rail_transit','utmgeom',32737,'POINT',2);
UPDATE sholm_rail_transit
SET utmgeom = ST_Transform(geom, 32737);
-- prepare rail for geographic analysis


SELECT addgeometrycolumn('evan','sholm_transit','utmgeom',32737,'POINT',2);
UPDATE sholm_transit
SET utmgeom = ST_Transform(geom, 32737);
-- prepare all transit for geographic analysis


SELECT addgeometrycolumn('evan','hood_w_res_cnt','utmgeom',32737,'POLYGON',2);
UPDATE hood_w_res_cnt
SET utmgeom = ST_Transform(geom, 32737);
-- prepare neighborhoods for geographic analysis


ALTER TABLE res_osm_pt ADD COLUMN access_rail INTEGER;
ALTER TABLE res_osm_pt ADD COLUMN access_all INTEGER;
-- add access yes/no columns to residential table

UPDATE res_osm_pt
SET access_rail = 1
FROM sholm_rail_transit
WHERE ST_DWITHIN(res_osm_pt.utmgeom, sholm_rail_transit.utmgeom, 402.34);
-- make access_rail equal one when residence is within 1/4mi or 402.34m of rail transit

UPDATE res_osm_pt
SET access_all = 1
FROM sholm_transit
WHERE ST_DWITHIN(res_osm_pt.utmgeom, sholm_transit.utmgeom, 402.34);
-- make access_all equal one when residence is within 1/4mi or 402.34m of any transit

select *
from res_osm_pt
where access_rail is null
limit 1000;
select access_rail, count(osm_id)
from res_osm_pt
group by access_rail
-- lets check, works!

select *
from res_osm_pt
where access_all is null
limit 1000;
select access_all, count(osm_id)
from res_osm_pt
group by access_all
-- lets check, works!

CREATE TABLE res_within_rail AS
SELECT *
FROM res_osm_pt
WHERE access_rail = 1
-- create table with only those residences within buffer of rail transit

CREATE TABLE res_within_all AS
SELECT *
FROM res_osm_pt
WHERE access_all = 1
-- create table with only those residences within buffer of all transit

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
-- count residences with access to rail in each neighborhood

create table hoods_w_transit_access as
  select
  a.hood_name as name , count(b.access_all) as transit_access
  from hood_w_res_cnt a
  join res_within_all b
  on st_intersects(a.geom, b.geom)
  group by a.hood_name
  -- count residences with access to all transit in each neighborhood


create table hoods_1 as
    select
    hood_w_res_cnt.hood_name as name,
    hood_w_res_cnt.count as total_count,
    hoods_w_rail_access.rail_access as rail_count,
    hood_w_res_cnt.geom as geom
    from hood_w_res_cnt
    full outer join hoods_w_rail_access
    on hood_w_res_cnt.hood_name = hoods_w_rail_access.name
-- join the neighborhoods with number with access to rail transit to the table with the names, total count, and geom

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
-- Perform similar join to get number of residences with access to all transit as well

update hoods_final
  set rail_access = 0
  where rail_access is null;
update hoods_final
  set transit_access = 0
  where transit_access is null
-- make access columns 0 instead of null

ALTER TABLE hoods_final
ADD COLUMN pct_rail float(8);
UPDATE hoods_final
SET pct_rail = rail_count*1.0/total_count*1.0;
ALTER TABLE hoods_final
ADD COLUMN pct_transit float(8);
UPDATE hoods_final
SET pct_transit = transit_count*1.0/total_count*1.0;
-- calculate percentage
