local config = require 'config'

local bridge = {}

bridge.targets = { 'ox_target', 'qb-target' }

---@type table[]
local registered = {}

---@return string?
local function target()
    if config.target ~= 'auto' then return config.target end

    for i = 1, #bridge.targets do
        if GetResourceState(bridge.targets[i]) == 'started' then return bridge.targets[i] end
    end

end

---@param option table
---@return table
local function qbOption(option)
    return {
        type = 'client',
        label = option.label,
        icon = option.icon,
        item = option.items and option.items[1],
        canInteract = function(entity) return option.canInteract(entity) end,
        action = function(entity) option.onSelect({ entity = entity }) end,
    }
end

---@param options table[]
function bridge.addVehicleOptions(options)
    local resource = target()

    if not resource or GetResourceState(resource) ~= 'started' then return end

    registered = options

    if resource == 'ox_target' then
        exports.ox_target:addGlobalVehicle(options)

        return
    end

    for i = 1, #options do
        local option = options[i]

        exports['qb-target']:AddTargetBone({ option.bones }, {
            options = { qbOption(option) },
            distance = option.distance,
        })
    end

end

function bridge.removeVehicleOptions()
    local resource = target()

    if not resource or GetResourceState(resource) ~= 'started' then return end

    if resource == 'ox_target' then
        local names = {}

        for i = 1, #registered do
            names[i] = registered[i].name
        end

        exports.ox_target:removeGlobalVehicle(names)

        return
    end

    for i = 1, #registered do
        local option = registered[i]

        exports['qb-target']:RemoveTargetBone({ option.bones }, option.label)
    end

end

---@param title string
---@param text string
---@param kind 'success' | 'error' | 'info'
function bridge.notify(title, text, kind)
    lib.notify({ title = title, description = text, type = kind })
end

return bridge
