# NASA Mars Trek integration

SIDERA VI requests tiles directly over HTTPS using the `ResourceURL` entries published in [NASA's Mars Trek WMTS catalog](https://trek.nasa.gov/tiles/apidoc/trekAPI.html?body=mars). The verified endpoints accept requests without an API key. The existing iOS networking policy applies.

## Products and coverage

The link for each product is its GetCapabilities document. The sample tiles returned valid PNGs with the advertised dimensions. The global layer is drawn first. Regional imagery is clipped at the published geographic bounding box and composited over CTX using the tile's PNG transparency.

| Mission | Product | Published coverage (west, south, east, north) | Matrix range | Verified request |
| --- | --- | --- | --- | --- |
| All missions | [MRO CTX Global Uncontrolled, Caltech](https://trek.nasa.gov/tiles/Mars/EQ/CTX_beta01_uncontrolled_5m_Caltech/1.0.0/WMTSCapabilities.xml) | −180, −90, 180, 90 | 0–11, 512 × 512 | [8/131/248 at Endeavour](https://astro.arcgis.com/arcgis/rest/services/OnMars/CTX/MapServer/tile/8/131/248), [6/36/42 at Valles](https://astro.arcgis.com/arcgis/rest/services/OnMars/CTX/MapServer/tile/6/36/42) |
| Jezero Crater | [MRO CTX Jezero Controlled](https://trek.nasa.gov/tiles/Mars/EQ/JEZ_ctx_B_soc_008_orthoMosaic_6m_Eqc_latTs0_lon0/1.0.0/WMTSCapabilities.xml) | 77.1604655, 18.2110274, 77.6991776, 18.7211945 | 0–13, 256 × 256 | [12/1629/5863](https://trek.nasa.gov/tiles/Mars/EQ/JEZ_ctx_B_soc_008_orthoMosaic_6m_Eqc_latTs0_lon0/1.0.0//default/default028mm/12/1629/5863.png) |
| Gale Crater | [MRO CTX Gale Crater Mosaic](https://trek.nasa.gov/tiles/Mars/EQ/Gale_CTX_BlockAdj_dd/1.0.0/WMTSCapabilities.xml) | 135.1842593, −6.5732988, 139.2413012, −2.8077809 | 0–12, 256 × 256 | [10/542/1807](https://trek.nasa.gov/tiles/Mars/EQ/Gale_CTX_BlockAdj_dd/1.0.0//default/default028mm/10/542/1807.png) |
| Endeavour Crater | [MRO HiRISE Opportunity Mosaic](https://trek.nasa.gov/tiles/Mars/EQ/HiRISE_Opportunity/1.0.0/WMTSCapabilities.xml) | −5.6179114, −2.8342616, −4.9306494, −1.8895077 | 0–17, 256 × 256 | [12/2099/3977](https://trek.nasa.gov/tiles/Mars/EQ/HiRISE_Opportunity/1.0.0//default/default028mm/12/2099/3977.png) |
| Columbia Hills | [MRO HiRISE Columbia Hills Mosaic](https://trek.nasa.gov/tiles/Mars/EQ/HiRISE_ColumbiaHills/1.0.0/WMTSCapabilities.xml) | 175.3183393, −14.847288, 175.7967313, −14.250304 | 0–16, 256 × 256 | [13/4758/16184](https://trek.nasa.gov/tiles/Mars/EQ/HiRISE_ColumbiaHills/1.0.0//default/default028mm/13/4758/16184.png) |
| Valles Marineris | Global MRO CTX | Global | 0–11, 512 × 512 | See the global product |

The team checked the [Jezero preliminary mosaic](https://trek.nasa.gov/tiles/Mars/EQ/Jezero_CTX_BlockAdj_dd/1.0.0/WMTSCapabilities.xml) and [Gusev CTX mosaic](https://trek.nasa.gov/tiles/Mars/EQ/Gusev_CTX_BlockAdj_dd/1.0.0/WMTSCapabilities.xml). Controlled Jezero and Columbia Hills HiRISE provide detail at the catalog coordinates. The [Spirit Roving Site Mosaic](https://trek.nasa.gov/tiles/Mars/EQ/spirit_hirise_mosaic/1.0.0/WMTSCapabilities.xml) ends at 175.5858031° E, west of Columbia Hills' catalog reference. The [Equatorial Valles mosaic](https://trek.nasa.gov/tiles/Mars/EQ/SE_Marineris_CTX_BlockAdj_dd/1.0.0/WMTSCapabilities.xml) misses the Valles catalog center. The [Viking global color mosaic](https://trek.nasa.gov/tiles/Mars/EQ/Mars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0/WMTSCapabilities.xml) also returned a [valid JPEG](https://trek.nasa.gov/tiles/Mars/EQ/Mars_Viking_MDIM21_ClrMosaic_global_232m/1.0.0//default/default028mm/7/50/183.jpg). CTX is used for global detail.

## Projection and tile addressing

- The selected capability snapshots advertise `urn:ogc:def:crs:EPSG::104905`, style `default`, and tile matrix set `default028mm`. The angular lattice has origin (−180°, 90°), numeric matrices, and 2 × 1 tiles at matrix 0 with each dimension doubling at each subsequent level. The advertised global [ArcGIS resource](https://astro.arcgis.com/arcgis/rest/services/OnMars/CTX/MapServer?f=pjson) independently confirms the Mars 2000 spherical degree grid, origin, and 512px raster.
- Scene x is east longitude and scene y increases south. Catalog longitudes normalize from 0–360° into [−180°, 180°). Columns wrap at the antimeridian, and rows stop at the poles. Tile geometry retains unwrapped longitude so the raster stays continuous while panning.
- Each layer chooses its matrix from angular degrees per screen pixel and its own raster size. Zoom starts at 1× relative to the regional extent and extends to at least 4×. The minimum upper limit increases where needed so each mission can fit its geographic exploration boundary in the viewport. A badge appears if the current view exceeds a visible layer's finest available raster. The scale bar is approximate horizontal ground scale at the viewport center, using the Mars 2000 spherical radius of 3,396,190 m and the cosine of latitude.
- Scene transforms are shared by the raster and demo markers so they stay aligned under pinch and pan. Reset restores the catalog reference as the view center and restores the initial angular span. Panning is local to the mission neighborhood.

## Loading and scientific limits

The tile renderer is independent of the transport. It fetches the visible matrix footprint, coalesces gesture updates, allows six requests in flight per dashboard, and ignores obsolete responses. Previously decoded imagery is reused during scale changes. The app retains a bounded in-memory byte cache and the dashboard bounds its decoded image cache. Retry retains successful tiles. Uncached imagery needs internet access, and caches are cleared when the app process exits.

The imagery is cartographic, with the registration and resolution of each published product. The exploration boundary uses the configured Mars-sphere distance from the existing Habitat Base. Astronauts, waypoints, routes, headings, pings, SOS, and mission goals are simulated. Base elevations are fixed catalog samples from the MOLA grid. [Scientific mission briefings](scientific_missions.md) · [Mission imagery credits](mars_mission_sources.md)
