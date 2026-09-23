-- ============================================================================
--  as-vehiclekeys (client) — QBox / QBCore
-- ============================================================================
local access = {}   -- [PLATE] = { has = bool, t = ms }
local sessionAccess = {}   -- [PLATE] = true  (hotwire/lockpick/carjack — never expires this session)
local engineRan = {}       -- [PLATE] = true  (a hotwired car's engine has run at least once)
local pickedOpen = {}      -- [PLATE] = true  (lockpicked open — don't re-lock, but no drive access)

local function trim(p) return (p or ''):gsub('%s+$', ''):upper() end
local function notify(msg, kind) lib.notify({ title = 'Vehicle Keys', description = msg, type = kind or 'inform' }) end
local function plateOf(veh) return trim(GetVehicleNumberPlateText(veh)) end
local function vehLabel(veh)
    local n = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
    if not n or n == '' or n == 'NULL' then n = GetDisplayNameFromVehicleModel(GetEntityModel(veh)) end
    return n
end

-- ---- access lookup (cached, refreshed from the server) ---------------------
local function fetchAccess(plate, force)
    plate = trim(plate)
    if sessionAccess[plate] then return true end          -- temporary access persists all session
    local c = access[plate]
    if not force and c and (GetGameTimer() - c.t) < 8000 then return c.has end
    local has = lib.callback.await('as-vehiclekeys:hasKeys', false, plate)
    access[plate] = { has = has and true or false, t = GetGameTimer() }
    return access[plate].has
end
local function setLocal(plate, has) access[trim(plate)] = { has = has and true or false, t = GetGameTimer() } end
-- temporary (session) grant from hotwire / lockpick / carjack — sticks until relog
local function grantSession(plate) plate = trim(plate); sessionAccess[plate] = true; engineRan[plate] = nil end
local function hasSession(plate) return sessionAccess[trim(plate)] == true end
local function revokeSession(plate)
    plate = trim(plate)
    sessionAccess[plate] = nil
    engineRan[plate] = nil
    access[plate] = nil            -- force a fresh server check next time (returns false → keyless)
end

RegisterNetEvent('as-vehiclekeys:setAccess', function(plate, has) setLocal(plate, has) end)

-- carjack state (used by the keys-to-drive loop and the carjack threads)
local carjacked = {}   -- [PLATE] = true  (marked when jacked/threatened out)
local function markCarjacked(veh)
    if veh and veh ~= 0 and DoesEntityExist(veh) then carjacked[trim(GetVehicleNumberPlateText(veh))] = true end
end
local function grantCarjack(veh, plate)
    carjacked[plate] = nil
    grantSession(plate)
    if Config.Carjack.giveKeyItem then
        TriggerServerEvent('as-vehiclekeys:hotwireGiveKey', plate, GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh))))
    else
        lib.callback.await('as-vehiclekeys:tempAccess', false, plate)
    end
    lib.notify({ title = 'Vehicle Keys', description = 'You grabbed the keys from the driver.', type = 'success' })
end

-- ---- dusa NUI hotwire minigame ---------------------------------------------
-- The cable-cutting UI lives in web/. It is self-contained: we open it, it posts
-- back hotwiresuccess / hotwirefailed / closeui, and we resolve a promise from
-- whichever arrives first. Nothing else in this resource uses NUI, so there is no
-- focus state to fight over.
local hotwirePromise = nil

local function resolveHotwire(result)
    SetNuiFocus(false, false)
    ClearPedTasks(PlayerPedId())
    if hotwirePromise then
        local p = hotwirePromise
        hotwirePromise = nil
        p:resolve(result)
    end
end

RegisterNUICallback('hotwiresuccess', function(_, cb)
    cb('ok')
    resolveHotwire(true)
end)

RegisterNUICallback('hotwirefailed', function(_, cb)
    cb('ok')
    -- dusa shocked the player here; keep the sting but don't hard-code damage
    local ped = PlayerPedId()
    SetEntityHealth(ped, math.max(GetEntityHealth(ped) - 5, 101))
    SetFlash(0, 0, 100, 10000, 100)
    resolveHotwire(false)
end)

-- Fired when the player presses ESC, and also after success/fail as the UI closes.
-- Treated as a cancel only if nothing has resolved yet.
RegisterNUICallback('closeui', function(_, cb)
    cb('ok')
    resolveHotwire(false)
end)

-- The fob endpoints exist in the ported UI but nothing here opens that screen.
-- They are registered so a stray POST can't spam "no such NUI callback".
for _, name in ipairs({ 'trunk', 'engine', 'light', 'togglelock' }) do
    RegisterNUICallback(name, function(_, cb) cb('ok') end)
end

---@param class number vehicle class, used to pick the success chance
---@return boolean
local function runDusaHotwire(class)
    if hotwirePromise then return false end

    local cfg = Config.DusaHotwire or {}
    local chance = (cfg.classChance and cfg.classChance[class]) or cfg.chance or 50

    hotwirePromise = promise.new()

    SendNUIMessage({ action = 'open', hotwirechance = chance })
    SetNuiFocus(true, true)

    if cfg.playAnim ~= false then
        local dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@'
        RequestAnimDict(dict)
        local t = GetGameTimer()
        while not HasAnimDictLoaded(dict) and GetGameTimer() - t < 500 do Wait(0) end
        TaskPlayAnim(PlayerPedId(), dict, 'machinic_loop_mechandplayer', 3.0, 1.0, -1, 49, 1, false, false, false)
    end

    return Citizen.Await(hotwirePromise) == true
end

-- run the configured minigame; returns true/false. `tier` picks t3 tuning.
-- `extraPins` adds difficulty on top (used to scale hotwire by vehicle class).
local function runMinigame(kind, tier, extraPins, class)
    extraPins = extraPins or 0

    -- Hotwiring can use a different minigame to lockpicking. Lockpicking is left
    -- on t3_lockpick; only the hotwire is swapped for the NUI cable puzzle.
    if kind == 'hotwire' and Config.HotwireMinigame == 'dusa' then
        return runDusaHotwire(class)
    end

    local minigame = (kind == 'hotwire' and Config.HotwireMinigame ~= 'dusa')
        and Config.HotwireMinigame or Config.Minigame

    if minigame == 't3' and GetResourceState('t3_lockpick') == 'started' then
        local t = (Config.T3 and Config.T3[tier]) or { strength = 0.5, difficulty = 2, pins = 5 }
        return exports['t3_lockpick']:startLockpick(t.strength, t.difficulty, (t.pins or 5) + extraPins) == true
    end
    -- fallback: ox_lib skill check (append an extra step per 2 extra pins)
    local diff
    if kind == 'hotwire' then diff = { table.unpack(Config.Hotwire.difficulty or { 'easy', 'medium' }) }
    else diff = { table.unpack((Config.Lockpick.difficulty or {})[tier] or { 'easy', 'medium' }) } end
    for _ = 1, math.floor(extraPins / 2) do diff[#diff + 1] = 'hard' end
    return lib.skillCheck(diff) == true
end

-- ---- helpers ---------------------------------------------------------------
local function nearestVehicle(maxDist)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return veh end
    local pos = GetEntityCoords(ped)
    local handle = GetClosestVehicle(pos.x, pos.y, pos.z, maxDist or Config.LockDistance, 0, 71)
    if handle ~= 0 and DoesEntityExist(handle) then return handle end
    return nil
end
local function vehicleByPlate(plate, maxDist)
    plate = trim(plate)
    local pos = GetEntityCoords(PlayerPedId())
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if plateOf(veh) == plate and #(pos - GetEntityCoords(veh)) < (maxDist or Config.LockDistance) then return veh end
    end
    return nil
end
local function keyFob()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    RequestAnimDict('anim@mp_player_intmenu@key_fob@')
    local t = GetGameTimer()
    while not HasAnimDictLoaded('anim@mp_player_intmenu@key_fob@') and GetGameTimer() - t < 400 do Wait(0) end
    TaskPlayAnim(ped, 'anim@mp_player_intmenu@key_fob@', 'fob_click', 3.0, 3.0, -1, 48, 0, false, false, false)
end
local function chirp(veh)
    if not Config.HornOnLock then return end
    SetVehicleLights(veh, 2); Wait(120); SetVehicleLights(veh, 0)
    StartVehicleHorn(veh, 90, GetHashKey('HELDDOWN'), false)
end

-- ---- lock / unlock ---------------------------------------------------------
local function toggleLockOn(veh)
    if not veh or not DoesEntityExist(veh) then return end
    local plate = plateOf(veh)
    -- locking requires a REAL key item — hotwire/lockpick session access can drive but not lock
    local realKey = lib.callback.await('as-vehiclekeys:hasKeys', false, plate)
    if not realKey then
        notify(hasSession(plate) and "You only hotwired this — no key to lock it." or "You don't have a key for this vehicle.", 'error')
        return
    end
    local lockNow = (GetVehicleDoorLockStatus(veh) ~= 2)
    local doorState = lockNow and 2 or 1

    -- Ask for network control before touching lock natives — otherwise the
    -- change is only visible on this client and never reaches anyone else
    -- standing nearby (this was the root cause of locks not syncing).
    NetworkRequestControlOfEntity(veh)
    local attempts = 0
    while not NetworkHasControlOfEntity(veh) and attempts < 20 do
        Wait(0)
        NetworkRequestControlOfEntity(veh)
        attempts = attempts + 1
    end

    SetVehicleDoorsLocked(veh, doorState)
    SetVehicleDoorsLockedForAllPlayers(veh, lockNow)

    -- Broadcast the change through the server so every other nearby client
    -- (not just this one) applies the new lock state.
    local netId = NetworkGetNetworkIdFromEntity(veh)
    TriggerServerEvent('as-vehiclekeys:server:toggleLock', netId, doorState)

    keyFob(); chirp(veh)
    notify((lockNow and 'Locked ' or 'Unlocked ') .. plate, lockNow and 'inform' or 'success')
end

RegisterCommand('vk_lock', function() toggleLockOn(nearestVehicle(Config.LockDistance)) end, false)
RegisterKeyMapping('vk_lock', 'Lock / unlock nearest vehicle', 'keyboard', Config.Keys.lock)

-- using the key item toggles that specific vehicle's lock
RegisterNetEvent('as-vehiclekeys:useKey', function(plate)
    setLocal(plate, true)
    local veh = vehicleByPlate(plate, Config.LockDistance)
    if veh then toggleLockOn(veh) else notify('That vehicle is not nearby.', 'error') end
end)

-- ---- require keys to drive -------------------------------------------------
if Config.RequireKeysToDrive then
    CreateThread(function()
        local lastVeh = 0
        local graceUntil = 0
        local engineKilled = {}   -- [PLATE] = true once we've forced the engine off for lack of access

        while true do
            local wait = 800
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
                local plate = plateOf(veh)
                if veh ~= lastVeh then
                    lastVeh = veh
                    fetchAccess(plate, true)                      -- fresh check on entry
                    -- Always give at least a short grace window on entry, even if
                    -- Config.EngineGrace is 0 — a freshly spawned/handed-over vehicle
                    -- can have a real key that just hasn't finished registering
                    -- server-side yet, and we don't want that instant to be final.
                    graceUntil = GetGameTimer() + math.max((Config.EngineGrace or 0), 1.5) * 1000
                    engineKilled[plate] = nil
                end
                if carjacked[plate] and not fetchAccess(plate) then
                    grantCarjack(veh, plate)                      -- took keys from the NPC driver
                end
                if fetchAccess(plate) then
                    -- Self-heal: if we previously killed the engine for this vehicle
                    -- because access looked missing, and it now checks out (e.g. the
                    -- key just finished syncing), give the engine back rather than
                    -- leaving the player stuck demanding a hotwire forever.
                    if engineKilled[plate] then
                        engineKilled[plate] = nil
                        ClearAllHelpMessages()
                    end
                else
                    if GetGameTimer() < graceUntil then
                        wait = 200                                -- grace: let it sputter a moment
                    else
                        wait = 0
                        SetVehicleEngineOn(veh, false, true, true)
                        engineKilled[plate] = true
                        if Config.Hotwire.enabled then
                            BeginTextCommandDisplayHelp('STRING')
                            AddTextComponentSubstringPlayerName(('Press [%s] to hotwire'):format(Config.Keys.hotwire))
                            EndTextCommandDisplayHelp(0, false, true, -1)
                        end
                    end
                end
            else
                lastVeh = 0
            end
            Wait(wait)
        end
    end)
end

-- ---- hotwired cars can stall / lose the hotwire when the engine dies --------
if Config.Hotwire.enabled and (Config.Hotwire.loseOnEngineOff or Config.Hotwire.loseOnExit or (Config.Hotwire.stall and Config.Hotwire.stall.enabled)) then
    CreateThread(function()
        local stallCfg = Config.Hotwire.stall or {}
        local lastStall = 0
        local lastVeh, lastPlate = 0, nil
        while true do
            local wait = 1000
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            local inDriver = veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped

            if inDriver then
                local plate = plateOf(veh)
                lastVeh, lastPlate = veh, plate
                if hasSession(plate) then
                    wait = 500
                    local running = GetIsVehicleEngineRunning(veh)
                    if running then engineRan[plate] = true end
                    -- random stall while driving
                    if stallCfg.enabled and running and GetGameTimer() - lastStall > (stallCfg.interval or 8000) then
                        lastStall = GetGameTimer()
                        if math.random(100) <= (stallCfg.chance or 0) then
                            SetVehicleEngineOn(veh, false, false, true)
                            running = false
                            notify('The engine stalls — hotwire it again.', 'error')
                        end
                    end
                    -- lose the hotwire once the engine has run and then cut out (in-seat stall)
                    if Config.Hotwire.loseOnEngineOff and engineRan[plate] and not running then
                        revokeSession(plate)
                    end
                end
            else
                -- just left / no longer driving the tracked car
                if lastPlate and hasSession(lastPlate) then
                    if Config.Hotwire.loseOnExit then
                        revokeSession(lastPlate)
                    else
                        engineRan[lastPlate] = nil   -- reset so re-entry doesn't count the exit-off as a stall
                    end
                end
                lastVeh, lastPlate = 0, nil
            end
            Wait(wait)
        end
    end)
end

-- ---- hotwire (driver seat, no key) -----------------------------------------
if Config.Hotwire.enabled then
    CreateThread(function()
        while true do
            local wait = 500
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and not fetchAccess(plateOf(veh)) then
                wait = 0
                if IsControlJustPressed(0, 74) then   -- H
                    local plate = plateOf(veh)
                    local class = GetVehicleClass(veh)
                    if Config.HotwireClass and Config.HotwireClass.blocked and Config.HotwireClass.blocked[class] then
                        notify("This vehicle can't be hotwired.", 'error'); Wait(1000)
                    else
                        -- must hold a lockpick (basic or advanced)
                        local tier = lib.callback.await('as-vehiclekeys:pickTier', false, 'hotwire')
                        if not tier then notify('You need a lockpick to hotwire.', 'error'); Wait(800)
                        else
                            local extra = (Config.HotwireClass and (Config.HotwireClass.extraPins[class] or Config.HotwireClass.defaultExtraPins)) or 0
                            local success = runMinigame('hotwire', tier, extra, class)
                            TriggerServerEvent('as-vehiclekeys:pickResult', 'hotwire', success, tier)
                            if success then
                                if Config.Hotwire.giveKeyItem then
                                    TriggerServerEvent('as-vehiclekeys:hotwireGiveKey', plate, vehLabel(veh))
                                else
                                    lib.callback.await('as-vehiclekeys:tempAccess', false, plate)
                                end
                                grantSession(plate)
                                notify('Hotwired — engine will start.', 'success')
                            else
                                notify('Hotwire failed.', 'error'); Wait(1500)
                            end
                        end
                    end
                end
            end
            Wait(wait)
        end
    end)
end

-- ---- lockpick (ox_target on a locked car, or optional /command) ------------
local function doLockpick(veh)
    veh = (veh and veh ~= 0) and veh or nearestVehicle(3.0)
    if not veh or not DoesEntityExist(veh) then notify('No vehicle nearby.', 'error'); return end
    local plate = plateOf(veh)
    if fetchAccess(plate) then notify('You already have a key for this one.', 'inform'); return end
    if GetVehicleDoorLockStatus(veh) ~= 2 then notify('That vehicle is already unlocked.', 'inform'); return end

    -- must hold a lockpick (item is checked, not consumed on use)
    local tier = lib.callback.await('as-vehiclekeys:pickTier', false, 'lockpick')
    if not tier then notify('You need a lockpick.', 'error'); return end

    local success = runMinigame('lockpick', tier)
    TriggerServerEvent('as-vehiclekeys:pickResult', 'lockpick', success, tier)
    if success then
        -- picking only gets you IN — door unlocked, but you still need to hotwire to drive
        SetVehicleDoorsLocked(veh, 1)
        SetVehicleDoorsLockedForAllPlayers(veh, false)
        pickedOpen[plate] = true            -- don't let the ambient sweep re-lock it
        notify('Lock picked — you\'re in, but you\'ll need to hotwire it.', 'success')
    else
        notify('Failed to pick the lock.', 'error')
    end
end

if Config.Lockpick.enabled then
    if Config.Lockpick.useTarget and GetResourceState('ox_target') == 'started' then
        exports.ox_target:addGlobalVehicle({
            {
                name     = 'as-vehiclekeys_lockpick',
                icon     = 'fa-solid fa-unlock',
                label    = 'Lockpick',
                distance = 2.0,
                -- only show on locked cars you don't already have a key for
                canInteract = function(entity)
                    if not entity or entity == 0 then return false end
                    if GetVehicleDoorLockStatus(entity) ~= 2 then return false end
                    return not fetchAccess(plateOf(entity))
                end,
                onSelect = function(data) doLockpick(data.entity) end,
            },
        })
    end
    if Config.Lockpick.command then
        RegisterCommand(Config.Lockpick.command, function() doLockpick(nil) end, false)
    end
end

-- ---- give keys to a nearby player ------------------------------------------
local function nearestPlayerId()
    local me = PlayerPedId(); local pos = GetEntityCoords(me)
    local best, bestD = nil, 5.0
    for _, pid in ipairs(GetActivePlayers()) do
        local p = GetPlayerPed(pid)
        if p ~= me and DoesEntityExist(p) then
            local d = #(pos - GetEntityCoords(p))
            if d < bestD then best, bestD = pid, d end
        end
    end
    return best and GetPlayerServerId(best) or nil
end

RegisterCommand(Config.GiveKeysCommand, function(_, args)
    local veh = nearestVehicle(Config.GiveKeysDistance)
    if not veh then notify('Get in or stand by the vehicle first.', 'error'); return end
    local plate = plateOf(veh)
    if not fetchAccess(plate) then notify("You don't have a key for this vehicle.", 'error'); return end
    local target = tonumber(args[1]) or nearestPlayerId()
    if not target then notify('No nearby player to give a key to.', 'error'); return end
    TriggerServerEvent('as-vehiclekeys:giveKeys', target, plate, vehLabel(veh))
end, false)

-- ---- police tool: pull a key from the nearest vehicle ----------------------
RegisterNetEvent('as-vehiclekeys:policePrompt', function()
    local veh = nearestVehicle(5.0)
    if not veh then notify('No vehicle nearby.', 'error'); return end
    if lib.progressCircle({ label = 'Cutting a key…', duration = 4000, useWhileDead = false, canCancel = true,
        disable = { move = true, car = true } }) then
        TriggerServerEvent('as-vehiclekeys:policePull', plateOf(veh), vehLabel(veh))
    else
        notify('Cancelled.', 'error')
    end
end)

exports('HasKey', function(plate) return fetchAccess(plate) end)

-- ---- lock ambient / parked NPC vehicles ------------------------------------
if Config.LockAmbient.enabled then
    CreateThread(function()
        local cfg = Config.LockAmbient
        while true do
            local pos = GetEntityCoords(PlayerPedId())
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                local pop = GetEntityPopulationType(veh)          -- 1-5 = ambient/random traffic & parked
                if pop >= 1 and pop <= 5 and #(pos - GetEntityCoords(veh)) < cfg.radius then
                    local plate = plateOf(veh)
                    if pickedOpen[plate] then
                        -- once picked, keep it unlocked even if the game re-locks it
                        if GetVehicleDoorLockStatus(veh) == 2 then
                            SetVehicleDoorsLocked(veh, 1)
                            SetVehicleDoorsLockedForAllPlayers(veh, false)
                        end
                    else
                        local mine = (access[plate] and access[plate].has) or carjacked[plate]
                        local empty = (not cfg.onlyEmpty) or IsVehicleSeatFree(veh, -1)
                        local class = GetVehicleClass(veh)
                        local skipClass = cfg.leaveUnlockedClasses and cfg.leaveUnlockedClasses[class]
                        if not mine and empty and not skipClass and GetVehicleDoorLockStatus(veh) ~= 2 then
                            SetVehicleDoorsLocked(veh, 2)
                        end
                    end
                end
            end
            Wait(cfg.interval or 3000)
        end
    end)
end

-- ---- carjacking (NPC-driven vehicles) --------------------------------------
if Config.Carjack.enabled then
    -- physically pulling an NPC out (jack)
    CreateThread(function()
        while true do
            local wait = 400
            local ped = PlayerPedId()
            if IsPedJacking(ped) then
                wait = 0
                local veh = GetVehiclePedIsTryingToEnter(ped)
                if veh == 0 then veh = GetVehiclePedIsIn(ped, true) end
                if veh ~= 0 then markCarjacked(veh) end
            end
            Wait(wait)
        end
    end)

    -- threatening the NPC driver out at gunpoint
    if Config.Carjack.gunpoint.enabled then
        CreateThread(function()
            local threatPed, threatStart = nil, 0
            while true do
                local wait = 250
                local player = PlayerId()
                local handled = false
                if IsPlayerFreeAiming(player) then
                    local aiming, entity = GetEntityPlayerIsFreeAimingAt(player)
                    if aiming and entity and entity ~= 0 and IsEntityAPed(entity) and not IsPedAPlayer(entity) then
                        local veh = GetVehiclePedIsIn(entity, false)
                        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == entity then
                            wait = 0; handled = true
                            if threatPed ~= entity then threatPed = entity; threatStart = GetGameTimer() end
                            if GetGameTimer() - threatStart > (Config.Carjack.gunpoint.holdTime or 700) then
                                markCarjacked(veh)
                                SetPedFleeAttributes(entity, 0, false)
                                ClearPedTasksImmediately(entity)
                                TaskLeaveVehicle(entity, veh, 4160)
                                Wait(600)
                                TaskSmartFleePed(entity, PlayerPedId(), 100.0, -1, false, false)
                                notify('The driver panics and bails, leaving the keys!', 'success')
                                threatPed = nil
                                Wait(1500)
                            end
                        end
                    end
                end
                if not handled then threatPed = nil end
                Wait(wait)
            end
        end)
    end
end

-- /returnkeys — reclaim a key for a vehicle you own but lost the key to
RegisterCommand('returnkeys', function()
    local veh = nearestVehicle(Config.LockDistance)
    if not veh then notify('Get in or stand by the vehicle first.', 'error'); return end
    TriggerServerEvent('as-vehiclekeys:returnMyKey', plateOf(veh))
end, false)

-- apply a lock state pushed from the server
RegisterNetEvent('as-vehiclekeys:applyLock', function(netId, state)
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if veh and veh ~= 0 and DoesEntityExist(veh) then SetVehicleDoorsLocked(veh, state) end
end)

-- Set a vehicle's lock state locally (1 = unlocked, 2 = locked). Entity or plate.
exports('SetLockState', function(vehicle, state)
    if type(vehicle) == 'string' then vehicle = vehicleByPlate(vehicle, 100.0) end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    SetVehicleDoorsLocked(vehicle, state)
    SetVehicleDoorsLockedForAllPlayers(vehicle, state == 2)
    return true
end)

-- qbx_vehiclekeys drop-in (accepts a vehicle entity, or a plate string)
exports('HasKeys', function(vehicle)
    if type(vehicle) == 'string' then return fetchAccess(vehicle) end
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    return fetchAccess(plateOf(vehicle))
end)
