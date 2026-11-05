--[[
    RP Freecam - client
    -------------------
    /freecam : mode photo, petit menu au clavier (sans curseur : la souris reste à la caméra).
      - Caméra libre : ZQSD / WASD, souris, E monter, A / Q descendre, Maj rapide, Ctrl lent, molette : zoom ;
        jamais plus loin que MaxDistance du personnage ; le monde se charge autour de la caméra (focus) ;
        le personnage ne bouge pas pendant ce temps.
      - Masquer la minimap, le HUD du jeu, les interfaces des scripts (événement 'rp_freecam:hideUi'), son personnage.
      - Zoom (champ de vision), vitesse, inclinaison ; Réinitialiser.
    Espace (caméra libre) ou H : masquer / afficher le menu (photo) ; Retour arrière / Échap : quitter, tout est remis
    comme avant.
    Performance : rien tant que /freecam n'est pas ouvert ; ensuite une boucle à chaque image jusqu'à la sortie.
]]

local C = FreecamConfig or {}
local FOV = C.Fov or {}
local SPEEDS = C.Speeds or { { label = 'Normale', value = 6.0 } }

local session = false   -- mode photo ouvert (/freecam)
local menuShown = true  -- menu visible (H)
local cam = nil
local state = {
    freecam = false, hideRadar = true, hideHud = true, hideUi = true, hidePed = false,
    fov = FOV.Default or 50.0, speed = math.min(2, #SPEEDS), roll = 0.0,
}
local index = 1
local camPos, camRot = nil, nil
local uiHidden = false

-- =========================================================================
-- MENU
-- =========================================================================
local function onOff(v) return v and 'Oui' or 'Non' end

local ITEMS = {
    { id = 'freecam', label = 'Caméra libre', kind = 'check' },
    { id = 'hideRadar', label = 'Masquer la minimap', kind = 'check' },
    { id = 'hideHud', label = 'Masquer le HUD du jeu', kind = 'check' },
    { id = 'hideUi', label = 'Masquer les interfaces', kind = 'check' },
    { id = 'hidePed', label = 'Masquer mon personnage', kind = 'check' },
    { id = 'fov', label = 'Zoom', kind = 'list' },
    { id = 'speed', label = 'Vitesse', kind = 'list' },
    { id = 'roll', label = 'Inclinaison', kind = 'list' },
    { id = 'reset', label = 'Réinitialiser', kind = 'button' },
    { id = 'quit', label = 'Quitter', kind = 'button' },
}

local function valueOf(item)
    if item.kind == 'check' then return state[item.id] end
    if item.id == 'fov' then return ('%d°'):format(math.floor(state.fov + 0.5)) end
    if item.id == 'speed' then return (SPEEDS[state.speed] or SPEEDS[1]).label end
    if item.id == 'roll' then return ('%d°'):format(math.floor(state.roll + 0.5)) end
    return nil
end

local function sendMenu()
    local items = {}
    for i, item in ipairs(ITEMS) do
        local camOnly = (item.id == 'fov' or item.id == 'roll' or item.id == 'speed') and not state.freecam
        items[i] = { label = item.label, kind = item.kind, value = valueOf(item), disabled = camOnly or nil,
            desc = camOnly and 'Avec la caméra libre.' or nil }
    end
    SendNUIMessage({ action = 'menu', data = { open = session and menuShown, index = index, items = items,
        freecam = state.freecam } })
end

-- =========================================================================
-- CAMÉRA LIBRE
-- =========================================================================
local function camDirection(rot)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local c = math.abs(math.cos(rx))
    return vector3(-math.sin(rz) * c, math.cos(rz) * c, math.sin(rx))
end

local function startCam()
    if cam then return end
    camPos = GetFinalRenderedCamCoord()
    local r = GetFinalRenderedCamRot(2)
    camRot = vector3(r.x, 0.0, r.z)
    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
    SetCamRot(cam, camRot.x, state.roll, camRot.z, 2)
    SetCamFov(cam, state.fov)
    RenderScriptCams(true, true, 300, true, true)
end

local function stopCam()
    if not cam then return end
    RenderScriptCams(false, true, 300, true, true)
    DestroyCam(cam, false)
    cam = nil
    ClearFocus()
end

--- Déplacement et rotation de la caméra (une image)
local function updateCam(dt)
    local sens = (C.Sensitivity or 6.0) * (state.fov / 50.0) -- zoomé : la souris tourne moins vite
    local mx, my = GetDisabledControlNormal(0, 1), GetDisabledControlNormal(0, 2)
    local rx = math.max(-89.0, math.min(89.0, camRot.x - my * sens))
    local rz = (camRot.z - mx * sens) % 360.0
    camRot = vector3(rx, 0.0, rz)

    local speed = (SPEEDS[state.speed] or SPEEDS[1]).value
    if IsDisabledControlPressed(0, 21) then speed = speed * 3.0 end   -- Maj
    if IsDisabledControlPressed(0, 36) then speed = speed * 0.25 end  -- Ctrl
    local forward = camDirection(camRot)
    local right = vector3(math.cos(math.rad(rz)), math.sin(math.rad(rz)), 0.0)
    local move = vector3(0.0, 0.0, 0.0)
    if IsDisabledControlPressed(0, 32) then move = move + forward end -- avancer
    if IsDisabledControlPressed(0, 33) then move = move - forward end -- reculer
    if IsDisabledControlPressed(0, 34) then move = move - right end   -- gauche
    if IsDisabledControlPressed(0, 35) then move = move + right end   -- droite
    if IsDisabledControlPressed(0, 38) then move = move + vector3(0.0, 0.0, 1.0) end -- E : monter
    if IsDisabledControlPressed(0, 44) then move = move - vector3(0.0, 0.0, 1.0) end -- Q / A : descendre
    local pos = camPos + move * (speed * dt)

    -- jamais plus loin que MaxDistance du personnage
    local max = C.MaxDistance or 0
    if max > 0 then
        local origin = GetEntityCoords(PlayerPedId())
        local offset = pos - origin
        local d = #offset
        if d > max then pos = origin + offset * (max / d) end
    end
    camPos = pos

    -- molette : zoom
    local step = FOV.Step or 2.5
    if IsDisabledControlJustPressed(0, 241) or IsDisabledControlJustPressed(0, 15) then
        state.fov = math.max(FOV.Min or 5.0, state.fov - step); sendMenu()
    elseif IsDisabledControlJustPressed(0, 242) or IsDisabledControlJustPressed(0, 14) then
        state.fov = math.min(FOV.Max or 100.0, state.fov + step); sendMenu()
    end

    SetCamCoord(cam, camPos.x, camPos.y, camPos.z)
    SetCamRot(cam, camRot.x, state.roll, camRot.z, 2)
    SetCamFov(cam, state.fov)
    SetFocusPosAndVel(camPos.x, camPos.y, camPos.z, 0.0, 0.0, 0.0) -- le monde se charge autour de la caméra
end

-- =========================================================================
-- MASQUAGES
-- =========================================================================
local function setUiHidden(hidden)
    if hidden == uiHidden then return end
    uiHidden = hidden
    TriggerEvent(C.HideUiEvent or 'rp_freecam:hideUi', hidden)
end

local function applyHides()
    if state.hideRadar then DisplayRadar(false) end
    if state.hideHud then
        for _, component in ipairs(C.HideHudComponents or {}) do HideHudComponentThisFrame(component) end
        HideHelpTextThisFrame()
    end
    if state.hidePed then SetEntityLocallyInvisible(PlayerPedId()) end
    setUiHidden(state.hideUi)
end

local function restore()
    stopCam()
    DisplayRadar(true)
    setUiHidden(false)
end

-- =========================================================================
-- ACTIONS DU MENU
-- =========================================================================
local function change(item, dir)
    if item.kind == 'check' and dir == 0 then
        state[item.id] = not state[item.id]
        if item.id == 'freecam' then if state.freecam then startCam() else stopCam() end end
        if item.id == 'hideRadar' and not state.hideRadar then DisplayRadar(true) end
    elseif item.id == 'fov' and state.freecam then
        local step = (FOV.Step or 2.5) * 2
        state.fov = math.max(FOV.Min or 5.0, math.min(FOV.Max or 100.0, state.fov + (dir ~= 0 and dir or 1) * step))
    elseif item.id == 'speed' and state.freecam then
        state.speed = ((state.speed - 1 + (dir ~= 0 and dir or 1)) % #SPEEDS) + 1
    elseif item.id == 'roll' and state.freecam then
        local step = C.RollStep or 5.0
        state.roll = math.max(-45.0, math.min(45.0, state.roll + (dir ~= 0 and dir or 1) * step))
    elseif item.id == 'reset' and dir == 0 then
        state.fov, state.roll, state.speed = FOV.Default or 50.0, 0.0, math.min(2, #SPEEDS)
    elseif item.id == 'quit' and dir == 0 then
        return false
    end
    return true
end

local function close()
    if not session then return end
    session = false
    state.freecam = false
    restore()
    sendMenu()
end

-- Touches du menu (sans curseur) : flèches 172-175, Entrée 191, Retour arrière 194 / 177, Échap 200 / 322, H 74
local MENU_CONTROLS = { 172, 173, 174, 175, 176, 177, 191, 194, 199, 200, 201, 202, 322, 74 }

local function run()
    CreateThread(function()
        local last = GetGameTimer()
        while session do
            local now = GetGameTimer()
            local dt = math.min(0.1, (now - last) / 1000.0)
            last = now
            if state.freecam and cam then
                DisableAllControlActions(0) -- le personnage ne bouge pas, les touches vont à la caméra
                for _, c in ipairs({ 245, 249 }) do EnableControlAction(0, c, true) end -- chat (T), voix (N)
                updateCam(dt)
            else
                for _, c in ipairs(MENU_CONTROLS) do DisableControlAction(0, c, true) end
            end
            applyHides()

            -- H (toujours) ou Espace (caméra libre : le personnage ne saute pas) : menu masqué / affiché, pour la photo
            if IsDisabledControlJustPressed(0, 74) or (state.freecam and cam and IsDisabledControlJustPressed(0, C.MenuToggleControl or 22)) then
                menuShown = not menuShown; sendMenu()
            elseif IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 194)
                or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
                close()
            elseif menuShown then
                if IsDisabledControlJustPressed(0, 172) then index = index > 1 and index - 1 or #ITEMS; sendMenu()
                elseif IsDisabledControlJustPressed(0, 173) then index = index < #ITEMS and index + 1 or 1; sendMenu()
                elseif IsDisabledControlJustPressed(0, 174) then change(ITEMS[index], -1); sendMenu()
                elseif IsDisabledControlJustPressed(0, 175) then change(ITEMS[index], 1); sendMenu()
                elseif IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then
                    if change(ITEMS[index], 0) == false then close() else sendMenu() end
                end
            end
            if IsEntityDead(PlayerPedId()) then close() end
            Wait(0)
        end
    end)
end

local function open()
    if session then
        menuShown = true
        return sendMenu()
    end
    if IsPauseMenuActive() or IsEntityDead(PlayerPedId()) then return end
    session, menuShown, index = true, true, 1
    sendMenu()
    run()
end

RegisterCommand(C.Command or 'freecam', open, false)
TriggerEvent('chat:addSuggestion', '/' .. (C.Command or 'freecam'), 'Mode photo : caméra libre, minimap et HUD masqués, zoom')

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if session then session = false; restore() end
end)

exports('active', function() return session end)
RPFreecam = { state = state, open = open, close = close, items = ITEMS, change = change } -- tests
