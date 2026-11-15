# Scientific missions

Dan and Adrian wrote the exploration objectives. Each briefing and its Missions checklist use the same three objectives. The mission descriptions summarize published Mars science, and the habitat bases, waypoints, radii and difficulty ratings define the educational simulation. The map draws the boundary at the published simulation radius from each Habitat Base using Mars spherical distance. **Fit area** zooms to the survey boundary and **View region** restores the overview.

The table lists planetocentric latitude and east-positive longitude in degrees. The regional reference is the briefing's named-feature reference. The existing simulation base is the center of the exploration boundary and the coordinate used to retrieve the elevation.

| Mission | Simulated difficulty | Type | Radius | Regional reference ° (lat, lon) | Habitat Base ° (lat, lon) | MOLA grid estimate |
| --- | --- | --- | ---: | --- | --- | ---: |
| Jezero Crater | Moderate | Delta geology | 500 m | 18.41, 77.69 | 18.386, 77.6564 | −2,652 m |
| Gale Crater | Easy | Sedimentology | 650 m | −5.44, 137.70 | −5.415, 137.725 | −2,606 m |
| Endeavour Crater | Challenging | Mineralogy | 750 m | −2.28, 354.80 | −2.295, 354.83 | −1,783 m |
| Columbia Hills | Hard | Hillside geology | 850 m | −14.5478, 175.6255 | −14.5478, 175.6165 | −1,934 m |
| Valles Marineris | Extreme | Canyon geology | 1.0 km | −13.74, 300.80 | −13.83, 300.845 | −3,874 m |

## Jezero Crater

Jezero is an impact crater in the Syrtis Major quadrangle of Mars. Its center is near 18.41° N, 77.69° E.

1. Look for geological evidence that liquid water once existed in Jezero Crater.
2. Examine exposed rocks for possible signs of ancient microbial life, including fossil-like shapes. Consider nonbiological explanations.
3. Survey the surface for a possible ancient river channel or water-flow path.

[USGS Gazetteer center](https://planetarynames.wr.usgs.gov/Feature/14300) · [USGS Syrtis Major quadrangle](https://planetarynames.wr.usgs.gov/images/mc13_mola.pdf) · [USGS geologic map](https://pubs.usgs.gov/publication/sim3464) · [NASA on potential biosignatures](https://www.nasa.gov/news-release/nasa-says-mars-rover-discovered-potential-biosignature-last-year/)

## Gale Crater

Gale is a roughly 154-kilometer-wide impact basin that formed an estimated 3.5 to 3.8 billion years ago. It is named for Australian astronomer Walter F. Gale.

1. Follow a short observation loop. Examine cross-bedding in two buttes and compare the apparent directions in which the layers dip.
2. Examine exposed rocks for geological evidence of past water activity.
3. Observe Aeolis Mons (Mount Sharp) from the local survey area and identify features that reveal its layered history.

[NASA Gale Crater age and name](https://science.nasa.gov/3d-resources/mars-trek-inside-gale-crater/) · [JPL Gale Crater size and lower Mount Sharp](https://www.jpl.nasa.gov/images/pia24085-gale-crater/) · [NASA Murray Buttes imagery](https://science.nasa.gov/photojournal/farewell-to-murray-buttes-image-2/)

## Endeavour Crater

Endeavour is an ancient impact crater about 22 kilometers across in Meridiani Planum. It became a major science destination for NASA’s Opportunity rover.

1. Review the mineral composition of exposed rocks and geological formations.
2. Survey the local crater rim and investigate the crater’s structure and surrounding terrain.
3. Examine soil and rocks for clues to past conditions that could have supported life.

[NASA Endeavour Crater and Opportunity](https://science.nasa.gov/resource/endeavour-crater-in-context/) · [USGS Gazetteer center](https://planetarynames.wr.usgs.gov/Feature/14501)

## Columbia Hills

The Columbia Hills lie inside Gusev Crater, about 3 kilometers from NASA’s Spirit rover landing site.

1. Plan a safe ascent around loose debris and compare hillside outcrops with basalt from the surrounding plains.
2. Compare the geological characteristics of five rock classes identified by Spirit: Clovis, Wishstone, Peace, Watchtower, and Backstay.
3. Look for mineralogical and geological evidence of ancient water activity.

[Spirit traverse and regional geology](https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2006JE002795) · [Rocks of the Columbia Hills and Backstay class](https://pubs.usgs.gov/publication/70030671) · [JPL site worksheet](https://marsnext.jpl.nasa.gov/documents/LandingSiteWorksheet_ColumbiaHillsGusev_final.pdf)

## Valles Marineris

Valles Marineris is the largest canyon system in the Solar System. It stretches across equatorial Mars east of the Tharsis volcanic province.

1. Read the regional terrain map and identify a route that avoids steep cliffs and hazardous ground.
2. Look for erosion, landslides, and collapse. Consider what the exposed rock layers might reveal about past habitability.
3. Examine landscape features for clues to ancient surface water and how Mars’s climate and atmosphere changed.

[NASA Valles Marineris geography](https://science.nasa.gov/3d-resources/mars-valles-marineris/) · [NASA canyon extent](https://science.nasa.gov/resource/the-grand-canyon-of-mars-valles-marineris/) · [USGS landslide study](https://www.usgs.gov/publications/landslides-valles-marineris-mars)

## Base elevation source and method

Source is NASA Mars Global Surveyor’s Mars Orbiter Laser Altimeter (MOLA) Mission Experiment Gridded Data Record (MEGDR), dataset `MGS-M-MOLA-5-MEGDR-L3-V1.0`. The `MEGT` 128 pixels/degree topography product gives absolute meters relative to the GMM3 Martian areoid (the `mgm1025` gravity solution evaluated to degree and order 50, per the tile labels). Local relief is an elevation difference between points and is outside the scope of these values. The tiles use a simple cylindrical projection with planetocentric IAU2000 latitude and positive east longitude. The spacing is 1/128° per pixel, about 463 m north–south with east–west spacing that varies with latitude. [NASA PDS MEGDR catalog](https://pds-geosciences.wustl.edu/missions/mgs/megdr.html) · [MOLA product specification](https://pds-geosciences.wustl.edu/mgs/mgs-m-mola-5-megdr-l3-v1/mgsl_300x/document/egdrsis.htm) · [NASA PDS 128 pixels/degree tiles and labels](https://pds-geosciences.wustl.edu/mgs/mgs-m-mola-5-megdr-l3-v1/mgsl_300x/meg128/)

1. Choose the `MEGT…hb.img` tile containing the exact Habitat Base coordinate and read its detached `.lbl` for bounds, resolution and sample format.
2. Find the containing pixel using zero-based `row = floor((north edge − latitude) × 128)` and `column = floor((longitude − west edge) × 128)`. Each tile row has 11,520 samples.
3. Read two bytes at `2 × (row × 11520 + column)` using an HTTP byte-range request. Decode them as a signed 16-bit big-endian integer in meters. Check the matching one-byte `MEGC…hb.img` hit count at `row × 11520 + column`.

| Base | MEGT tile | Row | Column | Grid cell center ° (lat, lon) | Byte offset | Raw hex | MOLA hits |
| --- | --- | ---: | ---: | --- | ---: | --- | ---: |
| Jezero Crater | `megt44n000hb.img` | 3278 | 9940 | 18.38671875, 77.66015625 | 75,545,000 | `f5a4` | 0 |
| Gale Crater | `megt00n090hb.img` | 693 | 6108 | −5.41796875, 137.72265625 | 15,978,936 | `f5d2` | 0 |
| Endeavour Crater | `megt00n270hb.img` | 293 | 10858 | −2.29296875, 354.83203125 | 6,772,436 | `f909` | 0 |
| Columbia Hills | `megt00n090hb.img` | 1862 | 10958 | −14.55078125, 175.61328125 | 42,922,396 | `f872` | 0 |
| Valles Marineris | `megt00n270hb.img` | 1770 | 3948 | −13.83203125, 300.84765625 | 40,788,696 | `f0de` | 0 |

All five grid cells contain valid elevations. Each companion hit count is zero, which the product label identifies as interpolation. These values are verified MOLA grid estimates for the cells containing the habitat coordinates. Direct laser returns at the exact base points and fine-scale local relief remain unverified. The app displays **MOLA base estimate** wherever it shows a value. A mission without a sourced elevation displays **Elevation unavailable**. Mars Trek optical imagery supplies visual context. [Mars Trek integration](mars_trek_integration.md)

## Editorial and checklist notes

The Jezero briefing uses the USGS-named crater center, while the existing Habitat Base remains the map boundary center. Possible biosignatures and habitable conditions remain hypotheses students can consider. Gale’s Mount Sharp objective is a local observation. Backstay is the documented fifth Spirit rock class for the Columbia Hills comparison. The canyon objectives treat clues about water, climate and habitability as questions for investigation.

Progress is saved on each installation by astronaut ID, mission ID and stable objective ID. The user checks each objective explicitly. The waypoint suggestions can select a destination without changing the completion state. The earlier checklist’s stored IDs remain in local preferences. The scientific objectives have new IDs because the completion criteria changed. Crew live presence uses its existing Firebase session independently of checklist progress.
