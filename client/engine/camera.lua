local SetCamCoord = SetCamCoord
local PointCamAtCoord = PointCamAtCoord
local GetFrameTime = GetFrameTime

local TRANSITION_MS = 600
local FOV = 45.0
local FOLLOW_RATE = 5.0

local camera = {}

local cam
local position
local aim
local wantPosition
local wantAim

---@param from vector3
---@param target vector3
---@param instant? boolean
function camera.start(from, target, instant)
    camera.stop()

    position, aim = from, target
    wantPosition, wantAim = from, target

    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    SetCamFov(cam, FOV)
    SetCamCoord(cam, from.x, from.y, from.z)
    PointCamAtCoord(cam, target.x, target.y, target.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, not instant, TRANSITION_MS, true, false)
end

---@param from vector3
---@param target vector3
function camera.aim(from, target)
    wantPosition, wantAim = from, target
end

function camera.update()
    if not cam then return end

    local blend = math.min(1.0, GetFrameTime() * FOLLOW_RATE)

    position = position + (wantPosition - position) * blend
    aim = aim + (wantAim - aim) * blend

    SetCamCoord(cam, position.x, position.y, position.z)
    PointCamAtCoord(cam, aim.x, aim.y, aim.z)
end

---@param instant? boolean
function camera.stop(instant)
    if not cam then return end

    RenderScriptCams(false, not instant, TRANSITION_MS, true, false)
    DestroyCam(cam, false)

    cam = nil
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    if cam then
        RenderScriptCams(false, false, 0, true, false)
        DestroyCam(cam, false)
    end

end)

return camera
