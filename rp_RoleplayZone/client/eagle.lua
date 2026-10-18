--[[
    RP RoleplayZone - client : ŒIL D'AIGLE (policiers)
    ---------------------------------------------------
    Une touche (Verr. Maj par défaut, modifiable dans les raccourcis FiveM) :
      - un court son et un effet d'écran (teinte froide, comme les visions du mode histoire) ;
      - une ONDE « RADAR » part du joueur et s'éloigne jusqu'à 15 m en CLIGNOTANT : un cercle blanc lumineux qui épouse
        le terrain (sols, murs, toits) ; chaque objet du décor et chaque véhicule qu'elle atteint ressort en CONTOUR
        BLANC un court instant ;
      - ce qui est À FOUILLER dans ces 15 m (objet / véhicule / périmètre à fouiller, arme au sol) reste en
        surbrillance plus longtemps et BAT comme un cœur : la couleur passe progressivement du blanc au jaune pâle
        et revient (deux pulsations douces, puis repos), sans apparaître / disparaître d'un coup ;
      - hors d'une zone de recherche : la zone la plus proche à moins de 100 m de son bord est POINTÉE : la caméra se
        tourne et zoome vers elle (comme le mode histoire) et une FLÈCHE directionnelle s'affiche à l'écran ;
        dans une zone : la flèche pointe la fouille la plus proche au-delà de 15 m (Eagle.InZoneArrow).
    Boucle à chaque image seulement pendant l'effet (quelques secondes), aucune sinon.
]]

RZ = RZ or {}
local Config = SceneConfig
local E = Config.Eagle or {}

local active = false
local lastUse = -1e9

local function ease(t) return 1 - (1 - t) * (1 - t) end

--- Battement de cœur (0 -> 1 -> 0) : deux pulsations douces (« boum… boum »), puis repos ; ms depuis le début
local function heartbeat(ms, period)
    local p = (ms % period) / period
    local function bump(center, width)
        local x = (p - center) / width
        return math.exp(-x * x)
    end
    return math.min(1.0, math.max(bump(0.17, 0.11), 0.8 * bump(0.43, 0.12)))
end

--- Couleur entre le blanc et `c` (part v de c)
local function blend(c, v)
    return { math.floor(255 + (c[1] - 255) * v + 0.5), math.floor(255 + (c[2] - 255) * v + 0.5), math.floor(255 + (c[3] - 255) * v + 0.5) }
end

local function bearing(from, to)
    return math.deg(math.atan(-(to.x - from.x), to.y - from.y))
end

local function normalize(a)
    a = (a + 180.0) % 360.0 - 180.0
    return a
end

-- =========================================================================
-- CIBLE POINTÉE (caméra + flèche)
-- =========================================================================
local function hintTarget(p)
    local inside = RZ.insideZone()
    local best, bestD
    if not inside then
        for _, s in ipairs(RZ.scenes()) do
            if s.kind == 'zone' then
                local d = RZ.dist2D(s.pos, p)
                if d > s.radius and d - s.radius <= (E.HintRange or 100.0) and (not bestD or d < bestD) then
                    best, bestD = s, d
                end
            end
        end
        if best then return { pos = best.pos, label = best.title ~= '' and best.title or 'Zone de recherche', camera = true,
            radius = best.radius } end
        return nil
    end
    if E.InZoneArrow == false then return nil end
    for _, s in ipairs(RZ.scenes()) do
        if s.kind ~= 'zone' and RZ.dist2D(s.pos, inside.pos) <= inside.radius + 2.0 then
            local d = RZ.dist2D(s.pos, p)
            if d > (E.Radius or 15.0) and (not bestD or d < bestD) then best, bestD = s, d end
        end
    end
    if best then return { pos = best.pos, label = 'Quelque chose à fouiller', camera = false, radius = 0 } end
    return nil
end

-- =========================================================================
-- CE QUE L'ONDE ATTEINT
-- =========================================================================
local function gather(p, R)
    local list, specials = {}, {}
    local me = vector3(p.x, p.y, p.z)
    local seen = {}
    -- à fouiller : objets des scènes, armes lâchées
    for _, s in ipairs(RZ.scenes()) do
        if s.kind ~= 'zone' then
            local sp = RZ.scenePos(s)
            local d = #(me - vector3(sp.x, sp.y, sp.z))
            if d <= R + (s.radius or 0) then
                if s.kind == 'object' then
                    local e = RZ.sceneEntity(s)
                    if e then seen[e] = true end
                    specials[#specials + 1] = { e = e, d = d, scene = s }
                else
                    specials[#specials + 1] = { d = math.max(0, d - s.radius), scene = s }
                end
            end
        end
    end
    local pools = { GetGamePool('CObject') }
    if E.Vehicles ~= false then pools[2] = GetGamePool('CVehicle') end
    for _, pool in ipairs(pools) do
        for _, e in ipairs(pool) do
            if not seen[e] and e ~= PlayerPedId() then
                local d = #(GetEntityCoords(e) - me)
                if d <= R + 1.0 and IsEntityVisible(e) then
                    if RZ.isDroppedWeapon(e) then
                        specials[#specials + 1] = { e = e, d = d }
                    else
                        list[#list + 1] = { e = e, d = d }
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    while #list > (E.MaxEntities or 160) do table.remove(list) end
    return list, specials
end

-- =========================================================================
-- EFFET
-- =========================================================================
local function startScreenFx()
    if E.PostFxIn and E.PostFxIn ~= '' then AnimpostfxPlay(E.PostFxIn, 0, false) end
    if E.Timecycle and E.Timecycle ~= '' then
        SetTimecycleModifier(E.Timecycle)
        SetTimecycleModifierStrength(E.TimecycleStrength or 0.55)
    end
end

local function stopScreenFx()
    if E.PostFxIn and E.PostFxIn ~= '' then AnimpostfxStop(E.PostFxIn) end
    if E.Timecycle and E.Timecycle ~= '' then ClearTimecycleModifier() end
    if E.PostFxOut and E.PostFxOut ~= '' then AnimpostfxPlay(E.PostFxOut, 0, false) end
end

local function eagleEye()
    if active then return end
    if not RZ.isSearcher() then return RZ.notify('Œil d\'aigle réservé aux policiers en service (unité du MDC).') end
    if IsPauseMenuActive() or RZ.selecting() or IsEntityDead(PlayerPedId()) then return end
    local now = GetGameTimer()
    if now - lastUse < (E.Cooldown or 6000) then return end
    lastUse, active = now, true

    local R = E.Radius or 15.0
    local waveTime = E.WaveTime or 1400
    local highlight, searchHighlight = E.Highlight or 1200, E.SearchHighlight or 4000
    local blink = E.Blink or 140
    local yellow = E.SearchColor or { 255, 236, 150 }
    local heartPeriod = E.Heartbeat or 1300
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local origin = { x = c.x, y = c.y, z = c.z - 0.95 }
    local list, specials = gather({ x = c.x, y = c.y, z = c.z }, R)

    RZ.sound('eagle')
    startScreenFx()
    SetEntityDrawOutlineColor(255, 255, 255, 255)
    SetEntityDrawOutlineShader(E.OutlineShader or 0)

    local target = hintTarget({ x = c.x, y = c.y, z = c.z })
    if target and target.camera then
        SetGameplayCoordHint(target.pos.x + 0.0, target.pos.y + 0.0, target.pos.z + 0.0, E.HintTime or 2600, 900, 700, 0)
        SetGameplayHintFov(E.HintFov or 32.0)
    end

    CreateThread(function()
        local start = GetGameTimer()
        local lit = {}      -- [entité] = fin de la surbrillance
        local special = {}  -- [entité] = début de son battement : à fouiller (blanc <-> jaune pâle)
        local shown, shownAt = 0.0, nil -- couleur des contours (0 blanc -> 1 jaune pâle), suivie en douceur
        local ringsLit = {} -- [id de scène] = { untilT, pts }
        local total = math.max(waveTime + searchHighlight, target and (E.ArrowTime or 4500) or 0, waveTime + highlight)
        local fxStopped = false
        local lastArrow = 0
        while true do
            local t = GetGameTimer() - start
            if t > total then break end
            local progress = math.min(1.0, t / waveTime)
            local waveR = R * ease(progress)

            -- onde : cercle blanc qui s'éloigne et s'efface, avec une traîne
            if progress < 1.0 then
                local here = GetEntityCoords(ped)
                local center = { x = origin.x, y = origin.y, z = here.z - 0.95 }
                -- l'onde clignote au fur et à mesure qu'elle s'agrandit
                local on = math.floor(t / blink) % 2 == 0
                local alpha = math.floor(230 * (1.0 - progress * 0.6) * (on and 1.0 or 0.3))
                if waveR > 0.4 then
                    RZ.drawRing(RZ.ringPoints(center, waveR, RZ.ringCount(waveR, 64), { up = 3.0, down = 6.0 }), 0.22, { 255, 255, 255 }, alpha)
                end
                if waveR > 2.0 then
                    RZ.drawRing(RZ.ringPoints(center, waveR * 0.82, RZ.ringCount(waveR, 40), { up = 3.0, down = 6.0 }), 0.08,
                        { 220, 235, 255 }, math.floor(alpha * 0.45), false)
                end
            end

            -- objets et véhicules atteints par l'onde : contour blanc un court instant
            local now = GetGameTimer()
            for _, item in ipairs(list) do
                if not item.done and item.d <= waveR then
                    item.done = true
                    if DoesEntityExist(item.e) then lit[item.e] = now + highlight end
                end
            end
            -- ce qui est à fouiller : plus longtemps (SearchHighlight), en battant comme un cœur
            for _, item in ipairs(specials) do
                if not item.done and item.d <= waveR then
                    item.done = true
                    if item.e and DoesEntityExist(item.e) then
                        lit[item.e] = now + searchHighlight
                        special[item.e] = now -- début de son battement
                    end
                    if item.scene then
                        local s = item.scene
                        local r = s.kind == 'perimeter' and s.radius or (s.radius or 1.0)
                        local sp = RZ.scenePos(s)
                        ringsLit[s.id] = { untilT = now + searchHighlight, pts = RZ.ringPoints(sp, r, RZ.ringCount(r, 48)),
                            pos = sp, kind = s.kind, from = now }
                    end
                end
            end
            -- BATTEMENT DE CŒUR : ce qui est à fouiller passe progressivement du blanc au jaune pâle et revient (deux
            -- pulsations douces, puis repos), sans apparaître / disparaître d'un coup. La couleur des contours du jeu est
            -- la même pour tout l'écran : tant que des contours ordinaires (blancs) sont affichés, le jaune d'un objet
            -- à fouiller monte dans une boîte autour de lui ; ensuite, c'est son contour qui prend la couleur.
            local generic, beat, remaining = false, 0.0, math.huge
            for e, untilT in pairs(lit) do
                if now > untilT or not DoesEntityExist(e) then
                    if DoesEntityExist(e) then SetEntityDrawOutline(e, false) end
                    lit[e], special[e] = nil, nil
                elseif not special[e] then
                    generic = true
                else
                    beat = math.max(beat, heartbeat(now - special[e], heartPeriod))
                    remaining = math.min(remaining, untilT - now)
                end
            end
            -- s'éteint doucement à la fin (pas de disparition d'un coup) ; la couleur suit le battement en douceur
            -- (aussi quand les contours blancs ordinaires s'éteignent : pas de saut de couleur)
            local alpha = generic and 255 or math.floor(255 * math.min(1.0, remaining / 600.0))
            local beatTarget = generic and 0.0 or beat
            local dtMs = math.max(0, now - (shownAt or now))
            shownAt = now
            shown = shown + (beatTarget - shown) * (1.0 - math.exp(-dtMs / 45.0))
            local c = blend(yellow, shown)
            SetEntityDrawOutlineColor(c[1], c[2], c[3], alpha)
            for e in pairs(lit) do
                SetEntityDrawOutline(e, true)
                if special[e] and generic then
                    local v = heartbeat(now - special[e], heartPeriod)
                    if v > 0.03 then RZ.drawBox(e, blend(yellow, v), math.floor(60 + 180 * v)) end
                end
            end
            for id, ring in pairs(ringsLit) do
                local left = ring.untilT - now
                if left <= 0 then
                    ringsLit[id] = nil
                else
                    local fade = math.min(1.0, left / 600.0)
                    local v = heartbeat(now - ring.from, heartPeriod)
                    local c = blend(yellow, v)
                    RZ.drawRing(ring.pts, ring.kind == 'perimeter' and 0.16 or 0.1, c, math.floor((200 + 35 * v) * fade))
                    if ring.kind == 'perimeter' then
                        DrawLightWithRange(ring.pos.x, ring.pos.y, ring.pos.z + 0.6, c[1], c[2], c[3], 3.5, (2.0 + 1.5 * v) * fade)
                    end
                end
            end

            -- flèche directionnelle vers la zone / la fouille pointée
            if target and t <= (E.ArrowTime or 4500) and now - lastArrow > 40 then
                lastArrow = now
                local here = GetEntityCoords(ped)
                local rel = normalize(bearing(here, target.pos) - GetGameplayCamRot(2).z)
                SendNUIMessage({ action = 'arrow', data = { show = true, angle = -rel, label = target.label,
                    distance = math.floor(math.max(0, RZ.dist2D(here, target.pos) - target.radius) + 0.5) } })
            elseif target and t > (E.ArrowTime or 4500) and not target.hidden then
                target.hidden = true
                SendNUIMessage({ action = 'arrow', data = { show = false } })
            end

            if not fxStopped and t > waveTime + 900 then
                fxStopped = true
                stopScreenFx()
            end
            Wait(0)
        end
        for e in pairs(lit) do if DoesEntityExist(e) then SetEntityDrawOutline(e, false) end end
        SetEntityDrawOutlineColor(255, 255, 255, 255)
        if not fxStopped then stopScreenFx() end
        SendNUIMessage({ action = 'arrow', data = { show = false } })
        active = false
    end)
end

RegisterCommand(E.Command or 'oeildaigle', eagleEye, false)
RegisterKeyMapping(E.Command or 'oeildaigle', 'Œil d\'aigle (policiers) : faire ressortir ce qui est à fouiller', 'keyboard', E.Key or 'CAPITAL')
TriggerEvent('chat:addSuggestion', '/' .. (E.Command or 'oeildaigle'), 'Œil d\'aigle : fait ressortir ce qui est à fouiller autour (15 m) et pointe la zone de recherche proche')

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() or not active then return end
    ClearTimecycleModifier()
    StopGameplayHint(true)
end)
