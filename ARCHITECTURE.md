# RailwayManager — Architecture Summary

_Snapshot of the codebase as of 30 Sep 2026 (HEAD `a36a2c1` "Releases route operator at end of route…"). Intended as the baseline for future changes._

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
| `Layout Elements/` | Static topology model: `Layout` base class, `Block`, `Point`, `Signal`, `Sensor` |
| `Layout Management/Route Management/` | `Route`, `Segment` (+ `WaitTime`), `TrackResource`, `LayoutRoute.swift` (graph building, `Layout.path()`, `layoutIsValid()`) |
| `Layout Management/Path/` | `Path`, `PathItem`, `PathItemRole` |
| `Layout Management/Layout State Management/` | `LayoutEvent` + `LayoutEventHub`, `LayoutTrackStateService` (actor – all mutable track state), `LayoutTrackSnapshot` |
| `Layout Management/Signals/` | `SignalTrackState` (per-signal aspect logic), `SignalCoordinator` (whole-layout refresh, distant & diverging aspects) |
| `Layout Management/Train control/` | `LayoutTrainController` (actor – train state/direction, DCC commands), `DCCSessionStore`, `TrainRuntimeState` |
| `Train/`, `Params/` | `Train`, `TrainSpeed`, `TrainSensor`; `TrainParams`, `TrainSpeedSetting`, `TrainStartFunction` |
| `Track Layouts/` | Concrete layouts: `Cellar` (live), `TestTrack2`, `TramSplit`; `Trains` (hard-coded train roster); `Cellar Routes` (hard-coded test route) |
| `MQTTManager/` | `MQTTManager` actor – telemetry publish, topology, route-request subscription, `RouteParams` |
| `ModelRailwayHardware/` | Hardware abstraction: `HardwarePoint`/`DCCHardwarePoint`/`CBUSHardwarePoint`, `HardwareSignal`/`CBUSHardwareSignal`, `HardwareTrain`/`CBUSHardwareTrain` (+ `Direction` enum lives here), `Led`, `Light`, `EventBus<T>`, `CBUSManager` (+ serial discovery, message encode/decode, op codes) |
| `Diagnostics/` | `printStatus()` dump of a snapshot |
| `Errors/` | `TrainError` (with `isFatal`) |
| `Extensions/` | Array `isUnique`, a `Queue`, async Sequence helpers, String helpers |
| `Resources/` | `params.json`, `trainParams.json` — **legacy, not read by any code** |

## 3. Runtime architecture

```
            CLI flags (-noMQTT -noCBUS -noDCC --mqtt-host --mqtt-port --log-level)
                                   │
                          RailwayManager.run()
                                   │  builds Cellar(), validates, connects MQTT, opens CBUS
                                   ▼
MQTT /railway/route ──► monitorRouteRequests ──► LayoutManager.runRoute(route, train)
console (sn/ss/x/st) ──► LayoutEventHub                    │
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
3. DCC keep-alive every 3 s.
4. Signal refresh every 0.2 s (only when not dormant).

## 4. Domain model

### Topology (static)
- **Block** – id string; `blockExit[.forward/.reverse]` = `.block(Block)`, `.point(PointSetting)`, `.noExit`, `.unknown`; `isUnMonitored` blocks are passed through for signalling.
- **Point** – id, DCC address (`DCCHardwarePoint`, optional `reversedConnection`), `branchOrientation` (left/right, used for signal route indication), `connections[.single/.splitStraight/.splitBranch]` → block or another point (back-to-back points supported), optional `defaultPosition` (restored when freed).
- **Signal** – location block, direction, `indication` (`.block` or `.point(point, leg)`), CBUS address (0 = dummy, not driven). Home + distant aspects: `off/stop/go/right/left`.
- **Sensor** – id, CBUS address, `SensorLocation` `.start/.end(block, gap)` (relative to forward), `.single`, `.station`. Events carry north/south orientation which, with train direction and `Train.trainFrontSensorOrientation`, determines whether the **front or rear** of the train tripped it.
- **Direction** – `forward`/`reverse`, always relative to the layout's forward direction.

### Derived at `buildLayout()`
- `blockRoutes` – every legal block→block transition per direction with the point settings required, found by `makeBlockRoutes()` walking point chains (facing → both legs, trailing → single).
- `forwardLayoutGraph` / `reverseLayoutGraph` – SwiftGraph directed graphs of those transitions.
- `Layout.path(from:to:direction:)` – BFS shortest path → `Path` of `PathItem`s (from, to, role, pointSettings).
- `layoutIsValid()` – consistency checks (exits, point connections symmetric, signals/sensors reference known items, no duplicate point settings). Failure is fatal at startup.

### Routes
- `Route` = id + `[Segment]`; `Segment` = `Path` + optional `WaitTime` (`fixed(s)`, `halt` 5 s, `station` 10 s, `terminus` 20 s). A direction change happens between segments.
- Routes arrive via MQTT (`RouteParams`: command, routeID, trainID, segments `{fromBlock,toBlock,direction,waitTime}`) or, with `-noMQTT`, the hard-coded B→A route in `Cellar Routes.swift` with the first train.
- MQTT commands: `1` runRoute, `2` stopAllTrains (reset track), `3` endManager.

### Runtime state (`LayoutTrackStateService`)
- Block: `vacant | reserved(train) | occupied(train) | vacating(train)`, transitions validated in `setStateForBlock`; freeing a block publishes `didFreeResource(.block)`.
- Point: direction, `reservedByTrain`, `freeWithBlock` (points are released when the block they were reserved from is freed).
- **Direction locks**: when a train reserves a block, all vacant contiguous blocks ahead (up to the next point) are locked to its direction; opposing trains can't reserve into them.
- Signals: cached `(home, distant)`; recomputed from a `LayoutTrackSnapshot`.

### Train runtime (`LayoutTrainController`)
- `TrainRuntimeState`: `idle, running(item), waiting, stoppingForResource, stoppedForResource, stoppingAtSensor, stoppingForTimer, stoppedAtSensor`.
- DCC sessions: `requestSession` (RLOC) → PLOC arrives as `didGetSession` → `activateSession`; ERR "session in use" → `sessionAllocated` → steal (GLOC). Commands wait up to 5 s for a session, then throw `noDCCSession`.
- Speeds: `TrainSpeed` `stop/slow/normal/fast/manual` mapped to power per train (`Trains.swift`), plus speed in cm/s used for station stop timing.

## 5. Route execution flow (`RouteOperator`)

1. `LayoutManager.runRoute` creates/reuses the train's operator → `resetRoute` (validates start block, requests DCC session, marks start block occupied) → publishes `didStartRoute`.
2. `handleStartRouteEvent`: state `.starting`, set direction, stop, light (F0) on; run the train's start functions (sounds) in a separate task, then `.active` and `processOccupiedRouteBlock()`.
3. `processNextFrontPathItem` advances the **front** index, sets direction for the segment, then `reserveOrRun`: reserve the next block/points/locks; if blocked → `stoppingForResource`, else set points and `running`.
4. **Sensor events** (`handleSensorSet`), classified by front/rear and start/end of block:
   - front at start of `toBlock` → block occupied, previous vacating, advance;
   - front inside `toBlock` → `checkForTrainStop` (timer stop, or `endRoute` if `.ending`);
   - front at end of `fromBlock` while still waiting → stop (`stoppedForResource`/`stoppedAtSensor`) or mark vacating;
   - rear at start of `toBlock` → previous block vacant, direction lock released, advance **rear** index.
5. `didFreeResource` → every operator waiting on that resource retries (`requestPathItem`).
6. Speed (`setTrainSpeed`) is derived from train state, block exit and the end signal aspect (stop→slow, diverging→normal, distant stop→normal, else fast).
7. Stops: last path item of a segment with a `waitTime` stops at the block's station sensor (delay = half train length / speed) or its end sensor. Last segment → `.ending` → `endRoute`: stop, idle, free all other blocks held by the train, wait, light off, release session, `.ended`, publish `didEndRoute`.
8. When no operators are active, `LayoutManager` schedules a **dormant** shutdown after 10 s (cancelled if a route starts): stop trains, signals off.

## 6. Signalling (`SignalCoordinator` / `SignalTrackState`)
- Each signal finds its **next monitored block** following its indication and current point positions (points against → stop).
- Home aspect `go` only if the signal block is vacant/occupied in the signal's direction and the next block is vacant or reserved for the same train; otherwise `stop`.
- `go` becomes `left/right` if the first point on the route is set to diverge (uses `branchOrientation`).
- Distant aspect = home aspect of the next signal in the same direction in the next block.
- Only changed signals are sent to hardware (CBUS ASON2 with home+distant bytes) and MQTT.

## 7. Hardware / external interfaces
- **CBUS** over CANUSB4 (auto-discovered by USB VID 0x04D8 / PID 0xF80C on macOS via IOKit, Linux via sysfs), 115200 baud, ASCII GridConnect frames `:S6FC0N<op><data>;`.
  - Out: DSPD (speed), DFNON/DFNOF (functions), RLOC/GLOC/KLOC/DKEEP (sessions), STOP, ARST, RDCC3 (DCC accessory packet for points), ASON2/ASOF (signals).
  - In: ASON1/ASOF1 (sensor set/unset with orientation), PLOC, ERR, STAT, ASOF3 (sensor statistics).
- **MQTT** topics: `railway/state` (JSON `LayoutItemState`), `railway/topology` (block end-signals, signal locations, points), `railway/route` (incoming `RouteParams`). Default broker `192.168.86.56:1883` (env `MQTT_HOST`/`MQTT_PORT` or CLI).
- **Console** (macOS): `sn<addr>` / `ss<addr>` simulate a north/south sensor pulse, `x` = shutdown (button 3), `st` = print status.
- **LEDs**: blue = dormant, green = running (slow flash = ending), red = error. No-op on macOS.

## 8. Error handling
- `TrainError` cases each flagged `isFatal`. In `runManager` a fatal error sets layout `.error` and `fatalError`s; route requests from MQTT that fail are logged and skipped.
- Any error inside `processEvent` triggers a CBUS emergency stop (`try!`).
- Telemetry failures are swallowed (`try?`) so they never fail a state change.

## 9. Known issues, loose ends & risks (candidates for future changes)

**Likely bugs**
1. **Duplicate keep-alive loops** – `LayoutTrackStateService.reset()` spawns an infinite keep-alive `Task` on every reset (in addition to the one in `LayoutManager`), never cancelled, and uses `try!` on `Task.sleep`. Each `stopAllTrainsResetTrack` adds another loop.
2. **Duplicate point address** – in `Cellar`, points 3 and 9 both use DCC address 56.
3. **`RouteOperator.requestPathItem`** – after finding a blocking resource it stops the train but then falls through, marks the block occupied, sets speed and returns `.active` (probably missing a `return`).
4. **`SensorLocation ==`** ignores associated values (`.start(A,…) == .start(B,…)` is true), and is inconsistent with the synthesised `Hashable`.
5. **Non-macOS build** – `Led` calls `HardwareManager.setLED`, which doesn't exist; iOS/Linux builds will fail.
6. `Layout.path()` – the "check a route exists in this direction" block is dead code (inner `if blocks.isEmpty` can't be true).
7. `LayoutManager.processEvent` error path uses `try! CBUSManager.shared.stopAllTrains()` – crashes if CBUS is unreachable.
8. `CBUSManager.powerTrain` delayed commands run in an untracked `Task`; a later stop can be overtaken by an earlier delayed speed command.

**Incomplete / TODO**
- `stopDelay` and timer stops hard-code `.forward` direction; speed-change delay should depend on block length.
- `stoppingAtSensor` and `waiting` train states are handled but never set; `didEndTimer`, buttons 1 and 5 unused.
- `processVacatedBlock` has an unfinished "Free any" comment.
- Lights (`Light`, `Block.associatedLights`, `CBUSManager.setLight/setClocks/setLED`) are stubs.
- Several signals/sensors in `Cellar` have address 0 (not wired yet); station sensors for H/J commented out.

**Dead / legacy code**
- `Resources/params.json`, `trainParams.json` (older schema, unread), `RailwayHardware.swift` (commented-out protocol), `CBUSHardwarePoint`, `CBUSManager.setPoint/resetPoint/setSignal(_:state:)`, `SignalCoordinator` instance (only statics used), `LayoutEvent.isRouteEvent/didChangeSignals`, `LayoutEventType`, `Queue`, async Sequence helpers, `TimeInterval.randomInterval`, `PathItem.initialPathItemForBlock`, `setDirectionForVacantContiguousBlocks`, `setReserveTrainForPointID`, `LayoutTrackStateService.nextActiveBlock` (duplicated in `SignalTrackState`), `Layout.trains` / `Layout.train(_:)`, `TestTrack2`, `TramSplit`, SunCalc dependency.
- `.swiftpm/xcode/ModelRailwayHardware/` is an older standalone copy of the hardware package (with its own `.git`, `LayoutHardwareController`, `CBUSHardwareDriver`) that has since been merged into `Sources/`. The main repo's git has an alternates entry pointing into Xcode DerivedData, which makes `git status` fail outside Xcode.

**Design observations**
- Layout and train roster are compiled in (`Cellar`, `Trains`); moving them to JSON/MQTT config would allow changes without rebuilds.
- No unit tests; the topology/path/signal logic is pure and would be easy to test with `TestTrack2`/`TramSplit`.
- Signals are both polled (0.2 s) and force-refreshed on every `signalState()` read.
- `Trains.trains` is a computed property that builds new `Train` values each call (fine because equality is by id, but wasteful).

## 10. How to extend (quick guide)
- **New layout**: subclass `Layout`, fill `blocks`, `points` (+ `setConnection`), block exits (`setExit`), `signals`, `sensors`, then call `buildLayout()`; switch `Cellar()` in `RailwayManager.runLayout`. Run to check `layoutIsValid()`.
- **New train**: add `TrainParams` in `Trains.swift` (DCC address, length in cm, power/speed per `TrainSpeed`, start functions).
- **New event**: add a case to `LayoutEvent` (+ `description`, `isRouteEvent`), publish via `LayoutEventHub.shared.publish`, handle in `LayoutManager.processEvent`.
- **New CBUS message**: add op code in `CBUSOpCodes.swift`, encoding in `CBUSManager.sendCBUSMessage`, decoding in `processReceivedMessage`.
- **New MQTT command**: extend `RouteParams.RouteCommand` and the switch in `RailwayManager.monitorRouteRequests`.
