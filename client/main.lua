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
local PROMPT_SCAN_MS = 500
local PROMPT_TICK_MS = 100
local PROMPT_SCAN_PADDING = 2.0

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
        local since = GetGameTimer()

        while true do
            hud.step(index, #steps, step.label, step.hint)

            local data = ctx.run(step)

            if data == nil then return 'cancelled' end

            local readyAt = since + step.minMs

            input.wait(ctx.opts, function()
                if GetGameTimer() >= readyAt then return true end
            end)

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

            since = GetGameTimer()

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
        game.recover(params.netId)

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

    local ran, outcome = pcall(runSteps, id, ctx)

    if not ran then
        lib.print.error(outcome)

        outcome = 'failed'
    end

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

RegisterNetEvent('bl_handson:client:recover', function(gameName, netId)
    if GetInvokingResource() then return end
    if type(netId) ~= 'number' then return end

    local game = games[gameName]
    if not game then return end

    game.recover(netId)
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
---@return string
local function label(wheelKey)
    return wheelKey == 'rear' and 'Change rear wheel' or 'Change front wheel'
end

---@type CKeybind
local keybind

---@param wheelKey 'front' | 'rear'
---@return table
local function option(wheelKey)
    local wheel = shared.wheels[wheelKey]

    return {
        name = ('bl_handson:wheel_%s'):format(wheelKey),
        label = label(wheelKey),
        icon = 'fas fa-screwdriver-wrench',
        bones = wheel.bone,
        distance = config.interactDistance,
        items = shared.itemsRequired() and { config.items.toolkit, wheel.item } or nil,
        canInteract = function(entity) return serviceable(entity) end,
        onSelect = function(data)
            local entity = data.entity

            if not entity or entity == 0 or not NetworkGetEntityIsNetworked(entity) then return end

            TriggerServerEvent('bl_handson:server:bikewheel', NetworkGetNetworkIdFromEntity(entity), wheelKey, 'target')
        end,

    }
end

local function registerOptions()
    bridge.addVehicleOptions({ option('front'), option('rear') })
end

registerOptions()

---@type { wheel: 'front' | 'rear', vehicle: integer }?
local prompt

---@param wheelKey? 'front' | 'rear'
---@param vehicle? integer
local function setPrompt(wheelKey, vehicle)
    if not wheelKey then
        if prompt then lib.hideTextUI() end

        prompt = nil

        return
    end

    local changed = not prompt or prompt.wheel ~= wheelKey

    prompt = { wheel = wheelKey, vehicle = vehicle --[[@as integer]] }

    if changed then
        lib.showTextUI(('[%s] %s'):format(keybind.currentKey, label(wheelKey)))
    end

end

---@param vehicle integer
---@return 'front' | 'rear' | nil
local function nearestWheel(vehicle)
    local coords = GetEntityCoords(cache.ped)
    local best, bestDistance = nil, config.prompt.distance

    for wheelKey, wheel in pairs(shared.wheels) do
        local bone = GetEntityBoneIndexByName(vehicle, wheel.bone)

        if bone ~= -1 then
            local distance = #(coords - GetWorldPositionOfEntityBone(vehicle, bone))

            if distance <= bestDistance then
                best, bestDistance = wheelKey, distance
            end

        end

    end

    return best
end

---@return boolean
local function promptAllowed()
    return not active and not cache.vehicle and not IsPedDeadOrDying(cache.ped, true) and not bridge.hasTarget()
end

keybind = lib.addKeybind({
    name = 'bl_handson_prompt',
    description = 'Change motorcycle wheel',
    defaultKey = config.prompt.key,
    onPressed = function()
        if not prompt or not promptAllowed() then return end

        local vehicle, wheelKey = prompt.vehicle, prompt.wheel

        if not DoesEntityExist(vehicle) or not serviceable(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then return end

        setPrompt()
        TriggerServerEvent('bl_handson:server:bikewheel', NetworkGetNetworkIdFromEntity(vehicle), wheelKey, 'prompt')
    end,
})

---@param vehicle integer | false | nil
---@param radius number
---@return boolean
local function inRange(vehicle, radius)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    if not promptAllowed() or not serviceable(vehicle) then return false end

    return #(GetEntityCoords(cache.ped) - GetEntityCoords(vehicle)) <= radius
end

CreateThread(function()
    local scanRadius = config.prompt.distance + PROMPT_SCAN_PADDING

    while true do
        local vehicle = promptAllowed() and lib.getClosestVehicle(GetEntityCoords(cache.ped), scanRadius, false)

        while inRange(vehicle, scanRadius) do
            setPrompt(nearestWheel(vehicle --[[@as integer]]), vehicle --[[@as integer]])
            Wait(PROMPT_TICK_MS)
        end

        setPrompt()
        Wait(PROMPT_SCAN_MS)
    end

end)

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

    if prompt then lib.hideTextUI() end

end)
