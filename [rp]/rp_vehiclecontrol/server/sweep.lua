--[[
    Vehicle Control - nettoyage des débris d'accident à l'œil (serveur)
    -------------------------------------------------------------------
    Un joueur qui balaie rejoint la zone en cours la plus proche (à moins de DebrisCleanup.JoinDistance m), sinon en
    ouvre une autour de lui (position lue par le serveur). La zone avance selon le nombre de joueurs qui la balaient
    (Seconds : 1, 2, 3 et plus) ; finie, elle est envoyée à TOUS les joueurs (débris retirés chez chacun) et gardée
    RememberSeconds s pour ceux qui arrivent ensuite. Aucune notification générale.
    Performance : une boucle de 250 ms seulement pendant un nettoyage.
]]

local C = VCConfig.DebrisCleanup or {}
if C.Enabled == false then return end

local RADIUS = C.Radius or 6.0
local jobs = {}       -- { id, x, y, z, progress, cleaners = { [src] = true } }
local jobOf = {}      -- [src] = job
local cleaned = {}    -- { x, y, z, r, at = os.time() }
local lastStart = {}
local seq = 0
local running = false

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if c.x == 0.0 and c.y == 0.0 then return nil end
    return c
end

local function count(job)
    local n = 0
    for _ in pairs(job.cleaners) do n = n + 1 end
    return n
end

--- Durée d'une zone (s) selon le nombre de joueurs qui la balaient
local function secondsFor(n)
    local list = C.Seconds or { 10, 6, 4 }
    return tonumber(list[math.min(n, #list)]) or 10
end

local function leave(src)
    local job = jobOf[src]
    jobOf[src] = nil
    if job then job.cleaners[src] = nil end
end

local function prune()
    local keep = C.RememberSeconds or 900
    local now = os.time()
    for i = #cleaned, 1, -1 do
        if now - cleaned[i].at > keep then table.remove(cleaned, i) end
    end
    while #cleaned > 200 do table.remove(cleaned, 1) end
end

local function finish(job)
    for i, j in ipairs(jobs) do if j == job then table.remove(jobs, i) break end end
    for src in pairs(job.cleaners) do
        jobOf[src] = nil
        TriggerClientEvent('rp_vehiclecontrol:sweepDone', src)
    end
    prune()
    local zone = { x = job.x, y = job.y, z = job.z, r = RADIUS, at = os.time() }
    cleaned[#cleaned + 1] = zone
    TriggerClientEvent('rp_vehiclecontrol:debrisCleaned', -1, { { x = zone.x, y = zone.y, z = zone.z, r = zone.r } })
end

local TICK = 250

local function run()
    if running then return end
    running = true
    CreateThread(function()
        while #jobs > 0 do
            Wait(TICK)
            for i = #jobs, 1, -1 do
                local job = jobs[i]
                -- un joueur parti trop loin (ou déconnecté) ne compte plus
                for src in pairs(job.cleaners) do
                    local c = pedCoords(src)
                    if not c or #(c - vector3(job.x, job.y, job.z)) > RADIUS + (C.Leave or 2.5) + 2.0 then
                        leave(src)
                        TriggerClientEvent('rp_vehiclecontrol:sweepRefused', src, 'Nettoyage interrompu : trop loin de la zone.')
                    end
                end
                local n = count(job)
                if n == 0 then
                    table.remove(jobs, i)
                else
                    job.progress = job.progress + (TICK / 1000.0) / secondsFor(n)
                    if job.progress >= 1.0 then
                        finish(job)
                    else
                        for src in pairs(job.cleaners) do
                            TriggerClientEvent('rp_vehiclecontrol:sweepProgress', src, job.progress, n)
                        end
                    end
                end
            end
        end
        running = false
    end)
end

RegisterNetEvent('rp_vehiclecontrol:sweepStart', function()
    local src = source
    local now = GetGameTimer()
    if lastStart[src] and now - lastStart[src] < 1000 then return end
    lastStart[src] = now
    local c = pedCoords(src)
    if not c then return end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return end
    leave(src)
    -- zone en cours la plus proche : on l'aide ; sinon une nouvelle autour du joueur
    local best, bestD
    for _, job in ipairs(jobs) do
        local d = #(c - vector3(job.x, job.y, job.z))
        if d <= (C.JoinDistance or 6.0) and (not bestD or d < bestD) then best, bestD = job, d end
    end
    if not best then
        seq = seq + 1
        best = { id = seq, x = c.x, y = c.y, z = c.z, progress = 0.0, cleaners = {} }
        jobs[#jobs + 1] = best
    end
    best.cleaners[src] = true
    jobOf[src] = best
    run()
end)

RegisterNetEvent('rp_vehiclecontrol:sweepStop', function() leave(source) end)

-- Joueur qui arrive : zones nettoyées récemment (avec leur âge, en ms)
RegisterNetEvent('rp_vehiclecontrol:debrisZones', function()
    local src = source
    prune()
    if #cleaned == 0 then return end
    local now, list = os.time(), {}
    for _, z in ipairs(cleaned) do list[#list + 1] = { x = z.x, y = z.y, z = z.z, r = z.r, age = (now - z.at) * 1000 } end
    TriggerClientEvent('rp_vehiclecontrol:debrisCleaned', src, list)
end)

AddEventHandler('playerDropped', function()
    leave(source)
    lastStart[source] = nil
end)

VCSweep = { jobs = jobs, cleaned = cleaned, secondsFor = secondsFor } -- pour les tests
