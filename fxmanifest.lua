fx_version 'cerulean'
game 'gta5'
use_experimental_fxv2_oal 'yes'
lua54 'yes'

author 'Byte Labs'
version '1.0.0'
description 'Byte Labs Hands-On: server-validated motorcycle wheel change simulator'
repository 'https://github.com/Byte-Labs-Studio/bl_handson'

shared_scripts {
    '@ox_lib/init.lua',
}

ox_lib 'math'

client_scripts {
    'client/main.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'web/index.html'
nui_callback_strict_mode 'true'

files {
    'config.lua',
    'shared/*.lua',
    'client/bridge.lua',
    'client/engine/*.lua',
    'client/games/*.lua',
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

data_file 'DLC_ITYP_REQUEST' 'stream/bl_handson.ytyp'

dependencies {
    '/onesync',
    'ox_lib',
}
