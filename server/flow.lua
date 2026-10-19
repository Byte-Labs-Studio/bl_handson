local config = require 'config'
local shared = require 'shared.bikewheel'
local bridge = require 'server.bridge'

local REQUEST_COOLDOWN_MS = 2000

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

---@param start fun(source: integer, gameName: string, params: table): boolean, string?
return function(start)
    RegisterNetEvent('bl_handson:server:bikewheel', function(netId, wheelKey)
        local src = source
        local now = GetGameTimer()

        if pending[src] then return end
        if now - (lastRequest[src] or 0) < REQUEST_COOLDOWN_MS then return end

        lastRequest[src] = now

        if type(netId) ~= 'number' or math.floor(netId) ~= netId then return end

        local wheel = shared.wheels[wheelKey]
        if not wheel then return end

        if bridge.count(src, config.items.toolkit) < 1 then return notify(src, 'error', 'no_toolkit') end
        if bridge.count(src, wheel.item) < 1 then return notify(src, 'error', 'no_wheel') end

        pending[src] = true

        local removed = bridge.remove(src, wheel.item)

        if not removed then
            pending[src] = nil

            return notify(src, 'error', 'no_wheel')
        end

        local ok, reason = start(src, 'bikewheel', { netId = netId, wheel = wheelKey })

        pending[src] = nil

        if not ok then
            if GetPlayerName(src) then
                bridge.refund(src, wheel.item)
                notify(src, 'error', reason or 'failed')
            end

            return
        end

        TriggerEvent('bl_handson:bikewheel:completed', src, netId, wheelKey)
        notify(src, 'success', 'done')
    end)

    AddEventHandler('playerDropped', function()
        lastRequest[source] = nil
    end)

end
