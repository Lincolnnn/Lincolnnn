--[[
    RP RoleplayZone - client : JOUEUR BLESSÉ -> scène automatique « traces de sang » (Config.Auto.Injury)
    -------------------------------------------------------------------------------------------------------
    À chaque dégât reçu (événement du jeu, aucune boucle) : à pied, au moins MinDamage points de vie perdus depuis le
    dernier dégât compté (ou à terre / mort) -> position au sol envoyée au serveur, qui crée la scène (vérifie la
    position et la fréquence). Les accidents de la route ont leur propre scène (rp_vehiclecontrol) : rien en véhicule.
]]

local A = (SceneConfig.Auto or {})
local I = A.Injury or {}
if A.Enabled == false or I.Enabled == false then return end

local lastHealth = nil
local lastSent = 0
local checking = false

--- Point au sol sous le joueur
local function groundUnder(ped)
    local c = GetEntityCoords(ped)
    local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 0.5, false)
    if not found or z < c.z - 3.0 then z = c.z - 0.95 end
    return { x = c.x, y = c.y, z = z }
end

local function check()
    local ped = PlayerPedId()
    local health = GetEntityHealth(ped)
    local before = lastHealth or GetEntityMaxHealth(ped)
    lastHealth = health
    if IsPedInAnyVehicle(ped, true) then return end
    local down = IsEntityDead(ped) or IsPedFatallyInjured(ped)
    if before - health < (I.MinDamage or 20) and not down then return end
    local now = GetGameTimer()
    if now - lastSent < math.max(10, tonumber(I.Cooldown) or 60) * 1000 then return end
    lastSent = now
    TriggerServerEvent('rp_scene:auto:injured', groundUnder(ped))
end

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' or type(args) ~= 'table' or args[1] ~= PlayerPedId() then return end
    if checking then return end
    checking = true
    CreateThread(function()
        Wait(0) -- points de vie à jour après le dégât
        checking = false
        check()
    end)
end)

-- Soigné / réapparu : on repart de sa vie actuelle (un soin ne compte pas comme une blessure)
AddEventHandler('playerSpawned', function() lastHealth = nil end)
RZ.injuryCheck = check -- pour les tests
