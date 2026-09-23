-- ============================================================================
--  qb-core items — add these to  qb-core/shared/items.lua
--  (Usable behaviour is registered in code, no export line needed for qb.)
-- ============================================================================

['vehiclekeys'] = {
    ['name'] = 'vehiclekeys',
    ['label'] = 'Vehicle Key',
    ['weight'] = 40,
    ['type'] = 'item',
    ['image'] = 'vehiclekeys.png',
    ['unique'] = true,          -- unique so each key keeps its own plate info
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'A key for a specific vehicle.'
},

['vehiclekeys_police'] = {
    ['name'] = 'vehiclekeys_police',
    ['label'] = 'Police Key Cutter',
    ['weight'] = 200,
    ['type'] = 'item',
    ['image'] = 'vehiclekeys_police.png',
    ['unique'] = false,
    ['useable'] = true,
    ['shouldClose'] = true,
    ['combinable'] = nil,
    ['description'] = 'Cut a key from any nearby vehicle. Police only.'
},

-- Tip: qb-inventory shows the key's plate/vehicle from its `info` metadata
-- (set automatically when the key is given).
