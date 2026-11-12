--[[
    MDC - PERMIS DE CONDUIRE ET NATIONALITÉS (État de Washington)
    ==============================================================
    Seule source des permis : le serveur valide avec ces listes, les rapports en tirent leurs options, l'interface les
    reçoit du serveur (rien à recopier ailleurs). Modifiable librement (puis « restart rp_mdc »).

    JURIDICTIONS (MDC_LICENSE_JURISDICTIONS) : Washington en premier, puis les États voisins (Oregon, Idaho, Montana,
    Californie) et les provinces canadiennes frontalières (Colombie-Britannique, Alberta).
      code, label, country ('US' / 'CA'), number (format du n° généré, voir server.lua : genLicenseNumber),
      classes = { { label, kind, minAge, maxAge, info, edl } }, endorsements = { { code, label, cdl } }
        kind : 'std' (standard), 'novice' (permis probatoire / graduated), 'learner' (apprentissage),
               'moto' (permis moto seul), 'cdl' (poids lourd commercial), 'clp' (apprentissage commercial),
               'heavy' (lourd non commercial)
        minAge / maxAge : âge requis (vérifié avec la date de naissance) ; maxAge : permis réservé aux mineurs
        edl = true : Enhanced Driver License, réservé aux citoyens américains (passage terrestre vers le Canada)
        endorsements (mentions) : cdl = true -> seulement sur un permis commercial (cdl / clp)

    NATIONALITÉS (MDC_NATIONALITIES) et STATUTS (MDC_IMMIGRATION) : cohérence vérifiée par le serveur :
      - citoyen américain (US) : permis d'un État américain ; peut avoir l'EDL de Washington ; SSN obligatoire ;
      - citoyen canadien (CA) :
          visiteur : séjour de 6 mois au plus (exempté de visa), date d'entrée -> « séjour autorisé jusqu'au », pas de
                     SSN, adresse au Canada, permis de SA province seulement (valable aux États-Unis pour un visiteur) ;
          résident permanent (green card), travailleur (visa TN, ACEUM), étudiant (visa F-1) : vit aux États-Unis,
                     SSN, permis d'un État américain ou de sa province, jamais l'EDL ; date de fin du statut / de la carte ;
      - double nationalité (US et CA) : comme un citoyen américain, et peut aussi garder un permis canadien.
      N° d'assurance sociale canadien (SIN) pour les Canadiens et la double nationalité ; passeport ; carte NEXUS.
]]

local CDL_ENDORSEMENTS = {
    { code = 'H', label = 'H - Matières dangereuses', cdl = true },
    { code = 'N', label = 'N - Citerne', cdl = true },
    { code = 'P', label = 'P - Transport de passagers', cdl = true },
    { code = 'S', label = 'S - Bus scolaire', cdl = true },
    { code = 'T', label = 'T - Doubles / triples remorques', cdl = true },
    { code = 'X', label = 'X - Citerne + matières dangereuses', cdl = true },
}
local function usEndorsements()
    local list = { { code = 'M', label = 'M - Moto (deux et trois roues)' } }
    for _, e in ipairs(CDL_ENDORSEMENTS) do list[#list + 1] = e end
    return list
end
local function commercial(prefix)
    return {
        { label = prefix .. 'CLP - Commercial Learner\'s Permit', kind = 'clp', minAge = 18, info = 'Apprentissage poids lourd, accompagné d\'un titulaire du CDL' },
        { label = 'CDL A', kind = 'cdl', minAge = 18, info = 'Semi-remorques, ensembles de plus de 26 001 lb (21 ans pour rouler entre États)' },
        { label = 'CDL B', kind = 'cdl', minAge = 18, info = 'Camions et autobus de plus de 26 001 lb' },
        { label = 'CDL C', kind = 'cdl', minAge = 18, info = 'Véhicules de 16 passagers et plus, matières dangereuses' },
    }
end
local function join(a, b) for _, v in ipairs(b) do a[#a + 1] = v end return a end

MDC_LICENSE_JURISDICTIONS = {
    {
        code = 'WA', label = 'WA - Washington', country = 'US', number = 'WA',
        classes = join({
            { label = 'Driver License (standard)', kind = 'std', minAge = 18, info = 'Permis de conduire standard' },
            { label = 'Enhanced Driver License (EDL)', kind = 'std', minAge = 18, edl = true,
                info = 'Permis amélioré : vaut document de voyage vers le Canada par la route ou la mer (citoyens américains)' },
            { label = 'Intermediate License (16-17 ans)', kind = 'novice', minAge = 16, maxAge = 17,
                info = 'Pas de passager de moins de 20 ans les 6 premiers mois, pas de conduite de 1 h à 5 h' },
            { label = 'Instruction Permit', kind = 'learner', minAge = 15, info = 'Apprentissage, accompagné d\'un titulaire de 5 ans de permis' },
            { label = 'Motorcycle Instruction Permit', kind = 'learner', minAge = 16, info = 'Apprentissage moto : de jour, sans passager' },
        }, commercial('')),
        endorsements = usEndorsements(),
    },
    {
        code = 'OR', label = 'OR - Oregon', country = 'US', number = 'OR',
        classes = join({
            { label = 'Class C - Standard', kind = 'std', minAge = 18, info = 'Permis standard (option REAL ID)' },
            { label = 'Provisional License (moins de 18 ans)', kind = 'novice', minAge = 16, maxAge = 17, info = 'Restrictions de passagers et de nuit' },
            { label = 'Instruction Permit', kind = 'learner', minAge = 15, info = 'Apprentissage accompagné' },
            { label = 'Motorcycle Instruction Permit', kind = 'learner', minAge = 16, info = 'Apprentissage moto' },
        }, commercial('')),
        endorsements = usEndorsements(),
    },
    {
        code = 'ID', label = 'ID - Idaho', country = 'US', number = 'ID',
        classes = join({
            { label = 'Class D - Standard', kind = 'std', minAge = 17, info = 'Permis standard' },
            { label = 'Class D - Graduated (moins de 17 ans)', kind = 'novice', minAge = 15, maxAge = 16, info = 'De jour, un seul passager de moins de 17 ans' },
            { label = 'Supervised Instruction Permit (SIP)', kind = 'learner', minAge = 14, info = 'Apprentissage accompagné' },
        }, commercial('')),
        endorsements = usEndorsements(),
    },
    {
        code = 'MT', label = 'MT - Montana', country = 'US', number = 'MT',
        classes = join({
            { label = 'Class D - Standard', kind = 'std', minAge = 18, info = 'Permis standard' },
            { label = 'First-Year Restricted License', kind = 'novice', minAge = 15, maxAge = 17, info = 'Première année : restrictions de nuit et de passagers' },
            { label = 'Learner License', kind = 'learner', minAge = 14, info = 'Apprentissage accompagné' },
        }, commercial('')),
        endorsements = usEndorsements(),
    },
    {
        code = 'CA', label = 'CA - Californie', country = 'US', number = 'CA',
        classes = join({
            { label = 'Class C - Standard', kind = 'std', minAge = 18, info = 'Permis standard' },
            { label = 'Provisional License (moins de 18 ans)', kind = 'novice', minAge = 16, maxAge = 17, info = 'Pas de passager de moins de 20 ans, pas de conduite de 23 h à 5 h' },
            { label = 'Instruction Permit', kind = 'learner', minAge = 15, info = 'Apprentissage accompagné' },
            { label = 'Class M1 - Moto', kind = 'moto', minAge = 16, info = 'Motos et scooters' },
            { label = 'Class M2 - Cyclomoteur', kind = 'moto', minAge = 16, info = 'Cyclomoteurs et vélos motorisés' },
            { label = 'Class A - Non commercial (remorques lourdes)', kind = 'heavy', minAge = 18, info = 'Remorques de plus de 10 000 lb (usage personnel)' },
            { label = 'Class B - Non commercial (camping-car)', kind = 'heavy', minAge = 18, info = 'Camping-cars de 40 à 45 pieds (usage personnel)' },
        }, commercial('')),
        endorsements = CDL_ENDORSEMENTS,
    },
    {
        code = 'BC', label = 'BC - Colombie-Britannique (Canada)', country = 'CA', number = 'BC',
        classes = {
            { label = 'Class 5 - Standard', kind = 'std', minAge = 18, info = 'Permis complet (après le programme de permis gradué)' },
            { label = 'Class 7 - Novice (N)', kind = 'novice', minAge = 16, info = 'Plaque N : un seul passager, zéro alcool' },
            { label = 'Class 7L - Learner (L)', kind = 'learner', minAge = 16, info = 'Plaque L : accompagné, pas de conduite de minuit à 5 h' },
            { label = 'Class 6 - Moto', kind = 'moto', minAge = 18, info = 'Moto, permis complet' },
            { label = 'Class 6L - Moto Learner', kind = 'learner', minAge = 16, info = 'Apprentissage moto' },
            { label = 'Class 4 - Taxi / ambulance', kind = 'cdl', minAge = 19, info = 'Taxis, ambulances, véhicules de 10 passagers au plus' },
            { label = 'Class 3 - Camions', kind = 'cdl', minAge = 18, info = 'Camions à plus de deux essieux' },
            { label = 'Class 2 - Autobus', kind = 'cdl', minAge = 19, info = 'Autobus de plus de 10 passagers' },
            { label = 'Class 1 - Semi-remorques', kind = 'cdl', minAge = 19, info = 'Semi-remorques et tous les véhicules' },
        },
        endorsements = { { code = 'Q', label = 'Q - Freins pneumatiques (air brake)', cdl = true } },
    },
    {
        code = 'AB', label = 'AB - Alberta (Canada)', country = 'CA', number = 'AB',
        classes = {
            { label = 'Class 5 - Standard', kind = 'std', minAge = 18, info = 'Permis complet' },
            { label = 'Class 5 GDL - Probationary', kind = 'novice', minAge = 16, info = 'Permis probatoire (2 ans), zéro alcool' },
            { label = 'Class 7 - Learner', kind = 'learner', minAge = 14, info = 'Apprentissage accompagné' },
            { label = 'Class 6 - Moto', kind = 'moto', minAge = 16, info = 'Moto' },
            { label = 'Class 4 - Taxi / ambulance', kind = 'cdl', minAge = 18, info = 'Taxis, ambulances, petits autobus' },
            { label = 'Class 3 - Camions', kind = 'cdl', minAge = 18, info = 'Camions à plus de deux essieux' },
            { label = 'Class 2 - Autobus', kind = 'cdl', minAge = 18, info = 'Autobus' },
            { label = 'Class 1 - Semi-remorques', kind = 'cdl', minAge = 18, info = 'Semi-remorques et tous les véhicules' },
        },
        endorsements = { { code = 'Q', label = 'Q - Freins pneumatiques (air brake)', cdl = true } },
    },
}

MDC_NATIONALITIES = {
    { code = 'US', label = 'Citoyen américain (US citizen)' },
    { code = 'CA', label = 'Citoyen canadien (Canadian citizen)' },
    { code = 'USCA', label = 'Double nationalité (US et CA)' },
}

-- Statut d'un citoyen canadien aux États-Unis (country = pays des permis possibles ; ssn : SSN attribué ;
-- abroad : vit au Canada ; months : durée du séjour autorisé depuis la date d'entrée)
MDC_IMMIGRATION = {
    { code = 'visitor', label = 'Visiteur (exempté de visa, 6 mois au plus)', short = 'Visiteur', countries = { CA = true },
        ssn = false, abroad = true, months = 6 },
    { code = 'permanent', label = 'Résident permanent (green card)', short = 'Résident permanent', countries = { US = true, CA = true },
        ssn = true, expiry = 'Fin de validité de la green card' },
    { code = 'worker', label = 'Travailleur (visa TN, ACEUM)', short = 'Visa TN', countries = { US = true, CA = true },
        ssn = true, expiry = 'Fin du visa TN' },
    { code = 'student', label = 'Étudiant (visa F-1)', short = 'Visa F-1', countries = { US = true, CA = true },
        ssn = true, expiry = 'Fin du visa F-1 (I-20)' },
}

-- Anciennes fiches (Géorgie et voisins) : affichées telles quelles, à refaire en modification
MDC_LEGACY_STATES = {
    GA = 'GA - Georgia (ancien)', FL = 'FL - Floride (ancien)', TN = 'TN - Tennessee (ancien)',
    SC = 'SC - South Carolina (ancien)', NC = 'NC - North Carolina (ancien)', AL = 'AL - Alabama (ancien)',
}
