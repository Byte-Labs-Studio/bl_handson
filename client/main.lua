local config = require 'config'
local shared = require 'shared.bikewheel'
local hud = require 'client.engine.hud'
local input = require 'client.engine.input'
local props = require 'client.engine.props'
local camera = require 'client.engine.camera'
local bridge = require 'client.bridge'

local DoesEntityExist = DoesEntityExist

local games = {
    bikewheel = require 'client.games.bikewheel',
}

local INTERACT_REARM_POLL_MS = 100
local INTERACT_REARM_TIMEOUT_MS = 15000
local MOTORCYCLE_CLASS = 8
local FADE_MS = 350
local FADE_TIMEOUT_MS = 2000
local MAX_PARKED_SPEED = 0.5

local MESSAGES = {
    done = 'New wheel fitted and torqued.',
    cancelled = 'You put the tools down.',
    strikes = 'You botched the job. The old wheel is going back on.',
    timeout = 'You took too long.',
    too_far = 'You walked away from the bike.',
    occupied = 'Someone got on the bike.',
    no_vehicle = 'The bike is gone.',
    not_a_bike = 'That is not a motorcycle.',
    in_use = 'Someone is already working on that bike.',
    busy = 'You are already working on something.',
    in_vehicle = 'Get off the bike first.',
    no_toolkit = 'You need a motorcycle tool kit.',
    no_wheel = 'You need a replacement wheel.',
    no_control = 'You could not get hold of the bike.',
    missing_props = 'Workshop props are missing. Tell staff.',
    rushed = 'Slow down, do it properly.',
    wrong_spacer = 'Wrong spacer for that side.',
    still_tight = 'Back both adjusters off further.',
    slack = 'Chain slack is out of spec.',
    alignment = 'The adjuster marks do not match.',
    under_torque = 'Under torque. Back it off and do it again.',
    over_torque = 'Over torque. Back it off and do it again.',
    no_bike = 'No parked motorcycle nearby.',
    no_permission = 'You are not allowed to do that.',
}

---@param reason? string
---@return string
local function message(reason)
    return MESSAGES[reason] or 'That did not work.'
end

---@param kind 'success' | 'error' | 'info'
---@param reason? string
local function notify(kind, reason)
    bridge.notify('Workshop', message(reason), kind)
end

---@type { id: integer, ctx?: table }?
local active

local function fadeOut()
    DoScreenFadeOut(FADE_MS)

    local deadline = GetGameTimer() + FADE_TIMEOUT_MS

    while not IsScreenFadedOut() and GetGameTimer() < deadline do
        Wait(0)
    end

end

---@param id integer
---@param ctx table
---@return 'done' | 'cancelled' | 'failed' outcome
---@return string? reason
local function runSteps(id, ctx)
    local steps = ctx.steps

    for index = 1, #steps do
        local step = steps[index]

        while true do
            hud.step(index, #steps, step.label, step.hint)

            local data = ctx.run(step)

            if data == nil then return 'cancelled' end

            local reply

            lib.callback('bl_handson:server:step', false, function(response)
                reply = response or { ok = false, failed = true, reason = 'no_reply' }
            end, id, step.name, data)

            reply = input.wait(ctx.opts, function() return reply end)

            if reply.ok then
                ctx.commit(step)
                hud.flash('good', step.label)

                if reply.done then return 'done' end

                break
            end

            if reply.failed then return 'failed', reply.reason end

            if reply.strike then
                input.sound('ERROR')
                hud.flash('strike', message(reply.reason), reply.strikes, config.maxStrikes)
                ctx.retry(step)
            elseif reply.reason ~= 'too_fast' then
                return 'failed', reply.reason
            end

        end

    end

    return 'done'
end

RegisterNetEvent('bl_handson:client:start', function(id, gameName, params, spec)
    if GetInvokingResource() then return end

    local game = games[gameName]

    if active or not game then
        TriggerServerEvent('bl_handson:server:cancel', id)

        return
    end

    active = { id = id }

    fadeOut()

    local prepared, ctx, reason = pcall(game.prepare, params, spec)

    if not prepared then
        lib.print.error(ctx)

        props.clear()
        camera.stop(true)
        ClearPedTasks(cache.ped)

        ctx, reason = nil, 'failed'
    end

    if not ctx then
        active = nil

        DoScreenFadeIn(FADE_MS)
        TriggerServerEvent('bl_handson:server:cancel', id)
        notify('error', reason)

        return
    end

    active.ctx = ctx

    input.begin()
    hud.show(true, game.title)
    DoScreenFadeIn(FADE_MS)

    local outcome = runSteps(id, ctx)

    hud.show(false)
    fadeOut()

    local cleaned, problem = pcall(ctx.cleanup, outcome == 'done')

    if not cleaned then lib.print.error(problem) end

    input.finish()
    DoScreenFadeIn(FADE_MS)

    active = nil

    if outcome ~= 'done' then
        TriggerServerEvent('bl_handson:server:cancel', id)
    end

end)

RegisterNetEvent('bl_handson:client:stop', function(id)
    if GetInvokingResource() then return end
    if not active or active.id ~= id then return end

    input.interrupt()
end)

RegisterNetEvent('bl_handson:client:result', function(kind, reason)
    if GetInvokingResource() then return end

    notify(kind == 'success' and 'success' or 'error', reason)
end)

RegisterNetEvent('bl_handson:client:fixTyre', function(netId, wheelIndex, tyreIndex)
    if GetInvokingResource() then return end
    if type(netId) ~= 'number' or type(wheelIndex) ~= 'number' or type(tyreIndex) ~= 'number' then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)

    if vehicle == 0 or not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle) then return end

    SetVehicleTyreFixed(vehicle, tyreIndex)
    SetVehicleWheelHealth(vehicle, wheelIndex, 1000.0)
end)

---@param entity integer
---@return boolean
local function serviceable(entity)
    if active then return false end
    if GetVehicleClass(entity) ~= MOTORCYCLE_CLASS then return false end
    if not IsVehicleSeatFree(entity, -1) then return false end

    return GetEntitySpeed(entity) <= MAX_PARKED_SPEED
end

---@param wheelKey 'front' | 'rear'
---@return table
local function option(wheelKey)
    local wheel = shared.wheels[wheelKey]

    return {
        name = ('bl_handson:wheel_%s'):format(wheelKey),
        label = wheelKey == 'rear' and 'Change rear wheel' or 'Change front wheel',
        icon = 'fas fa-screwdriver-wrench',
        bones = wheel.bone,
        distance = config.interactDistance,
        items = shared.itemsRequired and { config.items.toolkit, wheel.item } or nil,
        canInteract = function(entity) return serviceable(entity) end,
        onSelect = function(data)
            local entity = type(data) == 'table' and data.entity or data

            if not entity or entity == 0 or not NetworkGetEntityIsNetworked(entity) then return end

            TriggerServerEvent('bl_handson:server:bikewheel', NetworkGetNetworkIdFromEntity(entity), wheelKey, 'target')
        end,
    }
end

local function registerOptions()
    bridge.addVehicleOptions({ option('front'), option('rear') })
end

registerOptions()

---@param wheelKey 'front' | 'rear'
local function commandRequest(wheelKey)
    if active then return notify('error', 'busy') end
    if cache.vehicle then return notify('error', 'in_vehicle') end

    local vehicle = lib.getClosestVehicle(GetEntityCoords(cache.ped), config.command.distance, false)

    if not vehicle or not serviceable(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then
        return notify('error', 'no_bike')
    end

    TriggerServerEvent('bl_handson:server:bikewheel', NetworkGetNetworkIdFromEntity(vehicle), wheelKey, 'command')
end

if config.command.enabled or not bridge.hasTarget() then
    RegisterCommand(config.command.name, function(_, args)
        commandRequest(args[1] == 'front' and 'front' or 'rear')
    end, false)

    TriggerEvent('chat:addSuggestion', ('/%s'):format(config.command.name), 'Change a motorcycle wheel', {
        { name = 'wheel', help = 'front | rear (default rear)' },
    })
end

AddEventHandler('onResourceStart', function(resource)
    if not lib.table.contains(bridge.targets, resource) then return end

    CreateThread(function()
        local deadline = GetGameTimer() + INTERACT_REARM_TIMEOUT_MS

        while GetResourceState(resource) ~= 'started' do
            if GetGameTimer() >= deadline then return end

            Wait(INTERACT_REARM_POLL_MS)
        end

        registerOptions()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    if active and active.ctx then
        active.ctx.cleanup(false)
    end

    if active or IsScreenFadedOut() or IsScreenFadingOut() then
        DoScreenFadeIn(0)
    end

    bridge.removeVehicleOptions()

end)
