local shared = require 'shared.bikewheel'
local props = require 'client.engine.props'
local camera = require 'client.engine.camera'
local input = require 'client.engine.input'

local GetOffsetFromEntityInWorldCoords = GetOffsetFromEntityInWorldCoords
local SetEntityLocallyInvisible = SetEntityLocallyInvisible

local LIFT = 0.07
local CONTROL_TIMEOUT_MS = 2000
local KNEEL_DICT = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@'
local KNEEL_CLIP = 'machinic_loop_mechandplayer'
local BOLT_TRAVEL = 0.012
local NUT_TRAVEL = 0.012
local EAR_SPACING = 0.045
local CALIPER_HALF_WIDTH = 0.0225
local AXLE_HEAD_X = 0.16
local PED_OFFSET = 0.8
local DEFAULT_RADIUS = 0.31
local TOOL_FLEX_DEG = 8.0
local WHEEL_PER_TURN = 0.008
local MAX_BONE_REACH = 3.0
local TYRE_INDICES = { 0, 1, 4, 5 }
local PART_FADE_MS = 300
local ADJUSTER_MODELS = { 'ecrp_hs_adjuster_plate', 'ecrp_hs_adjuster_bolt' }
local ADJUSTER_BOLT_Y = -0.110
local ADJUSTER_HEAD_DEPTH = 0.003
local BOLT_REST = 0.0105
local NUT_REST = 0.0185
local AXLE_REST = 0.0127
local MAX_KNEEL_REACH = 2.5

local TOOL_MODELS = {
    ratchet = 'ecrp_hs_ratchet',
    breaker = 'ecrp_hs_breaker_bar',
    torque = 'ecrp_hs_torque_wrench',
}

local LAYOUT = {
    rear = {
        wheel = 'ecrp_hs_mc_wheel_r',
        halfWidth = 0.092,
        stand = 'ecrp_hs_paddock_r',
        nutX = -0.133,
        axleOut = 0.45,
        discX = 0.0745,
        caliperRadius = 0.109,
        caliperAngle = 135.0,
        caliperLift = vec3(0.05, -0.05, 0.16),
        spacerX = { thick = -0.105, thin = 0.086 },
        adjusters = { left = -0.118, right = 0.147 },
        chain = vec3(-0.07, -0.02, 0.105),
        brake = vec3(0.20, 0.55, 0.02),
        standY = -0.40,
        standPitch = -14.0,
        handle = vec3(0.0, -0.696, 0.573),
        dirY = -1.0,
        forward = 0.035,
        liftSign = -1.0,
    },
    front = {
        wheel = 'ecrp_hs_mc_wheel_f',
        halfWidth = 0.067,
        stand = 'ecrp_hs_paddock_f',
        nutX = -0.133,
        axleOut = 0.42,
        discX = 0.0605,
        caliperRadius = 0.149,
        caliperAngle = 160.0,
        caliperLift = vec3(0.06, -0.10, 0.08),
        spacerX = { thick = -0.080, thin = 0.072 },
        standY = 0.40,
        standPitch = 14.0,
        handle = vec3(0.0, 0.696, 0.573),
        dirY = 1.0,
        forward = 0.0,
        liftSign = 1.0,
    },
}

local STATIC_MODELS = {
    'ecrp_hs_axle', 'ecrp_hs_axle_nut', 'ecrp_hs_caliper', 'ecrp_hs_caliper_bolt',
    'ecrp_hs_spacer_thick', 'ecrp_hs_spacer_thin', 'ecrp_hs_ratchet', 'ecrp_hs_breaker_bar', 'ecrp_hs_torque_wrench',
}

local ZERO = vec3(0.0, 0.0, 0.0)

---@param v vector3
---@param degrees number
---@return vector3
local function rotateX(v, degrees)
    local r = math.rad(degrees)
    local c, s = math.cos(r), math.sin(r)

    return vec3(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
end

---@param v vector3
---@param degrees number
---@return vector3
local function rotateZ(v, degrees)
    local r = math.rad(degrees)
    local c, s = math.cos(r), math.sin(r)

    return vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
end

---@param vehicle integer
---@param bone string
---@return vector3?
local function boneLocal(vehicle, bone)
    local index = GetEntityBoneIndexByName(vehicle, bone)
    if index == -1 then return end

    local origin = GetEntityCoords(vehicle)
    local position = GetEntityBonePosition_2(vehicle, index)

    if #(position - origin) > MAX_BONE_REACH then
        position = GetWorldPositionOfEntityBone(vehicle, index)
    end

    if #(position - origin) > MAX_BONE_REACH then return end

    return GetOffsetFromEntityGivenWorldCoords(vehicle, position.x, position.y, position.z)
end

---@param vehicle integer
---@return boolean
local function takeControl(vehicle)
    if NetworkHasControlOfEntity(vehicle) then return true end

    local deadline = GetGameTimer() + CONTROL_TIMEOUT_MS

    NetworkRequestControlOfEntity(vehicle)

    while not NetworkHasControlOfEntity(vehicle) do
        if GetGameTimer() > deadline then return false end

        Wait(0)
    end

    return true
end

local game = { title = 'Motorcycle wheel change' }

---@param params { netId: integer, wheel: 'front' | 'rear' }
---@param spec BikeWheelSpec
---@return table? ctx
---@return string? reason
function game.prepare(params, spec)
    local wheel = shared.wheels[params.wheel]
    local layout = LAYOUT[params.wheel]

    if not wheel or not layout then return nil, 'bad_request' end

    local missing = props.missing({ layout.wheel, layout.stand, table.unpack(STATIC_MODELS) })
        or layout.adjusters and props.missing(ADJUSTER_MODELS)

    if missing then
        lib.print.error(('prop %s is not streamed'):format(missing))

        return nil, 'missing_props'
    end

    local vehicle = NetworkGetEntityFromNetworkId(params.netId)

    if vehicle == 0 or not DoesEntityExist(vehicle) then return nil, 'no_vehicle' end
    if not takeControl(vehicle) then return nil, 'no_control' end

    local hub = boneLocal(vehicle, wheel.bone)
    local other = boneLocal(vehicle, params.wheel == 'rear' and 'wheel_lf' or 'wheel_lr')
    local radius = GetVehicleWheelTireColliderSize(vehicle, wheel.wheelIndex)

    if not radius or radius < 0.15 then radius = DEFAULT_RADIUS end

    if not hub then
        lib.print.warn(('bone %s unreadable on %s, placing the rig from model size'):format(wheel.bone, GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))))

        local min, max = GetModelDimensions(GetEntityModel(vehicle))

        hub = vec3(0.0, params.wheel == 'rear' and min.y + radius or max.y - radius, min.z + radius)
    end

    local wheelbase = other and math.abs(hub.y - other.y) or 1.4
    local maxPitch = math.deg(math.atan(LIFT, wheelbase))

    local heading = GetEntityHeading(vehicle)
    local baseRotation = GetEntityRotation(vehicle, 2)

    SetEntityRotation(vehicle, baseRotation.x, 0.0, heading, 2, false)
    SetVehicleOnGroundProperly(vehicle)
    FreezeEntityPosition(vehicle, true)

    local baseCoords = GetEntityCoords(vehicle)
    local basePitch = GetEntityRotation(vehicle, 2).x

    local condition = {
        engine = GetVehicleEngineHealth(vehicle),
        body = GetVehicleBodyHealth(vehicle),
        tank = GetVehiclePetrolTankHealth(vehicle),
        dirt = GetVehicleDirtLevel(vehicle),
        burst = {},
    }

    for i = 1, #TYRE_INDICES do
        local tyre = TYRE_INDICES[i]

        if IsVehicleTyreBurst(vehicle, tyre, false) then
            condition.burst[tyre] = IsVehicleTyreBurst(vehicle, tyre, true)
        end

    end

    local brake = layout.brake and hub + layout.brake

    if not brake then
        local bar = boneLocal(vehicle, 'handlebars')

        brake = bar and bar + vec3(0.30, 0.0, 0.0) or hub + vec3(0.30, -0.30, 0.68)
    end

    local groundLocal = -radius - LIFT + 0.012

    local caliperAngle = layout.caliperAngle
    local caliperRoll = caliperAngle + 90.0
    local caliperCenter = hub + vec3(layout.discX, layout.caliperRadius * math.cos(math.rad(caliperAngle)), layout.caliperRadius * math.sin(math.rad(caliperAngle)))
    local earAxis = vec3(0.0, math.cos(math.rad(caliperRoll)), math.sin(math.rad(caliperRoll)))
    local earA = caliperCenter + earAxis * EAR_SPACING
    local earB = caliperCenter - earAxis * EAR_SPACING
    local upper, lower = earA, earB

    if earB.z > earA.z then upper, lower = earB, earA end

    local boltHead = {
        caliper_bolt_1 = vec3(caliperCenter.x + CALIPER_HALF_WIDTH, upper.y, upper.z),
        caliper_bolt_2 = vec3(caliperCenter.x + CALIPER_HALF_WIDTH, lower.y, lower.z),
    }

    local standOrigin = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, hub.y + layout.standY, hub.z)
    local found, groundZ = GetGroundZFor_3dCoord(standOrigin.x, standOrigin.y, standOrigin.z + 0.5, false)
    local standPivot = vec3(standOrigin.x, standOrigin.y, found and groundZ or standOrigin.z - radius)

    local parts = {
        wheel = { entity = props.spawn(layout.wheel, standPivot), offset = hub, rotation = ZERO },
        axle = { entity = props.spawn('ecrp_hs_axle', standPivot), offset = hub, rotation = ZERO },
        nut = { entity = props.spawn('ecrp_hs_axle_nut', standPivot), offset = hub + vec3(layout.nutX, 0.0, 0.0), rotation = ZERO },
        caliper = { entity = props.spawn('ecrp_hs_caliper', standPivot), offset = caliperCenter, rotation = vec3(caliperRoll, 0.0, 0.0) },
        caliper_bolt_1 = { entity = props.spawn('ecrp_hs_caliper_bolt', standPivot), offset = boltHead.caliper_bolt_1, rotation = ZERO },
        caliper_bolt_2 = { entity = props.spawn('ecrp_hs_caliper_bolt', standPivot), offset = boltHead.caliper_bolt_2, rotation = ZERO },
        spacer_thick = { entity = props.spawn('ecrp_hs_spacer_thick', standPivot), offset = hub + vec3(layout.spacerX.thick, 0.0, 0.0), rotation = ZERO },
        spacer_thin = { entity = props.spawn('ecrp_hs_spacer_thin', standPivot), offset = hub + vec3(layout.spacerX.thin, 0.0, 0.0), rotation = ZERO },
    }

    if layout.adjusters then
        for side, x in pairs(layout.adjusters) do
            parts['adjuster_plate_' .. side] = { entity = props.spawn(ADJUSTER_MODELS[1], standPivot), offset = hub + vec3(x, 0.0, 0.0), rotation = ZERO }
            parts['adjuster_bolt_' .. side] = { entity = props.spawn(ADJUSTER_MODELS[2], standPivot), offset = hub + vec3(x, ADJUSTER_BOLT_Y, 0.0), rotation = ZERO }
        end

    end

    local stand = props.spawn(layout.stand, standPivot)
    local tool

    ---@param name string
    local function sync(name)
        local part = parts[name]
        if not part then return end

        props.attach(part.entity, vehicle, part.offset, part.rotation)
    end

    ---@param name string
    ---@param offset vector3
    ---@param rotation? vector3
    local function move(name, offset, rotation)
        local part = parts[name]
        if not part then return end

        part.offset = offset
        part.rotation = rotation or part.rotation

        sync(name)
    end

    ---@param name string
    local function drop(name)
        props.remove(parts[name] and parts[name].entity)

        parts[name] = nil
    end

    ---@param name string
    ---@param model string
    ---@param offset vector3
    ---@param rotation? vector3
    local function add(name, model, offset, rotation)
        drop(name)

        parts[name] = { entity = props.spawn(model, standPivot), offset = offset, rotation = rotation or ZERO }

        sync(name)
        props.fadeIn(parts[name].entity, PART_FADE_MS)
    end

    for name in pairs(parts) do sync(name) end

    ---@param pitch number
    local function placeStand(pitch)
        props.place(stand, standPivot, vec3(pitch, 0.0, heading))
    end

    ---@param pitch number
    ---@return vector3
    local function handleAt(pitch)
        return standPivot + rotateZ(rotateX(layout.handle, pitch), heading)
    end

    ---@param progress number
    local function lift(progress)
        SetEntityRotation(vehicle, basePitch + layout.liftSign * maxPitch * progress, 0.0, heading, 2, false)
        SetEntityCoordsNoOffset(vehicle, baseCoords.x, baseCoords.y, baseCoords.z + LIFT * 0.5 * progress, false, false, false)
    end

    placeStand(layout.standPitch)

    ---@param offset vector3
    ---@return vector3
    local function world(offset)
        return GetOffsetFromEntityInWorldCoords(vehicle, offset.x, offset.y, offset.z)
    end

    ---@param name string
    ---@return vector3
    local function partWorld(name)
        return world(parts[name].offset)
    end

    local VIEWS = {
        stand = function() return hub + vec3(1.7, layout.dirY * 1.4, 0.75), hub + vec3(0.0, layout.dirY * 0.65, -0.05), 1 end,
        caliper = function() return caliperCenter + vec3(0.95, -0.25, 0.35), caliperCenter, 1 end,
        nut = function() return hub + vec3(layout.nutX - 0.95, -0.30, 0.40), hub + vec3(layout.nutX, 0.0, 0.0), -1 end,
        head = function() return hub + vec3(AXLE_HEAD_X + 0.55, -0.5, 0.2), hub + vec3(AXLE_HEAD_X, 0.0, 0.0), 1 end,
        wide = function() return hub + vec3(1.65, layout.dirY * 0.4, 0.4), hub + vec3(0.0, layout.dirY * 0.22, -0.08), 1 end,
        rear = function() return hub + vec3(0.0, -1.0, 0.22), hub + vec3(0.0, -0.1, 0.0), 0 end,
        brake = function() return brake + vec3(0.6, -0.35, 0.3), brake, 1 end,
    }

    local currentView = 'stand'

    lib.requestAnimDict(KNEEL_DICT)

    ---@param side integer
    local function kneel(side)
        local spot

        if side == 0 then
            spot = world(hub + vec3(0.0, -PED_OFFSET - 0.15, 0.0))
        else
            spot = world(hub + vec3(side * PED_OFFSET, 0.0, 0.0))
        end

        local facing = side == 0 and heading or heading + 90.0 * side

        if #(spot - GetEntityCoords(vehicle)) > MAX_KNEEL_REACH then return end

        SetEntityCoords(cache.ped, spot.x, spot.y, standPivot.z, false, false, false, false)
        SetEntityHeading(cache.ped, facing)
        TaskPlayAnim(cache.ped, KNEEL_DICT, KNEEL_CLIP, 8.0, 8.0, -1, 1, 0.0, false, false, false)
    end

    ---@param name string
    local function setView(name)
        currentView = name

        local from, target, side = VIEWS[name]()

        camera.aim(world(from), world(target))
        kneel(side)
    end

    do
        local from, target, side = VIEWS.stand()

        camera.start(world(from), world(target), true)
        kneel(side)
    end

    local opts = {
        render = function()
            local from, target = VIEWS[currentView]()

            camera.aim(world(from), world(target))
            camera.update()
            SetEntityLocallyInvisible(cache.ped)
        end,
    }

    ---@param kind 'ratchet' | 'breaker' | 'torque'
    ---@param offset vector3
    ---@param yaw number
    local function holdTool(kind, offset, yaw)
        props.remove(tool and tool.entity)

        tool = { entity = props.spawn(TOOL_MODELS[kind], standPivot), offset = offset, yaw = yaw }

        props.attach(tool.entity, vehicle, offset, vec3(0.0, 0.0, yaw))
    end

    ---@param degrees number
    local function spinTool(degrees)
        if not tool then return end

        props.attach(tool.entity, vehicle, tool.offset, vec3(-degrees, 0.0, tool.yaw))
    end

    local function dropTool()
        props.remove(tool and tool.entity)

        tool = nil
    end

    local adjust = { left = 0.0, right = 0.0 }
    local wheelY = 0.0

    ---@param side 'left' | 'right'
    ---@return vector3
    local function adjusterHead(side)
        return hub + vec3(layout.adjusters[side], ADJUSTER_BOLT_Y - ADJUSTER_HEAD_DEPTH + wheelY, 0.0)
    end

    local function syncAdjusters()
        if not layout.adjusters then return end

        for side, x in pairs(layout.adjusters) do
            move('adjuster_plate_' .. side, hub + vec3(x, wheelY, 0.0))
            move('adjuster_bolt_' .. side, hub + vec3(x, ADJUSTER_BOLT_Y + wheelY, 0.0), vec3(0.0, adjust[side] * 360.0, 0.0))
        end

    end

    ---@param target string
    ---@return vector3 base
    ---@return number direction
    local function fastener(target)
        if target == 'axle_nut' then return hub + vec3(layout.nutX, 0.0, 0.0), -1.0 end

        return boltHead[target], 1.0
    end

    local runners = {}

    ---@param step HandsonStep
    function runners.drag(step)
        local target = step.target

        if target == 'stand_handle' then
            local up, down = handleAt(layout.standPitch), handleAt(0.0)

            return input.drag({
                render = opts.render,
                from = function() return step.reverse and down or up end,
                to = function() return step.reverse and up or down end,
                onProgress = function(p)
                    local amount = step.reverse and 1.0 - p or p

                    placeStand(layout.standPitch * (1.0 - amount))
                    lift(amount)
                end,
            })
        end

        if target == 'caliper' then
            local seated, hung = caliperCenter, caliperCenter + layout.caliperLift
            local a, b = seated, hung

            if step.reverse then a, b = hung, seated end

            return input.drag({
                render = opts.render,
                from = function() return world(a) end,
                to = function() return world(b) end,
                onProgress = function(p) move('caliper', a + (b - a) * p) end,
            })
        end

        if target == 'axle' then
            local inside, outside = hub, hub + vec3(layout.axleOut, 0.0, 0.0)
            local a, b = inside, outside

            if step.reverse then a, b = outside, inside end

            move('axle', a, ZERO)

            return input.drag({
                render = opts.render,
                from = function() return world(a + vec3(AXLE_HEAD_X, 0.0, 0.0)) end,
                to = function() return world(b + vec3(AXLE_HEAD_X, 0.0, 0.0)) end,
                onProgress = function(p) move('axle', a + (b - a) * p) end,
            })
        end

        if target == 'wheel_forward' then
            local start = hub + vec3(0.0, wheelY, 0.0)

            return input.drag({
                render = opts.render,
                from = function() return world(hub) end,
                to = function() return world(hub + vec3(0.0, 0.12, 0.0)) end,
                onProgress = function(p) move('wheel', start + vec3(0.0, (layout.forward - wheelY) * p, 0.0)) end,
            })
        end

        if target == 'wheel_out' then
            local a = parts.wheel.offset
            local b = hub + vec3(0.45, layout.dirY * 0.55, -LIFT)

            return input.drag({
                render = opts.render,
                from = function() return world(a) end,
                to = function() return world(b) end,
                onProgress = function(p) move('wheel', a + (b - a) * p) end,
            })
        end

        if target == 'wheel_in' then
            local a = hub + vec3(0.45, layout.dirY * 0.75, -LIFT)
            local b = hub + vec3(0.0, layout.forward, 0.0)

            if not parts.new_wheel then
                add('new_wheel', layout.wheel, a)
            end

            move('new_wheel', a)

            return input.drag({
                render = opts.render,
                from = function() return world(a) end,
                to = function() return world(b) end,
                onProgress = function(p) move('new_wheel', a + (b - a) * p) end,
            })
        end

    end

    ---@param step HandsonStep
    function runners.turn(step)
        local base, outward = fastener(step.target)
        local name = step.target == 'axle_nut' and 'nut' or step.target
        local travel = step.target == 'axle_nut' and NUT_TRAVEL or BOLT_TRAVEL
        local loosening = step.dir < 0

        if not parts[name] then
            add(name, step.target == 'axle_nut' and 'ecrp_hs_axle_nut' or 'ecrp_hs_caliper_bolt', base)
        end

        local startAt = loosening and base or base + vec3(outward * travel, 0.0, 0.0)
        local endAt = loosening and base + vec3(outward * travel, 0.0, 0.0) or base

        move(name, startAt, ZERO)

        if step.tool then
            holdTool(step.tool, startAt, outward > 0 and 0.0 or 180.0)
        end

        local result = input.turn({
            render = opts.render,
            target = function() return partWorld(name) end,
            dir = step.dir,
            turns = step.turns,
            breakaway = step.breakaway and spec.breakaway or nil,
            onAngle = function(degrees, progress, strain)
                local at = startAt + (endAt - startAt) * progress

                move(name, at, vec3(-degrees, 0.0, 0.0))

                if tool then
                    tool.offset = at

                    spinTool(degrees + strain * TOOL_FLEX_DEG * step.dir)
                end

            end,
        })

        dropTool()

        return result
    end

    ---@param step HandsonStep
    function runners.torque(step)
        local base = fastener(step.target)

        move('nut', base, ZERO)
        holdTool(step.tool or 'torque', base, 180.0)

        local nm = input.torque({
            render = opts.render,
            target = function() return partWorld('nut') end,
            spec = spec.torque,
            onAngle = function(degrees)
                move('nut', base, vec3(-degrees, 0.0, 0.0))
                spinTool(degrees)
            end,
        })

        dropTool()

        return nm and { nm = nm }
    end

    ---@param step HandsonStep
    function runners.adjust(step)
        local wheelName = parts.new_wheel and 'new_wheel' or 'wheel'
        local activeSide

        local result = input.adjust({
            render = opts.render,
            left = function() return world(adjusterHead('left')) end,
            right = function() return world(adjusterHead('right')) end,
            start = { left = adjust.left, right = adjust.right },
            onChange = function(l, r, active, degrees)
                adjust.left, adjust.right = l, r
                wheelY = -((l + r) * 0.5) * WHEEL_PER_TURN

                move(wheelName, hub + vec3(0.0, wheelY, 0.0))
                syncAdjusters()

                if active ~= activeSide then
                    activeSide = active

                    if active then
                        holdTool('ratchet', adjusterHead(active), -90.0)
                    else
                        dropTool()
                    end

                end

                if active and degrees and tool then
                    tool.offset = adjusterHead(active)

                    spinTool(degrees)
                end

            end,

            done = step.goal == 'loose' and function(l, r)
                return l <= -spec.looseTurns and r <= -spec.looseTurns
            end or nil,

            gauge = function(l, r)
                if step.goal == 'loose' then
                    return {
                        type = 'loosen',
                        left = math.max(0.0, -l) / spec.looseTurns,
                        right = math.max(0.0, -r) / spec.looseTurns,
                        goal = spec.looseTurns,
                    }
                end

                local slack, skew = shared.chain(spec, l, r)

                return {
                    type = 'chain',
                    slack = math.floor(slack + 0.5),
                    lo = spec.slackLo,
                    hi = spec.slackHi,
                    skew = skew,
                    tolerance = spec.alignTolerance,
                    goal = step.goal,
                }
            end,
        })

        dropTool()

        return result
    end

    ---@param step HandsonStep
    function runners.pick(step)
        local slotX = step.side == wheel.thickSide and layout.spacerX.thick or layout.spacerX.thin
        local trayX = step.side * 0.30

        add('tray_thick', 'ecrp_hs_spacer_thick', hub + vec3(trayX, -0.08, -0.12))
        add('tray_thin', 'ecrp_hs_spacer_thin', hub + vec3(trayX, 0.08, -0.12))

        local choice = input.pick({
            render = opts.render,
            options = {
                { key = 'thick', pos = function() return partWorld('tray_thick') end },
                { key = 'thin', pos = function() return partWorld('tray_thin') end },
            },
        })

        if not choice then return end

        local chosen = 'tray_' .. choice

        move(chosen, hub + vec3(slotX, 0.0, 0.0))
        drop(choice == 'thick' and 'tray_thin' or 'tray_thick')

        parts['fitted_' .. step.side] = parts[chosen]
        parts[chosen] = nil

        return { choice = choice }
    end

    ---@param step HandsonStep
    function runners.click(step)
        local target = layout.chain

        return input.click({
            render = opts.render,
            target = function() return world(hub + target) end,
        })
    end

    ---@param step HandsonStep
    function runners.pump(step)
        return input.pump({
            render = opts.render,
            target = function() return world(brake) end,
            count = spec.pumps,
            onPump = function() end,
        })
    end

    ---@param name string
    ---@param offset vector3
    ---@param rotation vector3
    ---@param height number
    local function rest(name, offset, rotation, height)
        local part = parts[name]
        if not part then return end

        part.offset = offset
        part.rotation = rotation

        local spot = world(offset)
        local found, groundZ = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 0.5, false)

        DetachEntity(part.entity, false, false)
        props.place(part.entity, vec3(spot.x, spot.y, (found and groundZ or spot.z) + height), vec3(rotation.x, rotation.y, heading + rotation.z))
    end

    local commits = {
        caliper_bolt_1 = function() rest('caliper_bolt_1', vec3(hub.x + 0.40, hub.y - 0.05, hub.z + groundLocal), ZERO, BOLT_REST) end,
        caliper_bolt_2 = function() rest('caliper_bolt_2', vec3(hub.x + 0.40, hub.y - 0.10, hub.z + groundLocal), ZERO, BOLT_REST) end,
        axle_nut_off = function() rest('nut', hub + vec3(-0.45, 0.10, groundLocal), ZERO, NUT_REST) end,
        axle_out = function()
            rest('axle', hub + vec3(0.50, -0.15, groundLocal), vec3(0.0, 0.0, 90.0), AXLE_REST)
            drop('spacer_thick')
            drop('spacer_thin')
        end,

        chain_off = function()
            wheelY = layout.forward

            syncAdjusters()
        end,

        wheel_out = function() rest('wheel', hub + vec3(0.8, -layout.dirY * 0.45, groundLocal), vec3(0.0, 90.0, 0.0), layout.halfWidth) end,
        axle_torque = function() move('nut', hub + vec3(layout.nutX, 0.0, 0.0), ZERO) end,
    }

    ---@param step HandsonStep
    ---@return any data nil when cancelled
    local function run(step)
        setView(step.view)

        local runner = runners[step.kind]
        if not runner then return end

        local result = runner(step)
        if result == nil then return end

        return result
    end

    ---@param step HandsonStep
    local function commit(step)
        local action = commits[step.name]

        if action then action() end
    end

    ---@param step HandsonStep
    local function retry(step)
        if step.kind == 'pick' then
            drop('fitted_' .. step.side)
        end

    end

    ---@param fitted boolean
    local function restore(fitted)
        SetVehicleFixed(vehicle)
        SetVehicleEngineHealth(vehicle, condition.engine)
        SetVehicleBodyHealth(vehicle, condition.body)
        SetVehiclePetrolTankHealth(vehicle, condition.tank)
        SetVehicleDirtLevel(vehicle, condition.dirt)

        for tyre, completely in pairs(condition.burst) do
            if not fitted or tyre ~= wheel.tyreIndex then
                SetVehicleTyreBurst(vehicle, tyre, completely, 1000.0)
            end

        end

    end

    ---@param fitted boolean
    local function cleanup(fitted)
        dropTool()
        props.remove(stand)

        for name in pairs(parts) do drop(name) end

        camera.stop(true)
        RemoveAnimDict(KNEEL_DICT)
        ClearPedTasks(cache.ped)

        if DoesEntityExist(vehicle) then
            restore(fitted == true)
            SetEntityRotation(vehicle, basePitch, 0.0, heading, 2, false)
            SetEntityCoordsNoOffset(vehicle, baseCoords.x, baseCoords.y, baseCoords.z, false, false, false)
            FreezeEntityPosition(vehicle, false)
            SetVehicleOnGroundProperly(vehicle)
        end

    end

    FreezeEntityPosition(vehicle, false)
    SetVehicleWheelsCanBreak(vehicle, true)
    BreakOffVehicleWheel(vehicle, wheel.wheelIndex, false, true, true, false)
    SetEntityRotation(vehicle, basePitch, 0.0, heading, 2, false)
    SetEntityCoordsNoOffset(vehicle, baseCoords.x, baseCoords.y, baseCoords.z, false, false, false)
    FreezeEntityPosition(vehicle, true)

    return {
        opts = opts,
        steps = shared.steps[params.wheel],
        run = run,
        commit = commit,
        retry = retry,
        cleanup = cleanup,
    }
end

return game
