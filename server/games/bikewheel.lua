local shared = require 'shared.bikewheel'

local MAX_DISTANCE = 4.0
local MAX_ADJUST_TURNS = 12.0
local MAX_TORQUE = 400.0

---@type table<integer, boolean>
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
---@param params { netId: integer, wheel: string }
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

    locked[entity] = true

    SetEntityIgnoreRequestControlFilter(entity, true)
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
---@param ok boolean
function game.finish(session, ok)
    local entity = session.state.entity

    locked[entity] = nil

    if not DoesEntityExist(entity) then return end

    SetEntityIgnoreRequestControlFilter(entity, false)

    if not ok then return end

    local wheel = session.state.wheel
    local owner = NetworkGetEntityOwner(entity)

    if owner > 0 then
        TriggerClientEvent('bl_handson:client:fixTyre', owner, session.state.netId, wheel.wheelIndex, wheel.tyreIndex)
    end

end

return game
