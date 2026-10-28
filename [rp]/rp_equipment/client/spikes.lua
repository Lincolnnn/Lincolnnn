--[[
    RP Equipment - herse de riven_spikes (script payant de Riven Systems, s'il est installé)
    ----------------------------------------------------------------------------------------
    - Prendre / ranger la herse : UNIQUEMENT dans le menu Équipement ouvert au coffre (ligne « Herse »). Le menu se
      ferme et l'action de Riven elle-même est lancée (son animation, son stock par véhicule, ses messages), par le pont
      ox_target (export runOption) ; ces deux actions ne sont plus proposées par l'œil (ox_target/config.lua :
      HiddenPrefixes).
    - Herse en main : la touche « ranger » de Riven (X) ne la fait plus disparaître : elle revient aussitôt dans les
      mains (« posez-la au sol ou rangez-la dans le coffre »). Le code de Riven n'est pas modifié : ce script remarque
      seulement que la herse a quitté les mains alors que Riven est revenu au repos (ni lancée, ni posée, ni rangée au
      coffre) et la redonne (export equip de Riven). Mort, à bord d'un véhicule, à terre ou menotté : Riven la range
      lui-même, elle n'est pas redonnée.
    Performance : aucune boucle (un changement d'état seulement quand la herse entre ou sort des mains).
]]

local C = (Config.Stock or {}).Spikes or {}
local RES = C.Resource or 'riven_spikes'
local TYPE = C.Type or 'spikestrip'

RPSpikes = {}

local function started() return C.Enabled ~= false and GetResourceState(RES) == 'started' end

--- Ligne « Herse » du menu : Riven présent, menu ouvert au coffre
function RPSpikes.available(open)
    return open ~= nil and open.where == 'trunk' and started() and GetResourceState('ox_target') == 'started'
end

--- Une herse en main (état de Riven)
function RPSpikes.held() return LocalPlayer.state.rivenSpikeHand ~= nil end

local REASONS = {
    unavailable = 'Impossible ici : véhicule de police, à pied, mains libres (ou une herse en main pour la ranger).',
    missing = 'Herse indisponible (riven_spikes ou le pont ox_target n\'est pas démarré).',
}

--- 'take' : prendre la herse du coffre ; 'store' : ranger celle qu'on a en main
function RPSpikes.run(mode, vehicle)
    if not started() then return EquipNotify(REASONS.missing) end
    local name = mode == 'store' and 'riven_spikes_trunk_stow' or ('riven_spikes_trunk_' .. TYPE)
    local ok, ran, why = pcall(function() return exports.ox_target:runOption(name, vehicle) end)
    if not ok or not ran then EquipNotify(REASONS[why] or REASONS.missing) end
end

-- =========================================================================
-- TOUCHE « RANGER » DE RIVEN (X) : la herse en main ne disparaît plus
-- =========================================================================
local function riven(name, ...)
    local args = { ... }
    local ok, result = pcall(function() return exports[RES][name](exports[RES], table.unpack(args)) end)
    return ok and result or nil
end

--- Riven range la herse lui-même dans ces cas (sécurité) : on ne la redonne pas
local function forcedAway()
    local ped = PlayerPedId()
    return IsEntityDead(ped) or IsPedInAnyVehicle(ped, true) or IsPedSwimming(ped) or IsPedRagdoll(ped) or IsPedCuffed(ped)
end
RPSpikes.forcedAway = forcedAway -- pour les tests

local inHand = LocalPlayer.state.rivenSpikeHand
AddStateBagChangeHandler('rivenSpikeHand', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    local before = inHand
    inHand = value
    if value ~= nil or before == nil or not started() then return end
    -- Appelé avant que Riven ne se mette à jour : « idle » ici = rangée par sa touche (lancer, poser ou ranger au
    -- coffre le font passer par un autre état avant)
    if riven('getMode') ~= 'idle' or forcedAway() then return end
    local kind = before
    SetTimeout(300, function()
        if LocalPlayer.state.rivenSpikeHand ~= nil or forcedAway() then return end
        riven('equip', kind)
        EquipNotify('La herse ne se range pas dans la poche : posez-la au sol ou rangez-la dans le coffre (menu Équipement).')
    end)
end)
