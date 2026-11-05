local config = require 'config'

---@class HandsonGame
---@field prepare fun(source: integer, params: table): boolean, string?, table?
---@field spec fun(params: table, state: table): table
---@field steps fun(params: table): HandsonStep[]
---@field begin fun(session: HandsonSession)
---@field check fun(session: HandsonSession): boolean, string?
---@field validate fun(session: HandsonSession, step: HandsonStep, data: any): boolean, string?
---@field complete fun(session: HandsonSession): boolean, string?
---@field finish fun(session: HandsonSession, ok: boolean, reason?: string)

---@type table<string, HandsonGame>
local games = {
    bikewheel = require 'server.games.bikewheel',
}

local STEP_IDLE_MS = 120000
local SESSION_MAX_MS = 900000
local STEP_COOLDOWN_MS = 150
local WATCHDOG_MS = 2000

---@class HandsonSession
---@field id integer
---@field source integer
---@field game string
---@field params table
---@field state table
---@field spec table
---@field steps HandsonStep[]
---@field index integer
---@field strikes integer
---@field startedAt integer
---@field stepAt integer
---@field lastCall integer
---@field promise promise

---@type table<integer, HandsonSession>
local bySource = {}

local nextId = 0

---@type integer?
local watchdog

---@param session HandsonSession
---@param ok boolean
---@param reason? string
---@param notifyClient? boolean
local function finish(session, ok, reason, notifyClient)
    if bySource[session.source] ~= session then return end

    bySource[session.source] = nil

    if watchdog and not next(bySource) then
        ClearInterval(watchdog)

        watchdog = nil
    end

    games[session.game].finish(session, ok, reason)

    if notifyClient then
        TriggerClientEvent('bl_handson:client:stop', session.source, session.id, reason)
    end

    session.promise:resolve({ ok = ok, reason = reason })
end

---@param session HandsonSession
---@param reason string
---@return table
local function strike(session, reason)
    session.strikes += 1
    session.stepAt = GetGameTimer()

    if session.strikes >= config.maxStrikes then
        finish(session, false, 'strikes')

        return { ok = false, strike = true, failed = true, reason = reason, strikes = session.strikes }
    end

    return { ok = false, strike = true, reason = reason, strikes = session.strikes }
end

local function patrol()
    local now = GetGameTimer()

    for _, session in pairs(bySource) do
        if now - session.stepAt > STEP_IDLE_MS or now - session.startedAt > SESSION_MAX_MS then
            finish(session, false, 'timeout', true)
        else
            local alive, why = games[session.game].check(session)

            if not alive then
                finish(session, false, why, true)
            end

        end

    end

end

---@param source integer
---@param gameName string
---@param params table
---@return boolean ok
---@return string? reason
local function start(source, gameName, params)
    local game = games[gameName]
    if not game then return false, 'bad_game' end
    if type(params) ~= 'table' then return false, 'bad_request' end
    if bySource[source] then return false, 'busy' end
    if not GetPlayerName(source) then return false, 'no_player' end

    local ready, reason, state = game.prepare(source, params)
    if not ready then return false, reason end

    if bySource[source] then return false, 'busy' end

    nextId += 1

    local now = GetGameTimer()

    ---@type HandsonSession
    local session = {
        id = nextId,
        source = source,
        game = gameName,
        params = params,
        state = state --[[@as table]],
        steps = game.steps(params),
        index = 1,
        strikes = 0,
        startedAt = now,
        stepAt = now,
        lastCall = 0,
        promise = promise.new(),
    }

    session.spec = game.spec(params, session.state)
    bySource[source] = session

    if not watchdog then
        watchdog = SetInterval(patrol, WATCHDOG_MS)
    end

    game.begin(session)

    TriggerClientEvent('bl_handson:client:start', source, session.id, gameName, params, session.spec)

    local result = Citizen.Await(session.promise)

    return result.ok, result.reason
end

exports('start', start)

require 'server.flow'(start)

---@param source integer
---@return boolean
exports('isBusy', function(source)
    return bySource[source] ~= nil
end)

lib.callback.register('bl_handson:server:step', function(source, id, name, data)
    local session = bySource[source]

    if not session or session.id ~= id then
        return { ok = false, failed = true, reason = 'no_session' }
    end

    if type(name) ~= 'string' then return { ok = false, reason = 'bad_request' } end

    local now = GetGameTimer()

    if now - session.lastCall < STEP_COOLDOWN_MS then return { ok = false, reason = 'too_fast' } end

    session.lastCall = now

    local step = session.steps[session.index]

    if not step or step.name ~= name then return { ok = false, reason = 'out_of_order' } end

    if now - session.stepAt < step.minMs then return strike(session, 'rushed') end

    local game = games[session.game]
    local alive, why = game.check(session)

    if not alive then
        finish(session, false, why)

        return { ok = false, failed = true, reason = why }
    end

    local valid, invalid = game.validate(session, step, data)

    if not valid then return strike(session, invalid or 'wrong') end

    session.index += 1
    session.stepAt = now

    if session.index > #session.steps then
        local paid, unpaid = game.complete(session)

        if not paid then
            finish(session, false, unpaid)

            return { ok = false, failed = true, reason = unpaid }
        end

        finish(session, true)

        return { ok = true, done = true }
    end

    return { ok = true }
end)

RegisterNetEvent('bl_handson:server:cancel', function(id)
    local src = source
    local session = bySource[src]

    if not session or session.id ~= id then return end

    finish(session, false, 'cancelled')
end)

AddEventHandler('playerDropped', function()
    local session = bySource[source]

    if session then
        finish(session, false, 'dropped')
    end

end)

---@param src any
local function logout(src)
    if not GetInvokingResource() or type(src) ~= 'number' then return end

    local session = bySource[src]

    if session then
        finish(session, false, 'logout', true)
    end

end

AddEventHandler('QBCore:Server:OnPlayerUnload', logout)
AddEventHandler('esx:playerLogout', logout)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end

    for _, session in pairs(bySource) do
        finish(session, false, 'stopped', true)
    end

end)
