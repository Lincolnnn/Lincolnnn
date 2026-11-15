--[[
    MDC - DONNÉES DE DÉMONSTRATION (entièrement fictives)
    -----------------------------------------------------
    Commande CONSOLE SERVEUR uniquement (txAdmin > Console, ou la fenêtre du serveur) :
      mdc_demo status   nombre de fiches de démonstration présentes
      mdc_demo seed     crée les fiches (refusé s'il y en a déjà : purge ou regen d'abord)
      mdc_demo purge    supprime TOUTES les fiches de démonstration, et seulement elles
      mdc_demo regen    purge puis seed (mêmes fiches à chaque fois : générateur à graine fixe)

    Contenu (DEMO ci-dessous) :
      - Kidnapping Offenders (45) et Sex Offenders (70) : identités complètes (nom, date de naissance, SSN, adresse,
        téléphone, emploi, description physique, photo par défaut) inscrites au registre : charge retenue (RCW),
        niveau de risque, statut de suivi, dates (faits, jugement, libération, inscription, dernière mise à jour),
        tribunal, n° de dossier, peine, notes ; parfois un casier antérieur.
      - Rapports (80) de toutes natures : arrestations, accidents (PTCR), plaintes, vols, contrôles routiers, enquêtes,
        interventions médicales, conduite sous influence, fourrières… avec n°, auteur, unité, date, type, résumé,
        personnes (dont des inscrits au registre : ils apparaissent dans leurs antécédents) et intervention liée.
    Chaque fiche passe par les MÊMES contrôles que dans le MDC (server.lua) et porte demo = true : la purge ne touche
    jamais une fiche créée par un joueur. Noms, dates, adresses et numéros sont inventés (combinaisons aléatoires).
]]

local DEMO = {
    kidnap = 45,    -- Kidnapping Offenders (entre 30 et 60)
    sex = 70,       -- Sex Offenders
    reports = 80,   -- rapports déjà remplis (40 minimum)
    seed = 20261115, -- graine du générateur : mêmes données à chaque « seed »
    author = 'demo', -- createdBy des fiches (jamais un identifiant de joueur)
}

local API = MDCServer and MDCServer.demo
-- Dates en NUMÉROS DE JOUR (jours depuis le 01/01/1970, calendrier civil) : pas d'os.date / os.time sur des dates
-- de naissance antérieures à 1970 (refusées par le serveur sous Windows)
local DAY, MONTH = 1, 30.44

-- ---------------------------------------------------------------------------------------------------------------------
-- Générateur pseudo-aléatoire à graine fixe (indépendant de math.random : les fiches restent les mêmes)
-- ---------------------------------------------------------------------------------------------------------------------
local state = DEMO.seed
local function rnd(a, b)
    state = (state * 1103515245 + 12345) % 2147483648
    if not a then return state / 2147483648 end
    return a + (state % (b - a + 1))
end
local function pick(t) return t[rnd(1, #t)] end
local function chance(p) return rnd() < p end
local function weighted(list) -- { { valeur, poids }, ... }
    local total = 0
    for _, e in ipairs(list) do total = total + e[2] end
    local r = rnd() * total
    for _, e in ipairs(list) do
        r = r - e[2]
        if r <= 0 then return e[1] end
    end
    return list[#list][1]
end

local TODAY = 0
local function daysFromCivil(y, m, d)
    y = m <= 2 and y - 1 or y
    local era = (y >= 0 and y or y - 399) // 400
    local yoe = y - era * 400
    local doy = (153 * (m + (m > 2 and -3 or 9)) + 2) // 5 + d - 1
    local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    return era * 146097 + doe - 719468
end
local function civilFromDays(z)
    z = math.floor(z) + 719468
    local era = (z >= 0 and z or z - 146096) // 146097
    local doe = z - era * 146097
    local yoe = (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    local doy = doe - (365 * yoe + yoe // 4 - yoe // 100)
    local mp = (5 * doy + 2) // 153
    local d = doy - (153 * mp + 2) // 5 + 1
    local m = mp + (mp < 10 and 3 or -9)
    return yoe + era * 400 + (m <= 2 and 1 or 0), m, d
end
local function dateStr(day)
    local y, m, d = civilFromDays(day)
    return ('%02d/%02d/%04d'):format(d, m, y)
end
local function dayOf(str) -- 'JJ/MM/AAAA' -> numéro de jour
    return daysFromCivil(tonumber(str:sub(7, 10)), tonumber(str:sub(4, 5)), tonumber(str:sub(1, 2)))
end
local function yearOf(day) return (civilFromDays(day)) end
local function timeStr(minutes) return ('%02d:%02d'):format((minutes // 60) % 24, minutes % 60) end

-- ---------------------------------------------------------------------------------------------------------------------
-- Listes (fictives : combinaisons tirées au hasard, aucune personne réelle)
-- ---------------------------------------------------------------------------------------------------------------------
local MALE = { 'James', 'Michael', 'Robert', 'David', 'Daniel', 'Matthew', 'Anthony', 'Mark', 'Steven', 'Andrew',
    'Joshua', 'Kevin', 'Brian', 'Ryan', 'Jason', 'Justin', 'Brandon', 'Tyler', 'Aaron', 'Nathan', 'Kyle', 'Eric', 'Adam',
    'Travis', 'Cody', 'Derek', 'Shane', 'Dustin', 'Trevor', 'Marcus', 'Victor', 'Luis', 'Carlos', 'Miguel', 'Hector',
    'Dmitri', 'Tuan', 'Kenji', 'Malik', 'Darnell', 'Wesley', 'Colin', 'Garrett', 'Logan', 'Mason', 'Caleb', 'Ethan', 'Owen',
    'Russell', 'Gordon', 'Clayton', 'Floyd', 'Raymond', 'Curtis', 'Dwayne', 'Ivan', 'Rafael', 'Silas', 'Grady', 'Emmett' }
local FEMALE = { 'Jennifer', 'Jessica', 'Ashley', 'Amanda', 'Sarah', 'Stephanie', 'Nicole', 'Heather', 'Melissa',
    'Rebecca', 'Laura', 'Megan', 'Rachel', 'Kayla', 'Brittany', 'Danielle', 'Amber', 'Crystal', 'Tiffany', 'Vanessa',
    'Monica', 'Andrea', 'Erin', 'Kelsey', 'Natalie', 'Olivia', 'Hannah', 'Sophia', 'Mia', 'Leah', 'Maria', 'Rosa', 'Lucia',
    'Mai', 'Yuki', 'Priya', 'Aaliyah', 'Keisha', 'Brooke', 'Paige', 'Darlene', 'Tamara', 'Gloria', 'Irene', 'Noelle' }
local MIDDLE = { 'Lee', 'Ray', 'Ann', 'Marie', 'James', 'Lynn', 'Dean', 'Rose', 'Wayne', 'Jo', 'Allen', 'Jean', 'Scott', 'Mae' }
local LAST = { 'Abbott', 'Ballard', 'Barnes', 'Bennett', 'Bishop', 'Boyd', 'Bradley', 'Brooks', 'Burke', 'Caldwell',
    'Carlson', 'Carver', 'Chambers', 'Chandler', 'Cole', 'Conrad', 'Crawford', 'Cross', 'Dalton', 'Daniels', 'Dawson',
    'Dixon', 'Doyle', 'Drake', 'Duncan', 'Ellis', 'Erickson', 'Esposito', 'Farrell', 'Fischer', 'Fleming', 'Foley',
    'Fowler', 'Gibson', 'Gilbert', 'Graham', 'Griffin', 'Hale', 'Hansen', 'Harper', 'Hayes', 'Hendricks', 'Holt',
    'Hopkins', 'Howell', 'Hudson', 'Ingram', 'Jensen', 'Keller', 'Kemp', 'Lambert', 'Larsen', 'Lawson', 'Lindqvist',
    'Lowe', 'Lynch', 'Maddox', 'Marsh', 'McCoy', 'Mendoza', 'Mercer', 'Moreno', 'Nash', 'Nguyen', 'Nielsen', 'Novak',
    'O\'Brien', 'Olsen', 'Ortega', 'Palmer', 'Parsons', 'Pearson', 'Pham', 'Porter', 'Quinn', 'Ramos', 'Reyes', 'Rhodes',
    'Riley', 'Romero', 'Rowe', 'Salazar', 'Sandoval', 'Schmidt', 'Sharp', 'Shelton', 'Simmons', 'Sloan', 'Soto',
    'Stanton', 'Sutton', 'Tanaka', 'Thornton', 'Torres', 'Tran', 'Underwood', 'Vance', 'Vargas', 'Wade', 'Walsh',
    'Warner', 'Watts', 'Weaver', 'Webb', 'Wheeler', 'Whitaker', 'Wolfe', 'Yates', 'York', 'Zimmerman', 'Kowalski',
    'Haugen', 'Beaulieu', 'Okafor', 'Delgado', 'Fitzgerald', 'Gallagher', 'Kirby', 'Lund', 'Pruitt', 'Strand' }

-- Rues de King County (adresses inventées : numéros tirés au hasard) et leur ville
local STREETS = {
    { 'NE 145th St', 'Shoreline', 98155 }, { 'NE 160th St', 'Kenmore', 98028 }, { '84th Ave NE', 'Kenmore', 98028 },
    { '100th Ave NE', 'Kirkland', 98034 }, { 'Holmes Point Dr NE', 'Kirkland', 98034 }, { 'Juanita Dr NE', 'Kirkland', 98034 },
    { 'Bothell Way NE', 'Kenmore', 98028 }, { 'Lake City Way NE', 'Seattle', 98125 }, { 'Aurora Ave N', 'Seattle', 98133 },
    { 'Rainier Ave S', 'Seattle', 98118 }, { 'Martin Luther King Jr Way S', 'Seattle', 98108 }, { 'Greenwood Ave N', 'Seattle', 98103 },
    { 'Roosevelt Way NE', 'Seattle', 98115 }, { 'Delridge Way SW', 'Seattle', 98106 }, { 'California Ave SW', 'Seattle', 98116 },
    { '15th Ave NW', 'Seattle', 98107 }, { 'Ambaum Blvd SW', 'Burien', 98146 }, { 'SW 152nd St', 'Burien', 98166 },
    { 'Des Moines Memorial Dr S', 'Burien', 98148 }, { 'Pacific Hwy S', 'SeaTac', 98188 }, { 'SE 256th St', 'Kent', 98030 },
    { '104th Ave SE', 'Kent', 98031 }, { 'Benson Rd S', 'Renton', 98055 }, { 'Kent-Kangley Rd', 'Covington', 98042 },
    { 'Issaquah-Hobart Rd SE', 'Issaquah', 98027 }, { '228th Ave SE', 'Sammamish', 98075 }, { 'Avondale Rd NE', 'Redmond', 98052 },
    { 'Union Hill Rd', 'Redmond', 98053 }, { 'NE 8th St', 'Bellevue', 98004 }, { 'Bellevue Way NE', 'Bellevue', 98004 },
    { '148th Ave NE', 'Bellevue', 98007 }, { 'Northup Way', 'Bellevue', 98005 }, { 'S 320th St', 'Federal Way', 98003 },
    { 'Simonds Rd NE', 'Kenmore', 98028 }, { '428th Ave SE', 'North Bend', 98045 }, { 'Woodinville-Duvall Rd', 'Woodinville', 98072 },
}
local ROADS = { 'I-5', 'I-90', 'I-405', 'SR 522', 'SR 169', 'SR 18', 'US-2', 'SR 520' }
local JOBS = { 'Cariste', 'Plongeur', 'Chauffeur-livreur', 'Agent d\'entretien', 'Mécanicien', 'Sans emploi', 'Couvreur',
    'Cuisinier', 'Manutentionnaire', 'Agent de sécurité', 'Électricien', 'Vendeur', 'Peintre en bâtiment', 'Soudeur',
    'Serveur', 'Chauffeur poids lourd', 'Paysagiste', 'Préparateur de commandes', 'Technicien réseau', 'Ouvrier agricole',
    'Caissier', 'Charpentier', 'Pêcheur', 'Barman', 'Gardien d\'entrepôt', 'Laveur de vitres' }
local HAIR = { 'bruns', 'noirs', 'châtains', 'blonds', 'roux', 'gris', 'poivre et sel', 'rasés', 'dégarnis' }
local EYES = { 'marron', 'bleus', 'verts', 'noisette', 'gris' }
local BUILD = { 'mince', 'corpulence moyenne', 'trapu', 'athlétique', 'fort', 'élancé' }
local MARKS = { 'tatouage tribal avant-bras droit', 'cicatrice sourcil gauche', 'tatouage « 206 » nuque', 'piercing arcade',
    'tatouage d\'aigle épaule gauche', 'cicatrice de brûlure main droite', 'barbe fournie', 'boite légèrement (jambe gauche)',
    'tatouage de rose poignet', 'grain de beauté joue droite', 'lunettes à monture épaisse', 'dent en or (incisive)',
    'tatouage de flammes mollet', 'cicatrice lèvre supérieure', 'tatouage de texte avant-bras gauche' }
local MAKES = { 'Ford Fusion', 'Honda Accord', 'Toyota Camry', 'Subaru Outback', 'Chevrolet Silverado', 'Ford F-150',
    'Nissan Altima', 'Hyundai Elantra', 'Jeep Cherokee', 'Dodge Charger', 'Kia Sorento', 'Toyota Tacoma', 'Honda CR-V',
    'Volkswagen Jetta', 'Chevrolet Malibu', 'Subaru Forester', 'Ram 1500', 'Mazda 3', 'Toyota Corolla', 'GMC Sierra' }
local COLORS = { 'Noir', 'Blanc', 'Gris', 'Argent', 'Bleu', 'Rouge', 'Vert foncé', 'Bordeaux', 'Beige', 'Bleu marine' }
local INSURERS = { 'PEMCO', 'Progressive', 'State Farm', 'Allstate', 'GEICO', 'Safeco', 'Farmers', 'USAA' }
local OFFICERS = {
    { 'Tpr. A. Lindgren', 'WSP', '8A21' }, { 'Tpr. C. Okonkwo', 'WSP', '8A34' }, { 'Sgt. M. Haldane', 'WSP', '8S02' },
    { 'Tpr. J. Ferraro', 'WSP', '8B17' }, { 'Tpr. R. Whitcomb', 'WSP', '8B40' }, { 'Dep. S. Arvidson', 'KCSO', '2D14' },
    { 'Dep. L. Marchetti', 'KCSO', '2D27' }, { 'Dep. K. Brandt', 'KCSO', '3F11' }, { 'Sgt. T. Oyelaran', 'KCSO', '3S05' },
    { 'Dep. N. Castellano', 'KCSO', '3F32' }, { 'Det. E. Gundersen', 'KCSO', '2K09' }, { 'Dep. P. Ashworth', 'KCSO', '2D41' },
}
local TOW = { 'Lakeside Towing & Recovery', 'Cascade Tow Co.', 'Eastside Roadside Services', 'Rainier Valley Towing', 'Northend Auto Recovery' }
local HOSPITALS = { 'Harborview Medical Center', 'Overlake Medical Center', 'EvergreenHealth Kirkland', 'Valley Medical Center', 'Highline Medical Center' }

local REG_NOTES_A = {
    'Adresse vérifiée en personne, rien à signaler.', 'Visite de contrôle effectuée, domicile conforme à la déclaration.',
    'Se présente à chaque convocation, coopératif.', 'Nouveau numéro de téléphone déclaré au bureau du shérif.',
    'Changement d\'adresse déclaré dans le délai de 3 jours ouvrables.', 'Absent lors de deux passages, avis laissé sur place.',
    'Signalé par l\'agent de probation (DOC) pour un retard de pointage.', 'Courrier de vérification revenu non distribué.',
    'Logement temporaire en foyer, à revérifier chaque mois.', 'Employeur informé par le DOC des conditions de surveillance.',
    'Vit chez un membre de sa famille, adresse confirmée par téléphone.', 'Contrôle surprise sans incident.',
    'Déclaration de véhicule mise à jour (plaque et modèle).', 'Rendez-vous de traitement suivis régulièrement.',
    'A demandé une réévaluation de son niveau de risque.', 'Photo d\'identité du registre à refaire (ancienne).',
}
local REG_NOTES_B = {
    'Travaille de nuit dans un entrepôt de Kent.', 'Aucun contact connu avec la victime.', 'Possède un pick-up de couleur sombre.',
    'Fréquente un club de bowling le jeudi soir.', 'Signalé près d\'un parc en mai, sans infraction relevée.',
    'Suivi par un agent de probation de la région Nord.', 'Interdiction de séjour près des établissements scolaires rappelée.',
    'Ne possède pas de véhicule, se déplace en bus (King County Metro).', 'Héberge un colocataire, identité relevée.',
    'Bracelet électronique retiré à la fin de la mesure.', 'Inscrit à une formation professionnelle.', 'Chien de garde sur la propriété.',
    'Souffre de problèmes de dos, travaille à temps partiel.', 'Vit seul dans un mobil-home.', 'Contact régulier avec un pasteur local.',
    'Ancien employé d\'une société de déménagement.', 'Pas d\'arme déclarée, permis d\'arme révoqué.', 'Réside à moins de 2 km de son ancien domicile.',
}

-- Peines : conditions ajoutées après la durée de détention
local SEX_CONDITIONS = { 'Traitement spécialisé obligatoire (SOTP).', 'Interdiction de contact avec la victime.',
    'Interdiction de séjour à moins de 880 pieds d\'une école.', 'Évaluation psychosexuelle annuelle.',
    'Accès à Internet sous supervision uniquement.', 'Interdiction de contact non supervisé avec des mineurs.' }
local KIDNAP_CONDITIONS = { 'Interdiction de contact avec la victime et sa famille.', 'Bracelet électronique pendant 12 mois.',
    'Suivi psychologique obligatoire.', 'Interdiction de quitter l\'État sans autorisation.', 'Interdiction de port d\'arme.' }
local PRIORS = { 'theft3', 'assault4', 'dwls3', 'trespass2', 'mm3', 'vucsa', 'harass', 'disorderly', 'reckless', 'nvol' }

-- ---------------------------------------------------------------------------------------------------------------------
-- Générateurs simples
-- ---------------------------------------------------------------------------------------------------------------------
local used = { names = {}, cases = {}, notes = {}, plates = {} }

local function newName(sex)
    for _ = 1, 200 do
        local first = pick(sex == 'F' and FEMALE or MALE)
        local last = pick(LAST)
        local key = first .. ' ' .. last
        if not used.names[key] then
            used.names[key] = true
            return first, last
        end
    end
    return pick(sex == 'F' and FEMALE or MALE), pick(LAST) .. '-' .. pick(LAST)
end

local function newAddress()
    local s = pick(STREETS)
    return ('%d %s, %s'):format(rnd(100, 28999), s[1], s[2]), s
end

local function physical()
    local tall = rnd(0, 9)
    local height = tall < 7 and ('5\'%d"'):format(rnd(3, 11)) or ('6\'%d"'):format(rnd(0, 4))
    local parts = { height, ('%d lbs'):format(rnd(125, 265)), pick(BUILD), 'cheveux ' .. pick(HAIR), 'yeux ' .. pick(EYES) }
    if chance(0.55) then parts[#parts + 1] = pick(MARKS) end
    return table.concat(parts, ', ')
end

local function caseNumber(court, year)
    for _ = 1, 100 do
        local n
        if court == 'superior' then
            n = ('%02d-1-%05d-%d %s'):format(year % 100, rnd(100, 99999), rnd(0, 9), pick({ 'SEA', 'SEA', 'KNT' }))
        else
            n = ('%s%02d-%05d'):format(pick({ 'KC', 'SEA', 'BEL' }), year % 100, rnd(10, 99999))
        end
        if not used.cases[n] then used.cases[n] = true return n end
    end
    return ('X%d'):format(rnd(100000, 999999))
end

local function uniqueNote(...)
    for _ = 1, 40 do
        local a, b = pick(REG_NOTES_A), pick(REG_NOTES_B)
        local text = a .. ' ' .. b
        if not used.notes[text] then used.notes[text] = true return text end
    end
    return pick(REG_NOTES_A)
end

local function plate()
    local L = 'ABCDEFGHJKLMNPRSTUVWXYZ'
    for _ = 1, 50 do
        local p = ''
        for _ = 1, 3 do local i = rnd(1, #L) p = p .. L:sub(i, i) end
        p = p .. ('%04d'):format(rnd(0, 9999))
        if not used.plates[p] then used.plates[p] = true return p end
    end
    return 'DEMO' .. rnd(100, 999)
end

local function vin()
    local C = '0123456789ABCDEFGHJKLMNPRSTUVWXYZ'
    local v = ''
    for _ = 1, 17 do local i = rnd(1, #C) v = v .. C:sub(i, i) end
    return v
end

local function wdl(last, first)
    -- Format du permis de l'État de Washington : WDL + 9 caractères
    local C = '0123456789ABCDEFGHJKLMNPRSTUVWXYZ'
    local s = 'WDL'
    for _ = 1, 9 do local i = rnd(1, #C) s = s .. C:sub(i, i) end
    return s
end

local function offensesOf(filter)
    local list = {}
    for _, o in ipairs(MDC_OFFENSES or {}) do if filter(o) then list[#list + 1] = o end end
    return list
end

-- ---------------------------------------------------------------------------------------------------------------------
-- IDENTITÉS INSCRITES AU REGISTRE
-- ---------------------------------------------------------------------------------------------------------------------
local PRISON = { FA = { 96, 300 }, FB = { 36, 120 }, FC = { 12, 60 }, GM = { 2, 11 }, M = { 0, 3 } }

local function registryPayload(kind, offense, address)
    local class = offense.c
    local p = PRISON[class] or { 6, 24 }
    local months = rnd(p[1], p[2])
    -- libération entre 1 mois et 18 ans avant aujourd'hui (moins loin pour les peines courtes)
    local release = TODAY - rnd(30, class == 'FA' and 18 * 365 or 12 * 365) * DAY
    local registered = release + rnd(0, 3) * DAY
    if registered > TODAY - DAY then registered = TODAY - DAY end
    local conviction = release - months * MONTH - rnd(0, 25) * DAY
    local offenseT = conviction - rnd(60, 420) * DAY
    local level = class == 'FA' and weighted({ { '3', 5 }, { '2', 4 }, { '1', 1 } })
        or class == 'FB' and weighted({ { '3', 2 }, { '2', 5 }, { '1', 3 } })
        or weighted({ { '3', 1 }, { '2', 3 }, { '1', 6 } })
    local status = weighted({ { 'compliant', 74 }, { 'noncompliant', 18 }, { 'absconded', 8 } })
    local lastUpdate
    if status == 'absconded' then
        local since = math.floor(TODAY - registered)
        lastUpdate = registered + rnd(math.min(20, since), math.max(20, since))
    else
        lastUpdate = math.max(registered, TODAY - rnd(3, 320) * DAY)
    end
    lastUpdate = math.floor(math.min(lastUpdate, TODAY))
    local conditions = kind == 'sex' and SEX_CONDITIONS or KIDNAP_CONDITIONS
    local first = pick(conditions)
    local second = pick(conditions)
    local custody = class:sub(1, 1) == 'F' and 'Department of Corrections' or 'King County Jail'
    local sentence = ('%d mois de détention (%s), %d mois de surveillance (community custody). %s%s'):format(
        months, custody, rnd(12, 48), first, second ~= first and (' ' .. second) or '')
    local court = class:sub(1, 1) == 'F' and 'superior' or 'district'
    return {
        offense = offense.id, level = level, status = status, address = address, prisonMonths = months,
        offenseDate = dateStr(offenseT), convictionDate = dateStr(conviction), releaseDate = dateStr(release),
        registeredDate = dateStr(registered), lastUpdate = dateStr(lastUpdate),
        court = court, caseNumber = caseNumber(court, yearOf(conviction)),
        sentence = sentence, notes = uniqueNote(),
    }, offenseT, status, lastUpdate
end

local function priorConviction(dobT, beforeT)
    local from, to = dobT + 18.2 * 365.25 * DAY, beforeT - 90 * DAY
    if to - from < 60 * DAY then return nil end
    local id = pick(PRIORS)
    local o = API.Offenses[id]
    if not o then return nil end
    local offenseT = from + rnd() * (to - from)
    local conviction = offenseT + rnd(20, 160) * DAY
    if conviction > TODAY - DAY then conviction = TODAY - DAY end
    local disposition = pick({ 'guilty', 'plea', 'plea', 'deferred' })
    local days = rnd(0, 60)
    local sentence = days > 0 and ('%d jours de détention (dont %d avec sursis), amende de %d $.'):format(days, math.floor(days / 2), rnd(2, 20) * 50)
        or ('Amende de %d $ et 12 mois de probation.'):format(rnd(2, 20) * 50)
    return {
        offense = id, offenseDate = dateStr(offenseT), convictionDate = dateStr(conviction), court = 'district',
        caseNumber = caseNumber('district', yearOf(conviction)), disposition = disposition,
        sentence = sentence, notes = '',
    }
end

local function makeOffender(kind, offenses)
    for _ = 1, 30 do
        local sex = kind == 'sex' and (chance(0.92) and 'M' or 'F') or (chance(0.85) and 'M' or 'F')
        local first, last = newName(sex)
        local address = newAddress()
        local offense = pick(offenses)
        local reg, offenseT, status, lastUpdate = registryPayload(kind, offense, address)
        local ageAtOffense = rnd(19, 52)
        local dobT = offenseT - (ageAtOffense * 365.25 + rnd(0, 360)) * DAY
        local payload = {
            firstname = first, lastname = last, middlename = chance(0.35) and pick(MIDDLE) or '',
            dob = dateStr(dobT), sex = sex, address = address, job = pick(JOBS), physical = physical(),
            phone = '', ssn = '', nationality = 'US', condition = 'none',
            registrations = { [kind] = reg }, convictions = {},
        }
        if status == 'absconded' then
            payload.condition = 'wanted'
            payload.wantedReason = 'Failure to Register (RCW 9A.44.132) : ne réside plus à l\'adresse déclarée, localisation inconnue.'
            payload.wantedSince = dateStr(lastUpdate)
        end
        if chance(0.3) then
            local prior = priorConviction(dobT, offenseT)
            if prior then payload.convictions[1] = prior end
        end
        local record, err = API.Builders.identities(payload, nil, DEMO.author)
        if record then return record end
        print(('^3[MDC demo]^0 fiche refusée (%s), nouvel essai.'):format(tostring(err)))
    end
    return nil
end

-- ---------------------------------------------------------------------------------------------------------------------
-- RAPPORTS : thèmes (type de rapport, nature, rôles, véhicules, exposé des faits)
-- ---------------------------------------------------------------------------------------------------------------------
local THEMES = {
    { id = 'arrest_theft', type = 'arrest', n = 6, title = 'Vol avec effraction — suspect interpellé', kw = { 'burglary2', 'resburglary', 'theft2', 'theft3', 'mm2' },
      text = {
        'Le {date} vers {time}, appel pour un individu forçant la porte arrière d\'un commerce au {address}. À notre arrivée, {subject} a tenté de prendre la fuite à pied et a été rattrapé sur le parking. Outils de cambriolage et marchandise retrouvés dans son sac. Interpellé sans blessure, transporté au centre de détention.',
        'Le {date}, {subject} a été observé par une caméra de surveillance en train de sortir d\'un garage du {address} avec du matériel électroportatif. Repéré 15 minutes plus tard à proximité, il était en possession des objets décrits par la victime. Arrestation sur cause probable.' } },
    { id = 'arrest_assault', type = 'arrest', n = 4, title = 'Agression — interpellation', kw = { 'assault4', 'assault3', 'assault2', 'harass' },
      text = {
        'Le {date} à {time}, intervention pour une rixe devant un bar du {address}. Selon trois témoins concordants, {subject} a frappé la victime au visage à plusieurs reprises. La victime présente une plaie à l\'arcade, prise en charge par les secours. {subject} a été interpellé sur place.',
        'Le {date}, la victime a déclaré avoir été menacée puis poussée violemment par {subject} lors d\'un différend de voisinage au {address}. Lésions constatées (contusions à l\'épaule). L\'auteur, présent et agité, a été placé en état d\'arrestation.' } },
    { id = 'arrest_warrant', type = 'arrest', n = 4, title = 'Contrôle — personne recherchée', kw = { 'dwls1', 'dwls2', 'vucsa', 'obstruct', 'failreg' },
      text = {
        'Le {date} à {time}, contrôle du véhicule {model} immatriculé {plate} sur {address} pour un feu arrière défectueux. Le conducteur, {subject}, fait l\'objet d\'un mandat d\'arrêt actif. Identité confirmée par le WACIC. Interpellé sans incident, véhicule laissé stationné légalement.',
        'Le {date}, {subject} a été reconnu par l\'unité alors qu\'il marchait sur {address}. Vérification : mandat actif pour défaut de comparution. Arrestation sans résistance, transport au centre de détention.' } },
    { id = 'collision', type = 'ptcr', n = 12, title = 'Accident de la circulation',
      text = {
        'Le {date} vers {time}, collision entre deux véhicules à l\'intersection du {address}. D\'après les déclarations et la position des véhicules, le véhicule 1 n\'a pas respecté la priorité. Dégâts matériels importants, un conducteur légèrement blessé transporté par les pompiers.',
        'Le {date}, le véhicule 1 circulait sur {road} lorsqu\'il a percuté l\'arrière du véhicule 2 arrêté dans la file. Chaussée mouillée, visibilité réduite. Aucun blessé grave. Les deux véhicules ont été dépannés.',
        'Le {date} à {time}, sortie de route d\'un véhicule seul dans un virage du {address}. Le conducteur déclare avoir évité un animal. Glissières endommagées, signalement transmis au service des routes.' } },
    { id = 'complaint', type = 'incident', n = 9, nature = { 'Plainte pour menaces', 'Plainte pour harcèlement téléphonique', 'Plainte pour escroquerie en ligne', 'Plainte pour dégradations', 'Plainte pour violation de domicile' },
      kw = { 'harass', 'mm3', 'trespass1', 'idtheft2', 'stalking' }, roles = { 'victim', 'suspect' },
      text = {
        'Le {date}, {victim} s\'est présenté(e) pour déposer plainte. Il/elle déclare recevoir depuis plusieurs semaines des messages menaçants d\'une personne qu\'il/elle identifie comme {subject}. Captures d\'écran recueillies. Enquête en cours, suspect non encore entendu.',
        'Le {date} vers {time}, {victim} signale que son véhicule stationné au {address} a été rayé sur toute la longueur et que deux pneus ont été crevés. Un voisin a vu une personne correspondant au signalement de {subject} quitter les lieux. Photos prises, plainte enregistrée.',
        'Le {date}, {victim} déclare avoir versé 1 800 $ pour la location d\'un appartement qui n\'existait pas. Les échanges et le reçu de virement ont été recueillis. Dossier transmis aux enquêteurs.' } },
    { id = 'theft', type = 'incident', n = 9, nature = { 'Vol à l\'étalage', 'Vol de véhicule', 'Cambriolage résidentiel', 'Vol dans un véhicule', 'Vol de vélo' },
      kw = { 'theft3', 'theft2', 'resburglary', 'tmv', 'prowl2' }, roles = { 'victim', 'witness' }, vehicles = true,
      text = {
        'Le {date} vers {time}, {victim} constate la disparition de son véhicule {model} ({plate}) stationné devant le {address}. Aucune trace de verre au sol. Véhicule inscrit au fichier des véhicules volés (WACIC).',
        'Le {date}, cambriolage au domicile de {victim}, {address}, pendant son absence (entre 8 h et 18 h). Porte-fenêtre forcée, bijoux, ordinateur portable et console de jeux dérobés. Relevés de traces effectués, voisinage interrogé.',
        'Le {date} à {time}, le gérant du magasin au {address} signale un vol à l\'étalage. Le suspect a pris la fuite en direction de {road}. Images de vidéosurveillance demandées.' } },
    { id = 'traffic_stop', type = 'noi', n = 10, title = 'Contrôle routier',
      text = {
        'Contrôle radar sur {road} le {date} à {time}. Le véhicule {model} ({plate}) circulait au-dessus de la limite autorisée. Conducteur coopératif, documents en règle.',
        'Le {date}, véhicule contrôlé au {address} pour un passage au feu rouge. Le conducteur reconnaît l\'infraction. Avis remis en main propre.' } },
    { id = 'warning', type = 'wwarning', n = 6, title = 'Contrôle routier — avertissement',
      text = { 'Contrôle le {date} à {time} sur {address} : équipement défectueux constaté. Avertissement écrit, réparation à effectuer sous 15 jours.',
        'Le {date}, conducteur arrêté sur {road} pour un changement de voie sans clignotant. Pas d\'antécédent, simple avertissement.' } },
    { id = 'citation', type = 'crimcite', n = 6, title = 'Conduite avec permis suspendu / délit',
      text = { 'Le {date} à {time}, contrôle du véhicule {model} ({plate}) sur {address}. Le permis du conducteur, {subject}, est suspendu (3e degré). Citation remise, convocation au tribunal ; véhicule confié à un passager titulaire du permis.',
        'Le {date}, {subject} a été surpris en train de dérober des articles dans un commerce du {address}. Objets restitués au magasin. Citation pour vol (3e degré) remise sur place.' } },
    { id = 'investigation', type = 'incident', n = 6, nature = { 'Enquête de voisinage', 'Personne disparue — enquête', 'Découverte d\'un véhicule abandonné', 'Enquête sur des coups de feu entendus' },
      roles = { 'caller', 'witness' },
      text = {
        'Le {date}, enquête de voisinage au {address} à la suite de plusieurs signalements de bruits de verre la nuit. Six riverains entendus ; un témoin décrit un véhicule sombre circulant lentement vers {time}. Patrouilles renforcées.',
        'Le {date} à {time}, signalement de la disparition de {victim}, vu(e) pour la dernière fois près du {address}. Description diffusée aux unités, hôpitaux contactés. Personne retrouvée saine et sauve deux jours plus tard chez une connaissance.',
        'Le {date}, plusieurs appels pour des détonations entendues près du {address}. Aucune victime ni impact découvert. Trois douilles récupérées sur un terrain vague et placées sous scellés.' } },
    { id = 'medical', type = 'incident', n = 6, nature = { 'Assistance médicale — malaise', 'Overdose présumée', 'Personne blessée — chute', 'Assistance aux secours — personne inconsciente' },
      roles = { 'victim', 'caller' },
      text = {
        'Le {date} vers {time}, appel pour une personne inconsciente sur le trottoir du {address}. {victim} respirait faiblement ; naloxone administrée par l\'unité, reprise de conscience. Prise en charge par les pompiers et transport vers {hospital}.',
        'Le {date}, assistance aux secours pour {victim}, victime d\'une chute dans un escalier au {address}. Sécurisation des lieux et contact avec la famille. Pas d\'élément suspect.',
        'Le {date} à {time}, {victim} a fait un malaise au volant sur un parking du {address}, sans collision. Premiers secours jusqu\'à l\'arrivée de l\'ambulance, véhicule laissé stationné.' } },
    { id = 'dv', type = 'incident', n = 4, dv = true, nature = { 'Violence conjugale', 'Dispute conjugale' }, roles = { 'victim', 'suspect' }, kw = { 'assault4', 'dvinterfere', 'harass' },
      text = { 'Le {date} à {time}, appel d\'un voisin pour des cris au {address}. {victim} présente une rougeur au bras et déclare avoir été saisi(e) violemment par {subject}. Les parties ont été séparées ; l\'auteur a quitté les lieux avant notre arrivée. Ordonnance de non-contact proposée.' } },
    { id = 'dui', type = 'dui', n = 4, title = 'Conduite sous influence',
      text = { 'Le {date} vers {time}, le véhicule {model} ({plate}) zigzaguait sur {road}. Le conducteur, {subject}, présentait une forte odeur d\'alcool et des yeux injectés de sang. Épreuves de sobriété échouées, arrestation pour DUI, test de souffle au poste.' } },
    { id = 'impound', type = 'impound', n = 4, title = 'Mise en fourrière',
      text = { 'Véhicule {model} ({plate}) stationné en double file au {address}, gênant la circulation depuis plus de deux heures. Propriétaire injoignable. Inventaire effectué, remorquage par le dépanneur agréé.' } },
}

-- Valeurs plausibles d'un champ de rapport, selon sa clé
local function personData(identity)
    if identity then
        return { lastname = identity.lastname, firstname = identity.firstname, dob = identity.dob,
            sex = identity.sex == 'F' and 'female' or 'male', homeAddress = identity.address, phone = identity.phone }
    end
    local sex = chance(0.55) and 'M' or 'F'
    local first, last = newName(sex)
    local dob = TODAY - (rnd(18, 74) * 365.25 + rnd(0, 360))
    return { lastname = last, firstname = first, dob = dateStr(dob), sex = sex == 'F' and 'female' or 'male',
        homeAddress = (newAddress()), phone = ('%d-%03d-%04d'):format(pick({ 206, 206, 425, 253 }), rnd(200, 999), rnd(0, 9999)) }
end

local function vehicleData(owner)
    return { plate = plate(), plateState = 'WA', model = pick(MAKES), color = pick(COLORS), year = rnd(2005, 2023),
        vin = vin(), owner = owner and (owner.firstname .. ' ' .. owner.lastname) or '', insurance = pick(INSURERS) .. ' — ' .. rnd(1000000, 9999999) }
end

local TEXT = {
    address = function(ctx) return ctx.address end, street = function(ctx) return ctx.street end,
    city = function(ctx) return ctx.city end, crossStreet = function() return pick(STREETS)[1] end,
    dlNumber = function() return wdl() end, dlState = function() return 'WA' end, plateState = function() return 'WA' end,
    nature = function(ctx) return ctx.nature end,
    agency = function(ctx) return ctx.officer[2] == 'WSP' and 'Washington State Patrol' or 'King County Sheriff\'s Office' end,
    towCompany = function() return pick(TOW) end, towDest = function() return 'Fourrière ' .. pick(TOW) end,
    custody = function() return ('B%07d'):format(rnd(1000000, 9999999)) end,
    warrantNo = function() return ('W%02d-%06d'):format(rnd(18, 25), rnd(100000, 999999)) end,
    height = function() return ('5\'%d"'):format(rnd(4, 11)) end, hair = function() return pick(HAIR) end,
    eyes = function() return pick(EYES) end, marks = function() return chance(0.4) and pick(MARKS) or '' end,
    name = function() local f, l = newName(chance(0.5) and 'M' or 'F') return f .. ' ' .. l end,
    company = function() return 'Cascade Freight LLC' end, usdot = function() return tostring(rnd(1000000, 3999999)) end,
    transportedTo = function() return chance(0.3) and pick(HOSPITALS) or '' end,
    milepost = function() return ('MP %d.%d'):format(rnd(1, 180), rnd(0, 9)) end,
    refDistance = function() return ('%d pieds au nord de la sortie %d'):format(rnd(100, 2000), rnd(1, 200)) end,
    pbt = function() return ('0.%03d'):format(rnd(85, 190)) end, brac1 = function() return ('0.%03d'):format(rnd(85, 170)) end,
    brac2 = function() return ('0.%03d'):format(rnd(85, 170)) end, bloodResult = function() return 'En attente du laboratoire' end,
    admission = function() return pick({ 'Deux bières', 'Trois verres de vin', 'Quelques cocktails', 'Refuse de répondre' }) end,
    holdReason = function() return 'Restitution uniquement sur autorisation de l\'enquêteur' end,
    insurance = function() return pick(INSURERS) end,
}

local function fillText(key, ctx, level)
    local p, v = level.person, level.vehicle or ctx.vehicle
    if p and p[key] then return p[key] end
    if v and v[key] then return tostring(v[key]) end
    local fn = TEXT[key]
    return fn and fn(ctx) or nil
end

local AREA_TEXT = {
    statement = { '« Je n\'ai rien vu venir, il est arrivé très vite. »', '« J\'étais chez moi quand j\'ai entendu du bruit. »',
        '« Je veux porter plainte. »', '« Ce n\'est pas moi, je passais juste par là. »', '« Je confirme ce que j\'ai déclaré aux agents. »' },
    evidence = { 'Photographies des lieux, vidéosurveillance demandée au commerçant.', 'Deux traces de semelles relevées, objet en verre placé sous scellés.',
        'Liste des biens dérobés fournie par la victime (estimation 2 400 $).', 'Aucun élément matériel exploitable.' },
    seized = { 'Tournevis, pied-de-biche, gants, sac à dos.', 'Téléphone portable, 120 $ en espèces.', 'Couteau pliant (lame 3 pouces).', 'Aucun objet saisi.' },
    inventory = { 'Siège de bébé, parapluie, sac de sport (vêtements).', 'Boîte à outils, gilet de sécurité, câbles de démarrage.', 'Rien de visible dans l\'habitacle.' },
    condition = { 'Rayures sur la portière avant gauche, pare-chocs arrière enfoncé.', 'Bon état général, pneu avant droit sous-gonflé.', 'Pare-brise fissuré, rétroviseur droit manquant.' },
    details = { 'Faits constatés par l\'agent.', 'Infraction relevée à l\'aide du radar laser étalonné.', 'Reconnaît les faits.' },
    forceDetails = { 'Clé de bras pour le menotter après refus d\'obtempérer, sans blessure.' },
    injuryDetails = { 'Égratignure au genou lors de la chute pendant la fuite, vue par les pompiers.' },
}

local function fillNum(f, key)
    local v = ({ weight = rnd(130, 260), year = rnd(2005, 2023), speedLimit = pick({ 25, 30, 35, 40, 45, 60, 70 }),
        counts = 1, fine = pick({ 136, 139, 216, 250, 336, 429, 549 }), injured = rnd(0, 2), killed = 0, lanes = rnd(2, 4),
        hgn = rnd(4, 6), ols = rnd(2, 4), wat = rnd(2, 6), damageCost = rnd(8, 120) * 100, estSpeed = rnd(20, 55) })[key]
    if key == 'speedRecorded' then v = 35 + rnd(10, 40) end
    if not v then v = f.min or 0 end
    if f.min and v < f.min then v = f.min end
    if f.max and v > f.max then v = f.max end
    return v
end

local function offenseFor(f, root, theme)
    local function ok(o)
        if f.lock and type(f.lock) == 'table' then
            local locked = (f.lock.map or {})[root[f.lock.k]]
            if locked and o.c ~= locked then return false end
        end
        if type(f.classes) == 'table' then
            for _, c in ipairs(f.classes) do if c == o.c then return true end end
            return false
        end
        return true
    end
    local preferred = {}
    for _, id in ipairs(theme.kw or {}) do
        local o = API.Offenses[id]
        if o and ok(o) then preferred[#preferred + 1] = o.id end
    end
    if #preferred > 0 and chance(0.85) then return pick(preferred) end
    local all = {}
    for _, o in ipairs(MDC_OFFENSES or {}) do if ok(o) then all[#all + 1] = o.id end end
    return #all > 0 and pick(all) or nil
end

local fillFields
local function listCount(f, theme)
    local key = f.k
    local n = ({ persons = #(theme.roles or { 'victim' }), vehicles = theme.vehicles and 1 or 0, charges = rnd(1, 2),
        offenses = theme.kw and 1 or 0, violations = 1, units = 2, occupants = rnd(0, 1) })[key] or (f.min or 0)
    return math.max(f.min or 0, math.min(f.max or 10, n))
end

fillFields = function(fields, raw, ctx, level, theme)
    for _, f in ipairs(fields) do
        if f.t == 'group' then
            fillFields(f.f, raw, ctx, level, theme)
        elseif f.t == 'list' then
            local items = {}
            for i = 1, listCount(f, theme) do
                local item = {}
                local sub = { person = nil, vehicle = nil }
                if f.k == 'persons' then
                    local role = (theme.roles or {})[i] or 'witness'
                    item.role = role
                    sub.person = role == 'suspect' and ctx.subject or (role == 'victim' and ctx.victim) or personData(nil)
                elseif f.k == 'units' then
                    sub.person = i == 1 and ctx.subject or personData(nil)
                    sub.vehicle = i == 1 and ctx.vehicle or vehicleData(sub.person)
                elseif f.k == 'vehicles' then
                    sub.vehicle = ctx.vehicle
                elseif f.k == 'occupants' then
                    sub.person = personData(nil)
                end
                fillFields(f.f, item, ctx, sub, theme)
                items[#items + 1] = item
            end
            raw[f.k] = items
        elseif f.t == 'matrix' then
            for _, item in ipairs(raw[f.list] or {}) do
                local options = {}
                for _, g in ipairs(f.groups or {}) do for _, o in ipairs(g.o or {}) do options[#options + 1] = o[1] end end
                item[f.k] = #options > 0 and { pick(options) } or {}
            end
        elseif f.t == 'perUnit' then
            for _, item in ipairs(raw[f.list] or {}) do fillFields(f.f, item, ctx, { person = nil }, theme) end
        elseif f.k and raw[f.k] == nil then
            local key = f.k
            if f.t == 'text' then
                if (key == 'lastname' or key == 'firstname' or key == 'homeAddress' or key == 'phone') and not level.person then
                    level.person = ctx.subject
                end
                raw[key] = fillText(key, ctx, level) or ((f.req or f.reqIf) and 'Voir exposé des faits' or '')
            elseif f.t == 'area' then
                if key == 'narrative' then raw[key] = ctx.narrative
                elseif key == 'statement' then raw[key] = pick(AREA_TEXT.statement)
                else raw[key] = AREA_TEXT[key] and pick(AREA_TEXT[key]) or ((f.req or f.reqIf) and ctx.narrative or '') end
            elseif f.t == 'date' then
                if key == 'dob' then
                    if not level.person then level.person = ctx.subject end
                    raw[key] = level.person.dob
                elseif key == 'appearDate' then raw[key] = dateStr(ctx.when + rnd(14, 45) * DAY)
                else raw[key] = dateStr(ctx.when) end
            elseif f.t == 'time' then
                raw[key] = key == 'time' and ctx.time or timeStr(ctx.minutes + rnd(5, 50))
            elseif f.t == 'num' then
                raw[key] = level.vehicle and key == 'year' and level.vehicle.year or fillNum(f, key)
            elseif f.t == 'select' then
                if key == 'sex' then
                    if not level.person then level.person = ctx.subject end
                    raw[key] = level.person.sex
                elseif f.o and #f.o > 0 then
                    raw[key] = f.o[rnd(1, #f.o)][1]
                end
            elseif f.t == 'check' then
                if f.req then raw[key] = true -- case obligatoire (certification…)
                elseif key == 'dv' then raw[key] = theme.dv == true
                else raw[key] = key == 'miranda' or chance(0.15) end
            elseif f.t == 'checks' then
                raw[key] = (f.o and #f.o > 0) and { f.o[rnd(1, #f.o)][1] } or {}
            elseif f.t == 'offense' then
                raw[key] = offenseFor(f, ctx.root, theme)
            end
        end
    end
end

local function fillTemplate(text, ctx)
    return (text:gsub('{(%w+)}', function(k)
        local v = ({ date = dateStr(ctx.when), time = ctx.time, address = ctx.address, road = ctx.road,
            subject = ctx.subject.firstname .. ' ' .. ctx.subject.lastname, victim = ctx.victim.firstname .. ' ' .. ctx.victim.lastname,
            plate = ctx.vehicle.plate, model = ctx.vehicle.model, hospital = pick(HOSPITALS) })[k]
        return v or ''
    end))
end

local function makeReport(theme, offenders)
    local reportType = API.ReportTypes[theme.type]
    if not reportType then return nil, 'type inconnu : ' .. theme.type end
    for attempt = 1, 8 do
        local whenT = TODAY - rnd(0, 150)
        local minutes = rnd(0, 1439)
        local address, street = newAddress()
        -- personne principale : parfois un inscrit au registre (le rapport apparaît dans ses antécédents)
        local subjectIdentity = (#offenders > 0 and chance(0.4)) and pick(offenders) or nil
        local ctx = {
            when = whenT, minutes = minutes, time = timeStr(minutes), address = address, street = street[1], city = street[2],
            road = pick(ROADS), officer = pick(OFFICERS), nature = theme.nature and pick(theme.nature) or theme.title,
            subject = personData(subjectIdentity), victim = personData(nil),
        }
        ctx.vehicle = vehicleData((theme.roles or {})[1] == 'victim' and ctx.victim or ctx.subject)
        ctx.narrative = fillTemplate(pick(theme.text), ctx)
        local raw = {}
        ctx.root = raw
        for _, section in ipairs(reportType.sections) do fillFields(section.f, raw, ctx, { person = nil }, theme) end
        local data, err = API.buildReport(reportType, raw)
        if data then
            local number
            for _ = 1, 50 do
                number = ('RD%d'):format(rnd(1000, 9999))
                if not (MDCDB and MDCDB.numberUsed and MDCDB.numberUsed(number)) then break end
            end
            if MDCDB and MDCDB.useNumber then MDCDB.useNumber(number) end
            return {
                type = reportType.id, data = data,
                call = { id = 0, session = 'demo', number = number, title = ctx.nature, kind = 'intervention' },
                summary = API.reportSummary(reportType, data), searchText = API.reportSearchText(data),
                createdAt = whenT * 86400 + minutes * 60, createdByName = ('%s (%s)'):format(ctx.officer[1], ctx.officer[2]),
                unitName = ctx.officer[3],
            }
        end
        if attempt == 8 then return nil, err end
    end
end

-- ---------------------------------------------------------------------------------------------------------------------
-- COMMANDES
-- ---------------------------------------------------------------------------------------------------------------------
local function demoCounts()
    local c = { identities = 0, sex = 0, kidnap = 0, reports = 0 }
    for _, r in ipairs(API.Store.identities) do
        if r.demo then
            c.identities = c.identities + 1
            for _, reg in ipairs(r.registrations or {}) do c[reg.type] = (c[reg.type] or 0) + 1 end
        end
    end
    for _, r in ipairs(API.Store.reports) do if r.demo then c.reports = c.reports + 1 end end
    return c
end

local function purge()
    local removed = 0
    for _, kind in ipairs({ 'identities', 'reports' }) do
        local kept = {}
        for _, r in ipairs(API.Store[kind]) do
            if r.demo then removed = removed + 1 else kept[#kept + 1] = r end
        end
        for i = #API.Store[kind], 1, -1 do API.Store[kind][i] = nil end
        for i, r in ipairs(kept) do API.Store[kind][i] = r end
        API.saveStore(kind)
    end
    return removed
end

local function seed()
    state = DEMO.seed
    local now = os.date('*t')
    TODAY = daysFromCivil(now.year, now.month, now.day)
    used = { names = {}, cases = {}, notes = {}, plates = {} }
    for _, r in ipairs(API.Store.identities) do -- jamais le même nom qu'une fiche existante
        used.names[(r.firstname or '') .. ' ' .. (r.lastname or '')] = true
    end
    local offenders = {}
    for _, kind in ipairs({ 'kidnap', 'sex' }) do
        local offenses = offensesOf(function(o) return o.reg == kind end)
        for _ = 1, DEMO[kind] do
            local record = makeOffender(kind, offenses)
            if record then
                record.id = API.NextId.identities
                API.NextId.identities = API.NextId.identities + 1
                local reg = record.registrations[1]
                record.createdAt = dayOf(reg.registeredDate) * 86400 + 10 * 3600
                record.updatedAt = math.max(record.createdAt, dayOf(reg.lastUpdate) * 86400 + 15 * 3600)
                record.createdByName = kind == 'sex' and 'KCSO — Sex Offender Unit' or 'WSP — Registre'
                record.updatedByName = record.createdByName
                record.createdBy = DEMO.author
                record.demo = true
                API.Store.identities[#API.Store.identities + 1] = record
                offenders[#offenders + 1] = record
            end
        end
    end
    API.saveStore('identities')

    -- rapports : thèmes répartis jusqu'au nombre voulu, du plus ancien au plus récent
    local plan = {}
    local total = 0
    for _, t in ipairs(THEMES) do total = total + t.n end
    for _, t in ipairs(THEMES) do
        for _ = 1, math.max(1, math.floor(t.n * DEMO.reports / total + 0.5)) do plan[#plan + 1] = t end
    end
    local reports, failures = {}, 0
    for _, theme in ipairs(plan) do
        local r, err = makeReport(theme, offenders)
        if r then reports[#reports + 1] = r
        else
            failures = failures + 1
            print(('^3[MDC demo]^0 rapport %s non créé : %s'):format(theme.id, tostring(err)))
        end
    end
    table.sort(reports, function(a, b) return a.createdAt < b.createdAt end)
    for i, r in ipairs(reports) do
        r.id = API.NextId.reports
        API.NextId.reports = API.NextId.reports + 1
        r.number = API.uniqueValue('reports', 'number', API.genCaseNumber)
        r.createdBy = DEMO.author
        r.demo = true
        table.insert(API.Store.reports, i, r) -- avant les rapports des joueurs : les listes restent chronologiques
    end
    API.saveStore('reports')
    return #offenders, #reports, failures
end

MDCDemo = { seed = seed, purge = purge, counts = demoCounts, config = DEMO } -- (tests)

RegisterCommand('mdc_demo', function(source, args)
    if source ~= 0 then return end -- console serveur uniquement
    if not API or not API.ready() then
        print('^1[MDC demo]^0 Base de données pas encore prête : réessayez dans quelques secondes.')
        return
    end
    local action = (args[1] or 'status'):lower()
    local c = demoCounts()
    if action == 'status' then
        print(('^5[MDC demo]^0 %d identité(s) de démonstration (%d Sex Offenders, %d Kidnapping Offenders), %d rapport(s).')
            :format(c.identities, c.sex or 0, c.kidnap or 0, c.reports))
    elseif action == 'seed' or action == 'regen' then
        if action == 'seed' and (c.identities > 0 or c.reports > 0) then
            print('^3[MDC demo]^0 Des données de démonstration existent déjà : « mdc_demo regen » pour les recréer, « mdc_demo purge » pour les retirer.')
            return
        end
        if action == 'regen' then print(('^5[MDC demo]^0 %d fiche(s) de démonstration supprimée(s).'):format(purge())) end
        local ids, reps, failures = seed()
        print(('^5[MDC demo]^0 Créé : %d identité(s) inscrite(s) au registre, %d rapport(s)%s. Retirer : « mdc_demo purge ».')
            :format(ids, reps, failures > 0 and (' (%d échec(s), voir ci-dessus)'):format(failures) or ''))
    elseif action == 'purge' then
        print(('^5[MDC demo]^0 %d fiche(s) de démonstration supprimée(s) (fiches des joueurs intactes).'):format(purge()))
    else
        print('^3[MDC demo]^0 Usage : mdc_demo status | seed | purge | regen')
    end
end, true)
