local SendNUIMessage = SendNUIMessage

local hud = {}

local lastGauge

---@param visible boolean
---@param title? string
function hud.show(visible, title)
    lastGauge = nil

    SendNUIMessage({ action = 'visible', visible = visible, title = title })
end

---@param index integer
---@param total integer
---@param label string
---@param hint string
function hud.step(index, total, label, hint)
    lastGauge = nil

    SendNUIMessage({ action = 'step', index = index, total = total, label = label, hint = hint })
end

---@param data table
function hud.gauge(data)
    local key = json.encode(data)

    if key == lastGauge then return end

    lastGauge = key

    SendNUIMessage({ action = 'gauge', gauge = data })
end

---@param kind 'strike' | 'good' | 'info'
---@param text string
---@param strikes? integer
---@param maxStrikes? integer
function hud.flash(kind, text, strikes, maxStrikes)
    SendNUIMessage({ action = 'flash', kind = kind, text = text, strikes = strikes, maxStrikes = maxStrikes })
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    SendNUIMessage({ action = 'visible', visible = false })
end)

return hud
