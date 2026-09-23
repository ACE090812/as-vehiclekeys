-- ============================================================================
--  as-vehiclekeys (server) — QBox / QBCore + ox/qb inventory
-- ============================================================================
local FW = Config.Framework
if not FW then
    if GetResourceState('qbx_core') == 'started' then FW = 'qbox'
    elseif GetResourceState('qb-core') == 'started' then FW = 'qb' end
end
local INV = Config.Inventory
if not INV then
    if GetResourceState('ox_inventory') == 'started' then INV = 'ox'
    elseif GetResourceState('qb-inventory') == 'started' then INV = 'qb' end
end
local QB = (FW == 'qb') and exports['qb-core']:GetCoreObject() or nil

local KEY = Config.Items.key
local function trim(p) return (p or ''):gsub('%s+$', ''):upper() end
local function dbg(...) if Config.Debug then print('^3[vehiclekeys]^7', ...) end end
-- Plates are compared ignoring case and ALL spaces, so 'AB12 CDE', 'AB12CDE' and 'ab12cde ' are the same plate.
local function norm(p) return ((tostring(p or '')):gsub('%s+', ''):upper()) end

CreateThread(function()
    Wait(500)
    dbg(('framework=%s inventory=%s keyItem=%s'):format(tostring(FW), tostring(INV), tostring(KEY)))
end)

local function getPlayer(src)
    if FW == 'qbox' then return exports.qbx_core:GetPlayer(src)
    elseif FW == 'qb' then return QB.Functions.GetPlayer(src) end
end
local function jobName(src)
    local p = getPlayer(src)
    return p and p.PlayerData and p.PlayerData.job and p.PlayerData.job.name or nil
end
local function isPolice(src)
    local j = jobName(src); if not j then return false end
    for _, allowed in ipairs(Config.PoliceJobs) do if j == allowed then return true end end
    return false
end
local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Vehicle Keys', description = msg, type = kind or 'inform' })
end

local function invHasItem(src, item)
    if INV == 'ox' then
        return (exports.ox_inventory:Search(src, 'count', item) or 0) > 0
    else
        local p = getPlayer(src); if not p then return false end
        local it = p.Functions.GetItemByName(item)
        return it ~= nil and (it.amount or it.count or 0) > 0
    end
end

local function invRemoveItem(src, item, count)
    count = count or 1
    if INV == 'ox' then
        return exports.ox_inventory:RemoveItem(src, item, count) and true or false
    else
        local p = getPlayer(src); if not p then return false end
        return p.Functions.RemoveItem(item, count) and true or false
    end
end

-- ---- inventory bridge (keys) ----------------------------------------------
local function keyMeta(plate, vehicle)
    plate = trim(plate)
    return { plate = plate, vehicle = vehicle or 'Vehicle', description = ('%s\nPlate: %s'):format(vehicle or 'Vehicle', plate) }
end

local function giveKeyItem(src, plate, vehicle)
    plate = trim(plate)
    if hasKeyItem(src, plate) then dbg(('give %s: already has key'):format(plate)); return true end       -- no duplicates
    local ok
    if INV == 'ox' then
        ok = exports.ox_inventory:AddItem(src, KEY, 1, keyMeta(plate, vehicle)) and true or false
    else
        local p = getPlayer(src)
        ok = p and p.Functions.AddItem(KEY, 1, nil, keyMeta(plate, vehicle)) and true or false
    end
    dbg(('give %s to src %s -> %s (inv=%s)'):format(plate, tostring(src), tostring(ok), tostring(INV)))
    return ok
end

function hasKeyItem(src, plate)
    plate = trim(plate)
    if INV == 'ox' then
        local seen = {}
        for _, it in ipairs(exports.ox_inventory:Search(src, 'slots', KEY) or {}) do
            seen[#seen + 1] = ('[%s]'):format(tostring(it.metadata and it.metadata.plate))
            if it.metadata and it.metadata.plate and norm(it.metadata.plate) == norm(plate) then return true end
        end
        dbg(('hasKey src=%s wants [%s]: keys on player carry %s'):format(tostring(src), plate, #seen > 0 and table.concat(seen, ' ') or 'none'))
        return false
    else
        local p = getPlayer(src); if not p then return false end
        for _, it in ipairs(p.Functions.GetItemsByName(KEY) or {}) do
            if it.info and trim(it.info.plate) == plate then return true end
        end
        return false
    end
end

local function takeKeyItem(src, plate)
    plate = trim(plate)
    local ok = false
    if INV == 'ox' then
        local items = exports.ox_inventory:Search(src, 'slots', KEY) or {}
        local seen = {}
        for _, it in ipairs(items) do
            local mp = it.metadata and it.metadata.plate
            seen[#seen + 1] = tostring(mp)
            if mp and norm(mp) == norm(plate) then
                ok = exports.ox_inventory:RemoveItem(src, KEY, 1, nil, it.slot) and true or false
                break
            end
        end
        dbg(('take %s: keys on player carry plates [%s]'):format(plate, table.concat(seen, ', ')))
    else
        local p = getPlayer(src)
        if p then
            for _, it in ipairs(p.Functions.GetItemsByName(KEY) or {}) do
                if it.info and trim(it.info.plate) == plate then p.Functions.RemoveItem(KEY, 1, it.slot); ok = true; break end
            end
        end
    end
    dbg(('take %s from src %s -> %s'):format(plate, tostring(src), tostring(ok)))
    return ok
end

local function pushAccess(src, plate, has)
    TriggerClientEvent('as-vehiclekeys:setAccess', src, trim(plate), has)
end

-- ---- external integration (lockpick / steal minigame resources) ------------
-- drop-in for qb-vehiclekeys:server:setVehLockState (netId, state)
RegisterNetEvent('as-vehiclekeys:server:setVehLockState', function(netId, state)
    if not netId then return end
    TriggerClientEvent('as-vehiclekeys:applyLock', -1, netId, state)
end)

-- Normal player-triggered lock/unlock (key item / vk_lock bind) must also
-- broadcast to everyone, not just apply the state on the caller's own client.
RegisterNetEvent('as-vehiclekeys:server:toggleLock', function(netId, state)
    local src = source
    if not netId then return end
    -- state: 1 = unlocked, 2 = locked
    TriggerClientEvent('as-vehiclekeys:applyLock', -1, netId, state)
end)

-- Grant session access for a vehicle by its network id (e.g. after a hotwire
-- minigame). Mirrors qbx_vehiclekeys:server:hotwiredVehicle.
RegisterNetEvent('as-vehiclekeys:server:hotwiredVehicle', function(netId)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    pushAccess(src, trim(GetVehicleNumberPlateText(veh)), true)
end)

-- Give a persistent key item by network id (e.g. a dealership/lockpick that
-- should hand over a real key). vehicle label is optional.
RegisterNetEvent('as-vehiclekeys:server:giveKeyByNetId', function(netId, vehicle)
    local src = source
    local veh = netId and NetworkGetEntityFromNetworkId(netId) or 0
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    local plate = trim(GetVehicleNumberPlateText(veh))
    if giveKeyItem(src, plate, vehicle) then pushAccess(src, plate, true) end
end)

-- ---- callbacks used by the client -----------------------------------------
lib.callback.register('as-vehiclekeys:hasKeys', function(src, plate)
    return hasKeyItem(src, plate)
end)

-- hotwire success → give a real key item (client passes plate + label)
RegisterNetEvent('as-vehiclekeys:hotwireGiveKey', function(plate, vehicle)
    local src = source
    plate = trim(plate)
    if giveKeyItem(src, plate, vehicle) then pushAccess(src, plate, true) end
end)

-- hotwire / lockpick grant session access only (no persistent item)
lib.callback.register('as-vehiclekeys:tempAccess', function(src, plate)
    return true   -- client tracks temp access locally; server just acknowledges
end)

-- which lockpick tier does the player hold, for a given action ('hotwire'|'lockpick')?
-- returns 'advanced' | 'basic' | false
lib.callback.register('as-vehiclekeys:pickTier', function(src, action)
    local cfg = (action == 'hotwire') and Config.Hotwire or Config.Lockpick
    local items = cfg and cfg.items or {}
    if items.advanced and invHasItem(src, items.advanced) then return 'advanced' end
    if items.basic and invHasItem(src, items.basic) then return 'basic' end
    return false
end)

-- consume the pick if it snapped on failure (per action + tier)
RegisterNetEvent('as-vehiclekeys:pickResult', function(action, success, tier)
    local src = source
    local cfg = (action == 'hotwire') and Config.Hotwire or Config.Lockpick
    local items = cfg and cfg.items or {}
    local breakOn = cfg and cfg.breakOnFail or {}
    if not success and breakOn[tier] and items[tier] then
        invRemoveItem(src, items[tier], 1)
        notify(src, 'Your lockpick snapped.', 'error')
    end
end)

-- ---- give keys to a nearby player (copy of the key item) -------------------
RegisterNetEvent('as-vehiclekeys:giveKeys', function(target, plate, vehicle)
    local src = source
    plate = trim(plate)
    if not hasKeyItem(src, plate) then notify(src, "You don't have a key for that vehicle.", 'error'); return end
    target = tonumber(target)
    if not target or not getPlayer(target) then notify(src, 'That player is not available.', 'error'); return end
    if giveKeyItem(target, plate, vehicle) then
        pushAccess(target, plate, true)
        notify(src, ('Gave a key for %s.'):format(plate), 'success')
        notify(target, ('You received a key for %s (%s).'):format(vehicle or 'vehicle', plate), 'success')
    else
        notify(src, 'They have no room for the key.', 'error')
    end
end)

-- ---- police tool: pull a key from a nearby vehicle -------------------------
RegisterNetEvent('as-vehiclekeys:policePull', function(plate, vehicle)
    local src = source
    if not isPolice(src) then notify(src, 'Only police can use this.', 'error'); return end
    plate = trim(plate)
    if giveKeyItem(src, plate, vehicle) then
        pushAccess(src, plate, true)
        notify(src, ('Extracted a key for %s (%s).'):format(vehicle or 'vehicle', plate), 'success')
    else
        notify(src, 'Could not extract a key (already have one?).', 'inform')
    end
end)

-- ============================================================================
--  EXPORTS — call these from your garage on store / retrieve
-- ============================================================================
-- Vehicle taken OUT of the garage → give the owner their key item.
exports('GiveKey', function(src, plate, vehicle)
    dbg(('GiveKey export: src=%s plate=%s'):format(tostring(src), tostring(plate)))
    local ok = giveKeyItem(src, plate, vehicle)
    if ok then pushAccess(src, plate, true) end
    return ok
end)

-- Vehicle put AWAY in the garage → take the key item back off the player.
exports('TakeKey', function(src, plate)
    dbg(('TakeKey export: src=%s plate=%s'):format(tostring(src), tostring(plate)))
    local ok = takeKeyItem(src, plate)
    pushAccess(src, plate, false)
    return ok
end)

exports('HasKey', function(src, plate) return hasKeyItem(src, plate) end)

-- ---- return lost keys ------------------------------------------------------
local function ownsPlate(src, plate)
    local cid = getPlayer(src) and getPlayer(src).PlayerData and getPlayer(src).PlayerData.citizenid
    if not cid then return false, nil end
    local row = MySQL.single.await('SELECT plate, vehicle FROM player_vehicles WHERE citizenid = ? AND TRIM(plate) = ? LIMIT 1', { cid, plate })
    return row ~= nil, row
end

-- owner reclaims a key for a vehicle they own (e.g. dropped/lost it)
RegisterNetEvent('as-vehiclekeys:returnMyKey', function(plate)
    local src = source
    plate = trim(plate)
    if hasKeyItem(src, plate) then notify(src, 'You already have that key.', 'inform'); return end
    local owns, row = ownsPlate(src, plate)
    if not owns then notify(src, 'That vehicle is not registered to you.', 'error'); return end
    if giveKeyItem(src, plate, row.vehicle) then
        pushAccess(src, plate, true)
        notify(src, ('Re-issued your key for %s.'):format(plate), 'success')
    end
end)

-- admin: give any player a key for any plate  /returnkey [id] [plate]
lib.addCommand('returnkey', { help = 'Re-issue a vehicle key to a player', restricted = 'group.admin',
    params = { { name = 'id', type = 'playerId' }, { name = 'plate', type = 'string' } }
}, function(source, args)
    local target, plate = args.id, trim(args.plate)
    local row = MySQL.single.await('SELECT vehicle FROM player_vehicles WHERE TRIM(plate) = ? LIMIT 1', { plate })
    local label = row and row.vehicle or 'Vehicle'
    if giveKeyItem(target, plate, label) then
        pushAccess(target, plate, true)
        notify(source, ('Gave %s a key for %s.'):format(target, plate), 'success')
        notify(target, ('An admin re-issued your key for %s.'):format(plate), 'success')
    else
        notify(source, 'Could not give the key (inventory full?).', 'error')
    end
end)

-- Drop-in compatibility with qbx_vehiclekeys (entity-based):
--   exports.as-vehiclekeys:GiveKeys(src, vehicleEntity)
--   exports.as-vehiclekeys:RemoveKeys(src, vehicleEntity)
exports('GiveKeys', function(src, vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local plate = trim(GetVehicleNumberPlateText(vehicle))
    local label = GetEntityArchetypeName and GetEntityArchetypeName(vehicle) or 'Vehicle'
    local ok = giveKeyItem(src, plate, label)
    if ok then pushAccess(src, plate, true) end
    return ok
end)
exports('RemoveKeys', function(src, vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return false end
    local plate = trim(GetVehicleNumberPlateText(vehicle))
    local ok = takeKeyItem(src, plate)
    pushAccess(src, plate, false)
    return ok
end)

-- Set a vehicle's lock state from the server (1 = unlocked, 2 = locked).
-- Accepts a server-side entity handle or a network id. Syncs to all clients.
exports('SetLockState', function(vehicle, state)
    local netId
    if type(vehicle) == 'number' and vehicle ~= 0 then
        if DoesEntityExist(vehicle) then netId = NetworkGetNetworkIdFromEntity(vehicle)
        else netId = vehicle end
    end
    if not netId then return false end
    TriggerClientEvent('as-vehiclekeys:applyLock', -1, netId, state)
    return true
end)

-- ---- usable items ----------------------------------------------------------
-- Using a key item → toggle the lock of that specific vehicle.
local function onUseKey(src, meta)
    local plate = meta and meta.plate
    if not plate then return end
    TriggerClientEvent('as-vehiclekeys:useKey', src, trim(plate))
end
-- Using the police tool → ask the client for the nearest vehicle, then grant a key.
local function onUsePolice(src)
    if not isPolice(src) then notify(src, 'Only police can use this.', 'error'); return end
    TriggerClientEvent('as-vehiclekeys:policePrompt', src)
end

if INV == 'qb' then
    QB = QB or exports['qb-core']:GetCoreObject()
    QB.Functions.CreateUseableItem(Config.Items.key, function(src, item)
        onUseKey(src, item and item.info)
    end)
    QB.Functions.CreateUseableItem(Config.Items.police, function(src)
        onUsePolice(src)
    end)
end

-- ox_inventory calls these exports when the item is used (see /installation).
exports('useKey', function(event, item, inventory, slot, data)
    if event ~= 'usedItem' then return end
    local src = type(inventory) == 'table' and inventory.id or inventory
    onUseKey(src, item and item.metadata)
end)
exports('usePoliceTool', function(event, item, inventory, slot, data)
    if event ~= 'usedItem' then return end
    local src = type(inventory) == 'table' and inventory.id or inventory
    onUsePolice(src)
end)

if not FW then print('^1[as-vehiclekeys] No supported framework (qb / qbox) detected.^0') end
if not INV then print('^1[as-vehiclekeys] No supported inventory (ox_inventory / qb-inventory) detected.^0') end
