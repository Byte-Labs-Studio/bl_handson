local shared = require 'shared.bikewheel'
local bridge = require 'server.bridge'

local MAX_DISTANCE = 4.0
local MAX_ADJUST_TURNS = 12.0
local MAX_TORQUE = 400.0
local CONTROL_WINDOW_MS = 8000
local RECOVER_TRIES = 30
local RECOVER_RETRY_MS = 1000

---@type table<integer, integer>
local locked = {}

---@param value any
---@param limit number
---@return boolean
local function finite(value, limit)
    return type(value) == 'number' and value == value and value >= -limit and value <= limit
end

---@param source integer
---@param entity integer
---@return boolean
local function near(source, entity)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end

    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= MAX_DISTANCE
end

---@param min integer
---@param max integer
---@param step number
---@return number
local function pick(min, max, step)
    return math.random(min, max) * step
end

local game = {}

---@param source integer
---@param params { netId: integer, wheel: string, charge?: boolean }
---@return boolean ok
---@return string? reason
---@return table? state
function game.prepare(source, params)
    local netId = params.netId

    if type(netId) ~= 'number' or math.floor(netId) ~= netId or netId <= 0 then return false, 'bad_request' end

    local wheel = shared.wheels[params.wheel]
    if not wheel then return false, 'bad_request' end

    local entity = NetworkGetEntityFromNetworkId(netId)

    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return false, 'no_vehicle' end
    if GetVehicleType(entity) ~= 'bike' then return false, 'not_a_bike' end
    if GetPedInVehicleSeat(entity, -1) ~= 0 then return false, 'occupied' end
    if locked[entity] then return false, 'in_use' end
    if not near(source, entity) then return false, 'too_far' end

    local ped = GetPlayerPed(source)

    if GetVehiclePedIsIn(ped, false) ~= 0 then return false, 'in_vehicle' end

    return true, nil, { entity = entity, netId = netId, wheel = wheel }
end

---@param params { wheel: string }
---@return BikeWheelSpec
function game.spec(params)
    local rear = params.wheel == 'rear'

    return {
        torque = rear and (95.0 + pick(0, 4, 5.0)) or (65.0 + pick(0, 4, 5.0)),
        breakaway = 300.0 + pick(0, 6, 50.0),
        pumps = math.random(3, 5),
        slackBase = 26.0 + pick(0, 12, 1.0),
        slackPerTurn = 6.0,
        slackLo = 25.0,
        slackHi = 35.0,
        skew = pick(-3, 3, 0.25),
        looseTurns = 1.5,
        alignTolerance = 0.25,
    }
end

---@param params { wheel: string }
---@return HandsonStep[]
function game.steps(params)
    return shared.steps[params.wheel]
end

---@param session HandsonSession
function game.begin(session)
    local entity = session.state.entity
    local id = session.id

    locked[entity] = id

    SetEntityIgnoreRequestControlFilter(entity, true)

    SetTimeout(CONTROL_WINDOW_MS, function()
        if locked[entity] and locked[entity] ~= id then return end
        if not DoesEntityExist(entity) then return end

        SetEntityIgnoreRequestControlFilter(entity, false)
    end)

end

---@param session HandsonSession
---@return boolean alive
---@return string? reason
function game.check(session)
    local entity = session.state.entity

    if not DoesEntityExist(entity) then return false, 'no_vehicle' end
    if GetPedInVehicleSeat(entity, -1) ~= 0 then return false, 'occupied' end
    if not near(session.source, entity) then return false, 'too_far' end

    return true
end

---@param session HandsonSession
---@param step HandsonStep
---@param data any
---@return boolean valid
---@return string? reason
function game.validate(session, step, data)
    local spec = session.spec --[[@as BikeWheelSpec]]

    if step.kind == 'pick' then
        if type(data) ~= 'table' then return false, 'bad_request' end

        local wanted = step.side == session.state.wheel.thickSide and 'thick' or 'thin'

        return data.choice == wanted, 'wrong_spacer'
    end

    if step.kind == 'adjust' then
        if type(data) ~= 'table' then return false, 'bad_request' end
        if not finite(data.left, MAX_ADJUST_TURNS) or not finite(data.right, MAX_ADJUST_TURNS) then return false, 'bad_request' end

        if step.goal == 'loose' then
            return data.left <= -spec.looseTurns and data.right <= -spec.looseTurns, 'still_tight'
        end

        local slack, skew = shared.chain(spec, data.left, data.right)

        if slack < spec.slackLo or slack > spec.slackHi then return false, 'slack' end

        return math.abs(skew) <= spec.alignTolerance, 'alignment'
    end

    if step.kind == 'torque' then
        if type(data) ~= 'table' or not finite(data.nm, MAX_TORQUE) then return false, 'bad_request' end
        if data.nm < spec.torque * 0.95 then return false, 'under_torque' end

        return data.nm <= spec.torque * 1.07, 'over_torque'
    end

    return true
end

---@param session HandsonSession
---@return boolean paid
---@return string? reason
function game.complete(session)
    if not session.params.charge then return true end
    if not bridge.remove(session.source, session.state.wheel.item) then return false, 'no_wheel' end

    return true
end

---@param session HandsonSession
---@param netId integer
---@param gone? integer
local function recover(session, netId, gone)
    local entity = session.state.entity

    CreateThread(function()
        for _ = 1, RECOVER_TRIES do
            if not DoesEntityExist(entity) or locked[entity] then return end

            local owner = NetworkGetEntityOwner(entity)

            if owner > 0 and owner ~= gone then
                TriggerClientEvent('bl_handson:client:recover', owner, session.game, netId)

                return
            end

            Wait(RECOVER_RETRY_MS)
        end

        lib.print.warn(('bike %s had no owner to put its wheel back'):format(netId))
    end)

end

---@param session HandsonSession
---@param ok boolean
---@param reason? string
function game.finish(session, ok, reason)
    local entity = session.state.entity

    locked[entity] = nil

    if not DoesEntityExist(entity) then return end

    SetEntityIgnoreRequestControlFilter(entity, false)

    local netId = session.state.netId
    local owner = NetworkGetEntityOwner(entity)

    if reason == 'dropped' then
        recover(session, netId, session.source)
    elseif owner ~= session.source then
        recover(session, netId)
    end

    if not ok or owner <= 0 then return end

    local wheel = session.state.wheel

    TriggerClientEvent('bl_handson:client:fixTyre', owner, netId, wheel.wheelIndex, wheel.tyreIndex)
end

return game
