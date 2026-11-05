--[[
    MDC Standalone - Modèles des RAPPORTS (onglet "Rapports")
    ---------------------------------------------------------
    Formulaires de l'État de Washington (WSP / KCSO) : Notice of Infraction, Criminal Citation and Notice to Appear,
    Written Warning, Arrest Report, DUI Arrest Report, Police Traffic Collision Report (PTCR), Incident Report,
    Vehicle Impound / Inventory Report. Infractions et classifications : server/offenses.lua (RCW).
    Ce fichier décrit les formulaires. Il sert à la fois :
      - à l'interface (envoyé au NUI, qui construit les formulaires et les fiches),
      - au serveur (server.lua valide chaque rapport reçu avec ces mêmes règles).
    Pour ajouter un champ ou une option, modifiez UNIQUEMENT ce fichier.
    Chaque rapport est en plus lié à une intervention / un incident (choisi en première
    ligne du formulaire) : ce lien est géré par server.lua, il n'a pas à figurer ici.
    ⚠ Deux champs d'un même niveau ne doivent jamais avoir la même clé (k) : les
      groupes ne créent pas de niveau, seules les listes en créent un (le serveur
      signale les doublons dans la console au démarrage).
    ⚠ Ne changez pas la clé (k / valeur d'option) d'un champ déjà utilisé :
      les rapports déjà enregistrés ne l'afficheraient plus.

    Champ : { k = clé, t = type, l = libellé, ... }
      t = 'text'   texte court       (max, upper = majuscules, ph = exemple)
          'area'   texte long        (max, rows)
          'date'   JJ/MM/AAAA        (def = 'today', past = true : jamais dans le futur)
          'time'   HH:MM             (def = 'now')
          'num'    nombre entier     (min, max, unit = unité affichée, money = montant en $)
          'select' liste             (o = { { valeur, libellé }, ... })
          'check'  case à cocher
          'checks' plusieurs cases   (o = { { valeur, libellé }, ... })
          'group'  sous-case         (f = champs ; les données restent au même niveau)
          'list'   liste répétable   (f = champs, item = nom d'un élément, add = bouton, min, max)
          'lookup' remplissage depuis l'historique de l'onglet "Recherches" : une liste déroulante
                   s'ouvre sur le champ "nom de famille" (kind = 'identity') ou "immatriculation"
                   (kind = 'vehicle') et remplit les champs indiqués
                   (map = { champ_du_rapport = champ_de_la_fiche }, aucune donnée enregistrée)
          'note'   texte d'aide (aucune donnée)
          'matrix' tableau de cases par "Unit" (list = liste source, k = clé, groups = { { l, o } })
          'perUnit' tableau de champs par "Unit" (list = liste source, f = champs)
          'offclass' CLASSIFICATION d'une infraction (Traffic Infraction, Misdemeanor, Felony… : server/offenses.lua) ;
                   classes = classifications proposées (MDC_CLASS_SETS)
          'offense' INFRACTION du catalogue (server/offenses.lua), liste déroulante classée par catégorie ;
                   classKey = clé du champ 'offclass' du même niveau : choisir l'infraction règle la classification,
                   choisir d'abord la classification ne propose que ses infractions ; fineKey = clé du montant
                   rempli automatiquement (pénalité du barème, modifiable)
      ph    = texte                   exemple affiché dans un champ vide (texte d'aide pour 'checks')
      def   = valeur par défaut       ('today', 'now', 'unitAgency' = police de l'unité du joueur, ou une valeur)
      req   = true                    champ obligatoire (uniquement s'il est visible)
      reqIf = { condition }           obligatoire si la condition est vraie
      show  = { condition }           visible seulement si la condition est vraie
      w     = 1..4                    largeur (colonnes sur 4)
    Modèle : archived = true -> plus de nouveaux rapports de ce type (les anciens restent lisibles)
      Condition : { k = clé, eq = valeur } | { k = clé, ['in'] = { valeurs } }
                | { k = clé, any = { ... } } | { k = clé, none = { ... } }   (any / none : cases multiples)
    Section : { title, f = champs, show = { condition } } -> section entière masquée si la condition est fausse
]]

-- -------------------------------------------------------------------------
-- Listes communes
-- -------------------------------------------------------------------------
-- Toutes les classes délivrées par les États de server.lua (LICENSE_STATES)
local LICENSE_CLASSES = {
    { 'N/A', 'Aucune' },
    { 'Class C - Standard', 'Class C - Standard' },
    { 'Class D - Standard', 'Class D - Standard' },
    { 'Class E - Standard', 'Class E - Standard' },
    { 'Class E - Combiné', 'Class E - Combiné' },
    { 'Class F - Lourd', 'Class F - Lourd' },
    { 'Class M - Moto', 'Class M - Moto' },
    { 'Class G - Cyclomoteur', 'Class G - Cyclomoteur' },
    { 'CDL A', 'CDL A' },
    { 'CDL B', 'CDL B' },
    { 'CDL C', 'CDL C' },
    { 'Probatoire - Class CP', 'Probatoire - Class CP' },
    { 'Probatoire - Class D', 'Probatoire - Class D' },
    { 'Probatoire - Class MP', 'Probatoire - Class MP' },
}

local SEXES = { { 'male', '(M) Male' }, { 'female', '(F) Female' } }

local VEHICLE_TYPES = {
    { 'sedan', 'Berline' }, { 'suv', 'SUV' }, { 'coupe', 'Coupé' }, { 'hatchback', 'Citadine / compacte' },
    { 'wagon', 'Break' }, { 'pickup', 'Pick-up' }, { 'van', 'Van / minibus' }, { 'moto', 'Moto' },
    { 'truck', 'Camion' }, { 'semi', 'Tracteur routier' }, { 'bus', 'Bus' }, { 'other', 'Autre' },
}

-- Champs "date / heure / lieu" communs à tous les rapports
local function whenWhere()
    return {
        { k = 'date', t = 'date', l = 'Date', req = true, def = 'today', past = true },
        { k = 'time', t = 'time', l = 'Horaire', req = true, def = 'now' },
        { k = 'address', t = 'text', l = 'Adresse', req = true, max = 80, w = 2 },
        { k = 'block', t = 'text', l = 'Bloc', max = 40 },
    }
end

-- Personne : nom, prénom, DoB (+ domicile, licence), remplissable depuis l'historique des recherches.
-- Le domicile a sa propre clé (homeAddress) : "address" est l'adresse du lieu (whenWhere).
local function person(opts)
    opts = opts or {}
    local fields = {
        { t = 'lookup', kind = 'identity',
          map = { lastname = 'lastname', firstname = 'firstname', dob = 'dob', sex = 'sexReport', homeAddress = 'address',
                  dlNumber = 'licenseNumber', dlClass = 'licenseClass', dlState = 'licenseState' } },
        { k = 'lastname', t = 'text', l = 'Nom de famille', req = opts.req, reqIf = opts.reqIf, max = 40 },
        { k = 'firstname', t = 'text', l = 'Prénom', req = opts.req, max = 40 },
        { k = 'dob', t = 'date', l = 'Date de naissance', req = opts.req, past = true },
        { k = 'sex', t = 'select', l = 'Sexe', o = SEXES },
        { k = 'homeAddress', t = 'text', l = 'Domicile', max = 80, w = 2 },
    }
    if opts.license then
        -- licenseShow : condition d'affichage ; licenseReq : licence obligatoire (quand affichée)
        local show, req = opts.licenseShow, opts.licenseReq
        fields[#fields + 1] = { k = 'dlNumber', t = 'text', l = 'N° de licence (DL)', max = 20, upper = true, show = show, req = req }
        fields[#fields + 1] = { k = 'dlClass', t = 'select', l = 'Classe', o = LICENSE_CLASSES, show = show, req = req }
        fields[#fields + 1] = { k = 'dlState', t = 'text', l = 'État d\'émission (DL)', max = 40, show = show, req = req }
        if opts.restrictions then
            fields[#fields + 1] = { k = 'dlRestrictions', t = 'text', l = 'Restrictions (DL)', max = 80, ph = 'ex : verres correcteurs' }
        end
    end
    return fields
end

-- Véhicule : remplissable depuis l'historique des recherches (par immatriculation)
local function vehicle(opts)
    opts = opts or {}
    return {
        { t = 'lookup', kind = 'vehicle',
          map = { plate = 'plate', model = 'makeModel', color = 'color', owner = 'ownerFull', vin = 'vin', year = 'year', insurance = 'insurance' } },
        { k = 'plate', t = 'text', l = 'Immatriculation', req = opts.req, max = 8, upper = true },
        { k = 'plateState', t = 'text', l = 'État (plaque)', max = 40 },
        { k = 'model', t = 'text', l = 'Marque / modèle', max = 60 },
        { k = 'color', t = 'text', l = 'Couleur', max = 40 },
        { k = 'owner', t = 'text', l = 'Propriétaire', max = 80, w = 2 },
    }
end

-- Infractions (Citation, Traffic Citation, Convocation, Warning) : intitulé, case "Infraction"
-- pour détailler l'infraction commise, et l'amende pour les citations.
local function violations(withFine)
    local fields = { { k = 'offense', t = 'text', l = 'Intitulé de l\'infraction', req = true, max = 120, w = withFine and 3 or 4 } }
    if withFine then fields[2] = { k = 'fine', t = 'num', l = 'Amende', min = 0, max = 1000000, money = true } end
    fields[#fields + 1] = { k = 'details', t = 'area', l = 'Infraction (détail de l\'infraction commise)', max = 1500, rows = 3, w = 4 }
    return { k = 'violations', t = 'list', l = 'Infractions', item = 'Infraction', add = '+ Ajouter une infraction',
             min = 1, max = 15, f = fields }
end

local function narrative(label, req)
    return { k = 'narrative', t = 'area', l = label or 'Rapport narratif', req = req ~= false, max = 6000, rows = 10, w = 4 }
end

-- -------------------------------------------------------------------------
-- DOT-523 : listes propres au rapport d'accident
-- -------------------------------------------------------------------------
local VEHICLE_ISH = { k = 'types', any = { 'vehicle', 'hit_run', 'commercial' } } -- l'unit a un véhicule
local COMMERCIAL = { k = 'types', any = { 'commercial' } }

local DOT523 = {
    id = 'dot523',
    archived = true, -- ancien modèle (Géorgie) : remplacé par le Police Traffic Collision Report (PTCR)
    label = 'DOT-523 — Georgia Uniform Crash Report',
    short = 'DOT-523',
    button = 'DOT-523 (Crash Report)', -- texte du bouton (sinon : label)
    summary = '{street} {crossStreet} — {#units} unit(s)',
    sections = {
        {
            title = '0 - Amorce',
            f = {
                { k = 'date', t = 'date', l = 'Date', req = true, def = 'today', past = true },
                { k = 'time', t = 'time', l = 'Horaire', req = true, def = 'now' },
                { k = 'weather', t = 'select', l = 'Conditions météorologiques', req = true, o = {
                    { 'clear', 'Clair' }, { 'cloudy', 'Nuageux' }, { 'rain', 'Pluie' }, { 'fog', 'Brouillard' },
                    { 'snow', 'Neige' }, { 'sleet', 'Grésil / verglas' }, { 'wind', 'Vents violents' }, { 'smoke', 'Fumée / poussière' },
                } },
                { k = 'light', t = 'select', l = 'Luminosité', o = {
                    { 'day', 'Jour' }, { 'dawn', 'Aube' }, { 'dusk', 'Crépuscule' },
                    { 'night_lit', 'Nuit (route éclairée)' }, { 'night_dark', 'Nuit (route non éclairée)' },
                } },
                { k = 'surface', t = 'select', l = 'État de la chaussée', o = {
                    { 'dry', 'Sèche' }, { 'wet', 'Mouillée' }, { 'snow', 'Neige' }, { 'ice', 'Glace / verglas' },
                    { 'gravel', 'Boue / gravier' }, { 'oil', 'Huile / débris' },
                } },
                { k = 'county', t = 'text', l = 'Comté', req = true, max = 60, ph = 'ex : Los Santos County' },
                { k = 'agency', t = 'text', l = 'Service de police', req = true, max = 80, w = 2, def = 'unitAgency', ph = 'ex : Washington State Patrol' },
                { k = 'policeUnits', t = 'num', l = 'Nb d\'unités de police', req = true, min = 1, max = 50, def = 1 },
            },
        },
        {
            title = '1 - Impliqués',
            f = {
                { k = 'units', t = 'list', l = 'Units impliquées', item = 'Unit', add = '+ Ajouter une unit', min = 1, max = 10, f = {
                    { t = 'group', l = 'A) Type d\'entité', f = {
                        { k = 'types', t = 'checks', l = 'Type', ph = 'cochez tout ce qui s\'applique', req = true, w = 4, o = {
                            { 'vehicle', 'Véhicule' }, { 'pedestrian', 'Piéton' }, { 'hit_run', 'H&R (délit de fuite)' }, { 'commercial', 'Commercial' },
                        } },
                    } },
                    { t = 'group', l = 'B) Conducteur / piéton — identité et licence', f = {
                        { t = 'lookup', kind = 'identity',
                          map = { lastname = 'lastname', firstname = 'firstname', dob = 'dob', sex = 'sexReport', address = 'address',
                                  dlNumber = 'licenseNumber', dlClass = 'licenseClass', dlState = 'licenseState' } },
                        { k = 'lastname', t = 'text', l = 'Nom de famille', max = 40, reqIf = { k = 'types', none = { 'hit_run' } } },
                        { k = 'firstname', t = 'text', l = 'Prénom', max = 40 },
                        { k = 'dob', t = 'date', l = 'Date de naissance', past = true },
                        { k = 'sex', t = 'select', l = 'Sexe', o = SEXES },
                        { k = 'address', t = 'text', l = 'Adresse', max = 80, w = 2 },
                        { k = 'injury', t = 'select', l = 'Blessures', o = {
                            { 'none', 'Aucune' }, { 'possible', 'Possibles' }, { 'minor', 'Légères' }, { 'serious', 'Graves' }, { 'fatal', 'Mortelles' },
                        } },
                        { k = 'dlNumber', t = 'text', l = 'N° de licence (DL)', max = 20, upper = true },
                        { k = 'dlClass', t = 'select', l = 'Classe', o = LICENSE_CLASSES },
                        { k = 'dlState', t = 'text', l = 'État (DL)', max = 40 },
                        { k = 'dlRestrictions', t = 'text', l = 'Restrictions (DL)', max = 80, w = 2, ph = 'ex : verres correcteurs' },
                    } },
                    { t = 'group', l = 'C) DWI (conduite sous influence)', f = {
                        { t = 'note', l = 'Véhicule commercial : les tests DWI et leurs résultats sont obligatoires.', show = COMMERCIAL },
                        { k = 'dwiSuspected', t = 'check', l = 'Suspicion de DWI' },
                        { k = 'dwiTested', t = 'check', l = 'Tests DWI effectués', reqIf = COMMERCIAL },
                        { k = 'dwiResult', t = 'select', l = 'Résultat des tests', req = true, show = { k = 'dwiTested', eq = true }, w = 2, o = {
                            { 'alcpos_drgpos', 'Alc. Pos. / Drg. Pos.' }, { 'alcneg_drgneg', 'Alc. Neg. / Drg. Neg.' },
                            { 'alcpos_drgneg', 'Alc. Pos. / Drg. Neg.' }, { 'alcneg_drgpos', 'Alc. Neg. / Drg. Pos.' },
                        } },
                        { k = 'dwiSeized', t = 'check', l = 'Véhicule saisi (DWI)', show = VEHICLE_ISH },
                    } },
                    { k = 'occupants', t = 'list', l = 'D) Occupants', item = 'Occupant', add = '+ Ajouter un occupant', min = 0, max = 8,
                      show = VEHICLE_ISH, f = {
                        { k = 'name', t = 'text', l = 'Nom complet', req = true, max = 80, w = 2 },
                        { k = 'dob', t = 'date', l = 'Date de naissance', past = true },
                        { k = 'seat', t = 'select', l = 'Place', o = {
                            { 'front', 'Passager avant' }, { 'rear_left', 'Arrière gauche' }, { 'rear_center', 'Arrière centre' },
                            { 'rear_right', 'Arrière droit' }, { 'other', 'Autre' },
                        } },
                        { k = 'injury', t = 'select', l = 'Blessures', o = {
                            { 'none', 'Aucune' }, { 'possible', 'Possibles' }, { 'minor', 'Légères' }, { 'serious', 'Graves' }, { 'fatal', 'Mortelles' },
                        } },
                    } },
                    { t = 'group', l = 'E) Véhicule', show = VEHICLE_ISH, f = {
                        { t = 'lookup', kind = 'vehicle',
                          map = { plate = 'plate', vin = 'vin', model = 'makeModel', year = 'year', owner = 'ownerFull', insurance = 'insurance' } },
                        { k = 'owner', t = 'text', l = 'Propriétaire', max = 80, w = 2 },
                        { k = 'plate', t = 'text', l = 'Immatriculation', max = 8, upper = true },
                        { k = 'plateState', t = 'text', l = 'État (plaque)', max = 40 },
                        { k = 'vin', t = 'text', l = 'VIN', max = 17, upper = true },
                        { k = 'model', t = 'text', l = 'Marque / modèle', max = 60 },
                        { k = 'year', t = 'num', l = 'Année', min = 1900, max = 2100 },
                        { k = 'vehType', t = 'select', l = 'Type', o = VEHICLE_TYPES },
                        { k = 'insurance', t = 'text', l = 'Assurance', max = 80, w = 2, ph = 'Compagnie, n° de police, statut' },
                        { k = 'damage', t = 'select', l = 'Dégâts estimés', o = {
                            { 'none', 'Aucun' }, { 'minor', 'Mineurs' }, { 'functional', 'Fonctionnels' },
                            { 'disabling', 'Invalidants (remorquage)' }, { 'destroyed', 'Détruit' },
                        } },
                        { k = 'damageCost', t = 'num', l = 'Coût estimé des dégâts', min = 0, max = 10000000, money = true },
                    } },
                    { t = 'group', l = 'F) Véhicule commercial (CDL)', show = COMMERCIAL, f = {
                        { k = 'company', t = 'text', l = 'Compagnie', req = true, max = 80, w = 2 },
                        { k = 'companyAddress', t = 'text', l = 'Adresse de la compagnie', max = 120, w = 2 },
                        { k = 'usdot', t = 'text', l = 'USDOT (identifiant fédéral)', req = true, max = 10, ph = 'ex : 1234567' },
                        { k = 'cmvType', t = 'select', l = 'Type d\'unité', req = true, w = 2, o = {
                            { 'single', 'Simple (2/3 essieux)' }, { 'bobtail', 'Tracteur seul (bobtail)' },
                            { 'semi', 'Tracteur + semi-remorque' }, { 'multi', 'Tracteur + semi avec 2/3 remorques' },
                        } },
                        { k = 'cargo', t = 'select', l = 'Cargo Body Type', req = true, o = {
                            { 'van', 'Remorque classique' }, { 'flatbed', 'Plateau' }, { 'dump', 'Benne' },
                            { 'tank', 'Citerne' }, { 'auto', 'Auto-transporteur (voitures)' },
                        } },
                        { k = 'weight', t = 'num', l = 'Poids prévu du véhicule', min = 0, max = 500000, unit = 'lbs' },
                        { k = 'overweight', t = 'check', l = 'Suspicion de surcharge' },
                        { k = 'hazmat', t = 'check', l = 'Transport de matières dangereuses' },
                        { t = 'note', l = 'Surcharge suspectée : appelez la MCE (Motor Carrier Enforcement).', show = { k = 'overweight', eq = true } },
                    } },
                } },
            },
        },
        {
            title = '2 - Type de collision et conditions',
            f = {
                { t = 'group', l = 'A) Lieu précis de l\'accident', f = {
                    { k = 'street', t = 'text', l = 'Rue', req = true, max = 80, w = 2 },
                    { k = 'crossStreet', t = 'text', l = 'Croisement', max = 80, w = 2 },
                    { k = 'block', t = 'text', l = 'Bloc', max = 40 },
                    { k = 'direction', t = 'select', l = 'Direction', o = {
                        { 'N', 'Nord' }, { 'S', 'Sud' }, { 'E', 'Est' }, { 'W', 'Ouest' },
                        { 'NE', 'Nord-Est' }, { 'NW', 'Nord-Ouest' }, { 'SE', 'Sud-Est' }, { 'SW', 'Sud-Ouest' },
                    } },
                } },
                { k = 'causes', t = 'matrix', list = 'units', l = 'B) Le crash a été causé par (cochez toutes les possibilités pour chaque unit)', groups = {
                    { l = 'Manœuvre / action du véhicule', o = {
                        { 'speeding', 'Excès de vitesse' }, { 'fty', 'Refus de priorité' }, { 'signal', 'Non-respect d\'un feu / stop' },
                        { 'lane', 'Changement de voie dangereux' }, { 'following', 'Distance de sécurité insuffisante' },
                        { 'turn', 'Virage / demi-tour illégal' }, { 'wrongway', 'Circulation à contresens' },
                        { 'reckless', 'Conduite imprudente / agressive' }, { 'distracted', 'Inattention / téléphone' },
                        { 'lostcontrol', 'Perte de contrôle' }, { 'backing', 'Marche arrière dangereuse' }, { 'dui', 'Conduite sous influence' },
                    } },
                    { l = 'Action d\'un piéton', o = {
                        { 'ped_crossing', 'Traversée hors passage piéton' }, { 'ped_signal', 'Non-respect du signal piéton' },
                        { 'ped_road', 'Présence sur la chaussée' }, { 'ped_dart', 'Irruption soudaine' }, { 'ped_dui', 'Piéton sous influence' },
                    } },
                    { l = 'Encastrement', o = {
                        { 'underride', 'Encastrement sous le véhicule (underride)' }, { 'override', 'Passage par-dessus le véhicule (override)' },
                    } },
                    { l = 'Défaut du véhicule', o = {
                        { 'brakes', 'Freins' }, { 'tires', 'Pneus' }, { 'steering', 'Direction' }, { 'lights', 'Éclairage / feux' },
                        { 'coupling', 'Attelage / remorque' }, { 'load', 'Chargement mal arrimé' }, { 'defect_other', 'Autre défaut' },
                    } },
                } },
                { t = 'perUnit', list = 'units', l = 'C) Informations véhicules', f = {
                    { k = 'speedLimit', t = 'num', l = 'Vitesse autorisée', min = 0, max = 200, unit = 'mph', show = VEHICLE_ISH },
                    { k = 'speedInitial', t = 'num', l = 'Vitesse initiale estimée', min = 0, max = 300, unit = 'mph', show = VEHICLE_ISH },
                    { k = 'skid', t = 'num', l = 'Traces de pneus avant l\'impact', min = 0, max = 5000, unit = 'ft', show = VEHICLE_ISH },
                    { k = 'speedImpact', t = 'num', l = 'Vitesse estimée à l\'impact', min = 0, max = 300, unit = 'mph', show = VEHICLE_ISH },
                    { k = 'afterImpact', t = 'num', l = 'Distance parcourue après l\'impact', min = 0, max = 5000, unit = 'ft', show = VEHICLE_ISH },
                    { k = 'fire', t = 'check', l = 'Incendie', show = VEHICLE_ISH },
                } },
                { t = 'group', l = 'D) Informations sur le lieu', f = {
                    { k = 'workZone', t = 'select', l = 'Zone de travaux', o = {
                        { 'no', 'Non' }, { 'workers', 'Oui — ouvriers présents' }, { 'noworkers', 'Oui — sans ouvriers' },
                    } },
                    { k = 'roadType', t = 'select', l = 'Type de route', w = 2, o = {
                        { 'interstate', 'Interstate / autoroute' }, { 'us_highway', 'US Highway' }, { 'state_route', 'Route d\'État' },
                        { 'county_road', 'Route de comté' }, { 'city_street', 'Rue (agglomération)' },
                        { 'private', 'Route privée / parking' }, { 'dirt', 'Chemin non goudronné' },
                    } },
                    { k = 'lanes', t = 'num', l = 'Nombre de voies', min = 1, max = 12 },
                } },
            },
        },
        {
            title = '3 - Partie narrative',
            f = { narrative('Explication détaillée de l\'accident et de ses conditions') },
        },
    },
}

-- -------------------------------------------------------------------------
-- Autres rapports
-- -------------------------------------------------------------------------
local CITATION = {
    id = 'citation',
    archived = true, -- ancien modèle : remplacé par les formulaires de l'État de Washington
    label = 'Citation',
    short = 'Citation',
    summary = '{lastname} {firstname} — {#violations} infraction(s)',
    sections = {
        { title = 'Informations générales', f = whenWhere() },
        { title = 'Contrevenant', f = person({ req = true }) },
        { title = 'Infractions', f = { violations(true) } },
        { title = 'Comparution', f = {
            { k = 'courtDate', t = 'date', l = 'Date de comparution' },
            { k = 'court', t = 'text', l = 'Tribunal', max = 80, w = 2 },
            { k = 'refused', t = 'check', l = 'Refus de signer' },
        } },
        { title = 'Notes', f = { narrative('Notes de l\'agent', false) } },
    },
}

local TRAFFIC = {
    id = 'traffic', -- ancien "Traffic Ticket" : même clé, les rapports déjà rédigés restent lisibles
    archived = true, -- ancien modèle : remplacé par les formulaires de l'État de Washington
    label = 'Traffic Citation',
    short = 'Traffic Citation',
    summary = '{plate} — {lastname} {firstname}',
    sections = {
        { title = 'Informations générales', f = whenWhere() },
        { title = 'Conducteur', f = person({ req = true, license = true }) },
        { title = 'Véhicule', f = vehicle({ req = true }) },
        { title = 'Vitesse (si applicable)', f = {
            { k = 'speedLimit', t = 'num', l = 'Vitesse autorisée', min = 0, max = 200, unit = 'mph' },
            { k = 'speedRecorded', t = 'num', l = 'Vitesse relevée', min = 0, max = 300, unit = 'mph' },
            { k = 'speedMethod', t = 'select', l = 'Méthode', o = {
                { 'radar', 'Radar' }, { 'lidar', 'Lidar' }, { 'pacing', 'Pacing (suivi)' }, { 'visual', 'Estimation visuelle' },
            } },
        } },
        { title = 'Infractions', f = {
            { k = 'violations', t = 'list', l = 'Infractions', item = 'Infraction', add = '+ Ajouter une infraction', min = 1, max = 15, f = {
                { k = 'category', t = 'select', l = 'Type d\'infraction', req = true, o = {
                    { 'speeding', 'Excès de vitesse' }, { 'driving', 'Conduite' }, { 'control', 'Contrôle' },
                } },
                { k = 'offense', t = 'text', l = 'Intitulé de l\'infraction', req = true, max = 120, w = 3 },
                { k = 'details', t = 'area', l = 'Description de l\'infraction', max = 1500, rows = 3, w = 4 },
            } },
        } },
        { title = 'Comparution', f = {
            { k = 'courtDate', t = 'date', l = 'Date de comparution' },
            { k = 'court', t = 'text', l = 'Tribunal', max = 80, w = 2 },
        } },
        { title = 'Notes', f = { narrative('Notes de l\'agent', false) } },
    },
}

local CONVOCATION = {
    id = 'convocation',
    archived = true, -- ancien modèle : remplacé par les formulaires de l'État de Washington
    label = 'Convocation',
    short = 'Convocation',
    summary = '{lastname} {firstname} — {summonsDate}',
    sections = {
        { title = 'Informations générales', f = whenWhere() },
        { title = 'Personne convoquée', f = person({ req = true, license = true }) },
        { title = 'Infractions', f = { violations(false) } },
        { title = 'Convocation', f = {
            { k = 'summonsDate', t = 'date', l = 'Date de la convocation', req = true },
            { k = 'summonsTime', t = 'time', l = 'Heure', req = true },
            { k = 'summonsPlace', t = 'text', l = 'Lieu (tribunal, poste…)', req = true, max = 80, w = 2 },
            { k = 'refused', t = 'check', l = 'Refus de signer' },
        } },
        { title = 'Notes', f = { narrative('Notes de l\'agent', false) } },
    },
}

-- Ancien modèle, retiré : on ne peut plus en créer, les rapports existants restent lisibles
local TICKET = {
    id = 'ticket',
    archived = true,
    label = 'Ticket',
    short = 'Ticket',
    summary = '{plate} — {address}',
    sections = {
        { title = 'Informations générales', f = whenWhere() },
        { title = 'Véhicule', f = vehicle({ req = true }) },
        { title = 'Infractions', f = { violations(true) } },
        { title = 'Paiement', f = {
            { k = 'dueDate', t = 'date', l = 'Date limite de paiement' },
        } },
        { title = 'Notes', f = { narrative('Notes de l\'agent', false) } },
    },
}

-- Warning : "Infraction routière" -> identité complète avec licence + véhicule obligatoire ;
--           "Autre infraction"     -> identité seule. Puis l'intitulé et le détail.
local WARNING_ROAD = { k = 'category', eq = 'road' }
local WARNING_CHOSEN = { k = 'category', ['in'] = { 'road', 'other' } }

local WARNING = {
    id = 'warning',
    archived = true, -- ancien modèle : remplacé par les formulaires de l'État de Washington
    label = 'Warning',
    short = 'Warning',
    summary = '{lastname} {firstname} — {category}',
    sections = {
        { title = 'Informations générales', f = (function()
            local fields = whenWhere()
            fields[#fields + 1] = { k = 'category', t = 'select', l = 'Type d\'infraction', req = true, w = 2, o = {
                { 'road', 'Infraction routière' }, { 'other', 'Autre infraction' },
            } }
            return fields
        end)() },
        { title = 'Personne avertie', show = WARNING_CHOSEN,
          f = person({ req = true, license = true, licenseShow = WARNING_ROAD, licenseReq = true }) },
        { title = 'Véhicule', show = WARNING_ROAD, f = vehicle({ req = true }) },
        { title = 'Infraction', show = WARNING_CHOSEN, f = { violations(false) } },
        { title = 'Notes', f = { narrative('Notes de l\'agent', false) } },
    },
}

-- Ordre d'affichage dans l'onglet "Rapports" (archived = true : lecture seule, absent des boutons)
-- (modèles de l'État de Washington : plus bas, après les anciens modèles)
-- =========================================================================
-- FORMULAIRES DE L'ÉTAT DE WASHINGTON (WSP / KCSO)
-- Intitulés et termes officiels (Washington Uniform Court Docket, SECTOR, RCW) ; aides en français.
-- =========================================================================
local CLASS_SETS = MDC_CLASS_SETS or {}

local WA_SEXES = { { 'male', 'M — Homme' }, { 'female', 'F — Femme' }, { 'x', 'X — Non précisé' } }

local WA_COUNTIES = {
    { 'king', 'King County' }, { 'pierce', 'Pierce County' }, { 'snohomish', 'Snohomish County' },
    { 'kitsap', 'Kitsap County' }, { 'thurston', 'Thurston County' }, { 'spokane', 'Spokane County' },
    { 'clark', 'Clark County' }, { 'whatcom', 'Whatcom County' }, { 'skagit', 'Skagit County' },
    { 'yakima', 'Yakima County' }, { 'other', 'Autre comté' },
}

local WA_COURTS = {
    { 'kcdc_sea', 'King County District Court — Seattle (King County Courthouse)' },
    { 'kcdc_bel', 'King County District Court — Bellevue' },
    { 'kcdc_bur', 'King County District Court — Burien' },
    { 'kcdc_iss', 'King County District Court — Issaquah' },
    { 'kcdc_rjc', 'King County District Court — Kent (Maleng Regional Justice Center)' },
    { 'kcdc_red', 'King County District Court — Redmond' },
    { 'kcdc_sho', 'King County District Court — Shoreline' },
    { 'smc', 'Seattle Municipal Court' },
    { 'kcsc', 'King County Superior Court' },
    { 'pcdc', 'Pierce County District Court' },
    { 'sncdc', 'Snohomish County District Court' },
    { 'other', 'Autre tribunal' },
}

local WA_JAILS = {
    { 'kccf', 'King County Correctional Facility (KCCF) — Seattle' },
    { 'mrjc', 'Maleng Regional Justice Center (MRJC) — Kent' },
    { 'score', 'South Correctional Entity (SCORE) — Des Moines' },
    { 'pcj', 'Pierce County Jail — Tacoma' },
    { 'scj', 'Snohomish County Jail — Everett' },
    { 'other', 'Autre établissement' },
}

-- Types de permis (WA) + anciennes classes (fiches d'identité existantes, remplissage depuis l'historique)
local WA_DL_TYPES = {
    { 'DL', 'Permis de conduire' }, { 'EDL', 'Permis amélioré (EDL)' },
    { 'IL', 'Permis intermédiaire (moins de 18 ans)' }, { 'IP', 'Permis d\'apprentissage' },
    { 'DLM', 'Permis avec mention moto' },
    { 'CDL A', 'Permis poids lourd (CDL) — classe A' }, { 'CDL B', 'Permis poids lourd (CDL) — classe B' },
    { 'CDL C', 'Permis poids lourd (CDL) — classe C' }, { 'ID', 'Carte d\'identité seule (pas de permis)' },
}
for _, legacy in ipairs(LICENSE_CLASSES) do
    local known = false
    for _, o in ipairs(WA_DL_TYPES) do if o[1] == legacy[1] then known = true end end
    if not known then WA_DL_TYPES[#WA_DL_TYPES + 1] = legacy end
end

local WA_DL_STATUS = {
    { 'valid', 'Valide' }, { 'suspended', 'Suspendu' }, { 'revoked', 'Révoqué' }, { 'expired', 'Expiré' },
    { 'none', 'Sans permis' },
}

local WA_BODY_STYLES = {
    { 'sedan', 'Berline' }, { 'coupe', 'Coupé' }, { 'hatchback', 'Citadine / compacte' },
    { 'wagon', 'Break' }, { 'suv', 'SUV' }, { 'pickup', 'Pick-up' }, { 'van', 'Van / monospace' },
    { 'moto', 'Moto' }, { 'truck', 'Camion' }, { 'semi', 'Tracteur routier' }, { 'bus', 'Bus' },
    { 'rv', 'Camping-car' }, { 'other', 'Autre' },
}

local DIRECTIONS = {
    { 'N', 'Vers le nord' }, { 'S', 'Vers le sud' }, { 'E', 'Vers l\'est' }, { 'W', 'Vers l\'ouest' },
}

--- Date, heure et lieu (Washington)
local function waWhere(opts)
    opts = opts or {}
    return {
        { k = 'date', t = 'date', l = opts.dateLabel or 'Date', req = true, def = 'today', past = true },
        { k = 'time', t = 'time', l = opts.timeLabel or 'Heure', req = true, def = 'now' },
        { k = 'address', t = 'text', l = 'Lieu (adresse / route)', req = true, max = 80, w = 2 },
        { k = 'milepost', t = 'text', l = 'Borne kilométrique (Milepost)', max = 12, ph = 'ex : SR 520 MP 4.5' },
        { k = 'city', t = 'text', l = 'Ville / hors commune', max = 40, ph = 'ex : Unincorporated' },
        { k = 'county', t = 'select', l = 'Comté', req = true, def = 'king', o = WA_COUNTIES },
    }
end

--- Personne : nom, DOB, sexe, adresse (+ permis), remplissable depuis l'historique des recherches
local function waPerson(opts)
    opts = opts or {}
    local fields = {
        { t = 'lookup', kind = 'identity',
          map = { lastname = 'lastname', firstname = 'firstname', dob = 'dob', sex = 'sexReport', homeAddress = 'address',
                  dlNumber = 'licenseNumber', dlClass = 'licenseClass', dlState = 'licenseState' } },
        { k = 'lastname', t = 'text', l = 'Nom', req = opts.req, reqIf = opts.reqIf, max = 40 },
        { k = 'firstname', t = 'text', l = 'Prénom', req = opts.req, max = 40 },
        { k = 'dob', t = 'date', l = 'Date de naissance', req = opts.req, past = true },
        { k = 'sex', t = 'select', l = 'Sexe', o = WA_SEXES },
        { k = 'homeAddress', t = 'text', l = 'Adresse', max = 80, w = 3 },
        { k = 'phone', t = 'text', l = 'Téléphone', max = 20 },
    }
    if opts.license then
        fields[#fields + 1] = { k = 'dlNumber', t = 'text', l = 'N° de permis (OLN)', max = 20, upper = true, req = opts.licenseReq }
        fields[#fields + 1] = { k = 'dlState', t = 'text', l = 'État du permis', max = 40, ph = 'ex : WA' }
        fields[#fields + 1] = { k = 'dlClass', t = 'select', l = 'Type de permis', o = WA_DL_TYPES }
        fields[#fields + 1] = { k = 'dlStatus', t = 'select', l = 'Statut du permis', o = WA_DL_STATUS }
    end
    return fields
end

--- Véhicule (Vehicle License Number = plaque), remplissable depuis l'historique des recherches
local function waVehicle(opts)
    opts = opts or {}
    return {
        { t = 'lookup', kind = 'vehicle',
          map = { plate = 'plate', model = 'makeModel', color = 'color', owner = 'ownerFull', vin = 'vin', year = 'year', insurance = 'insurance' } },
        { k = 'plate', t = 'text', l = 'Plaque d\'immatriculation', req = opts.req, max = 8, upper = true },
        { k = 'plateState', t = 'text', l = 'État de la plaque', max = 40, ph = 'ex : WA' },
        { k = 'year', t = 'num', l = 'Année', min = 1900, max = 2100 },
        { k = 'model', t = 'text', l = 'Marque / modèle', max = 60 },
        { k = 'style', t = 'select', l = 'Carrosserie', o = WA_BODY_STYLES },
        { k = 'color', t = 'text', l = 'Couleur', max = 40 },
        { k = 'vin', t = 'text', l = 'VIN', max = 17, upper = true, w = 2 },
        { k = 'owner', t = 'text', l = 'Propriétaire', max = 80, w = 2 },
        { k = 'insurance', t = 'text', l = 'Assurance (compagnie / n° de contrat)', max = 80, w = 2 },
    }
end

--- Liste d'infractions / de charges : classification + infraction du catalogue (liées), et options.
--- La première ligne est déjà là (min 1), « + » en ajoute une. o.lock = { k = champ du rapport, map = { [valeur] =
--- classification } } : TOUTES les lignes sont de la classification imposée par ce champ (ex. Notice of Infraction
--- routière -> Traffic Infraction seulement) ; un autre type d'infraction = un autre rapport. Sans lock (Arrest, DUI,
--- Criminal Citation, Incident, collision…) : plusieurs classifications différentes dans le même rapport.
local function offenseList(o)
    local classes = CLASS_SETS[o.set] or CLASS_SETS.all
    local f = {
        { k = 'class', t = 'offclass', l = 'Classification', classes = classes, req = true, lock = o.lock },
        { k = 'code', t = 'offense', l = o.codeLabel or 'Infraction (RCW)', classes = classes, classKey = 'class',
          fineKey = o.fine and 'fine' or nil, req = true, w = 3, lock = o.lock },
    }
    if o.fine then f[#f + 1] = { k = 'fine', t = 'num', l = 'Pénalité', min = 0, max = 100000, money = true } end
    if o.counts then f[#f + 1] = { k = 'counts', t = 'num', l = 'Nombre de chefs', min = 1, max = 50, def = 1 } end
    if o.dv then f[#f + 1] = { k = 'dv', t = 'check', l = 'Violence conjugale (DV) — RCW 10.99' } end
    for _, extra in ipairs(o.extra or {}) do f[#f + 1] = extra end
    f[#f + 1] = { k = 'details', t = 'area', l = o.detailsLabel or 'Faits / description', max = 1500, rows = 2, w = 4 }
    return { k = o.k, t = 'list', l = o.l, item = o.item, add = o.add, min = o.min or 1, max = o.max or 3, f = f, show = o.show }
end

local CERTIFY = 'Je certifie sous peine de parjure, selon les lois de l\'État de Washington, avoir des motifs raisonnables '
    .. 'de croire, et croire, que la personne ci-dessus a commis la ou les infractions ci-dessus.'

local function certification()
    return { k = 'certify', t = 'check', l = CERTIFY, req = true, w = 4 }
end

-- -------------------------------------------------------------------------
-- NOTICE OF INFRACTION (Washington Uniform Court Docket) — infractions civiles : pénalité, pas de prison
-- -------------------------------------------------------------------------
local NOI_TRAFFIC = { k = 'kind', eq = 'traffic' }

local NOI = {
    id = 'noi',
    label = 'Notice of Infraction (NOI)',
    short = 'NOI',
    button = 'Notice of Infraction',
    summary = '{lastname} {firstname} — {plate} — {#violations} infraction(s)',
    sections = {
        { title = 'Notice of Infraction (Washington Uniform Court Docket)', f = (function()
            local fields = {
                { t = 'note', l = 'Infraction civile (ni casier ni prison) : infraction routière (RCW 46.63) ou civile hors route (RCW 7.80). 3 infractions au plus, comme sur le formulaire officiel.' },
                { k = 'kind', t = 'select', l = 'Type d\'avis', req = true, def = 'traffic', w = 2, o = {
                    { 'traffic', 'Infraction routière — Notice of Traffic Infraction (RCW 46.63)' }, { 'civil', 'Infraction civile hors route — Notice of Civil Infraction (RCW 7.80)' },
                } },
            }
            for _, f in ipairs(waWhere({ dateLabel = 'Date de l\'infraction', timeLabel = 'Heure de l\'infraction' })) do fields[#fields + 1] = f end
            fields[#fields + 1] = { k = 'court', t = 'select', l = 'Tribunal', req = true, def = 'kcdc_sea', w = 2, o = WA_COURTS }
            return fields
        end)() },
        { title = 'Conducteur / personne verbalisée', f = (function()
            local fields = waPerson({ req = true, license = true })
            fields[#fields + 1] = { k = 'cmv', t = 'check', l = 'Véhicule commercial (CMV)', show = NOI_TRAFFIC }
            fields[#fields + 1] = { k = 'hazmat', t = 'check', l = 'Matières dangereuses (HAZMAT)', show = NOI_TRAFFIC }
            fields[#fields + 1] = { k = 'collision', t = 'check', l = 'Accident impliqué', show = NOI_TRAFFIC }
            return fields
        end)() },
        { title = 'Véhicule', show = NOI_TRAFFIC, f = waVehicle({ req = true }) },
        { title = 'Vitesse (si applicable)', show = NOI_TRAFFIC, f = {
            { k = 'speedLimit', t = 'num', l = 'Vitesse autorisée', min = 0, max = 85, unit = 'mph' },
            { k = 'speedRecorded', t = 'num', l = 'Vitesse relevée', min = 0, max = 250, unit = 'mph' },
            { k = 'speedMethod', t = 'select', l = 'Mesurée par', o = {
                { 'radar', 'Radar' }, { 'lidar', 'Lidar (laser)' }, { 'pace', 'Suivi au véhicule de patrouille (pace)' },
                { 'aircraft', 'Avion de la WSP (WSP Aviation)' }, { 'visual', 'Estimation visuelle' },
            } },
            { k = 'speedZone', t = 'select', l = 'Zone particulière', o = {
                { 'school', 'Zone scolaire / aire de jeux' }, { 'work', 'Zone de travaux — ouvriers présents' },
            } },
        } },
        { title = 'Infractions', f = {
            { t = 'note', l = 'Toutes les infractions de l\'avis sont du type choisi en haut : routières (Traffic Infraction) pour une Notice of Traffic Infraction, civiles (Civil Infraction) pour une Notice of Civil Infraction. Une infraction d\'un autre type : un autre avis.' },
            offenseList({ k = 'violations', l = 'Infractions', item = 'Infraction', add = '+ Ajouter une infraction', set = 'infractions',
                fine = true, max = 3, lock = { k = 'kind', map = { traffic = 'TI', civil = 'CI' } } }),
        } },
        { title = 'Réponse et certification', f = {
            { t = 'note', l = 'La personne doit répondre sous 30 jours (RCW 46.63.070) : payer la pénalité, demander une audience d\'atténuation (mitigation hearing) ou contester l\'infraction (contested hearing). Sans réponse : défaut, pénalité majorée, et pour une traffic infraction suspension du permis.' },
            { k = 'signed', t = 'select', l = 'Signature', w = 2, o = {
                { 'signed', 'Signé — s\'engage à répondre' }, { 'refused', 'Refus de signer' }, { 'mailed', 'Envoyé par courrier' },
            } },
            certification(),
        } },
        { title = 'Notes de l\'agent', f = { narrative('Notes de l\'agent (non imprimées sur l\'avis)', false) } },
    },
}

-- -------------------------------------------------------------------------
-- CRIMINAL CITATION — Washington Uniform Court Docket (misdemeanor / gross misdemeanor) + Notice to Appear
-- -------------------------------------------------------------------------
local CC_VEHICLE = { k = 'traffic', eq = true }

local CRIMCITE = {
    id = 'crimcite',
    label = 'Criminal Citation and Notice to Appear',
    short = 'Criminal Citation',
    button = 'Criminal Citation',
    summary = '{lastname} {firstname} — {#charges} chef(s)',
    sections = {
        { title = 'Criminal Citation (Washington Uniform Court Docket)', f = (function()
            local fields = {
                { t = 'note', l = 'Délits seulement (misdemeanor, gross misdemeanor) : un crime (felony) se traite par une arrestation (Arrest Report). 3 chefs au plus.' },
            }
            for _, f in ipairs(waWhere({ dateLabel = 'Date des faits', timeLabel = 'Heure des faits' })) do fields[#fields + 1] = f end
            fields[#fields + 1] = { k = 'traffic', t = 'check', l = 'Délit routier (véhicule impliqué)' }
            return fields
        end)() },
        { title = 'Prévenu', f = waPerson({ req = true, license = true }) },
        { title = 'Véhicule', show = CC_VEHICLE, f = waVehicle({ req = true }) },
        { title = 'Chefs d\'accusation', f = {
            offenseList({ k = 'charges', l = 'Chefs d\'accusation', item = 'Chef d\'accusation', add = '+ Ajouter un chef', set = 'citable',
                codeLabel = 'Infraction (RCW)', dv = true, max = 3 }),
        } },
        { title = 'Convocation au tribunal (Notice to Appear)', f = {
            { k = 'court', t = 'select', l = 'Tribunal', req = true, def = 'kcdc_sea', w = 2, o = WA_COURTS },
            { k = 'appearDate', t = 'date', l = 'Date de comparution', req = true },
            { k = 'appearTime', t = 'time', l = 'Heure de comparution', req = true, def = '08:30' },
            { k = 'custodyStatus', t = 'select', l = 'Situation', req = true, w = 2, o = {
                { 'released', 'Laissé libre sur citation (s\'engage à comparaître)' }, { 'booked', 'Écroué' },
            } },
            { k = 'jail', t = 'select', l = 'Lieu d\'écrou', req = true, w = 2, o = WA_JAILS, show = { k = 'custodyStatus', eq = 'booked' } },
            { k = 'signed', t = 'select', l = 'Signature du prévenu', w = 2, o = {
                { 'signed', 'Signé — s\'engage à comparaître' }, { 'refused', 'Refus de signer' },
            } },
            { t = 'note', l = 'Refus de signer la promesse de comparaître : la personne peut être placée en détention.', show = { k = 'signed', eq = 'refused' } },
            certification(),
        } },
        { title = 'Exposé de la cause probable (Statement of Probable Cause)', f = { narrative('Exposé de la cause probable (Statement of Probable Cause)') } },
    },
}

-- -------------------------------------------------------------------------
-- WRITTEN WARNING — avertissement écrit (aucune pénalité, aucune suite judiciaire)
-- -------------------------------------------------------------------------
local WW_TRAFFIC = { k = 'kind', eq = 'traffic' }

local WWARNING = {
    id = 'wwarning',
    label = 'Written Warning',
    short = 'Written Warning',
    summary = '{lastname} {firstname} — {plate} — {#violations} infraction(s)',
    sections = {
        { title = 'Written Warning', f = (function()
            local fields = {
                { t = 'note', l = 'Avertissement écrit : aucune pénalité ni suite au tribunal ; il reste au dossier de la personne.' },
                { k = 'kind', t = 'select', l = 'Type de contact', req = true, def = 'traffic', w = 2, o = {
                    { 'traffic', 'Contrôle routier' }, { 'other', 'Autre contact' },
                } },
            }
            for _, f in ipairs(waWhere()) do fields[#fields + 1] = f end
            return fields
        end)() },
        { title = 'Personne avertie', f = waPerson({ req = true, license = true }) },
        { title = 'Véhicule', show = WW_TRAFFIC, f = waVehicle({ req = true }) },
        { title = 'Infractions', f = {
            offenseList({ k = 'violations', l = 'Infractions', item = 'Infraction', add = '+ Ajouter une infraction', set = 'infractions', max = 3,
                detailsLabel = 'Faits / correction demandée', lock = { k = 'kind', map = { traffic = 'TI', other = 'CI' } } }),
        } },
        { title = 'Notes de l\'agent', f = { narrative('Notes de l\'agent', false) } },
    },
}

-- -------------------------------------------------------------------------
-- ARREST REPORT (même clé qu'avant : les rapports déjà rédigés restent lisibles)
-- -------------------------------------------------------------------------
local ARREST_WARRANT = { k = 'arrestType', eq = 'warrant' }

local ARREST = {
    id = 'arrest',
    label = 'Arrest Report',
    short = 'Arrest',
    summary = '{lastname} {firstname} — {#charges} chef(s)',
    sections = {
        { title = 'Arrestation', f = (function()
            local fields = waWhere({ dateLabel = 'Date de l\'arrestation', timeLabel = 'Heure de l\'arrestation' })
            fields[#fields + 1] = { k = 'arrestType', t = 'select', l = 'Type d\'arrestation', req = true, w = 2, o = {
                { 'onview', 'Flagrant délit (on-view)' }, { 'pc', 'Sur cause probable (probable cause)' }, { 'warrant', 'Sur mandat (warrant)' },
                { 'citizen', 'Arrestation citoyenne — remise à la police' },
            } }
            fields[#fields + 1] = { k = 'warrantNo', t = 'text', l = 'N° du mandat', req = true, max = 30, upper = true, show = ARREST_WARRANT }
            fields[#fields + 1] = { k = 'warrantCourt', t = 'select', l = 'Tribunal émetteur', w = 2, o = WA_COURTS, show = ARREST_WARRANT }
            return fields
        end)() },
        { title = 'Personne arrêtée', f = (function()
            local fields = waPerson({ req = true, license = true })
            fields[#fields + 1] = { k = 'height', t = 'text', l = 'Taille', max = 10, ph = 'ex : 5\'10"' }
            fields[#fields + 1] = { k = 'weight', t = 'num', l = 'Poids', min = 50, max = 700, unit = 'lbs' }
            fields[#fields + 1] = { k = 'hair', t = 'text', l = 'Cheveux', max = 20 }
            fields[#fields + 1] = { k = 'eyes', t = 'text', l = 'Yeux', max = 20 }
            fields[#fields + 1] = { k = 'marks', t = 'text', l = 'Cicatrices, marques et tatouages', max = 120, w = 4 }
            return fields
        end)() },
        { title = 'Chefs d\'accusation', f = {
            offenseList({ k = 'charges', l = 'Chefs d\'accusation', item = 'Chef d\'accusation', add = '+ Ajouter un chef', set = 'criminal',
                codeLabel = 'Infraction (RCW)', counts = true, dv = true, max = 20,
                extra = { { k = 'charge', t = 'text', l = 'Précisions', max = 120, w = 2 } } }),
        } },
        { title = 'Droits, usage de la force et écrou', f = {
            { k = 'miranda', t = 'check', l = 'Droits Miranda lus' },
            { k = 'mirandaTime', t = 'time', l = 'Heure de lecture', show = { k = 'miranda', eq = true } },
            { k = 'waiver', t = 'select', l = 'Droits', w = 2, show = { k = 'miranda', eq = true }, o = {
                { 'waived', 'Renonce — accepte de répondre' }, { 'attorney', 'Invoque — demande un avocat' },
                { 'silent', 'Invoque — garde le silence' },
            } },
            { k = 'force', t = 'check', l = 'Usage de la force' },
            { k = 'injuries', t = 'check', l = 'Personne blessée' },
            { k = 'forceDetails', t = 'area', l = 'Usage de la force — détails', req = true, max = 1000, rows = 3, w = 4, show = { k = 'force', eq = true } },
            { k = 'injuryDetails', t = 'area', l = 'Blessures — détails', req = true, max = 1000, rows = 3, w = 4, show = { k = 'injuries', eq = true } },
            { k = 'medical', t = 'select', l = 'Médical', w = 2, o = {
                { 'none', 'Non nécessaire' }, { 'cleared', 'Examiné et apte (pompiers / EMS)' }, { 'hospital', 'Transporté à l\'hôpital' },
            } },
            { k = 'seized', t = 'area', l = 'Objets / preuves saisis', max = 1500, rows = 3, w = 4 },
            { k = 'jail', t = 'select', l = 'Lieu d\'écrou', req = true, w = 2, o = WA_JAILS },
            { k = 'custody', t = 'text', l = 'N° d\'écrou / notes', max = 80, w = 2 },
            { k = 'vehDisposition', t = 'select', l = 'Véhicule de la personne', w = 2, o = {
                { 'na', 'Sans objet' }, { 'impound', 'Mis en fourrière (voir Impound Report)' }, { 'released', 'Remis à un conducteur titulaire du permis' },
                { 'parked', 'Laissé stationné légalement' },
            } },
        } },
        { title = 'Cause probable (Certification for Determination of Probable Cause)', f = {
            { t = 'note', l = 'Exposé des faits établissant la cause probable (probable cause), lu par le juge pour maintenir la détention.' },
            narrative('Exposé des faits'),
            certification(),
        } },
    },
}

-- -------------------------------------------------------------------------
-- DUI ARREST REPORT (RCW 46.61.502 / .504)
-- -------------------------------------------------------------------------
local SFST_DONE = { k = 'sfst', eq = 'performed' }

local DUI = {
    id = 'dui',
    label = 'DUI Arrest Report',
    short = 'DUI',
    summary = '{lastname} {firstname} — {plate}',
    sections = {
        { title = 'Faits', f = (function()
            local fields = waWhere()
            fields[#fields + 1] = { k = 'contactReason', t = 'select', l = 'Motif du contrôle', req = true, w = 2, o = {
                { 'traffic', 'Infraction routière' }, { 'collision', 'Accident' }, { 'pc', 'Contrôle du véhicule — véhicule stationné occupé' },
                { 'citizen', 'Signalement d\'un citoyen' }, { 'other', 'Autre' },
            } }
            return fields
        end)() },
        { title = 'Personne contrôlée', f = waPerson({ req = true, license = true }) },
        { title = 'Véhicule', f = waVehicle() },
        { title = 'Observations de conduite', f = {
            { k = 'driving', t = 'checks', l = 'Constaté', ph = 'cochez tout ce qui s\'applique', o = {
                { 'weaving', 'Zigzague' }, { 'lane', 'Sort de sa voie' }, { 'speed', 'Vitesse irrégulière' },
                { 'wide', 'Virage trop large' }, { 'braking', 'Freinages brusques' }, { 'nolights', 'Phares éteints' },
                { 'stopped', 'Arrêté sur la chaussée' }, { 'collision', 'Accident' }, { 'slow', 'Réagit lentement aux feux' },
            } },
        } },
        { title = 'Observations au contact', f = {
            { k = 'contact', t = 'checks', l = 'Constaté', ph = 'cochez tout ce qui s\'applique', o = {
                { 'odor', 'Odeur d\'alcool' }, { 'eyes', 'Yeux rouges / larmoyants' }, { 'speech', 'Élocution pâteuse' },
                { 'balance', 'Équilibre instable' }, { 'fumble', 'Peine à sortir ses papiers' }, { 'admit', 'Reconnaît avoir bu' },
                { 'containers', 'Contenants ouverts dans le véhicule' }, { 'drugs', 'Signes de consommation de drogue' },
            } },
            { k = 'admission', t = 'text', l = 'Déclaration — quantité / type consommé', max = 120, w = 4 },
        } },
        { title = 'Tests de sobriété sur le terrain (SFST)', f = {
            { k = 'sfst', t = 'select', l = 'Tests SFST', req = true, w = 2, o = {
                { 'performed', 'Réalisés (volontairement)' }, { 'refused', 'Refusés' }, { 'na', 'Non proposés — sécurité / médical' },
            } },
            { k = 'hgn', t = 'num', l = 'HGN (nystagmus) — indices (sur 6)', min = 0, max = 6, show = SFST_DONE },
            { k = 'wat', t = 'num', l = 'Walk-and-Turn (marche) — indices (sur 8)', min = 0, max = 8, show = SFST_DONE },
            { k = 'ols', t = 'num', l = 'One-Leg Stand (sur une jambe) — indices (sur 4)', min = 0, max = 4, show = SFST_DONE },
            { k = 'pbt', t = 'text', l = 'Éthylotest portable (PBT)', max = 6, ph = '0.000' },
        } },
        { title = 'Arrestation, consentement implicite et test probant', f = {
            { k = 'miranda', t = 'check', l = 'Droits Miranda lus' },
            { k = 'implied', t = 'check', l = 'Avertissement de consentement implicite lu (Implied Consent, RCW 46.20.308)' },
            { k = 'testType', t = 'select', l = 'Test probant', req = true, w = 2, o = {
                { 'breath', 'Éthylomètre — BAC DataMaster DMT' }, { 'bloodwarrant', 'Prise de sang — sur mandat' },
                { 'bloodconsent', 'Prise de sang — avec consentement' }, { 'refused', 'Refus de l\'éthylomètre' }, { 'none', 'Aucun test — médical / impossible' },
            } },
            { k = 'brac1', t = 'text', l = 'Souffle — échantillon 1 (BrAC)', max = 6, ph = '0.000', show = { k = 'testType', eq = 'breath' } },
            { k = 'brac2', t = 'text', l = 'Souffle — échantillon 2 (BrAC)', max = 6, ph = '0.000', show = { k = 'testType', eq = 'breath' } },
            { k = 'bloodResult', t = 'text', l = 'Résultat sanguin (labo de toxicologie WSP)', max = 60, w = 2,
              show = { k = 'testType', ['in'] = { 'bloodwarrant', 'bloodconsent' } } },
            { k = 'dre', t = 'check', l = 'Évaluation par un expert drogues (DRE)' },
        } },
        { title = 'Chefs d\'accusation', f = {
            offenseList({ k = 'charges', l = 'Chefs d\'accusation', item = 'Chef d\'accusation', add = '+ Ajouter un chef', set = 'criminal',
                codeLabel = 'Infraction (RCW)', max = 6 }),
        } },
        { title = 'Suites', f = {
            { k = 'vehDisposition', t = 'select', l = 'Véhicule', req = true, w = 2, o = {
                { 'impound', 'Fourrière — immobilisation DUI de 12 h (RCW 46.55.360)' }, { 'released', 'Remis à un conducteur titulaire du permis' },
                { 'parked', 'Laissé stationné légalement' }, { 'na', 'Sans objet' },
            } },
            { k = 'custodyStatus', t = 'select', l = 'Situation', req = true, w = 2, o = {
                { 'booked', 'Écroué' }, { 'released', 'Laissé libre sur citation' }, { 'hospital', 'Remis à l\'hôpital' },
            } },
            { k = 'jail', t = 'select', l = 'Lieu d\'écrou', req = true, w = 2, o = WA_JAILS, show = { k = 'custodyStatus', eq = 'booked' } },
        } },
        { title = 'Rapport / cause probable', f = { narrative('Rapport — cause probable'), certification() } },
    },
}

-- -------------------------------------------------------------------------
-- POLICE TRAFFIC COLLISION REPORT (PTCR — SECTOR)
-- -------------------------------------------------------------------------
local KABCO = {
    { 'O', 'O — Aucune blessure apparente' }, { 'C', 'C — Blessure possible' }, { 'B', 'B — Blessure légère' },
    { 'A', 'A — Blessure grave' }, { 'K', 'K — Mortel' },
}
local RESTRAINTS = {
    { 'belt', 'Ceinture 3 points' }, { 'lap', 'Ceinture ventrale' }, { 'child', 'Siège enfant' },
    { 'helmet', 'Casque (moto / vélo)' }, { 'none', 'Aucune' }, { 'unknown', 'Inconnu' },
}
local EJECTION = { { 'no', 'Non éjecté' }, { 'partial', 'Partiellement éjecté' }, { 'total', 'Éjecté' }, { 'trapped', 'Coincé' } }
local UNIT_DRIVEN = { k = 'unitType', ['in'] = { 'mv', 'parked', 'hr' } }   -- unit avec un véhicule
local UNIT_PERSON = { k = 'unitType', ['in'] = { 'mv', 'ped', 'cyclist' } } -- conducteur / piéton connu
local UNIT_MOVING = { k = 'unitType', eq = 'mv' }

local PTCR = {
    id = 'ptcr',
    label = 'Police Traffic Collision Report',
    short = 'PTCR',
    button = 'Collision Report (PTCR)',
    summary = '{street} {crossStreet} — {#units} unit(s)',
    sections = {
        { title = 'Accident', f = {
            { t = 'note', l = 'Accident à déclarer : blessé, mort, ou au moins 1 000 $ de dégâts (RCW 46.52.030).' },
            { k = 'date', t = 'date', l = 'Date de l\'accident', req = true, def = 'today', past = true },
            { k = 'time', t = 'time', l = 'Heure', req = true, def = 'now' },
            { k = 'county', t = 'select', l = 'Comté', req = true, def = 'king', o = WA_COUNTIES },
            { k = 'city', t = 'text', l = 'Ville / hors commune', max = 40 },
            { k = 'street', t = 'text', l = 'Route / rue', req = true, max = 80, w = 2 },
            { k = 'crossStreet', t = 'text', l = 'À l\'intersection avec', max = 80, w = 2 },
            { k = 'milepost', t = 'text', l = 'Borne kilométrique (Milepost)', max = 12 },
            { k = 'refDistance', t = 'text', l = 'Distance d\'un point de repère', max = 30, ph = 'ex : 200 ft au nord de' },
            { k = 'agency', t = 'text', l = 'Service enquêteur', req = true, max = 80, w = 2, def = 'unitAgency' },
            { k = 'hitRun', t = 'check', l = 'Délit de fuite' },
            { k = 'damage1000', t = 'check', l = 'Dégâts de 1 000 $ ou plus' },
            { k = 'injured', t = 'num', l = 'Nombre de blessés', min = 0, max = 99 },
            { k = 'killed', t = 'num', l = 'Nombre de morts', min = 0, max = 99 },
        } },
        { title = 'Conditions et route', f = {
            { k = 'collisionType', t = 'select', l = 'Type de collision', req = true, w = 2, o = {
                { 'rearend', 'Collision arrière' }, { 'headon', 'Collision frontale' },
                { 'angle', 'Collision en angle (en T)' }, { 'sssame', 'Accrochage latéral — même sens' },
                { 'ssopp', 'Accrochage latéral — sens inverse' }, { 'reartoside', 'Arrière contre flanc' }, { 'reartorear', 'Arrière contre arrière (marche arrière)' },
                { 'fixed', 'Obstacle fixe' }, { 'overturn', 'Tonneau / renversement' }, { 'ped', 'Piéton' },
                { 'cyclist', 'Cycliste' }, { 'parked', 'Véhicule stationné' }, { 'animal', 'Animal' }, { 'other', 'Autre / sans collision' },
            } },
            { k = 'weather', t = 'select', l = 'Météo', req = true, w = 2, o = {
                { 'clear', 'Dégagé / peu nuageux' }, { 'overcast', 'Couvert' }, { 'rain', 'Pluie' }, { 'snow', 'Neige' },
                { 'fog', 'Brouillard / fumée' }, { 'sleet', 'Grésil / grêle / pluie verglaçante' }, { 'wind', 'Fort vent latéral' },
                { 'blowing', 'Sable / poussière / neige soufflés' }, { 'unknown', 'Inconnu' },
            } },
            { k = 'light', t = 'select', l = 'Luminosité', w = 2, o = {
                { 'day', 'Jour' }, { 'dawn', 'Aube' }, { 'dusk', 'Crépuscule' }, { 'darklit', 'Nuit — éclairage allumé' },
                { 'darkoff', 'Nuit — éclairage éteint' }, { 'dark', 'Nuit — sans éclairage' }, { 'unknown', 'Inconnu' },
            } },
            { k = 'surface', t = 'select', l = 'État de la chaussée', w = 2, o = {
                { 'dry', 'Sèche' }, { 'wet', 'Mouillée' }, { 'snow', 'Neige / neige fondue' }, { 'ice', 'Verglas / givre' },
                { 'water', 'Flaques d\'eau' }, { 'sand', 'Sable / boue / terre' }, { 'oil', 'Huile' }, { 'other', 'Autre' },
            } },
            { k = 'junction', t = 'select', l = 'Intersection', w = 2, o = {
                { 'intersection', 'À l\'intersection' }, { 'intrelated', 'Près d\'une intersection' },
                { 'notint', 'Hors intersection' }, { 'driveway', 'Entrée / sortie de propriété' }, { 'ramp', 'Bretelle d\'accès' }, { 'alley', 'Ruelle' },
            } },
            { k = 'control', t = 'select', l = 'Signalisation', w = 2, o = {
                { 'none', 'Aucune' }, { 'signal', 'Feu tricolore' }, { 'stop', 'Stop' }, { 'yield', 'Cédez le passage' },
                { 'flashing', 'Feu clignotant' }, { 'rr', 'Passage à niveau' }, { 'officer', 'Agent / signaleur' },
                { 'roundabout', 'Rond-point' },
            } },
            { k = 'workZone', t = 'select', l = 'Zone de travaux', o = {
                { 'no', 'Non' }, { 'workers', 'Oui — ouvriers présents' }, { 'noworkers', 'Oui — sans ouvriers' },
            } },
            { k = 'roadType', t = 'select', l = 'Type de route', w = 2, o = {
                { 'interstate', 'Interstate (autoroute)' }, { 'us_highway', 'US Route' }, { 'state_route', 'State Route (route d\'État)' },
                { 'county_road', 'Route de comté' }, { 'city_street', 'Rue' }, { 'private', 'Route privée / parking' },
            } },
            { k = 'lanes', t = 'num', l = 'Nombre de voies', min = 1, max = 12 },
        } },
        { title = 'Impliqués (units)', f = {
            { k = 'units', t = 'list', l = 'Units', item = 'Unit', add = '+ Ajouter une unit', min = 1, max = 10, f = {
                { k = 'unitType', t = 'select', l = 'Type d\'unit', req = true, w = 2, o = {
                    { 'mv', 'Véhicule en circulation' }, { 'parked', 'Véhicule stationné' }, { 'ped', 'Piéton' },
                    { 'cyclist', 'Cycliste' }, { 'hr', 'Véhicule en fuite — conducteur inconnu' },
                } },
                { t = 'group', l = 'Conducteur / piéton / cycliste', show = UNIT_PERSON, f = {
                    { t = 'lookup', kind = 'identity',
                      map = { lastname = 'lastname', firstname = 'firstname', dob = 'dob', sex = 'sexReport', address = 'address',
                              dlNumber = 'licenseNumber', dlClass = 'licenseClass', dlState = 'licenseState' } },
                    { k = 'lastname', t = 'text', l = 'Nom', req = true, max = 40 },
                    { k = 'firstname', t = 'text', l = 'Prénom', max = 40 },
                    { k = 'dob', t = 'date', l = 'Date de naissance', past = true },
                    { k = 'sex', t = 'select', l = 'Sexe', o = WA_SEXES },
                    { k = 'address', t = 'text', l = 'Adresse', max = 80, w = 3 },
                    { k = 'phone', t = 'text', l = 'Téléphone', max = 20 },
                    { k = 'dlNumber', t = 'text', l = 'N° de permis (OLN)', max = 20, upper = true, show = UNIT_MOVING },
                    { k = 'dlState', t = 'text', l = 'État du permis', max = 40, show = UNIT_MOVING },
                    { k = 'dlClass', t = 'select', l = 'Type de permis', o = WA_DL_TYPES, show = UNIT_MOVING },
                    { k = 'dlStatus', t = 'select', l = 'Statut du permis', o = WA_DL_STATUS, show = UNIT_MOVING },
                    { k = 'injury', t = 'select', l = 'Blessures (KABCO)', req = true, w = 2, o = KABCO },
                    { k = 'restraint', t = 'select', l = 'Ceinture / casque', o = RESTRAINTS },
                    { k = 'airbag', t = 'select', l = 'Airbag', show = UNIT_MOVING, o = {
                        { 'none', 'Non déclenché' }, { 'front', 'Déclenché — avant' }, { 'side', 'Déclenché — latéral' },
                        { 'multiple', 'Déclenché — plusieurs' }, { 'na', 'Sans objet' },
                    } },
                    { k = 'ejection', t = 'select', l = 'Éjection', o = EJECTION },
                    { k = 'condition', t = 'select', l = 'Sobriété', w = 2, o = {
                        { 'hnbd', 'N\'a pas bu' }, { 'hbdimpaired', 'A bu — capacités altérées' },
                        { 'hbdnot', 'A bu — capacités non altérées' }, { 'hbdunknown', 'A bu — altération inconnue' },
                        { 'drugs', 'Sous l\'emprise de drogues' }, { 'unknown', 'Inconnu' },
                    } },
                    { k = 'sobrietyTest', t = 'select', l = 'Test réalisé', o = {
                        { 'none', 'Aucune' }, { 'breath', 'Souffle' }, { 'blood', 'Sang' }, { 'refused', 'Refusés' },
                    } },
                    { k = 'distraction', t = 'select', l = 'Distraction du conducteur', w = 2, show = UNIT_MOVING, o = {
                        { 'none', 'Pas distrait' }, { 'phonetalk', 'Téléphone — appel' }, { 'phonetext', 'Téléphone — SMS / navigation' },
                        { 'device', 'Autre appareil électronique' }, { 'passenger', 'Passager' }, { 'outside', 'Extérieur du véhicule' },
                        { 'unknown', 'Inconnu' },
                    } },
                    { k = 'contributing', t = 'checks', l = 'Causes de l\'accident', ph = 'cochez tout ce qui s\'applique', o = {
                        { 'none', 'Aucune' }, { 'reasspeed', 'Vitesse inadaptée' }, { 'limit', 'Excès de vitesse' },
                        { 'row', 'Refus de priorité' }, { 'signal', 'Non-respect du stop / feu' },
                        { 'follow', 'Distance de sécurité insuffisante' }, { 'passing', 'Dépassement dangereux' }, { 'center', 'Franchissement de la ligne centrale' },
                        { 'inattention', 'Inattention' }, { 'alcohol', 'Sous l\'emprise de l\'alcool' }, { 'drugs', 'Sous l\'emprise de drogues' },
                        { 'asleep', 'Endormi / fatigué' }, { 'turn', 'Virage dangereux' }, { 'backing', 'Marche arrière dangereuse' },
                        { 'defective', 'Équipement défectueux' }, { 'pedrow', 'Refus de priorité à un piéton' },
                        { 'pedaction', 'Action d\'un piéton / cycliste' },
                    } },
                    { k = 'transportedTo', t = 'text', l = 'Transporté vers (hôpital / EMS)', max = 80, w = 2, ph = 'ex : Harborview Medical Center' },
                    { k = 'cited', t = 'check', l = 'Infraction relevée (citation / NOI)' },
                    offenseList({ k = 'violations', l = 'Infractions relevées', item = 'Infraction', add = '+ Ajouter une infraction', set = 'all',
                        min = 0, max = 3, show = { k = 'cited', eq = true } }),
                } },
                { t = 'group', l = 'Véhicule', show = UNIT_DRIVEN, f = {
                    { t = 'lookup', kind = 'vehicle',
                      map = { plate = 'plate', vin = 'vin', model = 'makeModel', year = 'year', owner = 'ownerFull', insurance = 'insurance' } },
                    { k = 'plate', t = 'text', l = 'Plaque d\'immatriculation', max = 8, upper = true },
                    { k = 'plateState', t = 'text', l = 'État de la plaque', max = 40 },
                    { k = 'year', t = 'num', l = 'Année', min = 1900, max = 2100 },
                    { k = 'model', t = 'text', l = 'Marque / modèle', max = 60 },
                    { k = 'vehType', t = 'select', l = 'Carrosserie', o = WA_BODY_STYLES },
                    { k = 'vin', t = 'text', l = 'VIN', max = 17, upper = true, w = 2 },
                    { k = 'owner', t = 'text', l = 'Propriétaire', max = 80, w = 2 },
                    { k = 'insurance', t = 'text', l = 'Assurance (compagnie / n° de contrat)', max = 80, w = 2 },
                    { k = 'direction', t = 'select', l = 'Sens de circulation', o = DIRECTIONS },
                    { k = 'action', t = 'select', l = 'Manœuvre', w = 2, o = {
                        { 'straight', 'Tout droit' }, { 'right', 'Tourne à droite' }, { 'left', 'Tourne à gauche' },
                        { 'uturn', 'Demi-tour' }, { 'slowing', 'Ralentit' }, { 'stopped', 'Arrêté dans la circulation' },
                        { 'starting', 'Démarre d\'un stationnement' }, { 'backing', 'Marche arrière' }, { 'lane', 'Change de voie' },
                        { 'overtaking', 'Dépasse' }, { 'merging', 'S\'insère' }, { 'parked', 'Stationné légalement' },
                    } },
                    { k = 'speedLimit', t = 'num', l = 'Vitesse autorisée', min = 0, max = 85, unit = 'mph' },
                    { k = 'estSpeed', t = 'num', l = 'Vitesse estimée', min = 0, max = 250, unit = 'mph' },
                    { k = 'damage', t = 'select', l = 'Gravité des dégâts', o = {
                        { 'none', 'Aucune' }, { 'minor', 'Légers' }, { 'functional', 'Fonctionnels' }, { 'disabling', 'Immobilisants' },
                    } },
                    { k = 'damageCost', t = 'num', l = 'Coût estimé des dégâts', min = 0, max = 10000000, money = true },
                    { k = 'towed', t = 'select', l = 'Remorquage', o = {
                        { 'no', 'Non remorqué' }, { 'damage', 'Remorqué — dégâts' }, { 'other', 'Remorqué — autre raison' },
                    } },
                    { k = 'towCompany', t = 'text', l = 'Dépanneur', max = 60, w = 2 },
                    { k = 'cmv', t = 'check', l = 'Véhicule commercial (CMV)' },
                    { k = 'company', t = 'text', l = 'Transporteur', req = true, max = 80, w = 2, show = { k = 'cmv', eq = true } },
                    { k = 'usdot', t = 'text', l = 'N° USDOT', req = true, max = 10, show = { k = 'cmv', eq = true } },
                    { k = 'hazmat', t = 'check', l = 'Plaque matières dangereuses', show = { k = 'cmv', eq = true } },
                } },
                { k = 'occupants', t = 'list', l = 'Passagers', item = 'Passager', add = '+ Ajouter un passager', min = 0, max = 8,
                  show = UNIT_DRIVEN, f = {
                    { k = 'name', t = 'text', l = 'Nom complet', req = true, max = 80, w = 2 },
                    { k = 'dob', t = 'date', l = 'Date de naissance', past = true },
                    { k = 'seat', t = 'select', l = 'Place', o = {
                        { 'front_mid', 'Avant milieu' }, { 'front', 'Avant droit' }, { 'rear_left', 'Arrière gauche' },
                        { 'rear_center', 'Arrière milieu' }, { 'rear_right', 'Arrière droit' }, { 'third', '3e rangée' },
                        { 'cargo', 'Zone de chargement' }, { 'other', 'Autre' },
                    } },
                    { k = 'injury', t = 'select', l = 'Blessures (KABCO)', o = KABCO, w = 2 },
                    { k = 'restraint', t = 'select', l = 'Ceinture', o = RESTRAINTS },
                    { k = 'ejection', t = 'select', l = 'Éjection', o = EJECTION },
                } },
            } },
        } },
        { title = 'Rapport et croquis', f = { narrative('Rapport — déroulement de l\'accident et description du croquis') } },
    },
}

-- -------------------------------------------------------------------------
-- INCIDENT REPORT (même clé qu'avant : les rapports déjà rédigés restent lisibles)
-- -------------------------------------------------------------------------
local INCIDENT = {
    id = 'incident',
    label = 'Incident Report',
    short = 'Incident',
    summary = '{nature} — {address}',
    sections = {
        { title = 'Faits', f = (function()
            local fields = waWhere({ dateLabel = 'Date des faits', timeLabel = 'Heure des faits' })
            table.insert(fields, 1, { k = 'nature', t = 'text', l = 'Nature des faits', req = true, max = 80, w = 3 })
            table.insert(fields, 2, { k = 'dv', t = 'check', l = 'Violence conjugale (DV)' })
            return fields
        end)() },
        { title = 'Infractions', f = {
            offenseList({ k = 'offenses', l = 'Infractions', item = 'Infraction', add = '+ Ajouter une infraction', set = 'all',
                codeLabel = 'Infraction (RCW)', min = 0, max = 10 }),
        } },
        { title = 'Personnes impliquées', f = {
            { k = 'persons', t = 'list', l = 'Personnes', item = 'Personne', add = '+ Ajouter une personne', min = 0, max = 15, f = (function()
                local fields = waPerson({ req = true })
                table.insert(fields, 1, { k = 'role', t = 'select', l = 'Rôle', req = true, o = {
                    { 'victim', 'Victime (V)' }, { 'suspect', 'Suspect (S)' }, { 'arrestee', 'Personne arrêtée (A)' }, { 'witness', 'Témoin (W)' },
                    { 'caller', 'Requérant (RP)' }, { 'other', 'Autre impliqué (O)' },
                } })
                fields[#fields + 1] = { k = 'statement', t = 'area', l = 'Déclaration', max = 1500, rows = 3, w = 4 }
                return fields
            end)() },
            { k = 'vehicles', t = 'list', l = 'Véhicules', item = 'Véhicule', add = '+ Ajouter un véhicule', min = 0, max = 10, f = (function()
                local fields = waVehicle({ req = true })
                fields[#fields + 1] = { k = 'role', t = 'select', l = 'Implication', o = {
                    { 'suspect', 'Véhicule suspect' }, { 'victim', 'Véhicule de la victime' }, { 'witness', 'Véhicule témoin' },
                    { 'stolen', 'Volé' }, { 'recovered', 'Retrouvé' }, { 'other', 'Autre' },
                } }
                fields[#fields + 1] = { k = 'notes', t = 'text', l = 'Notes', max = 200, w = 3 }
                return fields
            end)() },
        } },
        { title = 'Biens et preuves', f = {
            { k = 'evidence', t = 'area', l = 'Biens (volés / retrouvés / endommagés) et preuves recueillies', max = 1500, rows = 4, w = 4 },
        } },
        { title = 'Rapport narratif', f = { narrative() } },
    },
}

-- -------------------------------------------------------------------------
-- VEHICLE IMPOUND / INVENTORY REPORT (RCW 46.55)
-- -------------------------------------------------------------------------
local IMPOUND = {
    id = 'impound',
    label = 'Vehicle Impound / Inventory Report',
    short = 'Impound',
    summary = '{plate} — {model}',
    sections = {
        { title = 'Mise en fourrière', f = (function()
            local fields = waWhere()
            fields[#fields + 1] = { k = 'authority', t = 'select', l = 'Motif légal', req = true, w = 4, o = {
                { 'hazard', 'Danger / obstruction de la circulation — RCW 46.55.113' },
                { 'arrest', 'Conducteur arrêté — RCW 46.55.113' },
                { 'dwls', 'Conduite avec permis suspendu — RCW 46.55.113' },
                { 'dui', 'Arrestation DUI — immobilisation 12 h, RCW 46.55.360' },
                { 'abandoned', 'Véhicule abandonné (avis 24 h) — RCW 46.55.085' },
                { 'private', 'Propriété privée — RCW 46.55.080' },
                { 'stolen', 'Véhicule volé retrouvé' },
                { 'evidence', 'Pièce à conviction / enquête' },
                { 'collision', 'Accident — enlèvement impossible par le propriétaire / conducteur' },
                { 'other', 'Autre' },
            } }
            fields[#fields + 1] = { k = 'hold', t = 'check', l = 'Retenue police (police hold)' }
            fields[#fields + 1] = { k = 'holdReason', t = 'text', l = 'Motif de la retenue / restitution uniquement à', max = 120, w = 3, show = { k = 'hold', eq = true } }
            return fields
        end)() },
        { title = 'Véhicule', f = (function()
            local fields = waVehicle({ req = true })
            fields[#fields + 1] = { k = 'keys', t = 'check', l = 'Clés avec le véhicule' }
            fields[#fields + 1] = { k = 'condition', t = 'area', l = 'État du véhicule / dégâts existants', max = 800, rows = 2, w = 4 }
            return fields
        end)() },
        { title = 'Conducteur / responsable du véhicule', f = waPerson({ license = true }) },
        { title = 'Dépannage', f = {
            { k = 'towCompany', t = 'text', l = 'Dépanneur agréé (RTTO)', req = true, max = 80, w = 2 },
            { k = 'towDest', t = 'text', l = 'Lieu de stockage', max = 80, w = 2 },
            { k = 'towTime', t = 'time', l = 'Heure d\'arrivée du dépanneur' },
        } },
        { title = 'Inventaire', f = {
            { k = 'inventory', t = 'area', l = 'Inventaire des effets personnels (zones visibles / non verrouillées)', max = 2000, rows = 4, w = 4 },
        } },
        { title = 'Notes de l\'agent', f = { narrative('Notes de l\'agent', false) } },
    },
}

MDC_REPORT_TYPES = { NOI, CRIMCITE, WWARNING, ARREST, DUI, PTCR, INCIDENT, IMPOUND,
    -- anciens modèles (archived : lecture seule, absents des boutons)
    DOT523, CITATION, TRAFFIC, CONVOCATION, WARNING, TICKET }
