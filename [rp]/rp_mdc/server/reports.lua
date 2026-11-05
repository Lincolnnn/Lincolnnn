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

local WA_SEXES = { { 'male', 'M — Male' }, { 'female', 'F — Female' }, { 'x', 'X — Unspecified' } }

local WA_COUNTIES = {
    { 'king', 'King County' }, { 'pierce', 'Pierce County' }, { 'snohomish', 'Snohomish County' },
    { 'kitsap', 'Kitsap County' }, { 'thurston', 'Thurston County' }, { 'spokane', 'Spokane County' },
    { 'clark', 'Clark County' }, { 'whatcom', 'Whatcom County' }, { 'skagit', 'Skagit County' },
    { 'yakima', 'Yakima County' }, { 'other', 'Other County' },
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
    { 'other', 'Other Court' },
}

local WA_JAILS = {
    { 'kccf', 'King County Correctional Facility (KCCF) — Seattle' },
    { 'mrjc', 'Maleng Regional Justice Center (MRJC) — Kent' },
    { 'score', 'South Correctional Entity (SCORE) — Des Moines' },
    { 'pcj', 'Pierce County Jail — Tacoma' },
    { 'scj', 'Snohomish County Jail — Everett' },
    { 'other', 'Other Facility' },
}

-- Types de permis (WA) + anciennes classes (fiches d'identité existantes, remplissage depuis l'historique)
local WA_DL_TYPES = {
    { 'DL', 'Driver License' }, { 'EDL', 'Enhanced Driver License (EDL)' },
    { 'IL', 'Intermediate License (Under 18)' }, { 'IP', 'Instruction Permit' },
    { 'DLM', 'Driver License — Motorcycle Endorsement' },
    { 'CDL A', 'Commercial Driver License (CDL) — Class A' }, { 'CDL B', 'Commercial Driver License (CDL) — Class B' },
    { 'CDL C', 'Commercial Driver License (CDL) — Class C' }, { 'ID', 'Identicard Only (No Driving Privilege)' },
}
for _, legacy in ipairs(LICENSE_CLASSES) do
    local known = false
    for _, o in ipairs(WA_DL_TYPES) do if o[1] == legacy[1] then known = true end end
    if not known then WA_DL_TYPES[#WA_DL_TYPES + 1] = legacy end
end

local WA_DL_STATUS = {
    { 'valid', 'Valid' }, { 'suspended', 'Suspended' }, { 'revoked', 'Revoked' }, { 'expired', 'Expired' },
    { 'none', 'Unlicensed / Never Licensed' },
}

local WA_BODY_STYLES = {
    { 'sedan', 'Passenger Car — Sedan' }, { 'coupe', 'Passenger Car — Coupe' }, { 'hatchback', 'Passenger Car — Hatchback' },
    { 'wagon', 'Station Wagon' }, { 'suv', 'Sport Utility Vehicle (SUV)' }, { 'pickup', 'Pickup Truck' }, { 'van', 'Van / Minivan' },
    { 'moto', 'Motorcycle' }, { 'truck', 'Truck (Single Unit)' }, { 'semi', 'Truck Tractor' }, { 'bus', 'Bus' },
    { 'rv', 'Motor Home' }, { 'other', 'Other' },
}

local DIRECTIONS = {
    { 'N', 'Northbound' }, { 'S', 'Southbound' }, { 'E', 'Eastbound' }, { 'W', 'Westbound' },
}

--- Date, heure et lieu (Washington)
local function waWhere(opts)
    opts = opts or {}
    return {
        { k = 'date', t = 'date', l = opts.dateLabel or 'Date', req = true, def = 'today', past = true },
        { k = 'time', t = 'time', l = opts.timeLabel or 'Time (24h)', req = true, def = 'now' },
        { k = 'address', t = 'text', l = 'Location (Address / Roadway)', req = true, max = 80, w = 2 },
        { k = 'milepost', t = 'text', l = 'Milepost (State Route)', max = 12, ph = 'ex : SR 520 MP 4.5' },
        { k = 'city', t = 'text', l = 'City / Unincorporated', max = 40, ph = 'ex : Unincorporated' },
        { k = 'county', t = 'select', l = 'County', req = true, def = 'king', o = WA_COUNTIES },
    }
end

--- Personne : nom, DOB, sexe, adresse (+ permis), remplissable depuis l'historique des recherches
local function waPerson(opts)
    opts = opts or {}
    local fields = {
        { t = 'lookup', kind = 'identity',
          map = { lastname = 'lastname', firstname = 'firstname', dob = 'dob', sex = 'sexReport', homeAddress = 'address',
                  dlNumber = 'licenseNumber', dlClass = 'licenseClass', dlState = 'licenseState' } },
        { k = 'lastname', t = 'text', l = 'Last Name', req = opts.req, reqIf = opts.reqIf, max = 40 },
        { k = 'firstname', t = 'text', l = 'First Name', req = opts.req, max = 40 },
        { k = 'dob', t = 'date', l = 'Date of Birth (DOB)', req = opts.req, past = true },
        { k = 'sex', t = 'select', l = 'Sex', o = WA_SEXES },
        { k = 'homeAddress', t = 'text', l = 'Address', max = 80, w = 3 },
        { k = 'phone', t = 'text', l = 'Phone', max = 20 },
    }
    if opts.license then
        fields[#fields + 1] = { k = 'dlNumber', t = 'text', l = 'Driver License No. (OLN)', max = 20, upper = true, req = opts.licenseReq }
        fields[#fields + 1] = { k = 'dlState', t = 'text', l = 'DL State', max = 40, ph = 'ex : WA' }
        fields[#fields + 1] = { k = 'dlClass', t = 'select', l = 'License Type / Class', o = WA_DL_TYPES }
        fields[#fields + 1] = { k = 'dlStatus', t = 'select', l = 'License Status', o = WA_DL_STATUS }
    end
    return fields
end

--- Véhicule (Vehicle License Number = plaque), remplissable depuis l'historique des recherches
local function waVehicle(opts)
    opts = opts or {}
    return {
        { t = 'lookup', kind = 'vehicle',
          map = { plate = 'plate', model = 'makeModel', color = 'color', owner = 'ownerFull', vin = 'vin', year = 'year', insurance = 'insurance' } },
        { k = 'plate', t = 'text', l = 'Vehicle License No. (Plate)', req = opts.req, max = 8, upper = true },
        { k = 'plateState', t = 'text', l = 'Plate State', max = 40, ph = 'ex : WA' },
        { k = 'year', t = 'num', l = 'Year', min = 1900, max = 2100 },
        { k = 'model', t = 'text', l = 'Make / Model', max = 60 },
        { k = 'style', t = 'select', l = 'Body Style', o = WA_BODY_STYLES },
        { k = 'color', t = 'text', l = 'Color', max = 40 },
        { k = 'vin', t = 'text', l = 'VIN', max = 17, upper = true, w = 2 },
        { k = 'owner', t = 'text', l = 'Registered Owner', max = 80, w = 2 },
        { k = 'insurance', t = 'text', l = 'Insurance (Company / Policy No.)', max = 80, w = 2 },
    }
end

--- Liste d'infractions / de charges : classification + infraction du catalogue (liées), et options
local function offenseList(o)
    local classes = CLASS_SETS[o.set] or CLASS_SETS.all
    local f = {
        { k = 'class', t = 'offclass', l = 'Classification', classes = classes, req = true },
        { k = 'code', t = 'offense', l = o.codeLabel or 'Violation (RCW)', classes = classes, classKey = 'class',
          fineKey = o.fine and 'fine' or nil, req = true, w = 3 },
    }
    if o.fine then f[#f + 1] = { k = 'fine', t = 'num', l = 'Penalty Amount', min = 0, max = 100000, money = true } end
    if o.counts then f[#f + 1] = { k = 'counts', t = 'num', l = 'Count(s)', min = 1, max = 50, def = 1 } end
    if o.dv then f[#f + 1] = { k = 'dv', t = 'check', l = 'Domestic Violence (DV) — RCW 10.99' } end
    for _, extra in ipairs(o.extra or {}) do f[#f + 1] = extra end
    f[#f + 1] = { k = 'details', t = 'area', l = o.detailsLabel or 'Facts / Description', max = 1500, rows = 2, w = 4 }
    return { k = o.k, t = 'list', l = o.l, item = o.item, add = o.add, min = o.min or 1, max = o.max or 3, f = f, show = o.show }
end

local CERTIFY = 'I certify (or declare) under penalty of perjury under the laws of the State of Washington that I have '
    .. 'reasonable grounds to believe, and do believe, that the above-named person committed the above offense(s) contrary to law.'

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
    summary = '{lastname} {firstname} — {plate} — {#violations} violation(s)',
    sections = {
        { title = 'Washington Uniform Court Docket — Notice of Infraction', f = (function()
            local fields = {
                { t = 'note', l = 'Infraction civile (pas de casier ni de prison) : traffic infraction (RCW 46.63) ou civil infraction hors route (RCW 7.80). 3 violations au plus par docket, comme sur le formulaire officiel.' },
                { k = 'kind', t = 'select', l = 'Notice Type', req = true, def = 'traffic', w = 2, o = {
                    { 'traffic', 'Notice of Traffic Infraction (RCW 46.63)' }, { 'civil', 'Notice of Civil Infraction (RCW 7.80)' },
                } },
            }
            for _, f in ipairs(waWhere({ dateLabel = 'Date of Violation', timeLabel = 'Time of Violation' })) do fields[#fields + 1] = f end
            fields[#fields + 1] = { k = 'court', t = 'select', l = 'Court', req = true, def = 'kcdc_sea', w = 2, o = WA_COURTS }
            return fields
        end)() },
        { title = 'Driver / Person Charged', f = (function()
            local fields = waPerson({ req = true, license = true })
            fields[#fields + 1] = { k = 'cmv', t = 'check', l = 'Commercial Motor Vehicle (CMV)', show = NOI_TRAFFIC }
            fields[#fields + 1] = { k = 'hazmat', t = 'check', l = 'Hazardous Materials (HAZMAT)', show = NOI_TRAFFIC }
            fields[#fields + 1] = { k = 'collision', t = 'check', l = 'Collision Involved', show = NOI_TRAFFIC }
            return fields
        end)() },
        { title = 'Vehicle', show = NOI_TRAFFIC, f = waVehicle({ req = true }) },
        { title = 'Speed (if applicable)', show = NOI_TRAFFIC, f = {
            { k = 'speedLimit', t = 'num', l = 'Posted Speed Limit', min = 0, max = 85, unit = 'mph' },
            { k = 'speedRecorded', t = 'num', l = 'Alleged Speed', min = 0, max = 250, unit = 'mph' },
            { k = 'speedMethod', t = 'select', l = 'Speed Measured By', o = {
                { 'radar', 'Radar' }, { 'lidar', 'Lidar (Laser)' }, { 'pace', 'Pace — Patrol Vehicle' },
                { 'aircraft', 'Aircraft — WSP Aviation' }, { 'visual', 'Visual Estimate' },
            } },
            { k = 'speedZone', t = 'select', l = 'Special Zone', o = {
                { 'school', 'School / Playground Speed Zone' }, { 'work', 'Roadway Construction Zone — Workers Present' },
            } },
        } },
        { title = 'Violations', f = {
            offenseList({ k = 'violations', l = 'Violations', item = 'Violation', add = '+ Add Violation', set = 'infractions',
                fine = true, max = 3 }),
        } },
        { title = 'Response & Certification', f = {
            { t = 'note', l = 'La personne doit répondre sous 30 jours (RCW 46.63.070) : payer la pénalité, demander une audience d\'atténuation (mitigation hearing) ou contester l\'infraction (contested hearing). Sans réponse : défaut, pénalité majorée, et pour une traffic infraction suspension du permis.' },
            { k = 'signed', t = 'select', l = 'Signature', w = 2, o = {
                { 'signed', 'Signed — Promise to Respond' }, { 'refused', 'Refused to Sign' }, { 'mailed', 'Served by Mail' },
            } },
            certification(),
        } },
        { title = 'Officer Notes', f = { narrative('Officer Notes (not printed on the docket)', false) } },
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
    summary = '{lastname} {firstname} — {#charges} charge(s)',
    sections = {
        { title = 'Washington Uniform Court Docket — Criminal Citation', f = (function()
            local fields = {
                { t = 'note', l = 'Délits seulement (misdemeanor, gross misdemeanor) : un crime (felony) se traite par une arrestation (Arrest Report). 3 charges au plus par docket.' },
            }
            for _, f in ipairs(waWhere({ dateLabel = 'Date of Offense', timeLabel = 'Time of Offense' })) do fields[#fields + 1] = f end
            fields[#fields + 1] = { k = 'traffic', t = 'check', l = 'Criminal Traffic (vehicle involved)' }
            return fields
        end)() },
        { title = 'Defendant', f = waPerson({ req = true, license = true }) },
        { title = 'Vehicle', show = CC_VEHICLE, f = waVehicle({ req = true }) },
        { title = 'Charges', f = {
            offenseList({ k = 'charges', l = 'Charges', item = 'Charge', add = '+ Add Charge', set = 'citable',
                codeLabel = 'Charge (RCW)', dv = true, max = 3 }),
        } },
        { title = 'Notice to Appear', f = {
            { k = 'court', t = 'select', l = 'Court', req = true, def = 'kcdc_sea', w = 2, o = WA_COURTS },
            { k = 'appearDate', t = 'date', l = 'Appearance Date', req = true },
            { k = 'appearTime', t = 'time', l = 'Appearance Time', req = true, def = '08:30' },
            { k = 'custodyStatus', t = 'select', l = 'Custody Status', req = true, w = 2, o = {
                { 'released', 'Released on Citation (Promise to Appear)' }, { 'booked', 'Booked Into Jail' },
            } },
            { k = 'jail', t = 'select', l = 'Booking Facility', req = true, w = 2, o = WA_JAILS, show = { k = 'custodyStatus', eq = 'booked' } },
            { k = 'signed', t = 'select', l = 'Defendant Signature', w = 2, o = {
                { 'signed', 'Signed — Promise to Appear' }, { 'refused', 'Refused to Sign' },
            } },
            { t = 'note', l = 'Refus de signer la promesse de comparaître : la personne peut être placée en détention.', show = { k = 'signed', eq = 'refused' } },
            certification(),
        } },
        { title = 'Statement of Probable Cause', f = { narrative('Statement of Probable Cause') } },
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
    summary = '{lastname} {firstname} — {plate} — {#violations} violation(s)',
    sections = {
        { title = 'Written Warning', f = (function()
            local fields = {
                { t = 'note', l = 'Avertissement écrit : aucune pénalité ni suite au tribunal ; il reste au dossier de la personne.' },
                { k = 'kind', t = 'select', l = 'Contact Type', req = true, def = 'traffic', w = 2, o = {
                    { 'traffic', 'Traffic Stop' }, { 'other', 'Other Contact' },
                } },
            }
            for _, f in ipairs(waWhere()) do fields[#fields + 1] = f end
            return fields
        end)() },
        { title = 'Driver / Person Warned', f = waPerson({ req = true, license = true }) },
        { title = 'Vehicle', show = WW_TRAFFIC, f = waVehicle({ req = true }) },
        { title = 'Violations', f = {
            offenseList({ k = 'violations', l = 'Violations', item = 'Violation', add = '+ Add Violation', set = 'infractions', max = 3,
                detailsLabel = 'Facts / Correction Required' }),
        } },
        { title = 'Officer Notes', f = { narrative('Officer Notes', false) } },
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
    summary = '{lastname} {firstname} — {#charges} charge(s)',
    sections = {
        { title = 'Arrest Information', f = (function()
            local fields = waWhere({ dateLabel = 'Date of Arrest', timeLabel = 'Time of Arrest' })
            fields[#fields + 1] = { k = 'arrestType', t = 'select', l = 'Type of Arrest', req = true, w = 2, o = {
                { 'onview', 'On-View Arrest' }, { 'pc', 'Probable Cause Arrest' }, { 'warrant', 'Warrant Arrest' },
                { 'citizen', 'Citizen Arrest — Turned Over' },
            } }
            fields[#fields + 1] = { k = 'warrantNo', t = 'text', l = 'Warrant No.', req = true, max = 30, upper = true, show = ARREST_WARRANT }
            fields[#fields + 1] = { k = 'warrantCourt', t = 'select', l = 'Issuing Court', w = 2, o = WA_COURTS, show = ARREST_WARRANT }
            return fields
        end)() },
        { title = 'Arrestee', f = (function()
            local fields = waPerson({ req = true, license = true })
            fields[#fields + 1] = { k = 'height', t = 'text', l = 'Height', max = 10, ph = 'ex : 5\'10"' }
            fields[#fields + 1] = { k = 'weight', t = 'num', l = 'Weight', min = 50, max = 700, unit = 'lbs' }
            fields[#fields + 1] = { k = 'hair', t = 'text', l = 'Hair', max = 20 }
            fields[#fields + 1] = { k = 'eyes', t = 'text', l = 'Eyes', max = 20 }
            fields[#fields + 1] = { k = 'marks', t = 'text', l = 'Scars, Marks & Tattoos (SMT)', max = 120, w = 4 }
            return fields
        end)() },
        { title = 'Charges', f = {
            offenseList({ k = 'charges', l = 'Charges', item = 'Charge', add = '+ Add Charge', set = 'criminal',
                codeLabel = 'Charge (RCW)', counts = true, dv = true, max = 20,
                extra = { { k = 'charge', t = 'text', l = 'Additional Description', max = 120, w = 2 } } }),
        } },
        { title = 'Constitutional Rights, Force & Custody', f = {
            { k = 'miranda', t = 'check', l = 'Advised of Constitutional Rights (Miranda)' },
            { k = 'mirandaTime', t = 'time', l = 'Time Advised', show = { k = 'miranda', eq = true } },
            { k = 'waiver', t = 'select', l = 'Rights', w = 2, show = { k = 'miranda', eq = true }, o = {
                { 'waived', 'Waived — Agreed to Answer Questions' }, { 'attorney', 'Invoked — Requested an Attorney' },
                { 'silent', 'Invoked — Remained Silent' },
            } },
            { k = 'force', t = 'check', l = 'Use of Force' },
            { k = 'injuries', t = 'check', l = 'Arrestee Injured' },
            { k = 'forceDetails', t = 'area', l = 'Use of Force — Details', req = true, max = 1000, rows = 3, w = 4, show = { k = 'force', eq = true } },
            { k = 'injuryDetails', t = 'area', l = 'Injuries — Details', req = true, max = 1000, rows = 3, w = 4, show = { k = 'injuries', eq = true } },
            { k = 'medical', t = 'select', l = 'Medical', w = 2, o = {
                { 'none', 'Not Required' }, { 'cleared', 'Medically Cleared (Fire / EMS)' }, { 'hospital', 'Transported to Hospital' },
            } },
            { k = 'seized', t = 'area', l = 'Property / Evidence Seized', max = 1500, rows = 3, w = 4 },
            { k = 'jail', t = 'select', l = 'Booking Facility', req = true, w = 2, o = WA_JAILS },
            { k = 'custody', t = 'text', l = 'Booking No. / Notes', max = 80, w = 2 },
            { k = 'vehDisposition', t = 'select', l = 'Arrestee\'s Vehicle', w = 2, o = {
                { 'na', 'N/A' }, { 'impound', 'Impounded (see Impound Report)' }, { 'released', 'Released to Licensed Driver' },
                { 'parked', 'Left Legally Parked' },
            } },
        } },
        { title = 'Certification for Determination of Probable Cause', f = {
            { t = 'note', l = 'Exposé des faits établissant la cause probable (probable cause), lu par le juge pour maintenir la détention.' },
            narrative('Probable Cause Narrative'),
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
        { title = 'Incident', f = (function()
            local fields = waWhere()
            fields[#fields + 1] = { k = 'contactReason', t = 'select', l = 'Reason for Contact', req = true, w = 2, o = {
                { 'traffic', 'Traffic Violation' }, { 'collision', 'Collision' }, { 'pc', 'Physical Control — Occupied Parked Vehicle' },
                { 'citizen', 'Citizen Report' }, { 'other', 'Other' },
            } }
            return fields
        end)() },
        { title = 'Subject', f = waPerson({ req = true, license = true }) },
        { title = 'Vehicle', f = waVehicle() },
        { title = 'Driving Observations', f = {
            { k = 'driving', t = 'checks', l = 'Observed', ph = 'cochez tout ce qui s\'applique', o = {
                { 'weaving', 'Weaving' }, { 'lane', 'Lane Travel Violation' }, { 'speed', 'Speed Variance' },
                { 'wide', 'Wide Turn' }, { 'braking', 'Erratic Braking' }, { 'nolights', 'No Headlights' },
                { 'stopped', 'Stopped in Roadway' }, { 'collision', 'Collision' }, { 'slow', 'Slow Response to Signals' },
            } },
        } },
        { title = 'Observations at Contact', f = {
            { k = 'contact', t = 'checks', l = 'Observed', ph = 'cochez tout ce qui s\'applique', o = {
                { 'odor', 'Odor of Intoxicants' }, { 'eyes', 'Bloodshot / Watery Eyes' }, { 'speech', 'Slurred Speech' },
                { 'balance', 'Unsteady Balance' }, { 'fumble', 'Fumbled Documents' }, { 'admit', 'Admitted Drinking' },
                { 'containers', 'Open Containers in Vehicle' }, { 'drugs', 'Signs of Drug Impairment' },
            } },
            { k = 'admission', t = 'text', l = 'Statement — Amount / Type Consumed', max = 120, w = 4 },
        } },
        { title = 'Standardized Field Sobriety Tests (SFST)', f = {
            { k = 'sfst', t = 'select', l = 'SFSTs', req = true, w = 2, o = {
                { 'performed', 'Performed (Voluntary)' }, { 'refused', 'Refused' }, { 'na', 'Not Offered — Safety / Medical' },
            } },
            { k = 'hgn', t = 'num', l = 'HGN — Clues (of 6)', min = 0, max = 6, show = SFST_DONE },
            { k = 'wat', t = 'num', l = 'Walk-and-Turn — Clues (of 8)', min = 0, max = 8, show = SFST_DONE },
            { k = 'ols', t = 'num', l = 'One-Leg Stand — Clues (of 4)', min = 0, max = 4, show = SFST_DONE },
            { k = 'pbt', t = 'text', l = 'Portable Breath Test (PBT)', max = 6, ph = '0.000' },
        } },
        { title = 'Arrest, Implied Consent & Evidential Test', f = {
            { k = 'miranda', t = 'check', l = 'Advised of Constitutional Rights (Miranda)' },
            { k = 'implied', t = 'check', l = 'Implied Consent Warning for Breath Read (RCW 46.20.308)' },
            { k = 'testType', t = 'select', l = 'Evidential Test', req = true, w = 2, o = {
                { 'breath', 'Breath Test — BAC DataMaster DMT' }, { 'bloodwarrant', 'Blood Draw — Search Warrant' },
                { 'bloodconsent', 'Blood Draw — Consent' }, { 'refused', 'Refused Breath Test' }, { 'none', 'No Test — Medical / Unable' },
            } },
            { k = 'brac1', t = 'text', l = 'Breath Sample 1 (BrAC)', max = 6, ph = '0.000', show = { k = 'testType', eq = 'breath' } },
            { k = 'brac2', t = 'text', l = 'Breath Sample 2 (BrAC)', max = 6, ph = '0.000', show = { k = 'testType', eq = 'breath' } },
            { k = 'bloodResult', t = 'text', l = 'Blood Result (WSP Toxicology Lab)', max = 60, w = 2,
              show = { k = 'testType', ['in'] = { 'bloodwarrant', 'bloodconsent' } } },
            { k = 'dre', t = 'check', l = 'Drug Recognition Expert (DRE) Evaluation' },
        } },
        { title = 'Charges', f = {
            offenseList({ k = 'charges', l = 'Charges', item = 'Charge', add = '+ Add Charge', set = 'criminal',
                codeLabel = 'Charge (RCW)', max = 6 }),
        } },
        { title = 'Disposition', f = {
            { k = 'vehDisposition', t = 'select', l = 'Vehicle', req = true, w = 2, o = {
                { 'impound', 'Impounded — 12-Hour DUI Hold (RCW 46.55.360)' }, { 'released', 'Released to Licensed Driver' },
                { 'parked', 'Left Legally Parked' }, { 'na', 'N/A' },
            } },
            { k = 'custodyStatus', t = 'select', l = 'Custody Status', req = true, w = 2, o = {
                { 'booked', 'Booked Into Jail' }, { 'released', 'Released on Citation' }, { 'hospital', 'Released to Hospital' },
            } },
            { k = 'jail', t = 'select', l = 'Booking Facility', req = true, w = 2, o = WA_JAILS, show = { k = 'custodyStatus', eq = 'booked' } },
        } },
        { title = 'Narrative / Probable Cause', f = { narrative('Narrative — Probable Cause'), certification() } },
    },
}

-- -------------------------------------------------------------------------
-- POLICE TRAFFIC COLLISION REPORT (PTCR — SECTOR)
-- -------------------------------------------------------------------------
local KABCO = {
    { 'O', 'O — No Apparent Injury' }, { 'C', 'C — Possible Injury' }, { 'B', 'B — Suspected Minor Injury' },
    { 'A', 'A — Suspected Serious Injury' }, { 'K', 'K — Fatal Injury' },
}
local RESTRAINTS = {
    { 'belt', 'Lap & Shoulder Belt' }, { 'lap', 'Lap Belt Only' }, { 'child', 'Child Restraint' },
    { 'helmet', 'Helmet (Motorcycle / Bicycle)' }, { 'none', 'None Used' }, { 'unknown', 'Unknown' },
}
local EJECTION = { { 'no', 'Not Ejected' }, { 'partial', 'Partially Ejected' }, { 'total', 'Totally Ejected' }, { 'trapped', 'Trapped' } }
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
        { title = 'Collision Information', f = {
            { t = 'note', l = 'Collision à déclarer : blessé, mort, ou dégâts d\'au moins 1 000 $ (RCW 46.52.030).' },
            { k = 'date', t = 'date', l = 'Date of Collision', req = true, def = 'today', past = true },
            { k = 'time', t = 'time', l = 'Time (24h)', req = true, def = 'now' },
            { k = 'county', t = 'select', l = 'County', req = true, def = 'king', o = WA_COUNTIES },
            { k = 'city', t = 'text', l = 'City / Unincorporated', max = 40 },
            { k = 'street', t = 'text', l = 'Roadway / Street', req = true, max = 80, w = 2 },
            { k = 'crossStreet', t = 'text', l = 'At Intersection With', max = 80, w = 2 },
            { k = 'milepost', t = 'text', l = 'Milepost (State Route)', max = 12 },
            { k = 'refDistance', t = 'text', l = 'Distance From Reference Point', max = 30, ph = 'ex : 200 ft N of' },
            { k = 'agency', t = 'text', l = 'Investigating Agency', req = true, max = 80, w = 2, def = 'unitAgency' },
            { k = 'hitRun', t = 'check', l = 'Hit and Run' },
            { k = 'damage1000', t = 'check', l = 'Property Damage $1,000 or More' },
            { k = 'injured', t = 'num', l = 'Number Injured', min = 0, max = 99 },
            { k = 'killed', t = 'num', l = 'Number Killed', min = 0, max = 99 },
        } },
        { title = 'Environment & Roadway', f = {
            { k = 'collisionType', t = 'select', l = 'Collision Type', req = true, w = 2, o = {
                { 'rearend', 'Rear End (Front to Rear)' }, { 'headon', 'Head On (Front to Front)' },
                { 'angle', 'Angle (Entering at Angle / T-Bone)' }, { 'sssame', 'Sideswipe — Same Direction' },
                { 'ssopp', 'Sideswipe — Opposite Direction' }, { 'reartoside', 'Rear to Side' }, { 'reartorear', 'Rear to Rear (Backing)' },
                { 'fixed', 'Fixed Object' }, { 'overturn', 'Overturn / Rollover' }, { 'ped', 'Pedestrian' },
                { 'cyclist', 'Pedalcyclist' }, { 'parked', 'Parked Vehicle' }, { 'animal', 'Animal' }, { 'other', 'Other / Non-Collision' },
            } },
            { k = 'weather', t = 'select', l = 'Weather', req = true, w = 2, o = {
                { 'clear', 'Clear or Partly Cloudy' }, { 'overcast', 'Overcast' }, { 'rain', 'Raining' }, { 'snow', 'Snowing' },
                { 'fog', 'Fog / Smog / Smoke' }, { 'sleet', 'Sleet / Hail / Freezing Rain' }, { 'wind', 'Severe Crosswind' },
                { 'blowing', 'Blowing Sand / Dirt / Snow' }, { 'unknown', 'Unknown' },
            } },
            { k = 'light', t = 'select', l = 'Lighting Condition', w = 2, o = {
                { 'day', 'Daylight' }, { 'dawn', 'Dawn' }, { 'dusk', 'Dusk' }, { 'darklit', 'Dark — Street Lights On' },
                { 'darkoff', 'Dark — Street Lights Off' }, { 'dark', 'Dark — No Street Lights' }, { 'unknown', 'Unknown' },
            } },
            { k = 'surface', t = 'select', l = 'Roadway Surface Condition', w = 2, o = {
                { 'dry', 'Dry' }, { 'wet', 'Wet' }, { 'snow', 'Snow / Slush' }, { 'ice', 'Ice / Frost' },
                { 'water', 'Standing Water' }, { 'sand', 'Sand / Mud / Dirt' }, { 'oil', 'Oil' }, { 'other', 'Other' },
            } },
            { k = 'junction', t = 'select', l = 'Junction Relationship', w = 2, o = {
                { 'intersection', 'At Intersection and Related' }, { 'intrelated', 'Intersection Related — Not at Intersection' },
                { 'notint', 'Not at Intersection' }, { 'driveway', 'Driveway Related' }, { 'ramp', 'At Ramp Junction' }, { 'alley', 'Alley' },
            } },
            { k = 'control', t = 'select', l = 'Traffic Control', w = 2, o = {
                { 'none', 'None' }, { 'signal', 'Traffic Signal' }, { 'stop', 'Stop Sign' }, { 'yield', 'Yield Sign' },
                { 'flashing', 'Flashing Signal' }, { 'rr', 'Railroad Crossing Device' }, { 'officer', 'Officer / Flagger' },
                { 'roundabout', 'Roundabout' },
            } },
            { k = 'workZone', t = 'select', l = 'Work Zone', o = {
                { 'no', 'No' }, { 'workers', 'Yes — Workers Present' }, { 'noworkers', 'Yes — No Workers Present' },
            } },
            { k = 'roadType', t = 'select', l = 'Roadway Classification', w = 2, o = {
                { 'interstate', 'Interstate' }, { 'us_highway', 'US Route' }, { 'state_route', 'State Route (SR)' },
                { 'county_road', 'County Road' }, { 'city_street', 'City Street' }, { 'private', 'Private Road / Parking Lot' },
            } },
            { k = 'lanes', t = 'num', l = 'Number of Lanes', min = 1, max = 12 },
        } },
        { title = 'Units Involved', f = {
            { k = 'units', t = 'list', l = 'Units', item = 'Unit', add = '+ Add Unit', min = 1, max = 10, f = {
                { k = 'unitType', t = 'select', l = 'Unit Type', req = true, w = 2, o = {
                    { 'mv', 'Motor Vehicle in Transport' }, { 'parked', 'Parked Motor Vehicle' }, { 'ped', 'Pedestrian' },
                    { 'cyclist', 'Pedalcyclist' }, { 'hr', 'Hit and Run Vehicle — Driver Unknown' },
                } },
                { t = 'group', l = 'Driver / Pedestrian / Pedalcyclist', show = UNIT_PERSON, f = {
                    { t = 'lookup', kind = 'identity',
                      map = { lastname = 'lastname', firstname = 'firstname', dob = 'dob', sex = 'sexReport', address = 'address',
                              dlNumber = 'licenseNumber', dlClass = 'licenseClass', dlState = 'licenseState' } },
                    { k = 'lastname', t = 'text', l = 'Last Name', req = true, max = 40 },
                    { k = 'firstname', t = 'text', l = 'First Name', max = 40 },
                    { k = 'dob', t = 'date', l = 'Date of Birth (DOB)', past = true },
                    { k = 'sex', t = 'select', l = 'Sex', o = WA_SEXES },
                    { k = 'address', t = 'text', l = 'Address', max = 80, w = 3 },
                    { k = 'phone', t = 'text', l = 'Phone', max = 20 },
                    { k = 'dlNumber', t = 'text', l = 'Driver License No. (OLN)', max = 20, upper = true, show = UNIT_MOVING },
                    { k = 'dlState', t = 'text', l = 'DL State', max = 40, show = UNIT_MOVING },
                    { k = 'dlClass', t = 'select', l = 'License Type / Class', o = WA_DL_TYPES, show = UNIT_MOVING },
                    { k = 'dlStatus', t = 'select', l = 'License Status', o = WA_DL_STATUS, show = UNIT_MOVING },
                    { k = 'injury', t = 'select', l = 'Injury (KABCO)', req = true, w = 2, o = KABCO },
                    { k = 'restraint', t = 'select', l = 'Restraint / Helmet', o = RESTRAINTS },
                    { k = 'airbag', t = 'select', l = 'Airbag', show = UNIT_MOVING, o = {
                        { 'none', 'Not Deployed' }, { 'front', 'Deployed — Front' }, { 'side', 'Deployed — Side' },
                        { 'multiple', 'Deployed — Multiple' }, { 'na', 'Not Applicable' },
                    } },
                    { k = 'ejection', t = 'select', l = 'Ejection', o = EJECTION },
                    { k = 'condition', t = 'select', l = 'Sobriety', w = 2, o = {
                        { 'hnbd', 'Had Not Been Drinking' }, { 'hbdimpaired', 'HBD — Ability Impaired' },
                        { 'hbdnot', 'HBD — Ability Not Impaired' }, { 'hbdunknown', 'HBD — Unknown if Impaired' },
                        { 'drugs', 'Under Influence of Drugs' }, { 'unknown', 'Unknown' },
                    } },
                    { k = 'sobrietyTest', t = 'select', l = 'Test Given', o = {
                        { 'none', 'None' }, { 'breath', 'Breath' }, { 'blood', 'Blood' }, { 'refused', 'Refused' },
                    } },
                    { k = 'distraction', t = 'select', l = 'Driver Distraction', w = 2, show = UNIT_MOVING, o = {
                        { 'none', 'Not Distracted' }, { 'phonetalk', 'Cell Phone — Talking' }, { 'phonetext', 'Cell Phone — Texting / Browsing' },
                        { 'device', 'Other Electronic Device' }, { 'passenger', 'Passenger' }, { 'outside', 'Outside the Vehicle' },
                        { 'unknown', 'Unknown' },
                    } },
                    { k = 'contributing', t = 'checks', l = 'Contributing Circumstances', ph = 'cochez tout ce qui s\'applique', o = {
                        { 'none', 'None' }, { 'reasspeed', 'Exceeding Reasonably Safe Speed' }, { 'limit', 'Exceeding Stated Speed Limit' },
                        { 'row', 'Did Not Grant Right-of-Way to Vehicle' }, { 'signal', 'Disregard Stop Sign / Signal' },
                        { 'follow', 'Following Too Closely' }, { 'passing', 'Improper Passing' }, { 'center', 'Over Center Line' },
                        { 'inattention', 'Inattention' }, { 'alcohol', 'Under Influence of Alcohol' }, { 'drugs', 'Under Influence of Drugs' },
                        { 'asleep', 'Apparently Asleep / Fatigued' }, { 'turn', 'Improper Turn' }, { 'backing', 'Improper Backing' },
                        { 'defective', 'Operating Defective Equipment' }, { 'pedrow', 'Failure to Yield to Pedestrian' },
                        { 'pedaction', 'Pedestrian / Cyclist Action' },
                    } },
                    { k = 'transportedTo', t = 'text', l = 'Transported To (Hospital / EMS)', max = 80, w = 2, ph = 'ex : Harborview Medical Center' },
                    { k = 'cited', t = 'check', l = 'Citation / NOI Issued' },
                    offenseList({ k = 'violations', l = 'Violations Cited', item = 'Violation', add = '+ Add Violation', set = 'all',
                        min = 0, max = 3, show = { k = 'cited', eq = true } }),
                } },
                { t = 'group', l = 'Vehicle', show = UNIT_DRIVEN, f = {
                    { t = 'lookup', kind = 'vehicle',
                      map = { plate = 'plate', vin = 'vin', model = 'makeModel', year = 'year', owner = 'ownerFull', insurance = 'insurance' } },
                    { k = 'plate', t = 'text', l = 'Vehicle License No. (Plate)', max = 8, upper = true },
                    { k = 'plateState', t = 'text', l = 'Plate State', max = 40 },
                    { k = 'year', t = 'num', l = 'Year', min = 1900, max = 2100 },
                    { k = 'model', t = 'text', l = 'Make / Model', max = 60 },
                    { k = 'vehType', t = 'select', l = 'Body Style', o = WA_BODY_STYLES },
                    { k = 'vin', t = 'text', l = 'VIN', max = 17, upper = true, w = 2 },
                    { k = 'owner', t = 'text', l = 'Registered Owner', max = 80, w = 2 },
                    { k = 'insurance', t = 'text', l = 'Insurance (Company / Policy No.)', max = 80, w = 2 },
                    { k = 'direction', t = 'select', l = 'Direction of Travel', o = DIRECTIONS },
                    { k = 'action', t = 'select', l = 'Vehicle Action', w = 2, o = {
                        { 'straight', 'Going Straight Ahead' }, { 'right', 'Making Right Turn' }, { 'left', 'Making Left Turn' },
                        { 'uturn', 'Making U-Turn' }, { 'slowing', 'Slowing' }, { 'stopped', 'Stopped for Traffic' },
                        { 'starting', 'Starting From Parked' }, { 'backing', 'Backing' }, { 'lane', 'Changing Lanes' },
                        { 'overtaking', 'Overtaking / Passing' }, { 'merging', 'Merging' }, { 'parked', 'Legally Parked' },
                    } },
                    { k = 'speedLimit', t = 'num', l = 'Posted Speed Limit', min = 0, max = 85, unit = 'mph' },
                    { k = 'estSpeed', t = 'num', l = 'Estimated Speed', min = 0, max = 250, unit = 'mph' },
                    { k = 'damage', t = 'select', l = 'Vehicle Damage Severity', o = {
                        { 'none', 'None' }, { 'minor', 'Minor' }, { 'functional', 'Functional' }, { 'disabling', 'Disabling' },
                    } },
                    { k = 'damageCost', t = 'num', l = 'Estimated Damage', min = 0, max = 10000000, money = true },
                    { k = 'towed', t = 'select', l = 'Towed', o = {
                        { 'no', 'Not Towed' }, { 'damage', 'Towed — Due to Damage' }, { 'other', 'Towed — Other Reason' },
                    } },
                    { k = 'towCompany', t = 'text', l = 'Tow Company', max = 60, w = 2 },
                    { k = 'cmv', t = 'check', l = 'Commercial Motor Vehicle (CMV)' },
                    { k = 'company', t = 'text', l = 'Motor Carrier Name', req = true, max = 80, w = 2, show = { k = 'cmv', eq = true } },
                    { k = 'usdot', t = 'text', l = 'USDOT No.', req = true, max = 10, show = { k = 'cmv', eq = true } },
                    { k = 'hazmat', t = 'check', l = 'Hazardous Materials Placard', show = { k = 'cmv', eq = true } },
                } },
                { k = 'occupants', t = 'list', l = 'Passengers', item = 'Passenger', add = '+ Add Passenger', min = 0, max = 8,
                  show = UNIT_DRIVEN, f = {
                    { k = 'name', t = 'text', l = 'Full Name', req = true, max = 80, w = 2 },
                    { k = 'dob', t = 'date', l = 'Date of Birth (DOB)', past = true },
                    { k = 'seat', t = 'select', l = 'Seating Position', o = {
                        { 'front_mid', 'Front Middle' }, { 'front', 'Front Right' }, { 'rear_left', 'Second Row Left' },
                        { 'rear_center', 'Second Row Middle' }, { 'rear_right', 'Second Row Right' }, { 'third', 'Third Row' },
                        { 'cargo', 'Cargo Area' }, { 'other', 'Other' },
                    } },
                    { k = 'injury', t = 'select', l = 'Injury (KABCO)', o = KABCO, w = 2 },
                    { k = 'restraint', t = 'select', l = 'Restraint', o = RESTRAINTS },
                    { k = 'ejection', t = 'select', l = 'Ejection', o = EJECTION },
                } },
            } },
        } },
        { title = 'Narrative & Diagram Description', f = { narrative('Narrative — Sequence of Events and Diagram Description') } },
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
        { title = 'Incident Information', f = (function()
            local fields = waWhere({ dateLabel = 'Date Occurred', timeLabel = 'Time Occurred' })
            table.insert(fields, 1, { k = 'nature', t = 'text', l = 'Incident Type / Nature', req = true, max = 80, w = 3 })
            table.insert(fields, 2, { k = 'dv', t = 'check', l = 'Domestic Violence (DV)' })
            return fields
        end)() },
        { title = 'Offenses', f = {
            offenseList({ k = 'offenses', l = 'Offenses', item = 'Offense', add = '+ Add Offense', set = 'all',
                codeLabel = 'Offense (RCW)', min = 0, max = 10 }),
        } },
        { title = 'Involved Persons', f = {
            { k = 'persons', t = 'list', l = 'Persons', item = 'Person', add = '+ Add Person', min = 0, max = 15, f = (function()
                local fields = waPerson({ req = true })
                table.insert(fields, 1, { k = 'role', t = 'select', l = 'Role', req = true, o = {
                    { 'victim', 'Victim (V)' }, { 'suspect', 'Suspect (S)' }, { 'arrestee', 'Arrestee (A)' }, { 'witness', 'Witness (W)' },
                    { 'caller', 'Reporting Party (RP)' }, { 'other', 'Other / Involved (O)' },
                } })
                fields[#fields + 1] = { k = 'statement', t = 'area', l = 'Statement', max = 1500, rows = 3, w = 4 }
                return fields
            end)() },
            { k = 'vehicles', t = 'list', l = 'Vehicles', item = 'Vehicle', add = '+ Add Vehicle', min = 0, max = 10, f = (function()
                local fields = waVehicle({ req = true })
                fields[#fields + 1] = { k = 'role', t = 'select', l = 'Involvement', o = {
                    { 'suspect', 'Suspect Vehicle' }, { 'victim', 'Victim Vehicle' }, { 'witness', 'Witness Vehicle' },
                    { 'stolen', 'Stolen' }, { 'recovered', 'Recovered' }, { 'other', 'Other' },
                } }
                fields[#fields + 1] = { k = 'notes', t = 'text', l = 'Notes', max = 200, w = 3 }
                return fields
            end)() },
        } },
        { title = 'Property & Evidence', f = {
            { k = 'evidence', t = 'area', l = 'Property (Stolen / Recovered / Damaged) and Evidence Collected', max = 1500, rows = 4, w = 4 },
        } },
        { title = 'Narrative', f = { narrative() } },
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
        { title = 'Impound Information', f = (function()
            local fields = waWhere()
            fields[#fields + 1] = { k = 'authority', t = 'select', l = 'Impound Authority', req = true, w = 4, o = {
                { 'hazard', 'Traffic Hazard / Obstruction — RCW 46.55.113' },
                { 'arrest', 'Driver Arrested — RCW 46.55.113' },
                { 'dwls', 'Driving While License Suspended — RCW 46.55.113' },
                { 'dui', 'DUI Arrest — 12-Hour Hold, RCW 46.55.360' },
                { 'abandoned', 'Abandoned Vehicle (24 h Tag) — RCW 46.55.085' },
                { 'private', 'Private Property Impound — RCW 46.55.080' },
                { 'stolen', 'Stolen Vehicle Recovered' },
                { 'evidence', 'Evidence / Investigative Hold' },
                { 'collision', 'Collision — Owner / Driver Unable to Arrange Removal' },
                { 'other', 'Other' },
            } }
            fields[#fields + 1] = { k = 'hold', t = 'check', l = 'Police Hold' }
            fields[#fields + 1] = { k = 'holdReason', t = 'text', l = 'Hold Reason / Released Only To', max = 120, w = 3, show = { k = 'hold', eq = true } }
            return fields
        end)() },
        { title = 'Vehicle', f = (function()
            local fields = waVehicle({ req = true })
            fields[#fields + 1] = { k = 'keys', t = 'check', l = 'Keys With Vehicle' }
            fields[#fields + 1] = { k = 'condition', t = 'area', l = 'Vehicle Condition / Existing Damage', max = 800, rows = 2, w = 4 }
            return fields
        end)() },
        { title = 'Driver / Person in Control', f = waPerson({ license = true }) },
        { title = 'Tow', f = {
            { k = 'towCompany', t = 'text', l = 'Registered Tow Truck Operator (RTTO)', req = true, max = 80, w = 2 },
            { k = 'towDest', t = 'text', l = 'Storage Location', max = 80, w = 2 },
            { k = 'towTime', t = 'time', l = 'Time Tow Arrived' },
        } },
        { title = 'Inventory', f = {
            { k = 'inventory', t = 'area', l = 'Inventory of Personal Property (Visible / Unlocked Areas)', max = 2000, rows = 4, w = 4 },
        } },
        { title = 'Officer Notes', f = { narrative('Officer Notes', false) } },
    },
}

MDC_REPORT_TYPES = { NOI, CRIMCITE, WWARNING, ARREST, DUI, PTCR, INCIDENT, IMPOUND,
    -- anciens modèles (archived : lecture seule, absents des boutons)
    DOT523, CITATION, TRAFFIC, CONVOCATION, WARNING, TICKET }
