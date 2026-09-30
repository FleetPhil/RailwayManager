# RailwayManager — notes for Claude

Swift 6 command-line controller for Phil's model railway ("Cellar" layout): CBUS/DCC train, point and signal control, sensor handling, route running, MQTT telemetry and route requests.

**Read `ARCHITECTURE.md` first.** It describes the structure, runtime flow, known issues and, in section 11, the reversing-loop design, the steps taken and open loop-specific items.

## Working conventions
- Build is done by Phil in Xcode on his Mac; the code uses macOS-only APIs (IOKit) and hardware, so don't assume it can be built or run elsewhere. Make a change, let Phil build, then commit.
- Commit on `main`, author Phil Diggens <phil@diggens.com>. Don't push unless asked.
- Keep changes small, one step per commit, with no behaviour change unless that is the point of the change.
- For topology/path changes, Cellar's paths must stay identical (Cellar has no reversing loops).
- Keep `ARCHITECTURE.md` up to date with each change (known issues list, domain model, section 11 progress).
- Don't change the `BlockDirection` case names (`.forward`/`.reverse`); layout files and MQTT route JSON depend on them.

## Terminology
- `BlockDirection` – travel direction relative to a block's own orientation.
- `DCCDirection` – direction commanded to a loco decoder.
- Facing – per train, the block direction the loco travels in when DCC forward. `LayoutTrainController.dccDirection(_:)` is the only conversion between them.

## Testing without hardware
Run with `-noCBUS` (and `-noMQTT` to use the layout's hard-coded route from `setupRoutes` in `Cellar Routes.swift`). `-layout TestLoop` selects the reversing-loop test layout (default `Cellar`). On macOS the console accepts `sn<addr>` / `ss<addr>` to simulate a north/south sensor pulse, `st` for status, `dp` to dump block routes and paths to a file in the home directory, `x` to shut down.
