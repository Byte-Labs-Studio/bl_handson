local config = require 'config'

local bridge = {}

local INVENTORIES = { 'ox_inventory', 'qs-inventory', 'qb-core', 'es_extended' }

---@return string?
local function inventory()
    if config.inventory == 'none' then return end
    if config.inventory ~= 'auto' then return config.inventory end

    for i = 1, #INVENTORIES do
        if GetResourceState(INVENTORIES[i]) == 'started' then return INVENTORIES[i] end
    end

end

---@param source integer
---@return table?
local function qbPlayer(source)
    return exports['qb-core']:GetCoreObject().Functions.GetPlayer(source)
end

---@param source integer
---@return table?
local function esxPlayer(source)
    return exports.es_extended:getSharedObject().GetPlayerFromId(source)
end

---@param source integer
---@param item string
---@return number
function bridge.count(source, item)
    local backend = inventory()

    if backend == 'ox_inventory' then
        return exports.ox_inventory:Search(source, 'count', item) or 0
    end

    if backend == 'qs-inventory' then
        return exports['qs-inventory']:GetItemTotalAmount(source, item) or 0
    end

    if backend == 'qb-core' then
        local player = qbPlayer(source)
        local entry = player and player.Functions.GetItemByName(item)

        return entry and (entry.amount or entry.count) or 0
    end

    if backend == 'es_extended' then
        local player = esxPlayer(source)
        local entry = player and player.getInventoryItem(item)

        return entry and entry.count or 0
    end

    return 0
end

---@param source integer
---@param item string
---@return boolean
function bridge.remove(source, item)
    local backend = inventory()

    if backend == 'ox_inventory' then
        return exports.ox_inventory:RemoveItem(source, item, 1) == true
    end

    if backend == 'qs-inventory' then
        return exports['qs-inventory']:RemoveItem(source, item, 1) and true or false
    end

    if backend == 'qb-core' then
        local player = qbPlayer(source)

        return player and player.Functions.RemoveItem(item, 1) and true or false
    end

    if backend == 'es_extended' then
        local player = esxPlayer(source)
        local entry = player and player.getInventoryItem(item)

        if not entry or (entry.count or 0) < 1 then return false end

        player.removeInventoryItem(item, 1)

        return true
    end

    return false
end

return bridge
