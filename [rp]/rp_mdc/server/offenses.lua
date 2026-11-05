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
    { id = 'TI', label = 'Traffic Infraction', short = 'TI', info = 'Civil — monetary penalty (RCW 46.63)' },
    { id = 'CI', label = 'Civil Infraction (Non-Traffic)', short = 'CI', info = 'Civil — Class 1 to 4, up to $250 (RCW 7.80)' },
    { id = 'M', label = 'Misdemeanor', short = 'M', info = 'Up to 90 days in jail and/or $1,000 (RCW 9A.20.021)' },
    { id = 'GM', label = 'Gross Misdemeanor', short = 'GM', info = 'Up to 364 days in jail and/or $5,000 (RCW 9A.20.021)' },
    { id = 'FC', label = 'Class C Felony', short = 'C FEL', info = 'Up to 5 years and/or $10,000 (RCW 9A.20.021)' },
    { id = 'FB', label = 'Class B Felony', short = 'B FEL', info = 'Up to 10 years and/or $20,000 (RCW 9A.20.021)' },
    { id = 'FA', label = 'Class A Felony', short = 'A FEL', info = 'Up to life and/or $50,000 (RCW 9A.20.021)' },
}

local SPEED, MOVING, SAFETY = 'Speed', 'Moving Violations', 'Distracted Driving & Occupant Safety'
local EQUIP, LICENSE, PED = 'Equipment', 'License, Registration & Insurance', 'Pedestrian & Bicycle'
local CIVIL = 'Non-Traffic Civil Infractions'
local CTRAFFIC, DUI = 'Criminal Traffic', 'DUI & Impaired Driving'
local PERSONS, PROPERTY, WEAPONS = 'Crimes Against Persons', 'Property Crimes', 'Firearms & Weapons'
local DRUGS, ORDER = 'Controlled Substances & Alcohol', 'Public Order, Obstruction & Court Orders'

MDC_OFFENSES = {
    -- =====================================================================
    -- TRAFFIC INFRACTIONS (TI) — Notice of Infraction
    -- =====================================================================
    { id = 'spd01', rcw = 'RCW 46.61.400', t = 'Speeding — 1-5 MPH Over Limit', c = 'TI', g = SPEED, fine = 136 },
    { id = 'spd06', rcw = 'RCW 46.61.400', t = 'Speeding — 6-10 MPH Over Limit', c = 'TI', g = SPEED, fine = 157 },
    { id = 'spd11', rcw = 'RCW 46.61.400', t = 'Speeding — 11-15 MPH Over Limit', c = 'TI', g = SPEED, fine = 199 },
    { id = 'spd16', rcw = 'RCW 46.61.400', t = 'Speeding — 16-20 MPH Over Limit', c = 'TI', g = SPEED, fine = 243 },
    { id = 'spd21', rcw = 'RCW 46.61.400', t = 'Speeding — 21-25 MPH Over Limit', c = 'TI', g = SPEED, fine = 308 },
    { id = 'spd26', rcw = 'RCW 46.61.400', t = 'Speeding — 26-30 MPH Over Limit', c = 'TI', g = SPEED, fine = 375 },
    { id = 'spd31', rcw = 'RCW 46.61.400', t = 'Speeding — 31-35 MPH Over Limit', c = 'TI', g = SPEED, fine = 431 },
    { id = 'spd36', rcw = 'RCW 46.61.400', t = 'Speeding — 36-40 MPH Over Limit', c = 'TI', g = SPEED, fine = 508 },
    { id = 'spdcond', rcw = 'RCW 46.61.400(1)', t = 'Speed Too Fast for Conditions', c = 'TI', g = SPEED, fine = 136 },
    { id = 'spdschool', rcw = 'RCW 46.61.440', t = 'Speeding in a School or Playground Speed Zone', c = 'TI', g = SPEED, fine = 272 },
    { id = 'spdwork', rcw = 'RCW 46.61.527', t = 'Speeding in a Roadway Construction Zone', c = 'TI', g = SPEED, fine = 272 },
    { id = 'spdslow', rcw = 'RCW 46.61.425', t = 'Impeding Traffic — Minimum Speed', c = 'TI', g = SPEED, fine = 136 },

    { id = 'tcd', rcw = 'RCW 46.61.050', t = 'Failure to Obey Traffic Control Device', c = 'TI', g = MOVING, fine = 136 },
    { id = 'redlight', rcw = 'RCW 46.61.055', t = 'Failure to Stop at Red Signal', c = 'TI', g = MOVING, fine = 136 },
    { id = 'stopsign', rcw = 'RCW 46.61.190', t = 'Failure to Stop at Stop Sign', c = 'TI', g = MOVING, fine = 136 },
    { id = 'fty', rcw = 'RCW 46.61.180', t = 'Failure to Yield Right-of-Way at Intersection', c = 'TI', g = MOVING, fine = 136 },
    { id = 'ftyleft', rcw = 'RCW 46.61.185', t = 'Failure to Yield — Left Turn', c = 'TI', g = MOVING, fine = 136 },
    { id = 'ftyped', rcw = 'RCW 46.61.235', t = 'Failure to Yield to Pedestrian in Crosswalk', c = 'TI', g = MOVING, fine = 136 },
    { id = 'ftyemerg', rcw = 'RCW 46.61.210', t = 'Failure to Yield to Emergency Vehicle', c = 'TI', g = MOVING, fine = 136 },
    { id = 'moveover', rcw = 'RCW 46.61.212', t = 'Failure to Slow Down / Move Over — Emergency Zone', c = 'TI', g = MOVING, fine = 214 },
    { id = 'follow', rcw = 'RCW 46.61.145', t = 'Following Too Closely', c = 'TI', g = MOVING, fine = 136 },
    { id = 'lane', rcw = 'RCW 46.61.140', t = 'Improper Lane Travel / Unsafe Lane Change', c = 'TI', g = MOVING, fine = 136 },
    { id = 'keepright', rcw = 'RCW 46.61.100', t = 'Failure to Keep Right', c = 'TI', g = MOVING, fine = 136 },
    { id = 'leftlane', rcw = 'RCW 46.61.100(2)', t = 'Driving in Left Lane Except to Pass', c = 'TI', g = MOVING, fine = 136 },
    { id = 'oneway', rcw = 'RCW 46.61.135', t = 'Wrong Way on a One-Way Roadway', c = 'TI', g = MOVING, fine = 136 },
    { id = 'pass', rcw = 'RCW 46.61.110', t = 'Improper Passing', c = 'TI', g = MOVING, fine = 136 },
    { id = 'nopass', rcw = 'RCW 46.61.130', t = 'Passing in a No-Passing Zone', c = 'TI', g = MOVING, fine = 136 },
    { id = 'turn', rcw = 'RCW 46.61.290', t = 'Improper Turn', c = 'TI', g = MOVING, fine = 136 },
    { id = 'uturn', rcw = 'RCW 46.61.295', t = 'Improper U-Turn', c = 'TI', g = MOVING, fine = 136 },
    { id = 'signal', rcw = 'RCW 46.61.305', t = 'Failure to Signal', c = 'TI', g = MOVING, fine = 136 },
    { id = 'backing', rcw = 'RCW 46.61.605', t = 'Unsafe Backing', c = 'TI', g = MOVING, fine = 136 },
    { id = 'hov', rcw = 'RCW 46.61.165', t = 'HOV Lane Violation', c = 'TI', g = MOVING, fine = 186 },
    { id = 'schoolbus', rcw = 'RCW 46.61.370', t = 'Failure to Stop for School Bus', c = 'TI', g = MOVING, fine = 419 },
    { id = 'railroad', rcw = 'RCW 46.61.340', t = 'Failure to Stop at Railroad Grade Crossing', c = 'TI', g = MOVING, fine = 136 },
    { id = 'sidewalk', rcw = 'RCW 46.61.606', t = 'Driving on Sidewalk', c = 'TI', g = MOVING, fine = 136 },
    { id = 'neg2', rcw = 'RCW 46.61.525', t = 'Negligent Driving — Second Degree', c = 'TI', g = MOVING, fine = 550 },
    { id = 'neg2vu', rcw = 'RCW 46.61.526', t = 'Negligent Driving — Second Degree With a Vulnerable User Victim', c = 'TI', g = MOVING, fine = 5000 },

    { id = 'phone', rcw = 'RCW 46.61.672', t = 'Driving While Using a Personal Electronic Device', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'distract', rcw = 'RCW 46.61.673', t = 'Dangerously Distracted Driving', c = 'TI', g = SAFETY, fine = 99 },
    { id = 'belt', rcw = 'RCW 46.61.688', t = 'Failure to Wear Safety Belt', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'child', rcw = 'RCW 46.61.687', t = 'Child Passenger Restraint Violation', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'opencont', rcw = 'RCW 46.61.519', t = 'Open Container of Alcohol in Vehicle', c = 'TI', g = SAFETY, fine = 136 },
    { id = 'helmet', rcw = 'RCW 46.37.530', t = 'Motorcycle Helmet Required', c = 'TI', g = SAFETY, fine = 136 },

    { id = 'equip', rcw = 'RCW 46.37.010', t = 'Defective or Improper Equipment', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'headlights', rcw = 'RCW 46.37.020', t = 'No Headlights When Required', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'dim', rcw = 'RCW 46.37.230', t = 'Failure to Dim Headlights', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'taillamp', rcw = 'RCW 46.37.070', t = 'Defective Tail Lamp / License Plate Lamp', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'stoplamp', rcw = 'RCW 46.37.200', t = 'Defective Stop Lamp / Turn Signal', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'tint', rcw = 'RCW 46.37.430', t = 'Illegal Window Tinting', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'muffler', rcw = 'RCW 46.37.390', t = 'Defective or Modified Muffler / Excessive Noise', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'windshield', rcw = 'RCW 46.37.410', t = 'Obstructed or Damaged Windshield', c = 'TI', g = EQUIP, fine = 136 },
    { id = 'load', rcw = 'RCW 46.61.655', t = 'Unsecured Load', c = 'TI', g = EQUIP, fine = 228 },
    { id = 'studs', rcw = 'RCW 46.37.420', t = 'Studded Tires Out of Season', c = 'TI', g = EQUIP, fine = 136 },

    { id = 'regexp', rcw = 'RCW 46.16A.030', t = 'Expired Registration — 2 Months or Less', c = 'TI', g = LICENSE, fine = 136 },
    { id = 'regexp2', rcw = 'RCW 46.16A.030', t = 'Expired Registration — More Than 2 Months', c = 'TI', g = LICENSE, fine = 228 },
    { id = 'plates', rcw = 'RCW 46.16A.200', t = 'Failure to Display License Plates / Improper Display', c = 'TI', g = LICENSE, fine = 136 },
    { id = 'dlcarry', rcw = 'RCW 46.20.017', t = 'Failure to Carry or Display Driver License', c = 'TI', g = LICENSE, fine = 136 },
    { id = 'nvolid', rcw = 'RCW 46.20.015', t = 'No Valid Operator\'s License — With Valid ID', c = 'TI', g = LICENSE, fine = 250 },
    { id = 'insurance', rcw = 'RCW 46.30.020', t = 'No Proof of Liability Insurance', c = 'TI', g = LICENSE, fine = 550 },
    { id = 'address', rcw = 'RCW 46.20.205', t = 'Failure to Notify DOL of Change of Address', c = 'TI', g = LICENSE, fine = 136 },

    { id = 'pedyield', rcw = 'RCW 46.61.240', t = 'Pedestrian Failure to Yield (Outside Crosswalk)', c = 'TI', g = PED, fine = 68 },
    { id = 'bikelight', rcw = 'RCW 46.61.780', t = 'Bicycle Without Required Lamps at Night', c = 'TI', g = PED, fine = 136 },

    -- =====================================================================
    -- CIVIL INFRACTIONS (NON-TRAFFIC, RCW 7.80) — Notice of Civil Infraction
    -- =====================================================================
    { id = 'litter', rcw = 'RCW 70A.200.060(1)', t = 'Littering — Less Than One Cubic Foot (Class 3)', c = 'CI', g = CIVIL, fine = 50 },
    { id = 'cannabispub', rcw = 'RCW 69.50.445', t = 'Opening / Consuming Cannabis in View of the General Public (Class 3)', c = 'CI', g = CIVIL, fine = 50 },
    { id = 'smoking', rcw = 'RCW 70.160.070', t = 'Smoking in a Place Where Smoking Is Prohibited', c = 'CI', g = CIVIL, fine = 100 },

    -- =====================================================================
    -- MISDEMEANORS (M)
    -- =====================================================================
    { id = 'dwls3', rcw = 'RCW 46.20.342(1)(c)', t = 'Driving While License Suspended / Revoked — Third Degree (DWLS 3)', c = 'M', g = CTRAFFIC },
    { id = 'nvol', rcw = 'RCW 46.20.005', t = 'No Valid Operator\'s License — Without ID', c = 'M', g = CTRAFFIC },
    { id = 'neg1', rcw = 'RCW 46.61.5249', t = 'Negligent Driving — First Degree', c = 'M', g = CTRAFFIC },
    { id = 'hrunatt', rcw = 'RCW 46.52.010', t = 'Hit and Run — Unattended Vehicle or Property', c = 'M', g = CTRAFFIC },
    { id = 'failobey', rcw = 'RCW 46.61.022', t = 'Failure to Obey a Law Enforcement Officer', c = 'M', g = CTRAFFIC },
    { id = 'refuseinfo', rcw = 'RCW 46.61.020', t = 'Refusal to Give Information to or Cooperate With Officer', c = 'M', g = CTRAFFIC },
    { id = 'disorderly', rcw = 'RCW 9A.84.030', t = 'Disorderly Conduct', c = 'M', g = ORDER },
    { id = 'disperse', rcw = 'RCW 9A.84.020', t = 'Failure to Disperse', c = 'M', g = ORDER },
    { id = 'trespass2', rcw = 'RCW 9A.52.080', t = 'Criminal Trespass — Second Degree', c = 'M', g = PROPERTY },
    { id = 'resist', rcw = 'RCW 9A.76.040', t = 'Resisting Arrest', c = 'M', g = ORDER },
    { id = 'indecent', rcw = 'RCW 9A.88.010', t = 'Indecent Exposure', c = 'M', g = ORDER },
    { id = 'litter2', rcw = 'RCW 70A.200.060(2)', t = 'Littering — One Cubic Foot or More', c = 'M', g = ORDER },
    { id = 'parapher', rcw = 'RCW 69.50.412', t = 'Use of Drug Paraphernalia', c = 'M', g = DRUGS },
    { id = 'cannabis40', rcw = 'RCW 69.50.4014', t = 'Unlawful Possession of Cannabis — 40 Grams or Less', c = 'M', g = DRUGS },
    { id = 'cpl', rcw = 'RCW 9.41.050', t = 'Carrying a Concealed Pistol Without a License', c = 'M', g = WEAPONS },

    -- =====================================================================
    -- GROSS MISDEMEANORS (GM)
    -- =====================================================================
    { id = 'dui', rcw = 'RCW 46.61.502', t = 'Driving Under the Influence (DUI)', c = 'GM', g = DUI },
    { id = 'physctl', rcw = 'RCW 46.61.504', t = 'Physical Control of a Vehicle While Under the Influence', c = 'GM', g = DUI },
    { id = 'interlock', rcw = 'RCW 46.20.740', t = 'Operating a Vehicle Without a Required Ignition Interlock Device', c = 'GM', g = DUI },
    { id = 'reckless', rcw = 'RCW 46.61.500', t = 'Reckless Driving', c = 'GM', g = CTRAFFIC },
    { id = 'dwls2', rcw = 'RCW 46.20.342(1)(b)', t = 'Driving While License Suspended / Revoked — Second Degree (DWLS 2)', c = 'GM', g = CTRAFFIC },
    { id = 'dwls1', rcw = 'RCW 46.20.342(1)(a)', t = 'Driving While License Suspended / Revoked — First Degree (DWLS 1)', c = 'GM', g = CTRAFFIC },
    { id = 'hrunprop', rcw = 'RCW 46.52.020(5)', t = 'Hit and Run — Attended Vehicle (Property Damage Only)', c = 'GM', g = CTRAFFIC },
    { id = 'racing', rcw = 'RCW 46.61.530', t = 'Racing of Vehicles on Highways', c = 'GM', g = CTRAFFIC },
    { id = 'assault4', rcw = 'RCW 9A.36.041', t = 'Assault — Fourth Degree', c = 'GM', g = PERSONS },
    { id = 'harass', rcw = 'RCW 9A.46.020', t = 'Harassment', c = 'GM', g = PERSONS },
    { id = 'endanger', rcw = 'RCW 9A.36.050', t = 'Reckless Endangerment', c = 'GM', g = PERSONS },
    { id = 'stalking', rcw = 'RCW 9A.46.110', t = 'Stalking', c = 'GM', g = PERSONS },
    { id = 'dvinterfere', rcw = 'RCW 9A.36.150', t = 'Interfering With the Reporting of Domestic Violence', c = 'GM', g = PERSONS },
    { id = 'theft3', rcw = 'RCW 9A.56.050', t = 'Theft — Third Degree', c = 'GM', g = PROPERTY },
    { id = 'pspr3', rcw = 'RCW 9A.56.170', t = 'Possession of Stolen Property — Third Degree', c = 'GM', g = PROPERTY },
    { id = 'mm3', rcw = 'RCW 9A.48.090', t = 'Malicious Mischief — Third Degree', c = 'GM', g = PROPERTY },
    { id = 'trespass1', rcw = 'RCW 9A.52.070', t = 'Criminal Trespass — First Degree', c = 'GM', g = PROPERTY },
    { id = 'prowl2', rcw = 'RCW 9A.52.100', t = 'Vehicle Prowling — Second Degree', c = 'GM', g = PROPERTY },
    { id = 'obstruct', rcw = 'RCW 9A.76.020', t = 'Obstructing a Law Enforcement Officer', c = 'GM', g = ORDER },
    { id = 'falsestmt', rcw = 'RCW 9A.76.175', t = 'Making a False or Misleading Statement to a Public Servant', c = 'GM', g = ORDER },
    { id = 'nco', rcw = 'RCW 7.105.450', t = 'Violation of a No-Contact / Protection Order', c = 'GM', g = ORDER },
    { id = 'mip', rcw = 'RCW 66.44.270', t = 'Minor in Possession / Consumption of Alcohol', c = 'GM', g = DRUGS },
    { id = 'vucsa', rcw = 'RCW 69.50.4013', t = 'Possession of a Controlled Substance', c = 'GM', g = DRUGS },
    { id = 'display', rcw = 'RCW 9.41.270', t = 'Unlawful Display of a Weapon', c = 'GM', g = WEAPONS },

    -- =====================================================================
    -- CLASS C FELONIES (FC)
    -- =====================================================================
    { id = 'elude', rcw = 'RCW 46.61.024', t = 'Attempting to Elude a Pursuing Police Vehicle', c = 'FC', g = CTRAFFIC },
    { id = 'hruninj', rcw = 'RCW 46.52.020(4)(b)', t = 'Hit and Run — Injury', c = 'FC', g = CTRAFFIC },
    { id = 'assault3', rcw = 'RCW 9A.36.031', t = 'Assault — Third Degree (incl. Law Enforcement Officer)', c = 'FC', g = PERSONS },
    { id = 'harasskill', rcw = 'RCW 9A.46.020(2)(b)', t = 'Harassment — Threats to Kill', c = 'FC', g = PERSONS },
    { id = 'unlawimp', rcw = 'RCW 9A.40.040', t = 'Unlawful Imprisonment', c = 'FC', g = PERSONS },
    { id = 'ncofel', rcw = 'RCW 7.105.450(4)', t = 'Felony Violation of a No-Contact / Protection Order', c = 'FC', g = PERSONS },
    { id = 'theft2', rcw = 'RCW 9A.56.040', t = 'Theft — Second Degree', c = 'FC', g = PROPERTY },
    { id = 'tmvwp2', rcw = 'RCW 9A.56.075', t = 'Taking a Motor Vehicle Without Permission — Second Degree', c = 'FC', g = PROPERTY },
    { id = 'pspr2', rcw = 'RCW 9A.56.160', t = 'Possession of Stolen Property — Second Degree', c = 'FC', g = PROPERTY },
    { id = 'mm2', rcw = 'RCW 9A.48.080', t = 'Malicious Mischief — Second Degree', c = 'FC', g = PROPERTY },
    { id = 'prowl1', rcw = 'RCW 9A.52.095', t = 'Vehicle Prowling — First Degree', c = 'FC', g = PROPERTY },
    { id = 'idtheft2', rcw = 'RCW 9.35.020', t = 'Identity Theft — Second Degree', c = 'FC', g = PROPERTY },
    { id = 'forgery', rcw = 'RCW 9A.60.020', t = 'Forgery', c = 'FC', g = PROPERTY },
    { id = 'upf2', rcw = 'RCW 9.41.040(2)', t = 'Unlawful Possession of a Firearm — Second Degree', c = 'FC', g = WEAPONS },
    { id = 'escape2', rcw = 'RCW 9A.76.120', t = 'Escape — Second Degree', c = 'FC', g = ORDER },
    { id = 'rca1', rcw = 'RCW 9A.76.070', t = 'Rendering Criminal Assistance — First Degree', c = 'FC', g = ORDER },
    { id = 'pwidc', rcw = 'RCW 69.50.401(2)(c)', t = 'Delivery / Possession With Intent to Deliver — Schedule III-V', c = 'FC', g = DRUGS },

    -- =====================================================================
    -- CLASS B FELONIES (FB)
    -- =====================================================================
    { id = 'veh_assault', rcw = 'RCW 46.61.522', t = 'Vehicular Assault', c = 'FB', g = DUI },
    { id = 'felonydui', rcw = 'RCW 46.61.502(6)', t = 'Felony Driving Under the Influence', c = 'FB', g = DUI },
    { id = 'felonypc', rcw = 'RCW 46.61.504(6)', t = 'Felony Physical Control', c = 'FB', g = DUI },
    { id = 'hrundeath', rcw = 'RCW 46.52.020(4)(a)', t = 'Hit and Run — Death', c = 'FB', g = CTRAFFIC },
    { id = 'assault2', rcw = 'RCW 9A.36.021', t = 'Assault — Second Degree', c = 'FB', g = PERSONS },
    { id = 'driveby', rcw = 'RCW 9A.36.045', t = 'Drive-By Shooting', c = 'FB', g = PERSONS },
    { id = 'kidnap2', rcw = 'RCW 9A.40.030', t = 'Kidnapping — Second Degree', c = 'FB', g = PERSONS },
    { id = 'manslaughter2', rcw = 'RCW 9A.32.070', t = 'Manslaughter — Second Degree', c = 'FB', g = PERSONS },
    { id = 'intimps', rcw = 'RCW 9A.76.180', t = 'Intimidating a Public Servant', c = 'FB', g = ORDER },
    { id = 'intimwit', rcw = 'RCW 9A.72.110', t = 'Intimidating a Witness', c = 'FB', g = ORDER },
    { id = 'escape1', rcw = 'RCW 9A.76.110', t = 'Escape — First Degree', c = 'FB', g = ORDER },
    { id = 'robbery2', rcw = 'RCW 9A.56.210', t = 'Robbery — Second Degree', c = 'FB', g = PROPERTY },
    { id = 'burglary2', rcw = 'RCW 9A.52.030', t = 'Burglary — Second Degree', c = 'FB', g = PROPERTY },
    { id = 'resburglary', rcw = 'RCW 9A.52.025', t = 'Residential Burglary', c = 'FB', g = PROPERTY },
    { id = 'theft1', rcw = 'RCW 9A.56.030', t = 'Theft — First Degree', c = 'FB', g = PROPERTY },
    { id = 'tmv', rcw = 'RCW 9A.56.065', t = 'Theft of a Motor Vehicle', c = 'FB', g = PROPERTY },
    { id = 'psv', rcw = 'RCW 9A.56.068', t = 'Possession of a Stolen Vehicle', c = 'FB', g = PROPERTY },
    { id = 'tmvwp1', rcw = 'RCW 9A.56.070', t = 'Taking a Motor Vehicle Without Permission — First Degree', c = 'FB', g = PROPERTY },
    { id = 'pspr1', rcw = 'RCW 9A.56.150', t = 'Possession of Stolen Property — First Degree', c = 'FB', g = PROPERTY },
    { id = 'idtheft1', rcw = 'RCW 9.35.020', t = 'Identity Theft — First Degree', c = 'FB', g = PROPERTY },
    { id = 'mm1', rcw = 'RCW 9A.48.070', t = 'Malicious Mischief — First Degree', c = 'FB', g = PROPERTY },
    { id = 'arson2', rcw = 'RCW 9A.48.030', t = 'Arson — Second Degree', c = 'FB', g = PROPERTY },
    { id = 'upf1', rcw = 'RCW 9.41.040(1)', t = 'Unlawful Possession of a Firearm — First Degree', c = 'FB', g = WEAPONS },
    { id = 'pwidab', rcw = 'RCW 69.50.401(2)(a)', t = 'Delivery / Possession With Intent to Deliver — Narcotic (Sched. I-II) or Methamphetamine', c = 'FB', g = DRUGS },

    -- =====================================================================
    -- CLASS A FELONIES (FA)
    -- =====================================================================
    { id = 'vehhom', rcw = 'RCW 46.61.520', t = 'Vehicular Homicide', c = 'FA', g = DUI },
    { id = 'murder1', rcw = 'RCW 9A.32.030', t = 'Murder — First Degree', c = 'FA', g = PERSONS },
    { id = 'murder2', rcw = 'RCW 9A.32.050', t = 'Murder — Second Degree', c = 'FA', g = PERSONS },
    { id = 'manslaughter1', rcw = 'RCW 9A.32.060', t = 'Manslaughter — First Degree', c = 'FA', g = PERSONS },
    { id = 'assault1', rcw = 'RCW 9A.36.011', t = 'Assault — First Degree', c = 'FA', g = PERSONS },
    { id = 'kidnap1', rcw = 'RCW 9A.40.020', t = 'Kidnapping — First Degree', c = 'FA', g = PERSONS },
    { id = 'robbery1', rcw = 'RCW 9A.56.200', t = 'Robbery — First Degree', c = 'FA', g = PROPERTY },
    { id = 'burglary1', rcw = 'RCW 9A.52.020', t = 'Burglary — First Degree', c = 'FA', g = PROPERTY },
    { id = 'arson1', rcw = 'RCW 9A.48.020', t = 'Arson — First Degree', c = 'FA', g = PROPERTY },
}

-- Groupes de classifications utilisés par les rapports
MDC_CLASS_SETS = {
    infractions = { 'TI', 'CI' },                       -- Notice of Infraction, Written Warning
    citable = { 'M', 'GM' },                            -- Criminal Citation (pas de crime : arrestation)
    criminal = { 'M', 'GM', 'FC', 'FB', 'FA' },         -- Arrest Report, DUI
    all = { 'TI', 'CI', 'M', 'GM', 'FC', 'FB', 'FA' },  -- Incident Report, collision (citations délivrées)
}
