# Byte Labs - Hands-On
A hands-on, server-validated motorcycle wheel change simulator for your FiveM server.

Website: [Byte Labs](https://byte-labs.net)
Discord: [Byte Labs](https://discord.gg/fqsqSjZfxE)

Walk up to a parked motorcycle with a tool kit and a replacement wheel, target the front or rear wheel and do the job yourself: lift the bike on a paddock stand, crack the caliper bolts, break the axle nut loose, set the chain slack, torque it to spec and pump the brake. **22 steps for a rear wheel, 17 for the front.**

## Features
- Fully hands-on: every step is done with the mouse (drag, turn, adjust, pick, pump), no progress bars
- Server-validated: every step is checked in order, with minimum step times, and rushing or doing it wrong costs a strike
- Real tools and parts: paddock stands, ratchet, breaker bar, torque wrench, axle, spacers, chain adjusters and caliper (15 original streamed props)
- Real mechanics: breaker-bar breakaway, chain slack and adjuster alignment, torque spec with over/under torque, wrong-spacer checks
- The old wheel actually comes off the bike and the new one goes back on
- Items are only taken on start and refunded (or dropped) if the job fails
- Camera views per step and a clean NUI overlay with step progress and strike counter
- Auto-detects inventory and target resources, or runs fully standalone with a command
- Developer exports and a completion event to hook in tyre condition, XP, payouts and more

## Dependencies
- [ox_lib](https://github.com/overextended/ox_lib)
- OneSync
- Optional inventory: [ox_inventory](https://github.com/overextended/ox_inventory), qb-core (qb / ps / lj inventory), qs-inventory or es_extended
- Optional target: [ox_target](https://github.com/overextended/ox_target) or [qb-target](https://github.com/qbcore-framework/qb-target)

## Installation
1. Download
2. Extract the `bl_handson` folder to your resources directory
3. Add the items from [`install/`](install) to your inventory (see [Items](#items)), or skip this for [Standalone](#standalone)
4. Add `ensure bl_handson` to your server.cfg after ox_lib, your inventory and your target
5. Configure the `config.lua` to your liking

## Config
```lua
return {
    items = {
        toolkit = 'moto_toolkit',
        frontWheel = 'moto_wheel_front',
        rearWheel = 'moto_wheel_rear',
    },

    inventory = 'auto', -- 'auto' | 'none' | 'ox_inventory' | 'qs-inventory' | 'qb-core' | 'es_extended'
    requireItems = true, -- forced off when inventory = 'none'

    target = 'auto', -- 'auto' | 'none' | 'ox_target' | 'qb-target'

    command = {
        enabled = false, -- always on when no target is running
        name = 'changewheel',
        distance = 3.0,
        ace = false, -- false or an ace like 'bl_handson.use'
    },

    interactDistance = 1.8,
    maxStrikes = 3,
}
```

## Standalone
No framework, inventory or target needed, only ox_lib and OneSync. Players use a command instead of a target and no items are checked or taken. The job still runs fully server-validated, the tyre is still fixed and `bl_handson:bikewheel:completed` still fires.

```lua
return {
    items = {
        toolkit = 'moto_toolkit',
        frontWheel = 'moto_wheel_front',
        rearWheel = 'moto_wheel_rear',
    },

    inventory = 'none',
    requireItems = false,

    target = 'none',

    command = {
        enabled = true,
        name = 'changewheel',
        distance = 3.0,
        ace = 'bl_handson.use',
    },

    interactDistance = 1.8,
    maxStrikes = 3,
}
```

Stand next to a parked motorcycle with nobody on it and run:
```
/changewheel        -- rear wheel
/changewheel rear
/changewheel front
```

If `command.ace` is set, the server checks it on every command request. Grant it in your server.cfg:
```
add_ace group.mechanic bl_handson.use allow
add_principal identifier.license:xxxxxxxx group.mechanic
```
Set `ace = false` to let everyone use the command.

The command is also registered when `target = 'auto'` and no target resource is running, or when `command.enabled = true` next to a target.

## Items
The tool kit is kept, the replacement wheel is used up when the job is done.

| Item | Default name |
| --- | --- |
| Tool kit | `moto_toolkit` |
| Front wheel | `moto_wheel_front` |
| Rear wheel | `moto_wheel_rear` |

- **OX Inventory**: paste [`install/ox_inventory.lua`](install/ox_inventory.lua) into `ox_inventory/data/items.lua`
- **QB / PS / LJ Inventory**: paste [`install/qb-core.lua`](install/qb-core.lua) into `qb-core/shared/items.lua`
- **ESX**: run [`install/es_extended.sql`](install/es_extended.sql)

Item images are not included, see [`install/images`](install/images/README.md).

## Controls
| Key | Action |
| --- | --- |
| `LMB` | Grab / drag / turn |
| `E` | Confirm |
| `X` | Stop the job |

## Developers
### Exports (server)
```lua
-- Starts a game for a player and yields until it ends.
-- Items are not checked or taken here, do that yourself.
local ok, reason = exports.bl_handson:start(source, 'bikewheel', { netId = netId, wheel = 'rear' })

-- true while the player is in a game
local busy = exports.bl_handson:isBusy(source)
```

### Events (server)
Fired after a wheel change from the built-in target option has been completed.
```lua
AddEventHandler('bl_handson:bikewheel:completed', function(source, netId, wheel)
    -- wheel: 'front' | 'rear'
    local vehicle = NetworkGetEntityFromNetworkId(netId)
end)
```
Use `AddEventHandler`, not `RegisterNetEvent`, so clients cannot fake it.

## Known limitations
- Motorcycles only (vehicle class 8), parked, with nobody on them.
- On bikes the CFX wheel array is front = `1`, rear = `0` (tyre indexes front = `0`, rear = `4`).
- The real wheel is removed with `BreakOffVehicleWheel(vehicle, index, false, true, true, false)` (`deleteWheel = true`) and restored when the job ends.
- qb-target only checks for the tool kit before showing the option; the wheel item is still checked by the server.
- The `ecrp_hs_*` model names are baked into the streamed assets and stay as they are.

## License
[GPL-3.0](LICENSE)
