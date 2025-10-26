# CT Pizza map

## Goal

Inspired by [Somerville Coffeehoods](https://www.reddit.com/r/Somerville/comments/1nw6l20/map_of_somerville_coffeehoods/), want to make a fun little map of Portland coffeehoods and practice some cartography along the way. Some goals for this project include:
- Make some pretty simple isochrone maps around cafes
- Practice making maps look pretty

## Data

Data I'll need includes:
- Cafes in PDX
  - One strategy is to get from OR state business license data
  - Another is to get directly from OSM
- Portland roadway or sidewalk network
  - Sidewalk does not include crosswalks; streets could be used instead
    - Assume no walking on ramps, highways

## Procedure
1. Query all cafe's in pdx from OSM
1. Prepare cafes for joining
  1. Want to simplify the variables to include less null/non-essential variables
  1. Some exported as shapes and not points
    1. Take centroid of shapes to create points
    1. Join points from shapes and the other points into one points layers
1. Perform network analysis to find walksheds of each cafe
1. Make it pretty!
