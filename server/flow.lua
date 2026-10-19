local config = require 'config'
local shared = require 'shared.bikewheel'
local bridge = require 'server.bridge'

local REQUEST_COOLDOWN_MS = 2000

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
---@param via any
---@return boolean allowed
---@return string? reason
local function allowed(source, via)
    local hasTarget = targetAvailable()

    if via == 'target' and hasTarget then return true end

    if not (config.command.enabled or not hasTarget) then return false end

    if config.command.ace and not IsPlayerAceAllowed(source, config.command.ace) then
        return false, 'no_permission'
    end

    return true
end

---@param start fun(source: integer, gameName: string, params: table): boolean, string?
return function(start)
    RegisterNetEvent('bl_handson:server:bikewheel', function(netId, wheelKey, via)
        local src = source
        local now = GetGameTimer()

        if pending[src] then return end
        if now - (lastRequest[src] or 0) < REQUEST_COOLDOWN_MS then return end

        lastRequest[src] = now

        if type(netId) ~= 'number' or math.floor(netId) ~= netId then return end

        local wheel = shared.wheels[wheelKey]
        if not wheel then return end

        local permitted, denied = allowed(src, via)

        if not permitted then
            if denied then notify(src, 'error', denied) end

            return
        end

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
    end)

    AddEventHandler('playerDropped', function()
        lastRequest[source] = nil
    end)

end
