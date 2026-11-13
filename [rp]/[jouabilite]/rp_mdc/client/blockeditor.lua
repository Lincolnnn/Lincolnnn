--[[
    MDC - ÉDITEUR DE BLOCS DU PLD (admins) : /blocs
    -----------------------------------------------
    Comme le réglage des lampes des armes : un panneau en haut à droite, la souris pour régler, puis on se déplace.
      - Type : POINT (une coordonnée + rayon) ou CARRÉ (centre + largeur, hauteur, rotation -> 4 coins) ;
      - le bloc en cours est dessiné EN JEU (cylindre jaune pour un point, contour et poteaux pour un carré) et SUR LA
        CARTE (rayon / zone jaunes) ; sa position suit le joueur (« Suivre ma position ») ou reste figée ;
      - « Ajouter » : le bloc rejoint la liste (dessinée en vert, en jeu et sur la carte) ; la liste donne les lignes
        prêtes à copier dans config/blocs.json (« blocks ») ;
      - « Se déplacer » : rend la souris (le panneau reste) ; /blocs à nouveau : reprendre la souris.
    Permission vérifiée par le serveur (Config.BlockEditorAce, rp.admin par défaut). Boucle de dessin seulement
    pendant que l'éditeur est ouvert.
]]

local editor = nil -- { focus, type, name, radius, width, height, rotation, follow, center, list, blips }

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function playerPos()
    local c = GetEntityCoords(PlayerPedId())
    return vector3(c.x, c.y, c.z)
end

--- 4 coins d'un carré (centre, largeur sur X, hauteur sur Y, rotation en degrés), dans l'ordre du tour
local function squareCorners(c, w, h, rot)
    local r = math.rad(rot or 0.0)
    local cs, sn = math.cos(r), math.sin(r)
    local out = {}
    for _, p in ipairs({ { -w / 2, -h / 2 }, { w / 2, -h / 2 }, { w / 2, h / 2 }, { -w / 2, h / 2 } }) do
        out[#out + 1] = vector3(c.x + p[1] * cs - p[2] * sn, c.y + p[1] * sn + p[2] * cs, c.z)
    end
    return out
end

local function currentBlock()
    local c = editor.center
    local b = { name = editor.name ~= '' and editor.name or 'A RENOMMER', type = editor.type }
    if editor.type == 'point' then
        b.coords = { round2(c.x), round2(c.y) }
        b.radius = math.floor(editor.radius + 0.5)
    else
        b.corners = {}
        for _, p in ipairs(squareCorners(c, editor.width, editor.height, editor.rotation)) do
            b.corners[#b.corners + 1] = { round2(p.x), round2(p.y) }
        end
        b.size = { editor.width, editor.height, editor.rotation } -- (affichage)
        b.center = c
    end
    if b.type == 'point' then b.center = c end
    return b
end

--- Ligne JSON prête à copier (format de config/blocs.json)
local function blockLine(b)
    if b.type == 'point' then
        return ('{ "name": "%s", "type": "point", "coords": [%.2f, %.2f], "radius": %d }'):format(b.name, b.coords[1], b.coords[2], b.radius)
    end
    local parts = {}
    for _, p in ipairs(b.corners) do parts[#parts + 1] = ('[%.2f, %.2f]'):format(p[1], p[2]) end
    return ('{ "name": "%s", "type": "square", "corners": [%s] }'):format(b.name, table.concat(parts, ', '))
end

-- ---- Carte : rayon / zone (jaune : en cours ; vert : ajoutés) ----
local function removeBlip(b) if b and DoesBlipExist(b) then RemoveBlip(b) end end

local function makeBlip(b, color, alpha)
    local c = b.center
    local blip
    if b.type == 'point' then
        blip = AddBlipForRadius(c.x, c.y, c.z, b.radius + 0.0)
    else
        blip = AddBlipForArea(c.x, c.y, c.z, b.size[1] + 0.0, b.size[2] + 0.0)
        SetBlipRotation(blip, math.floor(b.size[3]))
    end
    SetBlipColour(blip, color)
    SetBlipAlpha(blip, alpha)
    return blip
end

local function refreshCurrentBlip()
    removeBlip(editor.blip)
    editor.blip = makeBlip(currentBlock(), 5, 110) -- jaune
end

local function sendState()
    local lines = {}
    for i, b in ipairs(editor.list) do lines[i] = { name = b.name, type = b.type, line = blockLine(b) } end
    local c = editor.center
    SendNUIMessage({ action = 'blockEditor', data = {
        open = true, focus = editor.focus, type = editor.type, name = editor.name, radius = editor.radius,
        width = editor.width, height = editor.height, rotation = editor.rotation, follow = editor.follow,
        x = round2(c.x), y = round2(c.y), list = lines, preview = blockLine(currentBlock()),
    } })
end

local function setFocus(on)
    editor.focus = on
    SetNuiFocus(on, on)
    sendState()
end

-- ---- Dessin en jeu ----
local function drawBlock(b, r, g, bl)
    local c = b.center
    local _, ground = GetGroundZFor_3dCoord(c.x, c.y, c.z + 50.0, false)
    local z = (ground and ground ~= 0.0) and ground or c.z - 1.0
    if b.type == 'point' then
        DrawMarker(1, c.x, c.y, z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, b.radius * 2.0, b.radius * 2.0, 6.0, r, g, bl, 70,
            false, false, 2, false, nil, nil, false)
        DrawMarker(28, c.x, c.y, z + 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.6, 0.6, r, g, bl, 220, false, false, 2, false, nil, nil, false)
    else
        local corners = squareCorners(c, b.size[1], b.size[2], b.size[3])
        for i, p in ipairs(corners) do
            local q = corners[i % 4 + 1]
            for _, h in ipairs({ 0.3, 2.0, 4.0 }) do DrawLine(p.x, p.y, z + h, q.x, q.y, z + h, r, g, bl, 255) end
            DrawMarker(1, p.x, p.y, z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.2, 1.2, 8.0, r, g, bl, 160, false, false, 2, false, nil, nil, false)
        end
    end
end

local function drawLoop()
    CreateThread(function()
        local lastCenter, lastBlip = nil, 0
        while editor do
            if editor.follow then editor.center = playerPos() end
            -- carte : le rayon / la zone suit la position (au plus toutes les 500 ms)
            if editor.follow and GetGameTimer() - lastBlip > 500 and (not lastCenter or #(editor.center - lastCenter) > 1.0) then
                lastBlip, lastCenter = GetGameTimer(), editor.center
                refreshCurrentBlip()
                if editor.focus then sendState() end
            end
            drawBlock(currentBlock(), 255, 200, 0)
            for _, b in ipairs(editor.list) do drawBlock(b, 60, 220, 90) end
            Wait(0)
        end
    end)
end

local function closeEditor()
    if not editor then return end
    removeBlip(editor.blip)
    for _, b in ipairs(editor.list) do removeBlip(b.blip) end
    editor = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'blockEditor', data = { open = false } })
end

--- Message au joueur : chat écrit (privé) s'il est démarré, sinon notification du jeu ; toujours en console F8
local function tell(text)
    print(('[MDC] %s'):format(text))
    local chat = GlobalState.rpChatResource or 'rp_chat'
    if GetResourceState(chat) == 'started' and pcall(function() exports[chat]:addPrivate({ title = 'Blocs', text = text }) end) then return end
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

RegisterNetEvent('mdc:client:blockEditor', function(ok, message)
    if not ok then return tell(message or 'Éditeur de blocs : réservé aux admins.') end
    if editor then return setFocus(true) end
    editor = { focus = true, type = 'point', name = '', radius = 75.0, width = 200.0, height = 150.0, rotation = 0.0,
        follow = true, center = playerPos(), list = {} }
    refreshCurrentBlip()
    SetNuiFocus(true, true)
    sendState()
    drawLoop()
    tell('Éditeur de blocs ouvert : « Se déplacer » rend la souris, /blocs la reprend.')
end)

RegisterCommand('blocs', function()
    if editor and not editor.focus then return setFocus(true) end -- reprendre la souris
    TriggerServerEvent('mdc:server:blockEditor')
end, false)

RegisterNUICallback('blockSet', function(d, cb)
    cb({ ok = true })
    if not editor or type(d) ~= 'table' then return end
    if d.type == 'point' or d.type == 'square' then editor.type = d.type end
    editor.name = tostring(d.name or editor.name):gsub('["\\]', ''):sub(1, 30)
    local function num(v, lo, hi, def) v = tonumber(v) return v and math.max(lo, math.min(hi, v)) or def end
    editor.radius = num(d.radius, 5, 2000, editor.radius)
    editor.width = num(d.width, 5, 5000, editor.width)
    editor.height = num(d.height, 5, 5000, editor.height)
    editor.rotation = num(d.rotation, 0, 359, editor.rotation)
    if d.follow ~= nil then editor.follow = d.follow == true end
    refreshCurrentBlip()
    sendState()
end)

RegisterNUICallback('blockHere', function(_, cb)
    cb({ ok = true })
    if not editor then return end
    editor.center, editor.follow = playerPos(), false
    refreshCurrentBlip()
    sendState()
end)

RegisterNUICallback('blockAdd', function(_, cb)
    cb({ ok = true })
    if not editor then return end
    local b = currentBlock()
    b.blip = makeBlip(b, 2, 90) -- vert
    editor.list[#editor.list + 1] = b
    editor.name = ''
    sendState()
end)

RegisterNUICallback('blockRemove', function(d, cb)
    cb({ ok = true })
    local i = editor and tonumber(type(d) == 'table' and d.index)
    if i and editor.list[i] then
        removeBlip(editor.list[i].blip)
        table.remove(editor.list, i)
        sendState()
    end
end)

RegisterNUICallback('blockMove', function(_, cb)
    cb({ ok = true })
    if editor then setFocus(false) end
end)

RegisterNUICallback('blockClose', function(_, cb)
    cb({ ok = true })
    closeEditor()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then closeEditor() end
end)

MDCBlockEditor = { corners = squareCorners, line = blockLine, state = function() return editor end } -- (tests)
