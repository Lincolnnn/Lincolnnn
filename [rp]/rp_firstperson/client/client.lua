--[[
    RP First Person - client
    ------------------------
    Tant que le joueur est à la 1re personne (à pied ; config : aussi à la 3e personne / en véhicule), à chaque image :
      - reset flag 200 (PRF_DisableActionMode) : le jeu ne passe pas en mode action (posture de combat courbée,
        démarche tactique), quelle que soit la raison (arme à feu, mains nues, arme blanche, objet, tir, bagarre…) ;
      - s'il y est déjà : SetPedUsingActionMode(false) le fait sortir tout de suite.
    Le personnage est animé par ce client puis synchronisé chez les autres : la posture normale se voit aussi depuis
    les joueurs autour (aucun serveur ne peut changer l'animation d'un autre joueur).
    Performance : hors 1re personne, une vérification toutes les CheckMs ms (0.00 ms) ; à la 1re personne, deux natives
    par image.
    Exports : isActive() (correction en cours sur cette image), setEnabled(bool), fixPosture(ped).
]]

local C = FirstPersonConfig or {}
local enabled = C.Enabled ~= false
local active = false

local FIRST_PERSON = 4 -- GetFollowPedCamViewMode : vue 1re personne

--- Retire le mode action (posture de combat) pour cette image
local function fixPosture(ped)
    SetPedResetFlag(ped, 200, true) -- PRF_DisableActionMode
    if IsPedUsingActionMode(ped) then SetPedUsingActionMode(ped, false, -1, 'DEFAULT_ACTION') end
end

--- La correction doit-elle s'appliquer maintenant ?
local function wanted(ped)
    if not enabled or IsEntityDead(ped) then return false end
    local inVehicle = IsPedInAnyVehicle(ped, false)
    if inVehicle and C.InVehicle ~= true then return false end
    if not inVehicle and C.OnFoot == false then return false end
    return C.ThirdPerson == true or GetFollowPedCamViewMode() == FIRST_PERSON
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        active = wanted(ped)
        if active then
            fixPosture(ped)
            Wait(0)
        else
            Wait(C.CheckMs or 250)
        end
    end
end)

if C.Command and C.Command ~= '' then
    RegisterCommand(C.Command, function()
        enabled = not enabled
        TriggerEvent('chat:addMessage', { args = { '1re personne', enabled
            and 'Posture normale à la 1re personne : activée.'
            or 'Posture normale à la 1re personne : coupée (posture du jeu).' } })
    end, false)
end

exports('isActive', function() return active end)
exports('setEnabled', function(value) enabled = value ~= false end)
exports('fixPosture', function(ped) fixPosture(ped or PlayerPedId()) end)

RPFirstPerson = { fixPosture = fixPosture, wanted = wanted } -- pour les tests
