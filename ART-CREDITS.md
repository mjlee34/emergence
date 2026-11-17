# Art sources

EMERGENCE generates its buildings and street geometry in Godot. The following Poly Haven assets provide the measured surfaces, vegetation and skies. The files needed at runtime ship with the project. [Poly Haven asset license (CC0)](https://polyhaven.com/license)

| Source asset | Artist | In-game use |
| --- | --- | --- |
| [Clean Asphalt](https://polyhaven.com/a/clean_asphalt) | Dimitrios Savva | Road surface |
| [Concrete Pavement](https://polyhaven.com/a/concrete_pavement) | Charlotte Baglioni | Walkways and paved lots |
| [Brick Wall 001](https://polyhaven.com/a/brick_wall_001) | Dimitrios Savva and Rob Tuytel | Brick façades and chimneys |
| [Grey Roof Tiles](https://polyhaven.com/a/grey_roof_tiles) | Rob Tuytel | Pitched roofs |
| [Grass Ground](https://polyhaven.com/a/grass_ground) | Charlotte Baglioni | Meadows, medians and gardens |
| [Fir Tree 01](https://polyhaven.com/a/fir_tree_01) | Rob Tuytel and Rico Cilliers | Conifer canopy and trunk |
| [Tree Small 02](https://polyhaven.com/a/tree_small_02) | Rico Cilliers | Deciduous trees and street planting |
| [Kloofendal 48d Partly Cloudy (Pure Sky)](https://polyhaven.com/a/kloofendal_48d_partly_cloudy_puresky) | Greg Zaal and Jarod Guest | Daylight sky and reflections |
| [Kloofendal Overcast (Pure Sky)](https://polyhaven.com/a/kloofendal_overcast_puresky) | Greg Zaal | Overcast sky and reflections |

The two sky hemispheres store logarithmically encoded radiance. The sky shader decodes and blends them with the simulated weather and solar position.

The material images were colour-graded. The companion maps store tangent-space normal X/Y in red/green and roughness in blue. The two foliage atlases were rendered from the original meshes at three elevations and two azimuths, then instanced across the valley.

## Passenger vehicles

The sedan, hatchback, estate, compact and minivan adapt Comrade1280’s *Generic passenger car pack* under CC BY 4.0. The conversion combines each vehicle into one surface, repacks the optical and wheel textures, separates body paint from trim, and locates its axles for animation. The game adds individual paint colours and weather-responsive shading. [Original models](https://sketchfab.com/3d-models/generic-passenger-car-pack-20f9af9b8a404d5cb022ac6fe87f21f5) · [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) · [Bundled attribution](game/art/vehicles/CREDITS.txt)

## Residents

The eight street characters adapt the adult avatars from Microsoft Rocketbox. Each model is posed, simplified to roughly 2,260 triangles, and paired with a reduced colour atlas. Limb weights drive the instanced walking and seated poses in Godot. [Microsoft Rocketbox](https://github.com/microsoft/Microsoft-Rocketbox) · [Bundled MIT license](game/art/residents/LICENSE.txt)

## Building facades

The four 512-pixel repeating facade textures in `game/art/` (`limestone.jpg`, `brickfront.jpg`, `curtainwall.jpg` and `bronze.jpg`) use an original atlas generated with the built-in ImageGen tool. Each quadrant depicts four storeys of limestone, brick, silver curtain wall or bronze framing. Geometry, material response, construction masking and occupied windows are rendered in Godot.

<details>
<summary>ImageGen production prompt</summary>

Create one square production architectural texture atlas with four equally sized square quadrants, abutting exactly at 50% both axes. Full bleed photoreal orthographic flat scans of repeatable upper-floor building facades, evenly lit overcast daylight, straight verticals/horizontals. Each quadrant shows precisely FOUR whole stories and FOUR bays across, arranged to repeat on all boundaries. Top-left: refined warm-gray limestone mid-rise, deep punched windows with dark steel French frames and pale stone lintels. Top-right: finely ribbed umber brick apartment block, recessed windows, occasional half-open blinds, slim iron Juliet railings. Bottom-left: silver-blue glass curtainwall, neutral nickel mullions and subtle steel spandrels, nuanced sky reflection. Bottom-right: smoked bronze modern office facade, closely spaced vertical bronze fins and broad dark window modules. Natural restrained material colors, soft ambient occlusion at sills, realistic physical window detail. Each image fills its quadrant to the edges without margins. No text, labels, perspective, sky background, ground, roofs, entrances or neighboring buildings.

</details>

## World atlas and terrain

The world atlas uses Natural Earth II with shaded relief and water at 1:50 million, projected into Web Mercator. Boundaries, populated places and lake outlines come from Natural Earth. The project distributes these data in the public domain. [Natural Earth downloads](https://www.naturalearthdata.com/downloads/)

Elevation tiles use the Terrarium encoding from Tilezen / Mapzen. The app shades these elevations for regional maps and samples them into a local grid for the simulator. Worldwide terrain, including the three offline regions, has multiple source providers. [Dataset and distribution](https://registry.opendata.aws/terrain-tiles/) · [Provider attribution bundled in the app](game/art/atlas/credits.txt) · [Source and licensing details](https://github.com/tilezen/joerd/blob/master/docs/attribution.md)
