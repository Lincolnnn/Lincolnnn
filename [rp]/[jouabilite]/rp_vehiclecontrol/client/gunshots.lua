--[[
    Vehicle Control - tirs sur un véhicule (client)
    -----------------------------------------------
    Un tir BIEN PLACÉ abîme vraiment le véhicule :
      - dans le MOTEUR (près de l'os "engine" du véhicule ; sans cet os : le tiers avant du véhicule, capot) :
        santé du moteur - dégâts de l'arme x EngineFactor (pistolet ~55, fusil ~70, sniper ~220 par balle) : le
        moteur passe par les paliers habituels (abîmé, très abîmé : cale et fume, détruit) ;
      - dans le RÉSERVOIR (os "petroltank…") : réservoir percé, l'essence fuit (fuel.lua).
    Les pneus, vitres et la carrosserie restent gérés par le jeu.
    C'est le TIREUR qui sait où sa balle a touché (point d'impact) : il l'envoie au serveur, qui le transmet au joueur
    qui contrôle le véhicule (seul lui peut changer sa santé). Aucune boucle : événement de dégâts du jeu.
]]

local Config = VCConfig.Gunshots or {}
local BULLET = 3 -- type de dégâts « balle » (GetWeaponDamageType)
local lastImpact = nil

--- Os d'un véhicule le plus proche du point d'impact parmi `names` : distance, nil si aucun
local function boneDistance(vehicle, names, impact)
    local best
    for _, name in ipairs(names or {}) do
        local index = GetEntityBoneIndexByName(vehicle, name)
        if index and index ~= -1 then
            local d = #(GetWorldPositionOfEntityBone(vehicle, index) - impact)
            if not best or d < best then best = d end
        end
    end
    return best
end

--- Partie touchée : 'engine', 'tank' ou nil
local function partHit(vehicle, impact)
    local engine = boneDistance(vehicle, Config.EngineBones or { 'engine' }, impact)
    if engine then
        if engine <= (Config.EngineRadius or 0.85) then return 'engine' end
    else
        -- pas d'os "engine" : le tiers avant du véhicule (capot), au-dessus des roues
        local min, max = GetModelDimensions(GetEntityModel(vehicle))
        local o = GetOffsetFromEntityGivenWorldCoords(vehicle, impact.x, impact.y, impact.z)
        local length = max.y - min.y
        if o.y >= max.y - length * (Config.FrontFallback or 0.33) and o.z >= min.z + 0.25 then return 'engine' end
    end
    local tank = boneDistance(vehicle, Config.TankBones or { 'petroltank', 'petroltank_l', 'petroltank_r' }, impact)
    if tank and tank <= (Config.TankRadius or 0.6) then return 'tank' end
    return nil
end

AddEventHandler('gameEventTriggered', function(name, args)
    if Config.Enabled == false or name ~= 'CEventNetworkEntityDamage' then return end
    local victim, attacker = args[1], args[2]
    local ped = PlayerPedId()
    if attacker ~= ped or not victim or victim == 0 or not DoesEntityExist(victim) or GetEntityType(victim) ~= 2 then return end
    local weapon = GetSelectedPedWeapon(ped)
    if GetWeaponDamageType(weapon) ~= BULLET then return end
    local ok, impact = GetPedLastWeaponImpactCoord(ped)
    if not ok or not impact then return end
    if lastImpact and #(lastImpact - impact) < 0.01 then return end -- même balle (événement en double)
    lastImpact = impact
    local part = partHit(victim, impact)
    if not part or not NetworkGetEntityIsNetworked(victim) then return end
    local damage = GetWeaponDamage(weapon, 0)
    if not damage or damage <= 0 then damage = Config.DefaultWeaponDamage or 30.0 end
    local amount = damage * (part == 'engine' and (Config.EngineFactor or 2.2) or (Config.TankFactor or 3.0))
    TriggerServerEvent('rp_vehiclecontrol:bulletHit', VehToNet(victim), part, amount)
end)

-- Le serveur transmet la balle au joueur qui contrôle le véhicule : c'est lui qui applique les dégâts
RegisterNetEvent('rp_vehiclecontrol:bulletHit', function(netId, part, amount)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local vehicle = NetToVeh(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) or not NetworkHasControlOfEntity(vehicle) then return end
    amount = tonumber(amount) or 0.0
    if part == 'engine' then
        VC.bulletEngine(vehicle, amount)
    elseif part == 'tank' then
        SetVehiclePetrolTankHealth(vehicle, math.max(GetVehiclePetrolTankHealth(vehicle) - amount, Config.TankFloor or 50.0))
    end
end)
