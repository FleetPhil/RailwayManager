# RailwayManager — Architecture Summary

_Snapshot of the codebase as of 30 Sep 2026 (HEAD `e52c46b` "Commit outstanding changes"). Intended as the baseline for future changes._

## 1. What it is

A Swift 6 command-line controller for a model railway (the "Cellar" layout). It:

- drives **trains, points and signals** over **CBUS** (MERG CAN bus) via a CANUSB4 serial adapter, using DCC for locos and accessory decoders;
- receives **sensor events** (train detection, north/south orientation) back from CBUS;
- runs **routes** (sequences of block-to-block segments) for one or more trains concurrently, with block reservation, point locking, direction locks and automatic signalling;
- publishes **telemetry** (block/point/signal/train state and layout topology) to an **MQTT** broker and receives **route commands** from MQTT.

Package: `swift-tools-version 6.1`, Swift language mode 6, platforms macOS 15 / iOS 16 (Linux code paths also exist). Single executable target `RailwayManager`.

Dependencies: SwiftSerial, swift-argument-parser, SwiftyBeaver (logging, global `log`), SwiftGraph (BFS path finding), mqtt-nio, CollectionConcurrencyKit. SunCalc is declared but not used.

~5,900 lines across 44 Swift files.

## 2. Folder map

| Folder | Contents |
|---|---|
| `Managers/` | `RailwayManager` (@main, CLI, startup, MQTT route intake, console commands), `LayoutManager` (actor – central event loop, layout lifecycle), `RouteOperator` (actor – one per train, executes a route) |
| `Layout Elements/` | Static topology model: `Layout` base class, `Block`, `Point`, `Signal`, `Sensor`, `BlockDirection` |
| `Layout Management/Route Management/` | `Route`, `Segment` (+ `WaitTime`), `TrackResource`, `LayoutRoute.swift` (graph building, `Layout.path()`, `layoutIsValid()`) |
| `Layout Management/Path/` | `Path`, `PathItem`, `PathItemRole` |
| `Layout Management/Layout State Management/` | `LayoutEvent` + `LayoutEventHub`, `LayoutTrackStateService` (actor – all mutable track state), `LayoutTrackSnapshot` |
| `Layout Management/Signals/` | `SignalTrackState` (per-signal aspect logic), `SignalCoordinator` (whole-layout refresh, distant & diverging aspects) |
| `Layout Management/Train control/` | `LayoutTrainController` (actor – train state/direction, DCC commands), `DCCSessionStore`, `TrainRuntimeState` |
| `Train/`, `Params/` | `Train`, `TrainSpeed`, `TrainSensor`; `TrainParams`, `TrainSpeedSetting`, `TrainStartFunction` |
| `Track Layouts/` | Concrete layouts: `Cellar` (live), `TestLoop` (reversing-loop test layout, dummy addresses), `TestTrack2`, `TramSplit`; `Trains` (hard-coded train roster); `Cellar Routes` (`setupRoutes`: hard-coded test route per layout), `TestLoop Routes` |
| `MQTTManager/` | `MQTTManager` actor – telemetry publish, topology, route-request subscription, `RouteParams` |
| `ModelRailwayHardware/` | Hardware abstraction: `HardwarePoint`/`DCCHardwarePoint`/`CBUSHardwarePoint`, `HardwareSignal`/`CBUSHardwareSignal`, `HardwareTrain`/`CBUSHardwareTrain`, `DCCDirection`, `Led`, `Light`, `EventBus<T>`, `CBUSManager` (+ serial discovery, message encode/decode, op codes) |
| `Diagnostics/` | `printStatus()` dump of a snapshot |
| `Errors/` | `TrainError` (with `isFatal`) |
| `Extensions/` | Array `isUnique`, a `Queue`, async Sequence helpers, String helpers |
| `Resources/` | `params.json`, `trainParams.json` — **legacy, not read by any code** |

## 3. Runtime architecture

```
            CLI flags (-noMQTT -noCBUS -noDCC -layout --mqtt-host --mqtt-port --log-level)
                                   │
                          RailwayManager.run()
                                   │  builds the -layout layout (default Cellar), validates, connects MQTT, opens CBUS
                                   ▼
MQTT /railway/route ──► monitorRouteRequests ──► LayoutManager.runRoute(route, train)
console (sn/ss/x/st/dp) ──► LayoutEventHub                    │
                              ▲   │ (AsyncStream)          ▼
CBUS serial ─► CBUSManager.CBUSEvents ─┘   └─► LayoutManager.processEvent ─► RouteOperator (per train)
                                                          │                         │
                                                          ▼                         ▼
                                          LayoutTrackStateService  ◄──────────  reserve / set state
                                          (blocks, points, signals, locks)
                                                │            │
                                   LayoutTrainController   SignalCoordinator (every 0.2 s)
                                   (DCC sessions, speed)          │
                                                │                 ▼
                                             CBUSManager ◄── Signal/Point hardware
                                                │
                                        MQTTManager (telemetry, /railway/state, /railway/topology)
```

### Concurrency model
- Everything mutable is inside **actors**: `LayoutManager`, `RouteOperator`, `LayoutTrackStateService`, `LayoutTrainController`, `DCCSessionStore`, `CBUSManager`, `MQTTManager`, `LayoutEventHub`/`EventBus`, `Led`, `Light`.
- Topology classes (`Layout`, `Block`, `Point`) are `@unchecked Sendable`: mutated only during `init`, then treated as immutable. `Layout.buildLayout()` **must** be called at the end of every subclass `init`.
- Singletons: `CBUSManager.shared`, `MQTTManager.shared`, `LayoutEventHub.shared`, `Led.shared`.
- `GlobalOptions` holds `nonisolated(unsafe)` statics set once at startup.
- `LayoutManager` spawns a new `Task` **per event** so long-running handlers (e.g. waiting for a DCC session) don't block the loop. Consequence: events can be processed concurrently/out of order; actors serialise access but interleave at every `await` (reentrancy).
- `LayoutTrackStateService.reservePathItem` has an explicit **no-await critical section** for check-and-reserve to prevent two trains reserving the same resources.

### Background tasks (started in `LayoutManager.init`)
1. Event loop over `LayoutEventHub`.
2. CBUS event pump → `LayoutEventHub`.
3. DCC keep-alive every 3 s (the only keep-alive loop; each session's failure is logged without stopping the rest).
4. Signal refresh every 0.2 s (only when not dormant).

## 4. Domain model

### Topology (static)
- **Block** – id string; `blockExit[.forward/.reverse]` = `.block(Block)`, `.point(PointSetting)`, `.noExit`, `.unknown`; `isUnMonitored` blocks are passed through for signalling.
- **Point** – id, DCC address (`DCCHardwarePoint`, optional `reversedConnection`), `branchOrientation` (left/right, used for signal route indication), `connections[.single/.splitStraight/.splitBranch]` → block or another point (back-to-back points supported), optional `defaultPosition` (restored when freed).
- **Signal** – location block, direction, `indication` (`.block` or `.point(point, leg)`), CBUS address (0 = dummy, not driven). Home + distant aspects: `off/stop/go/right/left`.
- **Sensor** – id, CBUS address, `SensorLocation` `.start/.end(block, gap)` (relative to forward), `.single`, `.station`. Events carry north/south orientation which, with train direction and `Train.trainFrontSensorOrientation`, determines whether the **front or rear** of the train tripped it.
- **BlockDirection** – `forward`/`reverse` travel direction relative to a block's own orientation (forward = towards the block's forward exit). Currently every layout is defined so all blocks share one orientation.
- **DCCDirection** – `forward`/`reverse` commanded to the loco decoder (loco-relative), used by the hardware layer (`HardwareTrain`, `CBUSMessage`, `CBUSManager.powerTrain`) and for working out which end of the train tripped a sensor. `LayoutTrainController.dccDirection(_:)` is the only conversion from `BlockDirection`: DCC forward when the train's travel direction matches its **facing**, otherwise DCC reverse.
- **Facing** – per train, the block direction the loco travels in when commanded DCC forward (`LayoutTrainController.trainFacing`, set with `setTrainFacing`). Defaults to forward, so on layouts without loops DCC direction always equals travel direction. When the front of a train enters a block across a loop closure (a path item with `fromDirection != toDirection`), `RouteOperator.processOccupiedRouteBlock` calls `crossOrientationChange`, which flips both the train's direction and its facing so the DCC direction is unchanged. Facing persists across routes. The train's direction (`trainDirections`) is its travel direction in the block the front is in.

### Derived at `buildLayout()`
- `blockRoutes` – every legal block→block transition per direction with the point settings required, found by `makeBlockRoutes()` walking point chains (facing → both legs, trailing → single). Each route also records `toDirection`, the travel direction on entering `toBlock`, derived by `Block.entryDirection(through:)` from which of `toBlock`'s own exits the connection arrives through (arriving via its forward exit = travelling reverse). It differs from `direction` only across a loop closure; `BlockRoute.description` shows it (`-> dir`) only then.
- `layoutGraph` – SwiftGraph directed graph of those transitions. Vertices are (block, travel direction) pairs named by `graphVertex()` (`"A+"` forward, `"A-"` reverse); each block route is an edge from `fromBlock`/`direction` to `toBlock`/`toDirection`.
- `Layout.path(from:to:direction:)` – BFS shortest path from the start block in the given direction to the target block in either direction → `Path` (starting direction) of `PathItem`s (from, to, fromDirection, toDirection, role, pointSettings). The directions differ only across a loop closure.
- `layoutIsValid()` – logs "Layout <name> is valid" on success; consistency checks (exits, point connections symmetric, every block→block link and point→block leg matched by exactly one exit on the receiving block, each signal's indication equal to its block's exit in the signal's direction, signals/sensors reference known items, no duplicate point settings). Failure is fatal at startup.

### Routes
- `Route` = id + `[Segment]`; `Segment` = `Path` + optional `WaitTime` (`fixed(s)`, `halt` 5 s, `station` 10 s, `terminus` 20 s). A direction change happens between segments.
- Routes arrive via MQTT (`RouteParams`: command, routeID, trainID, segments `{fromBlock,toBlock,direction,waitTime}`) or, with `-noMQTT`, the layout's hard-coded route from `setupRoutes` (`Cellar Routes.swift`; Cellar: B→H forward then H→B reverse; TestLoop: S→C forward then C→S reverse round the loop; none for other layouts) with the first train.
- MQTT commands: `1` runRoute, `2` stopAllTrains (reset track), `3` endManager.

### Runtime state (`LayoutTrackStateService`)
- Block: `vacant | reserved(train, direction) | occupied(train, direction) | vacating(train, direction)`, transitions validated in `setStateForBlock`; freeing a block publishes `didFreeResource(.block)`. The direction is the train's travel direction in that block, set from the path item (`fromDirection`/`toDirection`) or, for the start block, the route's initial direction. When a new segment reverses the train, `reverseTravelDirection(of:)` flips the direction in every block it holds. `snapshot.travelDirection(in:)` reads the direction from the block state. MQTT telemetry does not include it.
- Point: direction, `reservedByTrain`, `freeWithBlock` (points are released when the block they were reserved from is freed).
- **Direction locks** (`DirectionLock`: train + direction): when a train reserves a block, all vacant contiguous blocks ahead (up to the next point) are locked with the travel direction in each block (from `contiguousBlocks()` starting at the path item's `toDirection`). A train can't reserve a block if another train holds a lock in the opposite direction on it or any block contiguous beyond it; the reserving train's own locks are ignored, since they may be left from before it reversed. The check uses only stored lock directions, so it no longer awaits the train controller before the critical section.
- Signals: cached `(home, distant)`; recomputed from a `LayoutTrackSnapshot`.

### Train runtime (`LayoutTrainController`)
- `TrainRuntimeState`: `idle, running(item), waiting, stoppingForResource, stoppedForResource, stoppingAtSensor, stoppingForTimer, stoppedAtSensor`.
- DCC sessions: `requestSession` (RLOC) → PLOC arrives as `didGetSession` → `activateSession`; ERR "session in use" → `sessionAllocated` → steal (GLOC). Commands wait up to 5 s for a session, then throw `noDCCSession`.
- Speeds: `TrainSpeed` `stop/slow/normal/fast/manual` mapped to power per train (`Trains.swift`), plus speed in cm/s used for station stop timing.

## 5. Route execution flow (`RouteOperator`)

1. `LayoutManager.runRoute` creates/reuses the train's operator → `resetRoute` (validates start block, requests DCC session, marks start block occupied) → publishes `didStartRoute`.
2. `handleStartRouteEvent`: state `.starting`, set direction, stop, light (F0) on; run the train's start functions (sounds) in a separate task, then `.active` and `processOccupiedRouteBlock()`.
3. `processNextFrontPathItem` advances the **front** index, sets direction for the segment, then `reserveOrRun`: reserve the next block/points/locks; if blocked → `stoppingForResource`, else set points and `running`.
4. **Sensor events** (`handleSensorSet`), classified by front/rear (from the DCC direction) and start/end of block (from the travel direction in the sensor's block, read from its block state, falling back to the train's direction if the block is not held by the train):
   - front at start of `toBlock` → block occupied, previous vacating, advance;
   - front inside `toBlock` → `checkForTrainStop` (timer stop, or `endRoute` if `.ending`);
   - front at end of `fromBlock` while still waiting → stop (`stoppedForResource`/`stoppedAtSensor`) or mark vacating;
   - rear at start of `toBlock` → previous block vacant, direction lock released, advance **rear** index.
5. `didFreeResource` → every operator waiting on that resource retries (`requestPathItem`).
6. Speed (`setTrainSpeed`) is derived from train state, block exit and the end signal aspect (exit and end signal for the train's travel direction in that block) (stop→slow, diverging→normal, distant stop→normal, else fast). `lastCommandedTrainSpeed` tracks the last speed sent; `stopTrain()` resets it to `.stop`, so the next calculation always re-sends a speed. If a retry after a freed resource is still blocked, `requestPathItem` stops the train and returns without touching speed or route state.
7. Stops: last path item of a segment with a `waitTime` stops at the block's station sensor (delay = half train length / speed) or its end sensor. Last segment → `.ending` → `endRoute`: stop, idle, free all other blocks held by the train, wait, light off, release session, `.ended`, publish `didEndRoute`.
8. When no operators are active, `LayoutManager` schedules a **dormant** shutdown after 10 s (cancelled if a route starts): stop trains, signals off.

## 6. Signalling (`SignalCoordinator` / `SignalTrackState`)
- Each signal finds its **next monitored block** following its indication and current point positions (points against → stop), together with the travel direction in it of a train passing the signal (derived with `Block.entryDirection(through:)`; equal to the signal's direction except across a loop closure). Unmonitored blocks are passed through in their own travel direction.
- Home aspect `go` only if the signal block is vacant/occupied in the signal's direction and the next block is vacant or reserved for the same train; otherwise `stop`.
- `go` becomes `left/right` if the first point on the route is set to diverge (uses `branchOrientation`).
- Distant aspect = home aspect of the signal in the next block for the direction a train passing this signal travels in that block. If there is no such signal (siding, buffer stop), the distant shows caution (`stop`). The distant is only set while the home aspect is `go` (or a diverging aspect); otherwise it is `off`.
- Only changed signals are sent to hardware (CBUS ASON2 with home+distant bytes) and MQTT.

## 7. Hardware / external interfaces
- **CBUS** over CANUSB4 (auto-discovered by USB VID 0x04D8 / PID 0xF80C on macOS via IOKit, Linux via sysfs), 115200 baud, ASCII GridConnect frames `:S6FC0N<op><data>;`.
  - Out: DSPD (speed), DFNON/DFNOF (functions), RLOC/GLOC/KLOC/DKEEP (sessions), STOP, ARST, RDCC3 (DCC accessory packet for points), ASON2/ASOF (signals).
  - In: ASON1/ASOF1 (sensor set/unset with orientation), PLOC, ERR, STAT, ASOF3 (sensor statistics).
- **MQTT** topics: `railway/state` (JSON `LayoutItemState`), `railway/topology` (block end-signals, signal locations, points), `railway/route` (incoming `RouteParams`). Default broker `192.168.86.56:1883` (env `MQTT_HOST`/`MQTT_PORT` or CLI).
- **Console** (macOS): `sn<addr>` / `ss<addr>` simulate a north/south sensor pulse, `x` = shutdown (button 3), `st` = print status, `dp` = write every block route and every block-to-block path (both directions) to a timestamped file in the home directory (`Layout.topologyDump()`), for diffing topology changes.
- **LEDs**: blue = dormant, green = running (slow flash = ending), red = error. No-op on macOS; elsewhere driven via `CBUSManager.setLED` (currently an empty stub).

## 8. Error handling
- `TrainError` cases each flagged `isFatal`. In `runManager` a fatal error sets layout `.error` and `fatalError`s; route requests from MQTT that fail are logged and skipped.
- Any error inside `processEvent` triggers a CBUS emergency stop. If that fails (CBUS unreachable) the error is logged and the layout enters `.error` (red LED, individual stops attempted) instead of crashing.
- Delayed speed commands are held per DCC session in `CBUSManager.pendingSpeedCommands`. Any newer speed/stop for the session, a session release, or an emergency stop cancels the pending one, so a delayed speed can never override a later stop.
- Telemetry failures are swallowed (`try?`) so they never fail a state change.

## 9. Known issues, loose ends & risks (candidates for future changes)

**Likely bugs**
- None currently known.

**Incomplete / TODO**
- Speed-change delay should depend on block length.
- `stoppingAtSensor` and `waiting` train states are handled but never set; `didEndTimer`, buttons 1 and 5 unused.
- `processVacatedBlock` has an unfinished "Free any" comment.
- Lights (`Light`, `Block.associatedLights`, `CBUSManager.setLight/setClocks/setLED`) are stubs.
- Several signals/sensors in `Cellar` have address 0 (not wired yet); station sensors for H/J commented out.

**Dead / legacy code**
- `Resources/params.json`, `trainParams.json` (older schema, unread), `RailwayHardware.swift` (commented-out protocol), `CBUSHardwarePoint`, `CBUSManager.setPoint/resetPoint/setSignal(_:state:)`, `SignalCoordinator` instance (only statics used), `LayoutEvent.isRouteEvent/didChangeSignals`, `LayoutEventType`, `Queue`, async Sequence helpers, `TimeInterval.randomInterval`, `PathItem.initialPathItemForBlock`, `setDirectionForVacantContiguousBlocks`, `TrainError.noLockToRelease` (never thrown), `setReserveTrainForPointID`, `LayoutTrackStateService.nextActiveBlock` (duplicated in `SignalTrackState`), `Layout.trains` / `Layout.train(_:)`, `TestTrack2`, `TramSplit`, SunCalc dependency.
- `.swiftpm/xcode/ModelRailwayHardware/` held an older standalone copy of the hardware package, since merged into `Sources/ModelRailwayHardware/`. The folder is now empty, but the repo still tracks it as a submodule gitlink (mode 160000) with no `.gitmodules` entry, so `git submodule` commands fail. `git rm --cached .swiftpm/xcode/ModelRailwayHardware` removes the orphan entry.

**Design observations**
- Layout and train roster are compiled in (`Cellar`, `Trains`); moving them to JSON/MQTT config would allow changes without rebuilds.
- No unit tests; the topology/path/signal logic is pure and would be easy to test with `TestTrack2`/`TramSplit`.
- Signals are both polled (0.2 s) and force-refreshed on every `signalState()` read.
- Stop timing uses `Task.sleep` inside `RouteOperator` (`checkForTrainStop`, `endRoute`; there is a TODO to replace this with a stop event). The actor stays reentrant during the sleep, so other events for the same train can be processed while it waits.
- When a block is freed, its associated points are released one at a time with a 200 ms gap, so they don't all switch at once and risk a short.
- `Trains.trains` is a computed property that builds new `Train` values each call (fine because equality is by id, but wasteful).

## 10. How to extend (quick guide)
- **New layout**: subclass `Layout`, fill `blocks`, `points` (+ `setConnection`), block exits (`setExit`), `signals`, `sensors`, then call `buildLayout()`; add a case to `LayoutName` in `RailwayManager.swift` and select it with `-layout <name>`. Run to check `layoutIsValid()`.
- **New train**: add `TrainParams` in `Trains.swift` (DCC address, length in cm, power/speed per `TrainSpeed`, start functions).
- **New event**: add a case to `LayoutEvent` (+ `description`, `isRouteEvent`), publish via `LayoutEventHub.shared.publish`, handle in `LayoutManager.processEvent`.
- **New CBUS message**: add op code in `CBUSOpCodes.swift`, encoding in `CBUSManager.sendCBUSMessage`, decoding in `processReceivedMessage`.
- **New MQTT command**: extend `RouteParams.RouteCommand` and the switch in `RailwayManager.monitorRouteRequests`.

## 11. Reversing loop support

### Problem
Route finding and train control originally assumed one layout-wide meaning of "direction": `Layout.path()` searched a forward graph or a reverse graph, and commanding a train DCC-forward was assumed to move it forward in every block. A reversing loop breaks this: a train running DCC-forward goes out of a block in one direction and comes back through it in the other, so no single layout-wide orientation exists.

### Design: three separate directions
| Concept | Meaning | Changes when |
|---|---|---|
| **Travel direction in a block** (`BlockDirection`) | Which end of *that* block the train is heading for | Crossing a connection that flips orientation (the loop closure) |
| **DCC direction** (`DCCDirection`) | Loco decoder forward/reverse | Only when the route reverses the train (segment boundary) |
| **Facing** (per train, a `BlockDirection`) | Block direction the loco travels in when commanded DCC forward | Flips each time the train crosses a flipping connection |

- DCC direction = forward if travel direction == facing, else reverse (`LayoutTrainController.dccDirection`).
- Front/rear sensor detection uses the DCC direction (sensor magnets are fixed to the train).
- Block orientation is already local in the layout data: sensor start/end, signal directions and block exits are all relative to each block. A flip can be **derived** from existing definitions — entering block B through the connection listed as B's `forward` exit means travelling `reverse` in B; for a direct block→block link, check which of Y's exits points back to X. No new layout data is needed, and layouts without loops (Cellar) have no flips.

### Done
1. `Direction` renamed to `BlockDirection` (commit `6b087e5`, case names kept so layouts and MQTT JSON are unchanged).
2. `DCCDirection` added for the hardware layer, with `dccDirection(_:)` as the single conversion point (commit `621acea`).
3. Per-train facing (`trainFacing`, `facing(_:)`, `setTrainFacing`), defaulting to forward. Nothing changes facing yet.
4a. Topology dump: console `dp` writes `Layout.topologyDump()` (sorted block routes, and the path or "no route" for every block pair in both directions) to `~/RailwayManager-topology-<Layout>-<timestamp>.txt`. A Cellar baseline taken before step 4 is diffed after each topology sub-step.
4b. `BlockRoute.toDirection` (entry direction into the next block); `traversePointChain` also returns the point leg that connects to the block; `layoutIsValid()` requires links to be matched by the receiving block's exits.
4c. Single `layoutGraph` of block/direction vertices replaces the forward/reverse graphs; `path()` searches to the target block in either direction; `PathItem` has `fromDirection`/`toDirection`. Nothing reads the path item directions yet. `layoutIsValid()` logs success at info level.
4d. `contiguousBlocks()` returns (block, direction) pairs, following direction changes across block→block links and stopping if a block repeats.
5a. Direction locks store (train, direction) per block (`DirectionLock`) and are checked against the travel direction in each block; `reservePathItem` starts from the path item's `toDirection` and ignores the reserving train's own locks. Only differs from before if a train reverses while still holding locks ahead of it: those locks keep their original direction, where previously they took the train's new direction.
5b. `BlockRuntimeState` carries the train's travel direction in each block, and `snapshot.travelDirection(in:)` reads it from there instead of the train's single direction (the snapshot no longer holds train directions). When a new segment reverses the train, `RouteOperator.processNextFrontPathItem` calls `reverseTravelDirection(of:)` to flip the direction in every block the train holds, matching the old behaviour where all its blocks followed the train's direction.
6. Signals: `Signal.nextBlock` returns (block, direction) and the next-block direction checks in `signalIndication`, the distant-signal lookup and the diverging-route walk through unmonitored blocks use it instead of the signal's direction. `entryDirection` moved from `Layout` to `Block` so signal code can use it. `layoutIsValid()` checks each signal's indication matches its block exit (all Cellar signals do).
7a. `RouteOperator.handleSensorSet` works out start/end of block from the travel direction in the sensor's block (its block state) instead of the train's direction.
7b. `RouteOperator.travelDirection(in:)` (block state direction, falling back to the train's direction) is used by `handleSensorSet` and by `setTrainSpeed` for the block-exit check and end-signal lookup; the stop sensor (end sensor when there is no station sensor) is chosen with the path item's `toDirection`.
7c. Facing: `LayoutTrainController.crossOrientationChange` flips the train's direction and facing together when the front enters a block across a loop closure. `processNextFrontPathItem` detects a reversal by comparing the next path item's `fromDirection` with the train's direction (rather than the segment's starting direction), so a loop closure part-way through a segment is not mistaken for a reversal. No effect on Cellar (no loop closures).
8a. `TestLoop` layout (S stub, A approach, point 1, loop B→C returning via the branch into A) and the `-layout` option (`LayoutName`, default Cellar). `setupRoutes` returns nil for layouts without a built-in route.
8b. Built-in `TestLoop` route (`TestLoop Routes.swift`): S→C forward (through the branch, so the train crosses the loop closure and enters C travelling reverse), halt, then C→S reverse via B and A. DCC stays forward throughout; the train ends in S facing the other way. Console sequence with a short train (front = `sn`, rear = `ss` while DCC forward): `sn2 sn3 ss3 sn4 sn8 ss8 sn7`, wait for the halt, then `sn6 ss6 sn5 sn4 ss4 sn3 sn2 ss2 sn1`.

The Cellar topology dump was identical to the baseline after 4b and 4c (it does not cover `contiguousBlocks()`).

### Remaining steps
None: all steps are done, pending a run of the TestLoop route. Open items are under *Loop-specific considerations*.

### Loop-specific considerations
- Initial facing must be known; currently defaults to forward. May later come from config, a route request, or be persisted.
- Track polarity: none needed with an auto-reverser; if a relay is used, model it as a resource set with the path item, switched only while the train is wholly inside the loop.
- The loop must be longer than the train; reservation should treat the loop as a unit so a train cannot enter it without being able to leave.
