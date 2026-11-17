# EMERGENCE

Choose a point on Earth and descend from the map to a new settlement on its measured terrain. Gimje Plain, the Loire Valley and the Sacramento Valley are bundled for offline play. [Watch the flight into Gimje](captures/settlement-flight.mp4)

At street level, five passenger-car bodies share the roads with delivery vans and the town bus. Wheels turn with actual distance travelled, and daylight, rain and night lighting affect their glass, paint and lamps. Eight textured resident models walk between homes, workplaces and shops. [Watch a resident drive through town](captures/street-traffic.mp4) · [Compare the same street before and after](captures/street-before-after.jpg) · [Overcast skyline](captures/weathered-skyline.jpg)

Press **W** to watch a town acquire its skyline. Once an occupied commercial corner attracts enough trips, it can grow above the houses. Nearby busy frontages can redevelop into mid-rise blocks. The camera keeps its bearing and eases back as roofs rise. Orbiting, panning or zooming returns control to the observer.

Gimje seed 147 grew from 1,754 residents and a three-storey roofline to 27,505 residents and a 23-storey skyline. The time-lapse samples 28 dry afternoons during the first 53 simulation days. [Watch the skyline develop](captures/gimje-skyline-growth.mp4)

![The same town at 1,952, 4,076, and 12,605 residents](captures/gimje-small-skyline.jpg)

In the preceding street-layout study on the inland Gimje Plain, the same seed grew from 1,710 residents and a three-storey skyline to 55,926 residents, 273 street segments and a 32-storey centre. All three panels use the same camera position, heading and zoom. [Full street network](captures/gimje-street-network.jpg) · [Skyline from the neighbourhood](captures/gimje-city-skyline.jpg)

![The same streets at 1,710, 12,795 and 55,926 residents](captures/gimje-district-growth.jpg)

The visual references informed the spacing of towers above lower street walls and the transition into the surrounding neighbourhoods. [Vancouver aerial photographs by PWL Partnership](https://www.pwlpartnership.com/projects/george-wainborn-park) · [City of Portland downtown views](https://www.portland.gov/sites/default/files/council-documents/2026/Future-of-Downtown-Presentation-1.pdf)

The original Alder Reach fixture opens at 07:45. On the market street, commuters pass the bakery on their way to work. Click one to see their name, home, employer, and destination, then follow them through lunch and back home. Zoom out to watch the settlement grow on both sides of the river.

![The occupied skyline of Alder Reach in the late afternoon](captures/skyline-evening.jpg)

[Watch a street, a bridge and an eight-storey redevelopment under construction](captures/construction.mp4) · [Construction stages](captures/construction-stages.jpg)

[Watch sunset, rainfall and sunrise in the city](captures/city-weather.mp4) · [Street detail](captures/alder-street.jpg) · [Downtown in daylight](captures/alder-downtown.jpg) · [Night streets](captures/alder-night.jpg)

[Watch a new playground take shape and children use the slide](captures/neighbourhood-parks.mp4) · [Watch the morning bus and a resident’s drive to work](captures/bus-commute.mp4) · [Follow a café delivery and sale](captures/local-trade.mp4) · [Watch Lina Gray’s day in 17 seconds](captures/resident-day.mp4) · [Morning commute at full resolution](captures/morning-commute.png)

The same 110,745-resident district before and after the architecture update is shown at the same instant from the same camera. Residential and office buildings use separate masonry and curtain-wall facades with setback terraces, chamfered corners and different roof profiles. Near and distant meshes share those silhouettes. [Compare the two renders](captures/skyline-architecture.jpg)

## Play on Apple Silicon

Open `dist/EMERGENCE.app` after exporting. Click the map, search for a city in English or Korean, or paste latitude and longitude or a Google Maps place URL. Select **이곳에 정착** to survey the site and descend. In the city, **M** opens the map. Returning to the current city resumes play. Starting a new settlement replaces the current one.

The atlas uses Natural Earth cartography and Mapzen elevations. New locations require an internet connection for their initial survey. Each survey samples a 3.36 km square on a 20 m grid around the chosen coordinate. Surface detail depends on the source DEM. The developable region spans up to 2,880 × 1,920 m inside the survey. The prototype uses sites between 85° south and 85° north where the founding neighbourhood fits on dry, gently sloping ground. The water model uses sea level and mapped Natural Earth lakes. Narrow rivers, minor lakes, dikes and below-sea-level land require finer hydrography. [Geographic data credits](game/art/atlas/credits.txt)

### Google Maps in the Mac app

Supplying the environment variable `EMERGENCE_GOOGLE_MAPS_KEY` opens an embedded Google map at startup. Enable the Maps JavaScript API for the browser key and restrict its website origin to `http://127.0.0.1:43861/*`. Run `dist/EMERGENCE.app/Contents/MacOS/EMERGENCE` from the shell containing the variable. The page stays on loopback, WebKit loads Google's SDK, and a click passes the selected latitude and longitude to the terrain importer. Google renders its map through the zoom. The 3D city uses the independently sampled elevation grid. The key is read at runtime. [Google setup instructions](https://developers.google.com/maps/documentation/javascript/get-api-key)

Without a key, the built-in atlas opens directly. The Google 지도 ↗ button opens Google Maps in the browser. Copy a coordinate or place link back into the atlas search field.

The simulation starts at **1×** with one local minute passing per real second. At **10×**, a full day takes 2 minutes 24 seconds. Use **1000×** to watch streets extend, districts form and downtown lots redevelop. The district map marks arterials in gold, collectors in teal and local streets with thin pale lines. Green, amber and purple parcels show housing, commerce and industry.

| Action | Control |
| --- | --- |
| Inspect a shop or factory | Click the building, or select Markets or Works and then View counter or View yard |
| Track a wholesale order until the van finishes unloading | Follow delivery in the Local Trade panel |
| Track the skyline as the city develops | W or the weather indicator beneath the place name |
| Visit parks, public services and landmarks | Places menu, P to cycle, or click the grounds |
| Follow the nearest active construction project | G or Construction |
| Follow a resident | Click a pedestrian or private car, or choose Meet a resident |
| Follow Line 1 and see its next stop, queue and load | B, Follow bus, or click a bus |
| Follow a passenger through alighting and arrival | Meet a rider while following a bus |
| Visit a residential street, market or industrial yard | Homes, Markets or Works |
| Return to the market street | V or Street view |
| Orbit and take control of the camera | Drag |
| Pan | Shift-drag, middle-drag, or trackpad pan |
| Zoom | Scroll or pinch |
| Frame the current city and resume tracking | H or Fit city |
| Show or hide the network map | Districts |
| Pause and resume the previous speed | Space or the pause button |
| Choose 1×, 10×, 100×, or 1000× | Keys 1–4 or the speed buttons |

## Build from source

Use an Apple Silicon Mac with a C++20 compiler, CMake 3.20 or later, Python 3, and the standard Godot 4.4.1 macOS application. Set `GODOT` to the full path of the Godot executable. The editor and export templates are available from the [Godot 4.4.1 archive](https://godotengine.org/download/archive/4.4.1-stable/).

```sh
git clone --depth 1 --branch godot-4.4.1-stable https://github.com/godotengine/godot-cpp.git vendor/godot-cpp
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure

export GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
"$GODOT" --headless --path game --import
"$GODOT" --path game
```

For an app bundle, install the matching export templates through Godot and run the following. The script also accepts the path to the official `macos.zip` extracted from the template package. It takes the arm64 slice of the official runtime and verifies the exported app's ad-hoc signature.

```sh
tools/export-macos.sh
open dist/EMERGENCE.app
```

The Godot runtime, dependency checkout, and build outputs stay local. The application loads geographic terrain and generates settlement geometry and vehicles. Photo-based materials and instanced tree canopies are bundled for offline use. [Art sources](ART-CREDITS.md)

## The vertical slice

The founding township covers **960 × 640 metres**. As the population grows from 30,000 to 75,000, the planner can reach progressively farther into the **2,880 × 1,920 metre** region. Terrain and travel demand determine which parts develop. Each new settlement draws a fresh seed, including repeat visits to the same coordinates. Enter a seed in the picker to replay a particular founding layout on the same terrain and build. The map location and seed appear together in the city HUD.

When housing fills, the planner tallies residents’ scheduled commutes and shopping trips. Potential new streets connect surveyed points across slopes at different bearings. Main streets continue across several junctions. Side streets follow those bends and cross at staggered intervals. Closing a long detour and filling land between occupied streets both improve a proposal’s score. Vehicles and pedestrians use the same junctions visible in the road mesh.

Staffed shops and nearby bus stops help establish a commercial centre. A larger city can develop a second centre around jobs at least 255 m away. Access, footfall, population and available frontage determine where taller buildings pay off. A deep tower lot needs room behind its existing front door. Wide residential plots can share a row of attached homes. Completed blocks acquire gardens, paved courts or service yards according to their street frontage.

New streets open in stages. A roller follows the roadbed as pavement, shoulders and markings extend toward the next junction. Bridges advance across the river on piers and girders. Cars, freight and pedestrians can use the connection from its opening tick. Foundations, exposed floor slabs and cranes precede finished facades. Redevelopment dismantles the existing building before the new frame goes up. The founding settlement is already occupied when play begins. At 10× a local street takes 12 seconds and a building takes 36 seconds. At 1000× the same projects finish in 0.12 and 0.36 seconds.

At 10×, press **G** to follow an active street or building site as the city grows.

Every resident has a persistent address. Finished housing admits new residents, and shops and industrial workplaces hire up to their job capacity. Residents seeking work are matched against openings with a preference for nearby workplaces. Occupied housing and employment demand also influence new construction.

Each resident compares the door-to-door round trip for the destinations on their schedule. A private car requires access to a car and includes walking at both curbs and an individual parking penalty. A bus journey includes walking on the sidewalk network, waiting for a scheduled departure, a seat on each segment, and the walk to the destination. Workers visit nearby shops on foot during their lunch break. Residents without jobs make their own mode choices for trips to the shops.

The founding road graph determines the route of **Line 1**. Four buses circulate in two directions, serving each direction every 18 city minutes. Each vehicle holds 32 passengers and opens its doors at each two-minute stop. A full segment pushes subsequent riders to a later departure or another option. Click a private car to inspect its driver, or press **B** and select **Meet a rider**. The city map highlights the line, stops and tracked bus. To start alongside the morning queue in the fixture, launch with `-- --fixture --at=79 --bus=0`.

Building occupancy, workers on shift and shoppers at the till follow these schedules. A camera-dependent sample supplies the visible crowd. Industrial yards show workers carrying cartons, and occupied windows light up at dusk.

### Day, night and weather

The clock uses local solar time. Day one begins near the March equinox. Latitude and the passing days change the sun’s direction and the length of daylight. The original fixture uses 45° north. At dusk, occupied windows, streetlights and nearby vehicle headlights illuminate the streets. Press **W** or click the weather indicator to watch the skyline.

Each settlement generates its own weather from the simulation seed. Cloud cover, rain and wind evolve over several hours. Pedestrians open umbrellas, distant terrain grows hazy, and paving retains water after the rain passes. All weather and water motion follows the simulation clock, including pause and fast-forward. Existing checkpoints contain the seed, site and tick needed to recover these conditions.

### Parks and playgrounds

The municipal planner looks for homes with poor walking access to an existing garden or playground. It uses the open street graph, housing around the proposed entrance, ground slope, water, factory buffers and available space. Playgrounds also require clearance from arterials. The selected grounds and entrance remain reserved as streets and buildings expand.

Each site opens after 180 city minutes of landscaping. Residents fit walks into free time around work and shopping, linger along the garden path and return home. Some residents are children throughout this prototype. Children walk to play areas and take turns climbing the ladder and using the slide. Press **P** to cycle between facilities. The district map marks parks in green and playgrounds in coral.

### Schools, emergency services and landmarks

Every two simulation days the city surveys neighbourhoods without road access to a service. School demand counts children, hospital demand counts residents, and industrial and commercial employment influence fire and police coverage. A new station enters service after construction. The Places menu shows the selected facility’s catchment, school attendance or completed calls.

Children within walking distance can attend a weekday two-hour class that fits around their other trips. Each hospital, fire station and police station operates one vehicle. For a simulated call at an occupied building, the available station with the fastest road route sends its vehicle to the scene and back. Calls are simulated service requests. Disease, fire spread and crime outcomes are outside this slice.

One in five seeds qualifies for a landmark. After 24 days and 12,000 residents, the planner looks for a well-used street with an open view across water, or a major street axis near a civic space. An eligible city may grow without finding a site. A city can build one monument. Waterfront plots can receive the Beacon of Liberty, the Tidal gateway or Mariners’ light. A civic clock or an orbital observatory can rise on a promenade or a boulevard, while the lattice observation tower anchors a boulevard vista. The seed and surveyed parcel determine the design, material palette and height. Waterfront plazas reserve a 29 m radius and boulevard sites reserve 34 m. The four clock faces show local simulation time. [Six monuments built in six different cities](captures/landmark-families.jpg). Use **W** for the skyline or **Places** for a closer view. [Same-city skyline comparison](captures/landmark-skyline.jpg) · [Earlier civic prototypes](captures/civic-places.jpg)

### Local trade

Food producers supply bakeries, cafés and grocers. Textile mills supply outfitters. Each open business has its own inventory and cash account. Staff on shift earn staggered hourly payments from their employer’s till, and staffed workshops pack goods up to their storage limit. Residents with enough money buy one item during a shop visit. A successful sale transfers $12, removes one item from the shelf, and gives the shopper a receipt and a shopping bag.

A shop running low can spend $6 per unit on a wholesale order. A staffed supplier with matching stock and a free delivery van packs up to 48 units. The cargo remains on order until the van reaches the shop’s curb and the driver finishes unloading. Empty shelves, insufficient funds or a lack of staff can prevent a sale. The right-hand panel shows the selected business’s stock, sales or output, till and payroll. Following a delivery shows the manifest and highlights its route on the map.

The opening settlement starts with savings, working capital and shelf stock. This slice uses fixed prices, two commodity categories and a ten-minute trading interval. It omits raw-material supply chains, rents, loans and ownership transfers. A new business or arriving resident brings its own opening capital.

| Road class | Carriageway | Function |
| --- | --- | --- |
| Arterial | 14.2 m | Four lanes, a planted median, busy corridors and bridge approaches |
| Collector | 7.2 m | Marked two-lane streets that gather traffic from nearby blocks |
| Local | 4.2 m | Narrow unmarked residential access streets |

Vehicles use least-travel-time paths. Length and street class determine edge cost, speed and lane position. The traffic sample increases with population. Bridge decks use a shared elevation profile for the road mesh and vehicles.

Two cities on the same imported terrain at Gimje show how the new planner diverges after 25 simulation days. [Compare seeds 147 and 42](captures/gimje-seeds.jpg)

The earlier regional growth study shows the settlement’s footprint from one fixed camera as the arterial and a second collector cross the river. These captures use the previous simulation clock and seed rules. [Opening settlement](captures/region-0.png) · [Growth across the river](captures/region-1600.png) · [Both river crossings](captures/region-7200.png) · [Regional growth film](captures/growth.mp4)

The historical lunch capture used resident #1301 at tick 1110. Current assignments depend on the founding layout. Four ticks advance the clock by one minute. Use `--district=0`, `1` or `2` for a housing, market or industrial view, or `--atlas` for a fixed regional camera.

```sh
"$GODOT" --path game --resolution 1440x900 -- --seed=147 --resident=1300 --at=1110 --capture="$PWD/captures/lunch.png"
```

## Architecture

| Module | Responsibility |
| --- | --- |
| `geo/` | Local east/south metre grid, water mask and central elevation datum, plus the original analytical fixture. Planning, traffic, walking and rendering sample the same site. |
| `sim/` | Seeded random stream, fixed ticks, population, completed housing, construction, append-only road graph, route selection, resident schedules, job assignment, cached sidewalk paths, local production and trade, freight routing, and event history. This library compiles independently of Godot. |
| `replay/` | Geographic checkpoints embed the coordinate, sampled heights and lake mask for offline replay. Fixture version 13 and geographic version 9 checkpoints contain the seed, tick, and a state checksum which includes road opening ticks, previous building heights, resident assignments, shop accounts, wallets, travel choices, scheduled bus runs, civic sites, leisure visits and cargo in transit. When opening a previous checkpoint, the simulation reconstructs its historical boundary, street planner, and redevelopment rules through the saved tick, verifies its checksum, and surveys new connections as it continues. The new record stores that transition for future replays. Restoration replays the simulation and verifies the checksum. Restore time scales with elapsed ticks. |
| `extension/` | A narrow GDExtension adapter. It supplies road polylines, building records, statistics, resident records and itineraries, and packed vehicle and pedestrian poses to the scene. |
| `game/` | Godot Forward+ presentation, terrain mesh, instanced forest, animated water and construction, camera, and observer controls. Rendering interpolates between fixed simulation ticks. |

## Engineering limits of this milestone

- **Road geometry.** The founding bus circuit anchors a small planned quarter. Outside it, new links use surveyed junction sites, with protected space for continuations and side streets. Accepted polylines meet at shared endpoints. An existing segment can receive a new junction only at one of its ends, which limits infill where a long frontage is already built out.
- **Terrain integration.** Imported sites have a shared metre-based height sampler. The planner uses the site’s elevation and water mask to place roads and bridges. Street grading and finer river data remain future work.
- **Time and reproducibility.** The tests compare identical seeds across different tick batches on the same build. Floating-point terrain sampling makes bit-identical replay across different math libraries a separate validation task.
- **Growth horizon.** This model fills a finite site and reaches capacity. Residents drive their own trips and delivery vans carry wholesale orders. Line 1 keeps its founding circuit as the city expands. Additional lines, transfers, congestion, household aging and business closures remain future work.

## Verification and profiling

Run the C++ suite without Godot or the extension dependency:

```sh
cmake -S . -B build-core -DCITY_EXTENSION=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-core --parallel
ctest --test-dir build-core --output-on-failure
./build-core/city_profile
```

By default the profiler advances 40,000 ticks. Pass increasing target ticks to measure growth intervals, city dimensions and replay checksums. To measure the playable scene, run the frame sampler with vsync disabled. It measures 60 frames after a 15-frame warm-up.

```sh
./build-core/city_profile 300000 600000 657600 1200000
"$GODOT" --path game --resolution 1280x760 --disable-vsync --script ../tests/frame_profile.gd -- 1181800 overview 1000
```

In the preceding street-layout benchmark, seed 147 reached 105,858 residents, 481 street segments and 1,387 buildings at tick 1,200,000. The developed bounds spanned 1,614 × 1,074 m. A 60-frame sample of the 1000× overview near 50,000 residents on an M4 Pro at 1280 × 760 measured 43 ms median and 53 ms at the 95th percentile. [Earlier regional benchmark capture](captures/regional-scale.jpg)

The simulation retains individual homes, jobs, wallets and travel choices. The market indexes residents by their scheduled hours, settles attendance first, then applies wages and purchases in resident order. The renderer shows up to 240 nearby private cars including the tracked driver, while bus loads cover the entire network. Distant buildings use simpler meshes. Outside the original valley, zooming in streams up to nine fine terrain tiles around the camera focus.

After building the extension and importing the project, run the integration checks:

```sh
"$GODOT" --headless --path game --script ../tests/playable.gd
"$GODOT" --headless --path game --script ../tests/transport.gd
"$GODOT" --headless --path game --script ../tests/green_spaces.gd
"$GODOT" --headless --path game --script ../tests/landmark_view.gd
"$GODOT" --headless --path game --script ../tests/weather.gd
"$GODOT" --headless --fixed-fps 30 --path game --script ../tests/settlement.gd
"$GODOT" --headless --path game --script ../tests/city_blocks.gd
```

The map checks cover coordinate selection and search, the three bundled real sites, water rejection, the flight into the simulation and resuming a city. On macOS, running `"$GODOT" --path game --script ../tests/google_picker.gd` also exercises the embedded WebKit page using a local map test double. Live Google imagery requires a configured key.

The simulation checks exercise pause, every speed, camera motion and reset, visible growth, vehicle movement, district views and resident selection using the playable scene. The native tests cover multiple seeds, batch equivalence, checkpoint recovery, population capacity, road and vehicle bounds, redevelopment, bridge deck clearance, expansion to the far bank, finite home and job capacities, mode choice, segment capacity, boarding and arrival times, lunch trips and the return home. The transport scene test follows a waiting commuter into a moving bus and through the workplace door.

The market checks reconcile sales with wallets and payroll with business expenses, conserve cash and stock across transfers, and verify that goods enter shop inventory after unloading. To inspect the opening café’s delivery use `--counter=1 --freight` after Godot’s `--` argument separator.
