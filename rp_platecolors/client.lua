--[[
    RP PlateColors - Client
    -----------------------
    data/carcols.ymt (data_file CARCOLS_FILE) contient une copie des 6 plaques du jeu, avec une autre couleur de texte.
    Selon la manière dont le jeu traite ce fichier, deux cas :
      - les plaques sont AJOUTÉES à la liste du jeu (le nombre de types de plaques augmente) : on remplace sur les
        véhicules la plaque 0 à 5 par sa copie colorée (base + index), le joueur voit les nouvelles couleurs ;
      - le nombre ne change pas : le jeu n'a rien ajouté, le diagnostic l'indique dans la console F8
        (voir README, « méthode garantie »).
    Un véhicule n'est modifié que par son propriétaire réseau (synchronisé pour tous) : pas de conflit entre joueurs.

    Performance : un passage sur les véhicules toutes les secondes (Interval), deux natives par véhicule.
]]

local C = PlateColorsConfig
local base = nil          -- index de la 1re plaque colorée dans la liste du jeu (nil : plaques non ajoutées)
local total = 0           -- nombre de types de plaques connus du jeu

local function log(msg) print(('^3[rp_platecolors]^7 %s'):format(msg)) end

local function isVanillaCount(n)
    for _, v in ipairs(C.VanillaCounts) do
        if v == n then return true end
    end
    return false
end

--- Les plaques du fichier ont-elles été ajoutées à la suite de celles du jeu ?
local function detect()
    total = GetNumberOfVehicleNumberPlates()
    local start = total - C.CustomPlates
    base = (start > 0 and isVanillaCount(start)) and start or nil

    if base then
        log(('carcols.ymt chargé : plaques colorées %d à %d (%d types au total).'):format(base, total - 1, total))
    else
        log(('%d types de plaques : le jeu n\'a ajouté aucune plaque de carcols.ymt.'):format(total))
        log('Si les couleurs du texte n\'ont pas changé, utilisez la méthode garantie du README (update.rpf).')
    end
end

local function canEdit(veh)
    return not NetworkGetEntityIsNetworked(veh) or NetworkHasControlOfEntity(veh)
end

--- Plaque d'origine 0 à 5 -> copie colorée ; inverse avec back = true
local function remap(veh, back)
    local idx = GetVehicleNumberPlateTextIndex(veh)
    if back then
        if idx >= base and idx < base + C.CustomPlates then SetVehicleNumberPlateTextIndex(veh, idx - base) end
    elseif idx >= 0 and idx < C.CustomPlates then
        SetVehicleNumberPlateTextIndex(veh, base + idx)
    end
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    Wait(2000)
    detect()
    if not base or not C.AutoRemap then return end

    while true do
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            if canEdit(veh) then remap(veh, false) end
        end
        Wait(C.Interval)
    end
end)

-- À l'arrêt de la ressource, les copies disparaissent : on remet les plaques d'origine
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not base then return end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if canEdit(veh) then remap(veh, true) end
    end
end)

-- =========================================================================
-- COMMANDES DE TEST
-- =========================================================================
if C.InfoCommand then
    RegisterCommand(C.InfoCommand, function()
        detect()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh ~= 0 then
            log(('Véhicule actuel : plaque %d « %s ».'):format(GetVehicleNumberPlateTextIndex(veh), GetVehicleNumberPlateText(veh)))
        end
    end, false)
end

if C.TestCommand then
    RegisterCommand(C.TestCommand, function(_, args)
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        local idx = tonumber(args[1])
        if veh == 0 or not idx then return log(('Usage : /%s <index> dans un véhicule (0 à %d).'):format(C.TestCommand, total - 1)) end
        if idx < 0 or idx >= total then return log(('Index %d inconnu : 0 à %d.'):format(idx, total - 1)) end
        SetVehicleNumberPlateTextIndex(veh, math.floor(idx))
        log(('Plaque %d appliquée.'):format(idx))
    end, false)
end
