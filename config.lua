Config = {}

-- Print debug info to the server console (key give/take, detection, etc.)
Config.Debug = false

-- 'qb' | 'qbox'  — or false to auto-detect
Config.Framework = false

-- 'ox' | 'qb'  (ox_inventory / qb-inventory) — or false to auto-detect
Config.Inventory = false

-- Item names (must match the items you add to your inventory — see /installation).
Config.Items = {
    key    = 'vehiclekeys',          -- the per-vehicle key item (carries plate + model metadata)
    police = 'vehiclekeys_police',   -- police tool: pull a key from a nearby vehicle
}

-- Jobs allowed to use the police key tool
Config.PoliceJobs = { 'police', 'sheriff', 'lspd', 'bcso' }

-- Engine won't run unless you hold a key item for that plate (or hotwired/picked it).
Config.RequireKeysToDrive = true

-- Grace before a keyless engine cuts out, in seconds.
-- NOTE: any value above 0 lets a keyless car RUN for that long after you get in
-- (so a lockpicked car would start briefly before dying). Keep at 0 if you want
-- "lockpick gets you in, but you MUST hotwire to start it".
Config.EngineGrace = 0

-- Hotwire timing scales with vehicle class. t3_lockpick pins are added on top of
-- the tier's base pins, and the oxlib fallback difficulty grows too.
-- GTA vehicle class ids: 0 Compacts,1 Sedans,2 SUVs,3 Coupes,4 Muscle,5 Sports
-- Classics,6 Sports,7 Super,8 Motorcycles,9 Offroad,12 Vans,18 Emergency,19 Military
Config.HotwireClass = {
    extraPins = {          -- extra t3 pins by class (harder = more pins)
        [7] = 3,           -- Super
        [6] = 2,           -- Sports
        [4] = 1,           -- Muscle
        [12] = 1,          -- Vans
    },
    defaultExtraPins = 0,
    -- classes that simply can't be hotwired (returns a "can't hotwire" message)
    blocked = { [18] = true, [19] = true },   -- Emergency, Military
}

-- Lock/unlock distance (metres)
Config.LockDistance = 6.0

-- Giving keys to another player: gives them a COPY of the key item.
Config.GiveKeysCommand   = 'givekeys'
Config.GiveKeysDistance  = 3.0

-- Minigame used for LOCKPICKING: 't3' (t3_lockpick) or 'oxlib' (skill check).
-- Hotwiring has its own setting below (Config.HotwireMinigame).
Config.Minigame = 't3'

-- Minigame used for HOTWIRING:
--   'dusa'  = the NUI cable-cutting minigame in web/ (cut the cables, tape them,
--             touch the live one to the taped pair). Ported from dusa_vehiclekeys.
--   't3'    = t3_lockpick, same as lockpicking
--   'oxlib' = ox_lib skill check
Config.HotwireMinigame = 'dusa'

-- Settings for the 'dusa' hotwire minigame
Config.DusaHotwire = {
    chance = 50,        -- % chance the engine catches once you touch the live cable
                        -- (the UI rolls this; a failed roll just means try again)
    classChance = {     -- override the chance per vehicle class - harder cars, worse odds
        [7] = 25,       -- Super
        [6] = 35,       -- Sports
        [4] = 40,       -- Muscle
    },
    playAnim = true,    -- hunch over the wheel while working
}
-- t3_lockpick tuning: strength 0-1 (lower = harder), difficulty, pins
Config.T3 = {
    hotwire  = { strength = 0.4, difficulty = 3, pins = 5 },
    basic    = { strength = 0.5, difficulty = 2, pins = 5 },
    advanced = { strength = 0.7, difficulty = 2, pins = 4 },
}

-- Hotwiring a car you have no key for (driver seat). Now requires a lockpick item.
Config.Hotwire = {
    enabled     = true,
    items       = { basic = 'lockpick', advanced = 'advanced_lockpick' },  -- one of these is needed
    breakOnFail = { basic = true, advanced = false },                      -- snap the pick on failure
    difficulty  = { 'easy', 'easy', 'medium' },   -- used only when Config.Minigame = 'oxlib'
    giveKeyItem = false,  -- false = session access only (realistic: a hotwired car isn't yours)
    -- A hotwired car can stall. If its engine turns off, the hotwire is lost and
    -- must be redone (real keys are unaffected).
    loseOnEngineOff = true,
    loseOnExit      = false,   -- true = leaving the car also loses the hotwire
    stall = {
        enabled  = false,
        chance   = 12,     -- % chance per check to stall while driving a hotwired car
        interval = 8000,   -- ms between stall checks
    },
}

-- Lockpicking a locked car. Requires a lockpick item (checked, never consumed on
-- use — only broken on failure). With ox_target you just look at the car and pick
-- "Lockpick" (no command, no item-use, so it won't clash with other scripts).
Config.Lockpick = {
    enabled     = true,
    useTarget   = true,          -- ox_target option on locked vehicles
    command     = false,         -- set to 'lockpick' to also keep a /command
    items       = { basic = 'lockpick', advanced = 'advanced_lockpick' },
    difficulty  = { basic = { 'easy', 'medium' }, advanced = { 'easy' } },  -- oxlib fallback
    breakOnFail = { basic = true, advanced = false },   -- consume the pick if you fail
    giveTempKey = true,
}

-- Keybinds (rebindable under Settings ▸ Key Bindings)
Config.Keys = {
    lock    = 'U',   -- lock / unlock nearest vehicle you hold a key for
    hotwire = 'H',   -- driver seat of a keyless car
}

Config.HornOnLock = true   -- horn chirp + lights blip on lock/unlock

-- Lock ambient / parked NPC vehicles so they must be lockpicked (or carjacked)
-- to get into. Only affects game-spawned traffic/parked cars — never owned or
-- script-spawned vehicles, and never ones you already have access to.
Config.LockAmbient = {
    enabled  = true,
    radius   = 30.0,     -- lock ambient vehicles within this many metres
    interval = 3000,     -- ms between sweeps
    onlyEmpty = true,    -- only lock parked/empty ones (leave NPC-driven traffic alone)
    leaveUnlockedClasses = { [18] = false },  -- set a class id = true to leave it unlocked
}

-- Carjacking: if a vehicle has an NPC driver, no lockpick/hotwire is needed.
-- Jack them out (pull) or threaten them at gunpoint → you get the key (theirs was
-- in the ignition).
Config.Carjack = {
    enabled     = true,
    giveKeyItem = true,     -- carjack: you get the driver's key (it was in the ignition)
    gunpoint = {
        enabled  = true,
        holdTime = 700,     -- ms you must aim at the driver before they comply
    },
}
