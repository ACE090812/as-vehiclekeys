# as-vehiclekeys: item-based vehicle keys

Vehicle keys for **QBox / QBCore** where every key is a real **inventory item**. Each key is tied to one plate and shows the vehicle name. Players need a key to drive, and without one they have to lockpick the door and hotwire the car using a cable-cutting minigame. They can also carjack NPCs, hand out copies, and police can cut a key from any vehicle.

Works with **ox_inventory** or **qb-inventory**, and the framework and inventory are auto-detected.

---

## Features

### Keys as items
- Each key is a **unique item** with **metadata**: the plate and vehicle name, shown on the item tooltip
- **Keys to drive.** Without a key for that plate, the engine won't run. This can be turned off.
- **Lock and unlock** with **U** (rebindable) or by **using the key item**. Locks sync to every player, with a key-fob animation, a horn chirp and a light flash.
- You can only lock a car if you hold a real key. Hotwiring lets you drive but not lock.
- **Give a copy** of your key to a nearby player, or to a player by ID, with `/givekeys`
- Duplicate keys for the same plate are prevented per player
- **Garage aware.** The key is removed when the car is stored and handed back when it's taken out, through the exports.

### Lockpicking
- An **ox_target "Lockpick"** option appears on locked cars you don't have a key for, with no command needed. An optional `/lockpick` command is available too.
- Requires a **lockpick** or **advanced lockpick** item. The pick is checked on use, not consumed.
- A **basic pick can snap** when you fail, and an **advanced pick** doesn't by default.
- Picking the lock **only gets you in**. You still have to hotwire the car to drive it.
- Supports the **t3_lockpick** minigame or the **ox_lib skill check**

### Hotwiring
- Press **H** in the driver's seat of a car you have no key for. This also needs a lockpick.
- **Cable-cutting minigame**: cut the wires, tape them, and touch the live wire to the taped pair. You can also use t3_lockpick or an ox_lib skill check instead.
- **Difficulty scales by vehicle class**:
  - Super, sports, muscle and van classes get extra t3 pins or harder skill checks
  - The cable minigame's success chance changes per class
  - Emergency and military vehicles **can't be hotwired**
- A failed attempt gives a small **electric shock** (minor damage and a screen flash)
- A hotwire is **session access only**, so you don't get a key item. This is configurable.
- Optionally, the hotwire is **lost if the engine dies or you leave the car**, and **random stalling** can be enabled

### Carjacking
- **Pull an NPC out of their car** and you get their key, because it was in the ignition
- **Carjacking at gunpoint.** Aim at an NPC driver and they bail out, leaving the keys behind.
- You can give a real key item or session access only

### Ambient vehicles
- **Parked NPC cars are locked**, so you have to lockpick them. NPC traffic with drivers is left alone.
- Owned, script-spawned and already-accessed vehicles are never touched
- A car stays unlocked once you've picked it, even when the game tries to re-lock it
- You can choose vehicle classes that are always left unlocked

### Police
- **Police Key Cutter** item: cut a key from the nearest vehicle after a 4-second progress bar. It only works for the jobs in `Config.PoliceJobs`.

### Lost keys
- `/returnkeys`: re-issue a key for a car **you own**, checked against `player_vehicles`
- `/returnkey [id] [plate]`: an admin command to give any player a key for any plate

### Compatibility
- **Drop-in exports for qbx_vehiclekeys**: `GiveKeys`, `RemoveKeys` and `HasKeys` accept a vehicle entity
- Server and client exports to set lock state

---

## Requirements
| Resource | Required |
|---|---|
| `ox_lib` | ✅ |
| `oxmysql` | ✅ (used by `/returnkeys` and `/returnkey`) |
| `qbx_core` **or** `qb-core` | ✅ |
| `ox_inventory` **or** `qb-inventory` | ✅ |
| `ox_target` | Optional. Provides the Lockpick target option. |
| [`t3_lockpick`](https://github.com/T3development/t3_lockpick) | Optional. Used when a minigame is set to `'t3'`, otherwise the ox_lib skill check is used. |

## Installation
1. **Add the items** to your inventory:
   - **ox_inventory**: paste `installation/ox_inventory_items.lua` into `ox_inventory/data/items.lua`
   - **qb-inventory**: paste `installation/qb_items.lua` into `qb-core/shared/items.lua`
   - *(Optional)* add the `vehiclekeys.png` and `vehiclekeys_police.png` icons to your inventory images
   - The `lockpick` and `advanced_lockpick` items are **not** included. This resource uses your existing ones.
2. Drop `as-vehiclekeys` into `resources` and add it to `server.cfg` **after** ox_lib, oxmysql, your framework and your inventory:
   ```
   ensure as-vehiclekeys
   ```
3. Hook up your garage (see below) and adjust `config.lua`.

> ⚠️ Don't rename the resource folder. The hotwire minigame's NUI callbacks are hard-coded to `https://as-vehiclekeys/...` inside `web/script/main.js`.

## Garage integration
There's no universal garage event, so call these **server exports** from your garage:
```lua
-- Vehicle TAKEN OUT (spawned for the owner)
exports['as-vehiclekeys']:GiveKey(src, plate, vehicleLabel)

-- Vehicle STORED
exports['as-vehiclekeys']:TakeKey(src, plate)
```
`vehicleLabel` is only the display name shown on the key, for example `"Sultan"`. The model name works fine too.

If your garage already calls `qbx_vehiclekeys` (`GiveKeys` / `RemoveKeys` with a vehicle entity), just point those calls at `as-vehiclekeys`.

## Controls & commands
| Input | Action |
|---|---|
| **U** | Lock or unlock the nearest vehicle you hold a key for (rebindable) |
| Use **key item** | Toggle the lock on that key's vehicle |
| **H** | Hotwire from the driver's seat (needs a lockpick) |
| ox_target **Lockpick** | Pick a locked car's door (needs a lockpick) |
| `/givekeys [id]` | Give a copy of the key (to the nearest player if no ID is given) |
| `/returnkeys` | Re-issue a key for a car you own |
| `/returnkey [id] [plate]` | **Admin.** Give any player a key |
| Use **Police Key Cutter** | Cut a key from the nearest vehicle (police only) |

## Configuration (`config.lua`)
| Option | Description |
|---|---|
| `Config.Debug` | Console logging |
| `Config.Framework` / `Config.Inventory` | `false` to auto-detect, or `'qb'` / `'qbox'` and `'ox'` / `'qb'` |
| `Config.Items` | Key and police tool item names |
| `Config.PoliceJobs` | Jobs allowed to use the key cutter |
| `Config.RequireKeysToDrive` | The engine won't run without a key, hotwire or carjack |
| `Config.EngineGrace` | Seconds a keyless engine keeps running before it cuts out (keep this at `0`) |
| `Config.HotwireClass` | Extra difficulty per vehicle class, and classes that can't be hotwired |
| `Config.LockDistance` | Lock and unlock range in metres |
| `Config.GiveKeysCommand` / `Config.GiveKeysDistance` | Give-keys command name and range |
| `Config.Minigame` | Lockpick minigame: `'t3'` or `'oxlib'` |
| `Config.HotwireMinigame` | Hotwire minigame: `'dusa'` (cable cutting), `'t3'` or `'oxlib'` |
| `Config.DusaHotwire` | Cable minigame success chance, per-class chance and the working animation |
| `Config.T3` | t3_lockpick strength, difficulty and pins for hotwire, basic and advanced |
| `Config.Hotwire` | Enable, required items, break on fail, give a key item, lose on engine off or exit, stalling |
| `Config.Lockpick` | Enable, ox_target option, optional command, items, difficulty, break on fail |
| `Config.Keys` | Lock (`U`) and hotwire (`H`) keys |
| `Config.HornOnLock` | Horn chirp and light flash on lock and unlock |
| `Config.LockAmbient` | Lock parked NPC cars: radius, interval, empty cars only, classes to leave unlocked |
| `Config.Carjack` | Enable, give a key item, and gunpoint settings (enable and hold time) |

## Exports

### Server
```lua
exports['as-vehiclekeys']:GiveKey(src, plate, vehicleLabel)   -- give a key item → boolean
exports['as-vehiclekeys']:TakeKey(src, plate)                 -- remove a key item → boolean
exports['as-vehiclekeys']:HasKey(src, plate)                  -- boolean

-- qbx_vehiclekeys drop-in (vehicle entity)
exports['as-vehiclekeys']:GiveKeys(src, vehicle)
exports['as-vehiclekeys']:RemoveKeys(src, vehicle)

-- lock state for everyone (entity or netId, 1 = unlocked, 2 = locked)
exports['as-vehiclekeys']:SetLockState(vehicle, state)
```

### Client
```lua
exports['as-vehiclekeys']:HasKey(plate)             -- boolean (cached)
exports['as-vehiclekeys']:HasKeys(vehicleOrPlate)   -- qbx_vehiclekeys drop-in
exports['as-vehiclekeys']:SetLockState(vehicleOrPlate, state)
```

### Server events
```lua
-- Session access (can drive, no key item) for a vehicle by net id
TriggerServerEvent('as-vehiclekeys:server:hotwiredVehicle', netId)

-- Give a real key item for a vehicle by net id (e.g. dealership)
TriggerServerEvent('as-vehiclekeys:server:giveKeyByNetId', netId, vehicleLabel)
```

## Notes
- Hotwire and lockpick access is **session only** by default. It isn't saved and won't survive a garage cycle.
- The hotwire minigame UI is ported from `dusa_vehiclekeys`.
