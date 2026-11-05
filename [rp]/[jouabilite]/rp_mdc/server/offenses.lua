--[[
    MDC Standalone - Catalogue des infractions de l'État de Washington (RCW)
    ------------------------------------------------------------------------
    Utilisé par les rapports (server/reports.lua) : champs "Classification" (t = 'offclass') et "Violation / Charge"
    (t = 'offense'). Choisir une infraction règle sa classification ; choisir d'abord une classification ne propose
    que les infractions de cette classification.

    CLASSIFICATIONS (RCW 9A.20.021, RCW 46.63, RCW 7.80) :
      TI  Traffic Infraction            infraction civile au code de la route (Notice of Infraction, pénalité)
      CI  Civil Infraction (Non-Traffic) infraction civile hors route (RCW 7.80, classes 1 à 4)
      M   Misdemeanor                    jusqu'à 90 jours de prison et/ou 1 000 $
      GM  Gross Misdemeanor              jusqu'à 364 jours et/ou 5 000 $
      FC  Class C Felony                 jusqu'à 5 ans et/ou 10 000 $
      FB  Class B Felony                 jusqu'à 10 ans et/ou 20 000 $
      FA  Class A Felony                 jusqu'à la perpétuité et/ou 50 000 $

    Infraction : { id (unique, ne pas changer : gardé dans les rapports), rcw, t = intitulé officiel, c = classification,
                   g = catégorie (groupes de la liste déroulante), fine = pénalité en $ (infractions TI / CI : montant
                   total habituel du barème des tribunaux de district, IRLJ 6.2, frais légaux compris ; modifiable dans
                   le rapport) }
    Ajouter une infraction : une ligne ici, rien d'autre (interface et serveur suivent).
]]

MDC_OFFENSE_CLASSES = {
    { id = 'TI', label = 'Traffic Infraction', short = 'TI', info = 'Civil — pénalité financière (RCW 46.63)' },
    { id = 'CI', label = 'Civil Infraction (Non-Traffic)', short = 'CI', info = 'Civil — classes 1 à 4, jusqu\'à 250 $ (RCW 7.80)' },
    { id = 'M', label = 'Misdemeanor', short = 'M', info = 'Jusqu\'à 90 jours de prison et / ou 1 000 $ (RCW 9A.20.021)' },
    { id = 'GM', label = 'Gross Misdemeanor', short = 'GM', info = 'Jusqu\'à 364 jours de prison et / ou 5 000 $ (RCW 9A.20.021)' },
    { id = 'FC', label = 'Class C Felony', short = 'C FEL', info = 'Jusqu\'à 5 ans de prison et / ou 10 000 $ (RCW 9A.20.021)' },
    { id = 'FB', label = 'Class B Felony', short = 'B FEL', info = 'Jusqu\'à 10 ans de prison et / ou 20 000 $ (RCW 9A.20.021)' },
    { id = 'FA', label = 'Class A Felony', short = 'A FEL', info = 'Jusqu\'à la perpétuité et / ou 50 000 $ (RCW 9A.20.021)' },
}

local SPEED, MOVING, SAFETY = 'Vitesse', 'Règles de circulation', 'Distraction et sécurité des occupants'
local EQUIP, LICENSE, PED = 'Équipement du véhicule', 'Permis, immatriculation et assurance', 'Piétons et vélos'
local CIVIL = 'Infractions civiles (hors route)'
local CTRAFFIC, DUI = 'Délits routiers', 'Alcool / drogue au volant (DUI)'
local PERSONS, PROPERTY, WEAPONS = 'Atteintes aux personnes', 'Atteintes aux biens', 'Armes'
local DRUGS, ORDER = 'Stupéfiants et alcool', 'Ordre public, entrave et ordonnances'

MDC_OFFENSES = {
    -- =====================================================================
    -- TRAFFIC INFRACTIONS (TI) — Notice of Infraction
    -- =====================================================================
    { id = 'spd01', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 1 à 5 mph', c = 'TI', g = SPEED, fine = 136 },
    { id = 'spd06', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 6 à 10 mph', c = 'TI', g = SPEED, fine = 157 },
    { id = 'spd11', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 11 à 15 mph', c = 'TI', g = SPEED, fine = 199 },
    { id = 'spd16', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 16 à 20 mph', c = 'TI', g = SPEED, fine = 243 },
    { id = 'spd21', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 21 à 25 mph', c = 'TI', g = SPEED, fine = 308 },
    { id = 'spd26', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 26 à 30 mph', c = 'TI', g = SPEED, fine = 375 },
    { id = 'spd31', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 31 à 35 mph', c = 'TI', g = SPEED, fine = 431 },
    { id = 'spd36', rcw = 'RCW 46.61.400', t = 'Excès de vitesse — 36 à 40 mph', c = 'TI', g = SPEED, fine = 508 },
    { id = 'spdcond', rcw = 'RCW 46.61.400(1)', t = 'Vitesse inadaptée aux conditions', c = 'TI', g = SPEED, fine = 136 },
    { id = 'spdschool', rcw = 'RCW 46.61.440', t = 'Excès de vitesse en zone scolaire / aire de jeux', c = 'TI', g = SPEED, fine = 272 },
    { id = 'spdwork', rcw = 'RCW 46.61.527', t = 'Excès de vitesse en zone de travaux', c = 'TI', g = SPEED, fine = 272 },
    { id = 'spdslow', rcw = 'RCW 46.61.425', t = 'Gêne à la circulation — vitesse trop lente', c = 'TI', g = SPEED, fine = 136 },

    { id = 'tcd', rcw = 'RCW 46.61.050', t = 'Non-respect de la signalisation', c = 'TI', g = MOVING, fine = 136 },
    { id = 'redlight', rcw = 'RCW 46.61.055', t = 'Feu rouge non respecté', c = 'TI', g = MOVING, fine = 136 },
    { id = 'stopsign', rcw = 'RCW 46.61.190', t = 'Stop non respecté', c = 'TI', g = MOVING, fine = 136 },
    { id = 'fty', rcw = 'RCW 46.61.180', t = 'Refus de priorité à une intersection', c = 'TI', g = MOVING, fine = 136 },
    { id = 'ftyleft', rcw = 'RCW 46.61.185', t = 'Refus de priorité en tournant à gauche', c = 'TI', g = MOVING, fine = 136 },
    { id = 'ftyped', rcw = 'RCW 46.61.235', t = 'Refus de priorité à un piéton sur le passage', c = 'TI', g = MOVING, fine = 136 },
    { id = 'ftyemerg', rcw = 'RCW 46.61.210', t = 'Refus de priorité à un véhicule d\'urgence', c = 'TI', g = MOVING, fine = 136 },
    { id = 'moveover', rcw = 'RCW 46.61.212', t = 'Pas de ralentissement / de changement de voie près d\'un véhicule d\'urgence', c = 'TI', g = MOVING, fine = 214 },
    { id = 'follow', rcw = 'RCW 46.61.145', t = 'Distance de sécurité insuffisante', c = 'TI', g = MOVING, fine = 136 },
    { id = 'lane', rcw = 'RCW 46.61.140', t = 'Changement de voie dangereux / mauvaise voie', c = 'TI', g = MOVING, fine = 136 },
    { id = 'keepright', rcw = 'RCW 46.61.100', t = 'Non-respect de la circulation à droite', c = 'TI', g = MOVING, fine = 136 },
    { id = 'leftlane', rcw = 'RCW 46.61.100(2)', t = 'Circulation sur la voie de gauche sans dépasser', c = 'TI', g = MOVING, fine = 136 },
    { id = 'oneway', rcw = 'RCW 46.61.135', t = 'Contresens sur une voie à sens unique', c = 'TI', g = MOVING, fine = 136 },
    { id = 'pass', rcw = 'RCW 46.61.110', t = 'Dépassement dangereux', c = 'TI', g = MOVING, fine = 136 },
    { id = 'nopass', rcw = 'RCW 46.61.130', t = 'Dépassement interdit', c = 'TI', g = MOVING, fine = 136 },
    { id = 'turn', rcw = 'RCW 46.61.290', t = 'Virage dangereux', c = 'TI', g = MOVING, fine = 136 },
    { id = 'uturn', rcw = 'RCW 46.61.295', t = 'Demi-tour interdit', c = 'TI', g = MOVING, fine = 136 },
    { id = 'signal', rcw = 'RCW 46.61.305', t = 'Absence de clignotant', c = 'TI', g = MOVING, fine = 136 },
    { id = 'backing', rcw = 'RCW 46.61.605', t = 'Marche arrière dangereuse', c = 'TI', g = MOVING, fine = 136 },
    { id = 'hov', rcw = 'RCW 46.61.165', t = 'Voie de covoiturage (HOV) utilisée illégalement', c = 'TI', g = MOVING, fine = 186 },
    { id = 'schoolbus', rcw = 'RCW 46.61.370', t = 'Non-arrêt pour un bus scolaire', c = 'TI', g = MOVING, fine = 419 },
    { id = 'railroad', rcw = 'RCW 46.61.340', t = 'Non-arrêt à un passage à niveau', c = 'TI', g = MOVING, fine = 136 },
    { id = 'sidewalk', rcw = 'RCW 46.61.606', t = 'Circulation sur le trottoir', c = 'TI', g = MOVING, fine = 136 },
    { id = 'neg2', rcw = 'RCW 46.61.525', t = 'Conduite négligente — 2e degré', c = 'TI', g = MOVING, fine = 550 },
    { id = 'neg2vu', rcw = 'RCW 46.61.526', t = 'Conduite négligente — 2e degré avec victime vulnérable', c = 'TI', g = MOVING, fine = 5000 },

    { id = 'phone', rcw = 'RCW 46.61.672', t = 'Usage du téléphone / d\'un appareil électronique au volant', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'distract', rcw = 'RCW 46.61.673', t = 'Conduite dangereusement distraite', c = 'TI', g = SAFETY, fine = 99 },
    { id = 'belt', rcw = 'RCW 46.61.688', t = 'Défaut de ceinture', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'child', rcw = 'RCW 46.61.687', t = 'Enfant sans siège adapté', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'opencont', rcw = 'RCW 46.61.519', t = 'Contenant d\'alcool ouvert dans le véhicule', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'helmet', rcw = 'RCW 46.37.530', t = 'Défaut de casque (moto)', c = 'TI', g = SAFETY, fine = 136 },

    { id = 'equip', rcw = 'RCW 46.37.010', t = 'Équipement défectueux ou non conforme', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'headlights', rcw = 'RCW 46.37.020', t = 'Phares éteints quand obligatoires', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'dim', rcw = 'RCW 46.37.230', t = 'Pleins phares non baissés', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'taillamp', rcw = 'RCW 46.37.070', t = 'Feu arrière / éclairage de plaque défectueux', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'stoplamp', rcw = 'RCW 46.37.200', t = 'Feu stop / clignotant défectueux', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'tint', rcw = 'RCW 46.37.430', t = 'Vitres teintées non conformes', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'muffler', rcw = 'RCW 46.37.390', t = 'Pot d\'échappement modifié / bruit excessif', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'windshield', rcw = 'RCW 46.37.410', t = 'Pare-brise obstrué ou endommagé', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'load', rcw = 'RCW 46.61.655', t = 'Chargement mal arrimé', c = 'TI', g = EQUIP, fine = 228 },
    { id = 'studs', rcw = 'RCW 46.37.420', t = 'Pneus cloutés hors saison', c = 'TI', g = EQUIP, fine = 136 },

    { id = 'regexp', rcw = 'RCW 46.16A.030', t = 'Immatriculation expirée — 2 mois ou moins', c = 'TI', g = LICENSE, fine = 136 },
    { id = 'regexp2', rcw = 'RCW 46.16A.030', t = 'Immatriculation expirée — plus de 2 mois', c = 'TI', g = LICENSE, fine = 228 },
    { id = 'plates', rcw = 'RCW 46.16A.200', t = 'Plaques absentes ou mal fixées', c = 'TI', g = LICENSE, fine = 136 },
    { id = 'dlcarry', rcw = 'RCW 46.20.017', t = 'Permis non présenté', c = 'TI', g = LICENSE, fine = 136 },
    { id = 'nvolid', rcw = 'RCW 46.20.015', t = 'Conduite sans permis valide — avec pièce d\'identité', c = 'TI', g = LICENSE, fine = 250 },
    { id = 'insurance', rcw = 'RCW 46.30.020', t = 'Défaut d\'assurance', c = 'TI', g = LICENSE, fine = 550 },
    { id = 'address', rcw = 'RCW 46.20.205', t = 'Changement d\'adresse non déclaré au DOL', c = 'TI', g = LICENSE, fine = 136 },

    { id = 'pedyield', rcw = 'RCW 46.61.240', t = 'Piéton — refus de priorité hors passage', c = 'TI', g = PED, fine = 68 },
    { id = 'bikelight', rcw = 'RCW 46.61.780', t = 'Vélo sans éclairage la nuit', c = 'TI', g = PED, fine = 136 },

    -- =====================================================================
    -- CIVIL INFRACTIONS (NON-TRAFFIC, RCW 7.80) — Notice of Civil Infraction
    -- =====================================================================
    { id = 'litter', rcw = 'RCW 70A.200.060(1)', t = 'Dépôt de déchets — moins d\'un pied cube (classe 3)', c = 'CI', g = CIVIL, fine = 50 },
    { id = 'cannabispub', rcw = 'RCW 69.50.445', t = 'Consommation de cannabis en public (classe 3)', c = 'CI', g = CIVIL, fine = 50 },
    { id = 'smoking', rcw = 'RCW 70.160.070', t = 'Fumer dans un lieu interdit', c = 'CI', g = CIVIL, fine = 100 },

    -- =====================================================================
    -- MISDEMEANORS (M)
    -- =====================================================================
    { id = 'dwls3', rcw = 'RCW 46.20.342(1)(c)', t = 'Conduite avec permis suspendu / révoqué — 3e degré (DWLS 3)', c = 'M', g = CTRAFFIC },
    { id = 'nvol', rcw = 'RCW 46.20.005', t = 'Conduite sans permis valide — sans pièce d\'identité', c = 'M', g = CTRAFFIC },
    { id = 'neg1', rcw = 'RCW 46.61.5249', t = 'Conduite négligente — 1er degré', c = 'M', g = CTRAFFIC },
    { id = 'hrunatt', rcw = 'RCW 46.52.010', t = 'Délit de fuite — véhicule ou bien sans personne', c = 'M', g = CTRAFFIC },
    { id = 'failobey', rcw = 'RCW 46.61.022', t = 'Refus d\'obtempérer à un agent', c = 'M', g = CTRAFFIC },
    { id = 'refuseinfo', rcw = 'RCW 46.61.020', t = 'Refus de donner son identité / de coopérer avec un agent', c = 'M', g = CTRAFFIC },
    { id = 'disorderly', rcw = 'RCW 9A.84.030', t = 'Trouble à l\'ordre public', c = 'M', g = ORDER },
    { id = 'disperse', rcw = 'RCW 9A.84.020', t = 'Refus de se disperser', c = 'M', g = ORDER },
    { id = 'trespass2', rcw = 'RCW 9A.52.080', t = 'Intrusion — 2e degré', c = 'M', g = PROPERTY },
    { id = 'resist', rcw = 'RCW 9A.76.040', t = 'Rébellion lors d\'une arrestation', c = 'M', g = ORDER },
    { id = 'indecent', rcw = 'RCW 9A.88.010', t = 'Exhibitionnisme', c = 'M', g = ORDER },
    { id = 'litter2', rcw = 'RCW 70A.200.060(2)', t = 'Dépôt de déchets — un pied cube ou plus', c = 'M', g = ORDER },
    { id = 'parapher', rcw = 'RCW 69.50.412', t = 'Usage de matériel de consommation de drogue', c = 'M', g = DRUGS },
    { id = 'cannabis40', rcw = 'RCW 69.50.4014', t = 'Détention illégale de cannabis — 40 g ou moins', c = 'M', g = DRUGS },
    { id = 'cpl', rcw = 'RCW 9.41.050', t = 'Port d\'arme dissimulée sans permis (CPL)', c = 'M', g = WEAPONS },

    -- =====================================================================
    -- GROSS MISDEMEANORS (GM)
    -- =====================================================================
    { id = 'dui', rcw = 'RCW 46.61.502', t = 'Conduite sous l\'emprise de l\'alcool / de drogues (DUI)', c = 'GM', g = DUI },
    { id = 'physctl', rcw = 'RCW 46.61.504', t = 'Contrôle d\'un véhicule sous l\'emprise (Physical Control)', c = 'GM', g = DUI },
    { id = 'interlock', rcw = 'RCW 46.20.740', t = 'Conduite sans l\'éthylotest anti-démarrage obligatoire', c = 'GM', g = DUI },
    { id = 'reckless', rcw = 'RCW 46.61.500', t = 'Conduite dangereuse (Reckless Driving)', c = 'GM', g = CTRAFFIC },
    { id = 'dwls2', rcw = 'RCW 46.20.342(1)(b)', t = 'Conduite avec permis suspendu / révoqué — 2e degré (DWLS 2)', c = 'GM', g = CTRAFFIC },
    { id = 'dwls1', rcw = 'RCW 46.20.342(1)(a)', t = 'Conduite avec permis suspendu / révoqué — 1er degré (DWLS 1)', c = 'GM', g = CTRAFFIC },
    { id = 'hrunprop', rcw = 'RCW 46.52.020(5)', t = 'Délit de fuite — dégâts matériels seulement', c = 'GM', g = CTRAFFIC },
    { id = 'racing', rcw = 'RCW 46.61.530', t = 'Course de véhicules sur la voie publique', c = 'GM', g = CTRAFFIC },
    { id = 'assault4', rcw = 'RCW 9A.36.041', t = 'Agression — 4e degré', c = 'GM', g = PERSONS },
    { id = 'harass', rcw = 'RCW 9A.46.020', t = 'Harcèlement / menaces', c = 'GM', g = PERSONS },
    { id = 'endanger', rcw = 'RCW 9A.36.050', t = 'Mise en danger d\'autrui', c = 'GM', g = PERSONS },
    { id = 'stalking', rcw = 'RCW 9A.46.110', t = 'Traque (stalking)', c = 'GM', g = PERSONS },
    { id = 'dvinterfere', rcw = 'RCW 9A.36.150', t = 'Entrave au signalement de violences conjugales', c = 'GM', g = PERSONS },
    { id = 'theft3', rcw = 'RCW 9A.56.050', t = 'Vol — 3e degré', c = 'GM', g = PROPERTY },
    { id = 'pspr3', rcw = 'RCW 9A.56.170', t = 'Recel — 3e degré', c = 'GM', g = PROPERTY },
    { id = 'mm3', rcw = 'RCW 9A.48.090', t = 'Dégradation volontaire — 3e degré', c = 'GM', g = PROPERTY },
    { id = 'trespass1', rcw = 'RCW 9A.52.070', t = 'Intrusion — 1er degré', c = 'GM', g = PROPERTY },
    { id = 'prowl2', rcw = 'RCW 9A.52.100', t = 'Effraction de véhicule — 2e degré', c = 'GM', g = PROPERTY },
    { id = 'obstruct', rcw = 'RCW 9A.76.020', t = 'Entrave à un agent', c = 'GM', g = ORDER },
    { id = 'falsestmt', rcw = 'RCW 9A.76.175', t = 'Fausse déclaration à un agent public', c = 'GM', g = ORDER },
    { id = 'nco', rcw = 'RCW 7.105.450', t = 'Violation d\'une ordonnance d\'éloignement / de protection', c = 'GM', g = ORDER },
    { id = 'mip', rcw = 'RCW 66.44.270', t = 'Mineur en possession d\'alcool / ayant consommé', c = 'GM', g = DRUGS },
    { id = 'vucsa', rcw = 'RCW 69.50.4013', t = 'Détention de stupéfiants', c = 'GM', g = DRUGS },
    { id = 'display', rcw = 'RCW 9.41.270', t = 'Exhibition illégale d\'une arme', c = 'GM', g = WEAPONS },

    -- =====================================================================
    -- CLASS C FELONIES (FC)
    -- =====================================================================
    { id = 'elude', rcw = 'RCW 46.61.024', t = 'Fuite devant un véhicule de police (Eluding)', c = 'FC', g = CTRAFFIC },
    { id = 'hruninj', rcw = 'RCW 46.52.020(4)(b)', t = 'Délit de fuite — blessé', c = 'FC', g = CTRAFFIC },
    { id = 'assault3', rcw = 'RCW 9A.36.031', t = 'Agression — 3e degré (dont sur un agent)', c = 'FC', g = PERSONS },
    { id = 'harasskill', rcw = 'RCW 9A.46.020(2)(b)', t = 'Menaces de mort', c = 'FC', g = PERSONS },
    { id = 'unlawimp', rcw = 'RCW 9A.40.040', t = 'Séquestration', c = 'FC', g = PERSONS },
    { id = 'ncofel', rcw = 'RCW 7.105.450(4)', t = 'Violation aggravée d\'une ordonnance d\'éloignement / de protection', c = 'FC', g = PERSONS },
    { id = 'theft2', rcw = 'RCW 9A.56.040', t = 'Vol — 2e degré', c = 'FC', g = PROPERTY },
    { id = 'tmvwp2', rcw = 'RCW 9A.56.075', t = 'Utilisation d\'un véhicule sans autorisation — 2e degré', c = 'FC', g = PROPERTY },
    { id = 'pspr2', rcw = 'RCW 9A.56.160', t = 'Recel — 2e degré', c = 'FC', g = PROPERTY },
    { id = 'mm2', rcw = 'RCW 9A.48.080', t = 'Dégradation volontaire — 2e degré', c = 'FC', g = PROPERTY },
    { id = 'prowl1', rcw = 'RCW 9A.52.095', t = 'Effraction de véhicule — 1er degré', c = 'FC', g = PROPERTY },
    { id = 'idtheft2', rcw = 'RCW 9.35.020', t = 'Usurpation d\'identité — 2e degré', c = 'FC', g = PROPERTY },
    { id = 'forgery', rcw = 'RCW 9A.60.020', t = 'Faux et usage de faux', c = 'FC', g = PROPERTY },
    { id = 'upf2', rcw = 'RCW 9.41.040(2)', t = 'Détention illégale d\'arme à feu — 2e degré', c = 'FC', g = WEAPONS },
    { id = 'escape2', rcw = 'RCW 9A.76.120', t = 'Évasion — 2e degré', c = 'FC', g = ORDER },
    { id = 'rca1', rcw = 'RCW 9A.76.070', t = 'Aide à un criminel — 1er degré', c = 'FC', g = ORDER },
    { id = 'pwidc', rcw = 'RCW 69.50.401(2)(c)', t = 'Trafic / détention en vue de vente — classes III à V', c = 'FC', g = DRUGS },

    -- =====================================================================
    -- CLASS B FELONIES (FB)
    -- =====================================================================
    { id = 'veh_assault', rcw = 'RCW 46.61.522', t = 'Blessures graves au volant (Vehicular Assault)', c = 'FB', g = DUI },
    { id = 'felonydui', rcw = 'RCW 46.61.502(6)', t = 'DUI aggravé (Felony DUI)', c = 'FB', g = DUI },
    { id = 'felonypc', rcw = 'RCW 46.61.504(6)', t = 'Physical Control aggravé', c = 'FB', g = DUI },
    { id = 'hrundeath', rcw = 'RCW 46.52.020(4)(a)', t = 'Délit de fuite — mort', c = 'FB', g = CTRAFFIC },
    { id = 'assault2', rcw = 'RCW 9A.36.021', t = 'Agression — 2e degré', c = 'FB', g = PERSONS },
    { id = 'driveby', rcw = 'RCW 9A.36.045', t = 'Tir depuis un véhicule (drive-by)', c = 'FB', g = PERSONS },
    { id = 'kidnap2', rcw = 'RCW 9A.40.030', t = 'Enlèvement — 2e degré', c = 'FB', g = PERSONS },
    { id = 'manslaughter2', rcw = 'RCW 9A.32.070', t = 'Homicide involontaire — 2e degré', c = 'FB', g = PERSONS },
    { id = 'intimps', rcw = 'RCW 9A.76.180', t = 'Intimidation d\'un agent public', c = 'FB', g = ORDER },
    { id = 'intimwit', rcw = 'RCW 9A.72.110', t = 'Intimidation d\'un témoin', c = 'FB', g = ORDER },
    { id = 'escape1', rcw = 'RCW 9A.76.110', t = 'Évasion — 1er degré', c = 'FB', g = ORDER },
    { id = 'robbery2', rcw = 'RCW 9A.56.210', t = 'Vol avec violence — 2e degré', c = 'FB', g = PROPERTY },
    { id = 'burglary2', rcw = 'RCW 9A.52.030', t = 'Cambriolage — 2e degré', c = 'FB', g = PROPERTY },
    { id = 'resburglary', rcw = 'RCW 9A.52.025', t = 'Cambriolage d\'habitation', c = 'FB', g = PROPERTY },
    { id = 'theft1', rcw = 'RCW 9A.56.030', t = 'Vol — 1er degré', c = 'FB', g = PROPERTY },
    { id = 'tmv', rcw = 'RCW 9A.56.065', t = 'Vol de véhicule', c = 'FB', g = PROPERTY },
    { id = 'psv', rcw = 'RCW 9A.56.068', t = 'Recel de véhicule volé', c = 'FB', g = PROPERTY },
    { id = 'tmvwp1', rcw = 'RCW 9A.56.070', t = 'Utilisation d\'un véhicule sans autorisation — 1er degré', c = 'FB', g = PROPERTY },
    { id = 'pspr1', rcw = 'RCW 9A.56.150', t = 'Recel — 1er degré', c = 'FB', g = PROPERTY },
    { id = 'idtheft1', rcw = 'RCW 9.35.020', t = 'Usurpation d\'identité — 1er degré', c = 'FB', g = PROPERTY },
    { id = 'mm1', rcw = 'RCW 9A.48.070', t = 'Dégradation volontaire — 1er degré', c = 'FB', g = PROPERTY },
    { id = 'arson2', rcw = 'RCW 9A.48.030', t = 'Incendie volontaire — 2e degré', c = 'FB', g = PROPERTY },
    { id = 'upf1', rcw = 'RCW 9.41.040(1)', t = 'Détention illégale d\'arme à feu — 1er degré', c = 'FB', g = WEAPONS },
    { id = 'pwidab', rcw = 'RCW 69.50.401(2)(a)', t = 'Trafic / détention en vue de vente — stupéfiants (classes I-II) ou méthamphétamine', c = 'FB', g = DRUGS },

    -- =====================================================================
    -- CLASS A FELONIES (FA)
    -- =====================================================================
    { id = 'vehhom', rcw = 'RCW 46.61.520', t = 'Homicide au volant (Vehicular Homicide)', c = 'FA', g = DUI },
    { id = 'murder1', rcw = 'RCW 9A.32.030', t = 'Meurtre — 1er degré', c = 'FA', g = PERSONS },
    { id = 'murder2', rcw = 'RCW 9A.32.050', t = 'Meurtre — 2e degré', c = 'FA', g = PERSONS },
    { id = 'manslaughter1', rcw = 'RCW 9A.32.060', t = 'Homicide involontaire — 1er degré', c = 'FA', g = PERSONS },
    { id = 'assault1', rcw = 'RCW 9A.36.011', t = 'Agression — 1er degré', c = 'FA', g = PERSONS },
    { id = 'kidnap1', rcw = 'RCW 9A.40.020', t = 'Enlèvement — 1er degré', c = 'FA', g = PERSONS },
    { id = 'robbery1', rcw = 'RCW 9A.56.200', t = 'Vol avec violence — 1er degré', c = 'FA', g = PROPERTY },
    { id = 'burglary1', rcw = 'RCW 9A.52.020', t = 'Cambriolage — 1er degré', c = 'FA', g = PROPERTY },
    { id = 'arson1', rcw = 'RCW 9A.48.020', t = 'Incendie volontaire — 1er degré', c = 'FA', g = PROPERTY },
}

-- Groupes de classifications utilisés par les rapports
MDC_CLASS_SETS = {
    infractions = { 'TI', 'CI' },                       -- Notice of Infraction, Written Warning
    citable = { 'M', 'GM' },                            -- Criminal Citation (pas de crime : arrestation)
    criminal = { 'M', 'GM', 'FC', 'FB', 'FA' },         -- Arrest Report, DUI
    all = { 'TI', 'CI', 'M', 'GM', 'FC', 'FB', 'FA' },  -- Incident Report, collision (citations délivrées)
}
