local hud = require 'client.engine.hud'

local DisableAllControlActions = DisableAllControlActions
local EnableControlAction = EnableControlAction
local SetMouseCursorActiveThisFrame = SetMouseCursorActiveThisFrame
local SetMouseCursorSprite = SetMouseCursorSprite
local GetDisabledControlNormal = GetDisabledControlNormal
local IsDisabledControlJustPressed = IsDisabledControlJustPressed
local IsDisabledControlJustReleased = IsDisabledControlJustReleased
local IsDisabledControlPressed = IsDisabledControlPressed
local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord
local DrawSprite = DrawSprite
local GetFrameTime = GetFrameTime
local GetGameTimer = GetGameTimer
local PlaySoundFrontend = PlaySoundFrontend

local CURSOR_X = 239
local CURSOR_Y = 240
local MOUSE_LEFT = 24
local KEY_CANCEL = 73
local KEY_CONFIRM = 38
local KEEP_ENABLED = { 199, 200, 245, 249 }

local SPRITE_NORMAL = 1
local SPRITE_HOVER = 3
local SPRITE_GRAB = 4

local HOVER_PX = 34
local MIN_RADIUS_PX = 14
local DRAG_SNAP = 0.92
local EFFORT_DECAY = 160.0
local SNUG_DEG = 90.0
local TORQUE_DEG = 180.0
local BREAKOVER_RATE = 0.15
local CLICK_RESET = 0.9
local PUMP_GAP_MS = 250
local ADJUST_LIMIT = 10.0
local DOT_DICT = 'shared'
local DOT_NAME = 'emptydot_32'
local DOT_SIZE = 0.014
local DOT_SIZE_HOT = 0.019
local SIDES = { 'left', 'right' }

local input = {}

local width, height = 1920, 1080
local interrupted = false

local state = {
    x = 0.0,
    y = 0.0,
    pressed = false,
    held = false,
    released = false,
    cancel = false,
    confirm = false,
}

---@class HandsonFrameOpts
---@field render fun()

function input.begin()
    width, height = GetActiveScreenResolution()
    interrupted = false

    lib.requestStreamedTextureDict(DOT_DICT)
end

function input.finish()
    SetStreamedTextureDictAsNoLongerNeeded(DOT_DICT)
end

function input.interrupt()
    interrupted = true
end

---@param opts HandsonFrameOpts
local function frame(opts)
    DisableAllControlActions(0)

    for i = 1, #KEEP_ENABLED do
        EnableControlAction(0, KEEP_ENABLED[i], true)
    end

    SetMouseCursorActiveThisFrame()

    state.x = GetDisabledControlNormal(0, CURSOR_X) * width
    state.y = GetDisabledControlNormal(0, CURSOR_Y) * height
    state.pressed = IsDisabledControlJustPressed(0, MOUSE_LEFT)
    state.held = IsDisabledControlPressed(0, MOUSE_LEFT)
    state.released = IsDisabledControlJustReleased(0, MOUSE_LEFT)
    state.cancel = interrupted or IsDisabledControlJustPressed(0, KEY_CANCEL)
    state.confirm = IsDisabledControlJustPressed(0, KEY_CONFIRM)

    opts.render()
end

---@param pos vector3
---@return number? x
---@return number? y
local function project(pos)
    local visible, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
    if not visible then return end

    return sx * width, sy * height
end

---@param pos vector3
---@return number distance
---@return number? sx
---@return number? sy
local function distanceTo(pos)
    local sx, sy = project(pos)
    if not sx then return math.huge end

    local dx, dy = state.x - sx, state.y - sy

    return math.sqrt(dx * dx + dy * dy), sx, sy
end

---@param pos vector3
---@param hot boolean
---@param dim? boolean
local function marker(pos, hot, dim)
    local r, g, b, a = 255, 200, 60, 170

    if hot then
        r, g, b, a = 120, 255, 140, 220
    elseif dim then
        r, g, b, a = 255, 255, 255, 70
    end

    local visible, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
    if not visible then return end

    local size = hot and DOT_SIZE_HOT or DOT_SIZE

    DrawSprite(DOT_DICT, DOT_NAME, sx, sy, size, size * width / height, 0.0, r, g, b, a)
end

---@param grabbing boolean
---@param hot boolean
local function sprite(grabbing, hot)
    SetMouseCursorSprite(grabbing and SPRITE_GRAB or hot and SPRITE_HOVER or SPRITE_NORMAL)
end

---@param name string
---@param set? string
function input.sound(name, set)
    PlaySoundFrontend(-1, name, set or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
end

---@class HandsonRotary
---@field last? number

---@param rotary HandsonRotary
---@param sx number?
---@param sy number?
---@return number delta clockwise degrees on screen since the last frame
local function rotate(rotary, sx, sy)
    if not sx then return 0.0 end

    local dx, dy = state.x - sx, state.y - sy

    if dx * dx + dy * dy < MIN_RADIUS_PX * MIN_RADIUS_PX then return 0.0 end

    local angle = math.deg(math.atan(dy, dx))
    local last = rotary.last

    rotary.last = angle

    if not last then return 0.0 end

    return (angle - last + 540.0) % 360.0 - 180.0
end

---@class HandsonClickOpts : HandsonFrameOpts
---@field target fun(): vector3

---@param opts HandsonClickOpts
---@return boolean? clicked nil when cancelled
function input.click(opts)
    while true do
        frame(opts)

        if state.cancel then return end

        local pos = opts.target()
        local hot = distanceTo(pos) <= HOVER_PX

        marker(pos, hot)
        sprite(false, hot)

        if hot and state.pressed then
            input.sound('SELECT')

            return true
        end

        Wait(0)
    end

end

---@class HandsonDragOpts : HandsonFrameOpts
---@field from fun(): vector3
---@field to fun(): vector3
---@field onProgress fun(progress: number)

---@param opts HandsonDragOpts
---@return boolean? done nil when cancelled
function input.drag(opts)
    local progress = 0.0
    local grabbing = false

    while true do
        frame(opts)

        if state.cancel then return end

        local a, b = opts.from(), opts.to()
        local handle = a + (b - a) * progress
        local hot = false

        if not grabbing then
            hot = distanceTo(handle) <= HOVER_PX

            marker(handle, hot)
            marker(b, false, true)

            if hot and state.pressed then
                grabbing = true
            end

        elseif not state.held then
            grabbing = false

            if progress >= DRAG_SNAP then
                opts.onProgress(1.0)
                input.sound('SELECT')

                return true
            end

            progress = 0.0
        else
            local ax, ay = project(a)
            local bx, by = project(b)

            if ax and bx then
                local vx, vy = bx - ax, by - ay
                local length = vx * vx + vy * vy

                if length > 1.0 then
                    progress = math.clamp(((state.x - ax) * vx + (state.y - ay) * vy) / length, 0.0, 1.0)
                end

            end

            marker(b, progress >= DRAG_SNAP, true)
        end

        sprite(grabbing, hot)
        opts.onProgress(progress)
        hud.gauge({ type = 'progress', value = progress })

        Wait(0)
    end

end

---@class HandsonTurnOpts : HandsonFrameOpts
---@field target fun(): vector3
---@field dir 1 | -1
---@field turns number
---@field breakaway? number
---@field onAngle fun(degrees: number, progress: number, strain: number)
---@field onCrack? fun()

---@param opts HandsonTurnOpts
---@return boolean? done nil when cancelled
function input.turn(opts)
    local goal = opts.turns * 360.0
    local turned = 0.0
    local effort = 0.0
    local cracked = not opts.breakaway
    local grabbing = false
    local rotary = {}

    while true do
        frame(opts)

        if state.cancel then return end

        local pos = opts.target()
        local distance, sx, sy = distanceTo(pos)
        local hot = false

        if not grabbing then
            hot = distance <= HOVER_PX

            marker(pos, hot)

            if hot and state.pressed then
                grabbing = true
                rotary.last = nil
            end

        elseif not state.held then
            grabbing = false
        else
            local useful = rotate(rotary, sx, sy) * opts.dir

            if cracked then
                turned = math.max(0.0, turned + useful)
            elseif useful > 0.0 then
                effort += useful

                if effort >= opts.breakaway then
                    cracked = true

                    input.sound('Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS')

                    if opts.onCrack then opts.onCrack() end
                end

            end

        end

        local strain = 0.0

        if not cracked then
            effort = math.max(0.0, effort - EFFORT_DECAY * GetFrameTime())
            strain = effort / opts.breakaway
        end

        sprite(grabbing, hot)
        opts.onAngle(turned * opts.dir, math.min(1.0, turned / goal), strain)
        hud.gauge({ type = 'turn', value = math.min(1.0, turned / goal), strain = not cracked and strain or nil })

        if turned >= goal then return true end

        Wait(0)
    end

end

---@class HandsonTorqueOpts : HandsonFrameOpts
---@field target fun(): vector3
---@field spec number
---@field onAngle fun(degrees: number)

---@param opts HandsonTorqueOpts
---@return number? nm nil when cancelled
function input.torque(opts)
    local turned = 0.0
    local clicked = false
    local grabbing = false
    local rotary = {}

    while true do
        frame(opts)

        if state.cancel then return end

        local pos = opts.target()
        local distance, sx, sy = distanceTo(pos)
        local hot = false
        local nm = math.max(0.0, (turned - SNUG_DEG) / TORQUE_DEG) * opts.spec

        if not grabbing then
            hot = distance <= HOVER_PX

            marker(pos, hot)

            if hot and state.pressed then
                grabbing = true
                rotary.last = nil
            end

        elseif not state.held then
            grabbing = false

            if clicked then return nm end
        else
            local delta = rotate(rotary, sx, sy)

            if clicked and delta > 0.0 then
                delta *= BREAKOVER_RATE
            end

            turned = math.max(0.0, turned + delta)
            nm = math.max(0.0, (turned - SNUG_DEG) / TORQUE_DEG) * opts.spec

            if not clicked and nm >= opts.spec then
                clicked = true

                input.sound('CLICK_BACK', 'WEB_NAVIGATION_SOUNDS_PHONE')
            elseif clicked and nm < opts.spec * CLICK_RESET then
                clicked = false
            end

        end

        sprite(grabbing, hot)
        opts.onAngle(turned)
        hud.gauge({ type = 'torque', value = math.floor(nm + 0.5), spec = opts.spec, clicked = clicked })

        Wait(0)
    end

end

---@class HandsonAdjustOpts : HandsonFrameOpts
---@field left fun(): vector3
---@field right fun(): vector3
---@field start { left: number, right: number }
---@field onChange fun(left: number, right: number, active?: 'left' | 'right', degrees?: number)
---@field gauge fun(left: number, right: number): table
---@field done? fun(left: number, right: number): boolean

---@param opts HandsonAdjustOpts
---@return { left: number, right: number }? turns nil when cancelled
function input.adjust(opts)
    local turns = { left = opts.start.left, right = opts.start.right }
    local active
    local rotary = {}

    while true do
        frame(opts)

        if state.cancel then return end

        local finished

        if opts.done then
            finished = not state.held and opts.done(turns.left, turns.right)
        else
            finished = state.confirm
        end

        if finished then
            input.sound('SELECT')

            return { left = turns.left, right = turns.right }
        end

        local hot = false

        if not active then
            for i = 1, #SIDES do
                local side = SIDES[i]
                local pos = opts[side]()
                local over = distanceTo(pos) <= HOVER_PX

                marker(pos, over)

                if over then
                    hot = true

                    if state.pressed then
                        active = side
                        rotary.last = nil
                    end

                end

            end

        elseif not state.held then
            active = nil
        else
            local _, sx, sy = distanceTo(opts[active]())

            turns[active] = math.clamp(turns[active] + rotate(rotary, sx, sy) / 360.0, -ADJUST_LIMIT, ADJUST_LIMIT)
        end

        sprite(active ~= nil, hot)
        opts.onChange(turns.left, turns.right, active, active and turns[active] * 360.0 or nil)
        hud.gauge(opts.gauge(turns.left, turns.right))

        Wait(0)
    end

end

---@class HandsonPickOption
---@field key string
---@field pos fun(): vector3

---@class HandsonPickOpts : HandsonFrameOpts
---@field options HandsonPickOption[]

---@param opts HandsonPickOpts
---@return string? key nil when cancelled
function input.pick(opts)
    while true do
        frame(opts)

        if state.cancel then return end

        local hot = false

        for i = 1, #opts.options do
            local option = opts.options[i]
            local pos = option.pos()
            local over = distanceTo(pos) <= HOVER_PX

            marker(pos, over)

            if over then
                hot = true

                if state.pressed then
                    input.sound('SELECT')

                    return option.key
                end

            end

        end

        sprite(false, hot)

        Wait(0)
    end

end

---@class HandsonPumpOpts : HandsonFrameOpts
---@field target fun(): vector3
---@field count integer
---@field onPump fun(count: integer)

---@param opts HandsonPumpOpts
---@return boolean? done nil when cancelled
function input.pump(opts)
    local count = 0
    local lastAt = 0

    while true do
        frame(opts)

        if state.cancel then return end

        local pos = opts.target()
        local hot = distanceTo(pos) <= HOVER_PX
        local now = GetGameTimer()

        marker(pos, hot)
        sprite(false, hot)

        if hot and state.pressed and now - lastAt >= PUMP_GAP_MS then
            lastAt = now
            count += 1

            input.sound('NAV_UP_DOWN')
            opts.onPump(count)

            if count >= opts.count then return true end
        end

        hud.gauge({ type = 'count', value = count, goal = opts.count })

        Wait(0)
    end

end

---@param opts HandsonFrameOpts
---@param ready fun(): any
---@return any
function input.wait(opts, ready)
    while true do
        local value = ready()

        if value ~= nil then return value end

        frame(opts)
        sprite(false, false)

        Wait(0)
    end

end

return input
