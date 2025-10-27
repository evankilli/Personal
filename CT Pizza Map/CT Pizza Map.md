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
    - Take layer of all state highways with speed limits
    - Take layer of all local roads that have speed limit Data
    - For local roads without, either assign 30 or 25 based on urban vs. rural classification
    - For interchanges, set standard speed limit
- CT census blocks? CT lots? What's my lowest level of geographic analysis
  - May be able to ghet away without this

## Procedure
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
  1. Load in state highways with speed limits
  1. Load in local roads
    1. Load in local roads with speed limits
    1. Load in local roads without speed limits
  1. Prepare local  roads
    1. Separate out local roads from the shape not containing speed limits that are in the dataset with speed limits
    1. For remaining roads, compare to urbanized areas
    1. If urban, 30mph; if rural, 35mph (as general rule)
    1. Re-join local roads into one layer
    1. Save out local roads
  1. Join local roads and state highways into one layer
    1. Save out joined roads layer
1. Perform network analysis by points to create isochrone for each point


## sources
- [CT Pizza Trail](https://ctvisit.com/articles/connecticut-pizza-trail)
- [CT Roads](https://magic.lib.uconn.edu/connecticut_data.html)
  - [Info about road classifications](https://www2.census.gov/geo/pdfs/reference/mtfccs.pdf)
- Urban areas and state boundaries were found through [TIGER/Line](https://www.census.gov/cgi-bin/geo/shapefiles/index.php)
- [Guidance around speed limits](https://portal.ct.gov/dot/-/media/dot/osta/guidelines-for-establishing-speed-limits-in-the-state-of-connecticut-102021.pdf)
