--[[
    MDC Standalone - Modèles des RAPPORTS (onglet "Rapports")
    ---------------------------------------------------------
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
      ph    = texte                   exemple affiché dans un champ vide (texte d'aide pour 'checks')
      def   = valeur par défaut       ('today', 'now', 'unitDept' = service de l'unité du joueur, ou une valeur)
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
local LICENSE_CLASSES = {
    { 'N/A', 'Aucune' },
    { 'Class C - Standard', 'Class C - Standard' },
    { 'Class F - Lourd', 'Class F - Lourd' },
    { 'Class E - Combiné', 'Class E - Combiné' },
    { 'Class M - Moto', 'Class M - Moto' },
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
                { k = 'agency', t = 'text', l = 'Service de police', req = true, max = 80, w = 2, def = 'unitDept', ph = 'ex : Atlanta Police Department' },
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
local ARREST = {
    id = 'arrest',
    label = 'Arrest Report',
    short = 'Arrest',
    summary = '{lastname} {firstname} — {#charges} charge(s)',
    sections = {
        { title = 'Informations générales', f = whenWhere() },
        { title = 'Personne arrêtée', f = (function()
            local fields = person({ req = true, license = true })
            fields[#fields + 1] = { k = 'marks', t = 'text', l = 'Signes distinctifs', max = 120, w = 4 }
            return fields
        end)() },
        { title = 'Charges', f = {
            { k = 'charges', t = 'list', l = 'Charges', item = 'Charge', add = '+ Ajouter une charge', min = 1, max = 20, f = {
                { k = 'charge', t = 'text', l = 'Charge', req = true, max = 120, w = 4 },
                { k = 'details', t = 'area', l = 'Détail de la charge', max = 1500, rows = 3, w = 4 },
            } },
        } },
        { title = 'Arrestation', f = {
            { k = 'miranda', t = 'check', l = 'Droits Miranda lus' },
            { k = 'force', t = 'check', l = 'Usage de la force' },
            { k = 'injuries', t = 'check', l = 'Blessures' },
            { k = 'forceDetails', t = 'area', l = 'Détails de l\'usage de la force', req = true, max = 1000, rows = 3, w = 4, show = { k = 'force', eq = true } },
            { k = 'injuryDetails', t = 'area', l = 'Détails des blessures', req = true, max = 1000, rows = 3, w = 4, show = { k = 'injuries', eq = true } },
            { k = 'seized', t = 'area', l = 'Objets saisis / preuves', max = 1500, rows = 3, w = 4 },
            { k = 'custody', t = 'text', l = 'Lieu de détention', max = 80, w = 2 },
        } },
        { title = 'Rapport narratif', f = { narrative() } },
    },
}

local INCIDENT = {
    id = 'incident',
    label = 'Incident Report',
    short = 'Incident',
    summary = '{nature} — {address}',
    sections = {
        { title = 'Informations générales', f = (function()
            local fields = whenWhere()
            table.insert(fields, 1, { k = 'nature', t = 'text', l = 'Nature de l\'incident', req = true, max = 80, w = 4 })
            return fields
        end)() },
        { title = 'Impliqués', f = {
            { k = 'persons', t = 'list', l = 'Individus', item = 'Individu', add = '+ Ajouter un individu', min = 0, max = 15, f = (function()
                local fields = person({ req = true })
                table.insert(fields, 1, { k = 'role', t = 'select', l = 'Rôle', req = true, o = {
                    { 'victim', 'Victime' }, { 'suspect', 'Suspect' }, { 'witness', 'Témoin' }, { 'caller', 'Requérant' }, { 'other', 'Autre' },
                } })
                fields[#fields + 1] = { k = 'phone', t = 'text', l = 'Téléphone', max = 20 }
                fields[#fields + 1] = { k = 'statement', t = 'area', l = 'Déclaration', max = 1500, rows = 3, w = 4 }
                return fields
            end)() },
            -- Véhicules enregistrés (liste déroulante de l'historique des recherches sur l'immatriculation)
            { k = 'vehicles', t = 'list', l = 'Véhicules', item = 'Véhicule', add = '+ Ajouter un véhicule', min = 0, max = 10, f = (function()
                local fields = vehicle({ req = true })
                fields[#fields + 1] = { k = 'role', t = 'select', l = 'Implication', o = {
                    { 'suspect', 'Véhicule suspect' }, { 'victim', 'Véhicule de la victime' }, { 'witness', 'Véhicule témoin' }, { 'other', 'Autre' },
                } }
                fields[#fields + 1] = { k = 'notes', t = 'text', l = 'Observations', max = 200, w = 3 }
                return fields
            end)() },
        } },
        { title = 'Biens et preuves', f = {
            { k = 'evidence', t = 'area', l = 'Biens, objets et preuves', max = 1500, rows = 4, w = 4 },
        } },
        { title = 'Rapport narratif', f = { narrative() } },
    },
}

local CITATION = {
    id = 'citation',
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
MDC_REPORT_TYPES = { DOT523, ARREST, INCIDENT, CITATION, TRAFFIC, CONVOCATION, WARNING, TICKET }
