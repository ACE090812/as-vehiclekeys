fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'as-vehiclekeys'
description 'as-vehiclekeys — item-based vehicle keys with metadata, hotwiring, lockpicking, carjacking & police key cutter (QBox / QBCore)'
author 'ACE Studios'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
}

-- NUI cable-cutting hotwire minigame (ported from dusa_vehiclekeys).
-- Used when Config.HotwireMinigame = 'dusa'. The endpoints inside web/script/main.js
-- are hard-coded to https://as-vehiclekeys/..., so do not rename this resource
-- without updating that file too.
ui_page 'web/index.html'

files {
    'web/index.html',
    'web/assets/img/*',
    'web/assets/style/*',
    'web/script/*',
}

-- Optional (only if Config.Minigame = 't3'):
--   t3_lockpick  (https://github.com/T3development/t3_lockpick)
