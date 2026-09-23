-- ============================================================================
--  ox_inventory items — add these to  ox_inventory/data/items.lua
--  `consume = 0` = the item is NOT removed when used.
--  `server.export` makes the item call this resource when used.
--
--  NOTE: the lockpick/advanced_lockpick items are NOT touched here — they're
--  shared with your other scripts. This resource only *checks* that you hold one
--  (via the ox_target "Lockpick" option) and breaks it on failure; it never hooks
--  the item's "use", so there's no conflict.
-- ============================================================================

['vehiclekeys'] = {
    label = 'Vehicle Key',
    weight = 40,
    stack = false,          -- each key is unique (its own plate metadata)
    close = true,
    consume = 0,            -- using the key (to lock/unlock) never removes it
    description = 'A key for a specific vehicle.',
    server = {
        export = 'as-vehiclekeys.useKey',
    },
    -- ox_inventory shows metadata.description (plate + vehicle) on the tooltip.
},

['vehiclekeys_police'] = {
    label = 'Police Key Cutter',
    weight = 200,
    stack = true,
    close = true,
    consume = 0,            -- reusable tool, not consumed on use
    description = 'Cut a key from any nearby vehicle. Police only.',
    server = {
        export = 'as-vehiclekeys.usePoliceTool',
    },
},
