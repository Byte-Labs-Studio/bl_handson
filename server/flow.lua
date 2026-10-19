local config = require 'config'
local shared = require 'shared.bikewheel'
local bridge = require 'server.bridge'

local REQUEST_COOLDOWN_MS = 2000
local COMMAND_RADIUS = 3.0

local TARGETS = { 'ox_target', 'qb-target' }

---@type table<integer, integer>
local lastRequest = {}

---@type table<integer, boolean>
local pending = {}

---@param source integer
---@param kind 'success' | 'error' | 'info'
---@param reason string
local function notify(source, kind, reason)
    TriggerClientEvent('bl_handson:client:result', source, kind, reason)
end

---@return boolean
local function targetAvailable()
    if config.target == 'none' then return false end

    if config.target ~= 'auto' then return GetResourceState(config.target) == 'started' end

    for i = 1, #TARGETS do
        if GetResourceState(TARGETS[i]) == 'started' then return true end
    end

    return false
end

---@param source integer
---@return integer?
local function closestBike(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return end

    local coords = GetEntityCoords(ped)
    local vehicles = GetGamePool('CVehicle')
    local best, bestDistance = nil, COMMAND_RADIUS

    for i = 1, #vehicles do
        local vehicle = vehicles[i]

        if GetVehicleType(vehicle) == 'bike' and GetPedInVehicleSeat(vehicle, -1) == 0 then
            local distance = #(coords - GetEntityCoords(vehicle))

            if distance < bestDistance then
                best, bestDistance = vehicle, distance
            end

        end

    end

    return best
end

---@param start fun(source: integer, gameName: string, params: table): boolean, string?
return function(start)
    ---@param src integer
    ---@param netId any
    ---@param wheelKey any
    local function request(src, netId, wheelKey)
        local now = GetGameTimer()

        if pending[src] then return end
        if now - (lastRequest[src] or 0) < REQUEST_COOLDOWN_MS then return end

        lastRequest[src] = now

        if type(netId) ~= 'number' or math.floor(netId) ~= netId then return end

        local wheel = shared.wheels[wheelKey]
        if not wheel then return end

        local useItems = shared.itemsRequired

        if useItems then
            if bridge.count(src, config.items.toolkit) < 1 then return notify(src, 'error', 'no_toolkit') end
            if bridge.count(src, wheel.item) < 1 then return notify(src, 'error', 'no_wheel') end
        end

        pending[src] = true

        if useItems and not bridge.remove(src, wheel.item) then
            pending[src] = nil

            return notify(src, 'error', 'no_wheel')
        end

        local ok, reason = start(src, 'bikewheel', { netId = netId, wheel = wheelKey })

        pending[src] = nil

        if not ok then
            if GetPlayerName(src) then
                if useItems then bridge.refund(src, wheel.item) end

                notify(src, 'error', reason or 'failed')
            end

            return
        end

        TriggerEvent('bl_handson:bikewheel:completed', src, netId, wheelKey)
        notify(src, 'success', 'done')
    end

    RegisterNetEvent('bl_handson:server:bikewheel', function(netId, wheelKey, via)
        local src = source
        local hasTarget = targetAvailable()

        if via == 'target' and not hasTarget then return end
        if via == 'prompt' and hasTarget then return end
        if via ~= 'target' and via ~= 'prompt' then return end

        request(src, netId, wheelKey)
    end)

    if config.command then
        lib.addCommand(config.command.name, {
            help = 'Change a motorcycle wheel',
            params = {
                { name = 'wheel', type = 'string', help = 'front | rear (default rear)', optional = true },
            },
            restricted = config.command.restricted or nil,
        }, function(source, args)
            local vehicle = closestBike(source)

            if not vehicle then return notify(source, 'error', 'no_bike') end

            request(source, NetworkGetNetworkIdFromEntity(vehicle), args.wheel == 'front' and 'front' or 'rear')
        end)
    end

    AddEventHandler('playerDropped', function()
        lastRequest[source] = nil
    end)

end
