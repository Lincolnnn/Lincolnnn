--[[
    RP NPC Control - serveur
    ------------------------
    - Filtre définitif : toute entité que le JEU tente de créer (population "ambiante" : trafic, garés, piétons,
      scénarios, renforts) avec un modèle de PNJ ou de véhicule d'urgence est refusée avant même d'exister, pour
      tous les joueurs. Les entités créées par un joueur ou un script (population "mission") passent toujours.
    - Densités (config.lua : Density) publiées pour tous les clients (GlobalState.npcDensity), modifiables sans
      redémarrage avec la commande npcdensity (console ou permission ACE "command.npcdensity").
    Aucune boucle.
]]

local Config = NPCConfig
local AMBIENT = { [1] = true, [2] = true, [3] = true, [4] = true, [5] = true } -- population créée par le jeu

local blocked = {}
for _, name in ipairs(Config.EmergencyPeds or {}) do blocked[GetHashKey(name)] = true end
for _, name in ipairs(Config.EmergencyVehicles or {}) do blocked[GetHashKey(name)] = true end

if Config.DisableEmergencyServices then
    AddEventHandler('entityCreating', function(entity)
        if blocked[GetEntityModel(entity)] and AMBIENT[GetEntityPopulationType(entity)] then
            CancelEvent() -- jamais créé : ni au commissariat, ni à la caserne, ni à l'hôpital, ni dans le trafic
        end
    end)
end

-- =========================================================================
-- DENSITÉS (0.0 à 3.0 ; 1.0 = jeu de base)
-- =========================================================================
local function clamp(value)
    value = tonumber(value)
    if not value or value ~= value then return nil end
    return math.max(0.0, math.min(3.0, value))
end

local base = Config.Density or {}
local density = { Traffic = clamp(base.Traffic) or 1.0, Parked = clamp(base.Parked) or clamp(base.Traffic) or 1.0, Peds = clamp(base.Peds) or 1.0 }
GlobalState.npcDensity = density

local KEYS = { traffic = 'Traffic', parked = 'Parked', peds = 'Peds' }

local function reply(src, text)
    if src == 0 then return print(('[rp_NPCcontrol] %s'):format(text)) end
    TriggerClientEvent('chat:addMessage', src, { args = { 'PNJ', text }, color = { 140, 200, 255 } })
end

-- npcdensity traffic|parked|peds|all <0.0 - 3.0> : essai sans redémarrer (la valeur de config.lua revient au redémarrage)
RegisterCommand(Config.DensityCommand or 'npcdensity', function(src, args)
    local what, value = (args[1] or ''):lower(), clamp(args[2])
    if not value or (what ~= 'all' and not KEYS[what]) then
        local d = GlobalState.npcDensity or density
        return reply(src, ('Utilisation : npcdensity traffic|parked|peds|all 0.0-3.0 (actuel : trafic %.2f, garés %.2f, piétons %.2f)')
            :format(d.Traffic, d.Parked, d.Peds))
    end
    local d = GlobalState.npcDensity or density
    local new = { Traffic = d.Traffic, Parked = d.Parked, Peds = d.Peds }
    if what == 'all' then
        new.Traffic, new.Parked, new.Peds = value, value, value
    else
        new[KEYS[what]] = value
    end
    GlobalState.npcDensity = new
    reply(src, ('Densité : trafic %.2f, garés %.2f, piétons %.2f'):format(new.Traffic, new.Parked, new.Peds))
end, true)

print(('^5[rp_NPCcontrol]^0 services d\'urgence du jeu : %s ; densité : trafic %.2f, garés %.2f, piétons %.2f')
    :format(Config.DisableEmergencyServices and 'supprimés' or 'actifs', density.Traffic, density.Parked, density.Peds))
