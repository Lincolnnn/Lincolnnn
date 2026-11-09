--[[
    RP Weapons Control - serveur : relaie les tirs aux SEULS joueurs proches du tireur (Sync.Range)
    Paquets vérifiés (nombre de tirs, type d'arme connu, direction du tir) et limités (Sync.MaxPerSecond par joueur).
    Aucune boucle.
]]

local W = WeaponsConfig
local S = W.Sync or {}
local window = {} -- [src] = { second, count }

local function allowed(src)
    local now = os.time()
    local w = window[src]
    if not w or w.second ~= now then w = { second = now, count = 0 } window[src] = w end
    w.count = w.count + 1
    return w.count <= (S.MaxPerSecond or 25)
end

RegisterNetEvent('rp_weaponscontrol:shots', function(data)
    local src = source
    if type(data) ~= 'table' or not allowed(src) then return end
    local count = math.floor(tonumber(data.count) or 0)
    if count < 1 or count > 30 or type(data.key) ~= 'string' or not (W.Profiles or {})[data.key] then return end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local origin = GetEntityCoords(ped)
    local range = S.Range or 120.0
    -- direction du tir (du canon vers le point visé) : 6 nombres, départ près du tireur, longueur raisonnable
    local aim = nil
    if type(data.aim) == 'table' and #data.aim == 6 then
        local a = {}
        for i = 1, 6 do a[i] = tonumber(data.aim[i]) end
        if a[6] then
            local dx, dy, dz = a[1] - origin.x, a[2] - origin.y, a[3] - origin.z
            local lx, ly, lz = a[4] - a[1], a[5] - a[2], a[6] - a[3]
            if dx * dx + dy * dy + dz * dz <= 100.0 and lx * lx + ly * ly + lz * lz <= 90000.0 then aim = a end
        end
    end
    for _, id in ipairs(GetPlayers()) do
        local target = tonumber(id)
        if target ~= src then
            local other = GetPlayerPed(target)
            if other and other ~= 0 and #(GetEntityCoords(other) - origin) <= range then
                TriggerClientEvent('rp_weaponscontrol:shots', target, src, count, data.key, data.suppressed == true, data.smoke == true, aim)
            end
        end
    end
end)

AddEventHandler('playerDropped', function() window[source] = nil end)

-- =========================================================================
-- EMPLACEMENT DE LA LAMPE PAR ARME (admins) : /editflashlight (Flashlight.EditCommand) ouvre le réglage chez l'admin
-- (permission ACE Flashlight.EditAce, ex. add_ace group.admin rp_weaponscontrol.admin allow) ; « Enregistrer pour
-- tous » : gardé ici (KVP rpFlashPos, même après un redémarrage) et publié pour tous (état global rpFlashPos =
-- { ["hachage"] = { x, y, z } }). Aucune boucle.
-- =========================================================================
local FL = W.Flashlight or {}
local EDIT_ACE = FL.EditAce or 'rp_weaponscontrol.admin'

local function canEdit(src)
    return src ~= 0 and (IsPlayerAceAllowed(src, EDIT_ACE) or IsPlayerAceAllowed(src, 'command'))
end

local positions = {}
do
    local raw = GetResourceKvpString('rpFlashPos')
    local ok, data = pcall(json.decode, raw or '{}')
    if ok and type(data) == 'table' then positions = data end
    GlobalState.rpFlashPos = positions
end

RegisterCommand(FL.EditCommand or 'editflashlight', function(src)
    if src == 0 then return print('[rp_weaponscontrol] /' .. (FL.EditCommand or 'editflashlight') .. ' : en jeu seulement, arme en main.') end
    if not canEdit(src) then
        return TriggerClientEvent('rp_weaponscontrol:notify', src, 'Réservé aux admins (permission ' .. EDIT_ACE .. ').')
    end
    TriggerClientEvent('rp_weaponscontrol:editFlash', src)
end, false)

RegisterNetEvent('rp_weaponscontrol:saveFlashPos', function(weapon, pos)
    local src = source
    if not canEdit(src) then return end
    local h = math.tointeger(tonumber(weapon))
    if not h or h < 0 or h > 0xFFFFFFFF then return end
    local key = tostring(h)
    if pos == false then
        positions[key] = nil
    else
        if type(pos) ~= 'table' then return end
        local p = {}
        for i = 1, 3 do
            local v = tonumber(pos[i])
            if not v or v ~= v then return end
            p[i] = math.floor(math.max(-0.8, math.min(0.8, v)) * 1000 + 0.5) / 1000
        end
        positions[key] = p
    end
    SetResourceKvp('rpFlashPos', json.encode(positions))
    GlobalState.rpFlashPos = positions
    TriggerClientEvent('rp_weaponscontrol:notify', src, pos == false and 'Emplacement de la lampe remis par défaut pour tous.'
        or ('Emplacement de la lampe enregistré pour tous (arme 0x%08X).'):format(h))
end)
