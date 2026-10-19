local CreateObjectNoOffset = CreateObjectNoOffset
local AttachEntityToEntity = AttachEntityToEntity
local SetEntityCoordsNoOffset = SetEntityCoordsNoOffset
local SetEntityRotation = SetEntityRotation
local DoesEntityExist = DoesEntityExist

local props = {}

---@type table<integer, true>
local spawned = {}

---@param models string[]
---@return string? missing
function props.missing(models)
    for i = 1, #models do
        if not IsModelInCdimage(joaat(models[i])) then return models[i] end
    end

end

---@param model string
---@param coords vector3
---@return integer entity
function props.spawn(model, coords)
    local hash = joaat(model)

    lib.requestModel(hash)

    local entity = CreateObjectNoOffset(hash, coords.x, coords.y, coords.z, false, false, false)

    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(entity, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityInvincible(entity, true)

    spawned[entity] = true

    return entity
end

---@param entity integer
---@param parent integer
---@param offset vector3
---@param rotation vector3
function props.attach(entity, parent, offset, rotation)
    if not DoesEntityExist(entity) then return end

    AttachEntityToEntity(entity, parent, 0, offset.x, offset.y, offset.z, rotation.x, rotation.y, rotation.z, false, false, false, false, 2, true)
end

---@param entity integer
---@param coords vector3
---@param rotation vector3
function props.place(entity, coords, rotation)
    if not DoesEntityExist(entity) then return end

    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, false, false, false)
    SetEntityRotation(entity, rotation.x, rotation.y, rotation.z, 2, false)
end

---@param entity integer
---@param ms integer
function props.fadeIn(entity, ms)
    if not DoesEntityExist(entity) then return end

    SetEntityAlpha(entity, 0, false)

    CreateThread(function()
        local started = GetGameTimer()

        while DoesEntityExist(entity) do
            local progress = (GetGameTimer() - started) / ms

            if progress >= 1.0 then
                ResetEntityAlpha(entity)

                return
            end

            SetEntityAlpha(entity, math.floor(progress * 255), false)

            Wait(0)
        end

    end)
end

---@param entity integer?
function props.remove(entity)
    if not entity then return end

    spawned[entity] = nil

    if DoesEntityExist(entity) then
        DetachEntity(entity, false, false)
        DeleteEntity(entity)
    end

end

function props.clear()
    for entity in pairs(spawned) do
        props.remove(entity)
    end

end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    props.clear()
end)

return props
