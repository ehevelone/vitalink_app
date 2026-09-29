# ZIP centroid data

`zip-centroids.json` is generated from the U.S. Census Bureau's 2026
ZIP Code Tabulation Areas Gazetteer file:

https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2026_Gazetteer/2026_Gaz_zcta_national.zip

Each entry maps a five-digit ZCTA to its representative latitude and
longitude. VitaLink uses these points only to estimate nearby provider
search distances; they are not street-level coordinates.
