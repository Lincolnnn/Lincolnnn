--[[
    RP STAGES - serveur
    -------------------
    Reçoit l'état choisi par le CONDUCTEUR d'un véhicule configuré, le vérifie (bon conducteur, bon modèle, état cohérent
    avec la configuration : sirène seulement au stage 3, stages secondaires superposés ou non…) puis le partage à tous
    les joueurs par le state bag « rpStages » du véhicule. Aucune boucle.
]]

local C = RPStagesConfig
local Logic = RPStagesLogic
local DATA = Logic.load(C)
local last = {} -- [joueur] = GetGameTimer() du dernier envoi

for _, w in ipairs(DATA.warnings) do print(('^3[rp_stages]^0 config.lua : %s'):format(w)) end
do
    local n = 0
    for _ in pairs(DATA.byHash) do n = n + 1 end
    print(('^5[rp_stages]^0 %d véhicule(s) configuré(s).'):format(n))
end

RegisterNetEvent('rp_stages:set', function(netId, data)
    local src = source
    local now = GetGameTimer()
    if last[src] and now - last[src] < 80 then return end -- 12 changements / s au plus
    last[src] = now
    if C.Ace and not IsPlayerAceAllowed(src, C.Ace) then return end
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    if GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src) then return end -- conducteur seulement
    local cfg = DATA.byHash[Logic.unsigned(GetEntityModel(veh))]
    if not cfg then return end
    local st = Logic.sanitize(cfg, data)
    local old = Entity(veh).state.rpStages
    st.v = math.max(math.tointeger(tonumber(type(data) == 'table' and data.v) or 0) or 0, ((type(old) == 'table' and old.v) or 0) + 1)
    Entity(veh).state:set('rpStages', st, true)
end)

AddEventHandler('playerDropped', function() last[source] = nil end)

RPStagesServer = { data = DATA } -- (tests)
