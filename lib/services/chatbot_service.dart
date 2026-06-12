import 'dart:math';

class ChatbotService {
  final List<Map<String, String>> _history = [];

  // ─── Knowledge Base ───────────────────────────────────────────────────────
  static const Map<String, String> _responses = {
    // ── Greetings ──────────────────────────────────────────────────────────
    'hello': 'Vanakkam! 👋 I\'m your Tamil Nadu Road Safety Assistant. How can I help you drive safely today?',
    'hi': 'Vanakkam! 👋 How can I help you today?',
    'hey': 'Hey there! Vanakkam! 😊 Ask me anything about Tamil Nadu traffic rules.',
    'good morning': 'Good morning! 🌅 Drive safe today. How can I help you?',
    'good afternoon': 'Good afternoon! ☀️ How can I assist you with road safety?',
    'good evening': 'Good evening! 🌆 How can I assist you with road safety?',
    'good night': 'Good night! 🌙 Rest well and drive safely tomorrow. Vanakkam!',
    'vanakkam': 'Vanakkam! 🙏 How can I help you today?',

    // ── Speed Limits ────────────────────────────────────────────────────────
    'speed limit': '🚗 Speed limits in Tamil Nadu:\n• City/Urban roads: 50 km/h\n• State highways: 70 km/h\n• National highways: 100 km/h\n• School/Hospital zones: 25–30 km/h\n• Expressways (e.g. Chennai–Bengaluru): 120 km/h\n\nAlways follow posted signs — they override general limits.',
    'speed limit chennai': '🚗 In Chennai city, the speed limit is 50 km/h on most roads. School zones and hospital areas have lower limits of 25–30 km/h.',
    'speed': '🚗 Speed limits in Tamil Nadu:\n• City roads: 50 km/h\n• State highways: 70 km/h\n• National highways: 100 km/h\n\nOverspeeding fine: ₹1,000 (first offence), ₹2,000 (repeat offence).',
    'overspeeding': '⚠️ Overspeeding fine in TN:\n• First offence: ₹1,000\n• Repeat offence: ₹2,000\n• Heavy vehicles: ₹2,000 (first), ₹4,000 (repeat)\n\nOverspeeding is the #1 cause of fatal accidents. Please drive within limits!',
    'expressway': '🛣️ Expressway speed limits in TN:\n• Cars/bikes: up to 120 km/h\n• Buses: up to 100 km/h\n• Trucks: up to 80 km/h\n• Emergency lane must NEVER be used except for breakdowns or emergencies.',

    // ── Helmet ──────────────────────────────────────────────────────────────
    'helmet': '🪖 Helmet rules in Tamil Nadu:\n• Mandatory for both rider AND pillion\n• Must be BIS-certified (ISI mark)\n• Fine for not wearing: ₹1,000\n• Licence suspension possible for repeat offence\n• Children above 4 years on bikes must also wear helmets\n\nAlways wear a proper helmet — it saves lives!',
    'helmet fine': '🪖 The fine for not wearing a helmet in Tamil Nadu is ₹1,000. Applies to both rider and pillion passenger.',
    'helmet law': '🪖 Under TN Motor Vehicles Rules, helmets are mandatory for all two-wheeler riders and pillions. Only BIS-certified (ISI marked) helmets are valid. Fine: ₹1,000.',
    'children helmet': '🪖 Children above 4 years of age riding as pillion on a two-wheeler must wear a helmet. A child safety harness is also recommended. Fine for violation: ₹1,000.',

    // ── Seat Belt ───────────────────────────────────────────────────────────
    'seat belt': '🔒 Seat belt rules in Tamil Nadu:\n• Mandatory for ALL occupants (front + rear)\n• Fine: ₹1,000\n• Air bags are NOT a substitute for seat belts\n• Children under 4 must use a child restraint/car seat\n\nAlways buckle up — it reduces fatality risk by 45%!',
    'seatbelt': '🔒 Seat belts are mandatory for all occupants in Tamil Nadu. Fine for not wearing: ₹1,000. This includes rear seat passengers too!',
    'seat belt fine': '🔒 The fine for not wearing a seat belt in Tamil Nadu is ₹1,000, applicable to both driver and all passengers.',
    'child seat': '🧒 Child safety rules in TN vehicles:\n• Children under 4 years must use an approved child car seat\n• Children under 12 should NOT sit in the front seat\n• Violation fine: ₹1,000\n\nA child safety seat reduces injury risk by up to 70%!',

    // ── Drunk Driving ───────────────────────────────────────────────────────
    'drunk driving': '🍺 Drunk driving rules in Tamil Nadu:\n• Legal limit: 30mg alcohol per 100ml blood\n• Zero tolerance for drivers under 18\n• Fine: ₹10,000 + imprisonment up to 6 months\n• Repeat offence: ₹15,000 + 2 years imprisonment\n• Licence cancellation\n\nNever drink and drive!',
    'drink and drive': '🍺 Drunk driving is a serious offence in TN:\n• Fine: ₹10,000 + imprisonment\n• BAC limit: 30mg/100ml\n• Zero tolerance for under-18 drivers\n\nIf you drink, take a cab. It\'s not worth the risk!',
    'alcohol': '🍺 Driving under alcohol influence in TN:\n• BAC limit: 30mg per 100ml blood\n• Fine: ₹10,000 + up to 6 months jail\n• Repeat: ₹15,000 + 2 years jail\n• Licence will be suspended/cancelled.',
    'drunken driving': '🍺 Drunken driving fine in Tamil Nadu is ₹10,000 with possible imprisonment. BAC limit is 30mg/100ml blood. Zero tolerance for drivers under 18 years.',
    'drug driving': '💊 Driving under influence of drugs in TN:\n• Treated same as drunk driving\n• Fine: ₹10,000 + up to 6 months imprisonment\n• Repeat: ₹15,000 + 2 years imprisonment\n• Immediate licence suspension\n\nDrugs severely impair reaction time. Never drive after taking any intoxicant!',

    // ── Mobile Phone ────────────────────────────────────────────────────────
    'mobile': '📱 Using mobile phone while driving in TN:\n• Fine: ₹5,000\n• Hands-free devices are allowed\n• Pull over safely if you must take a call\n\nStay focused on the road — no call is worth your life!',
    'phone': '📱 Using a phone while driving:\n• Fine: ₹5,000 in Tamil Nadu\n• Includes texting, browsing, and calling\n• Hands-free/Bluetooth is permitted\n\nOne second of distraction can cause an accident!',
    'mobile phone': '📱 Mobile phone use while driving is fined ₹5,000 in Tamil Nadu. This includes talking, texting, and using apps. Hands-free calling via Bluetooth is allowed.',

    // ── Documents ───────────────────────────────────────────────────────────
    'documents': '📄 Documents required while driving in TN:\n• Driving Licence (DL)\n• Vehicle Registration Certificate (RC)\n• Insurance Certificate (valid)\n• Pollution Under Control (PUC) Certificate\n• Fitness Certificate (for commercial vehicles)\n\nDigiLocker copies are legally accepted!',
    'driving documents': '📄 Mandatory documents while driving:\n1. Driving Licence (DL)\n2. Registration Certificate (RC)\n3. Valid Insurance\n4. PUC Certificate\n\nYou can show these via DigiLocker app — no need for physical copies!',
    'document': '📄 While driving in Tamil Nadu, carry:\n• DL (Driving Licence)\n• RC (Registration Certificate)\n• Insurance Certificate\n• PUC Certificate\n\nDigiLocker is accepted by TN police.',
    'digilocker': '📲 DigiLocker is officially accepted in Tamil Nadu. Store your DL, RC, Insurance, and PUC on the DigiLocker app. No need to carry physical copies. Download: digilocker.gov.in',

    // ── Driving Licence ─────────────────────────────────────────────────────
    'driving licence': '🪪 Driving Licence info in TN:\n• Apply at nearest RTO office\n• Learner\'s licence first (valid 6 months)\n• Permanent licence after driving test\n• Minimum age: 18 years (LMV), 20 years (transport vehicles)\n• Apply online at parivahan.gov.in',
    'licence': '🪪 For Driving Licence in Tamil Nadu:\n• Visit your local RTO or apply at parivahan.gov.in\n• Learner\'s licence → Driving test → Permanent licence\n• Minimum age: 18 years for cars/bikes',
    'dl': '🪪 Driving Licence (DL) is mandatory to drive in TN. Apply at RTO or parivahan.gov.in. Driving without a licence: fine ₹5,000.',
    'learner licence': '🪪 Learner\'s Licence in TN:\n• Apply at RTO or parivahan.gov.in\n• Valid for 6 months\n• Must display "L" board on vehicle\n• Must be accompanied by a licensed driver\n• Minimum age: 18 years (16 for gearless bikes up to 50cc)',
    'driving without licence': '⛔ Driving without a valid licence in Tamil Nadu:\n• Fine: ₹5,000\n• Vehicle may be seized\n• Criminal case possible for repeat offence\n\nAlways carry your valid DL while driving!',
    'minor driving': '⛔ Underage driving in Tamil Nadu:\n• Vehicle owner/guardian is liable\n• Fine: ₹25,000 on the guardian/owner\n• Vehicle registration cancelled for 1 year\n• The minor\'s ability to get a licence may be affected\n\nNever allow minors to drive!',

    // ── Insurance ───────────────────────────────────────────────────────────
    'insurance': '🛡️ Vehicle insurance in Tamil Nadu:\n• Third-party insurance is mandatory by law\n• Driving without insurance: fine ₹2,000 (first), ₹4,000 (repeat)\n• Comprehensive insurance highly recommended\n• Renew before expiry to avoid fines',
    'insurance fine': '🛡️ Driving without valid insurance in TN:\n• First offence: ₹2,000\n• Repeat offence: ₹4,000 or imprisonment up to 3 months',
    'third party insurance': '🛡️ Third-party insurance is compulsory under the Motor Vehicles Act. It covers damage/injury caused to others. Without it: fine ₹2,000 (first), ₹4,000 (repeat). Always keep insurance valid!',

    // ── PUC ─────────────────────────────────────────────────────────────────
    'puc': '💨 PUC (Pollution Under Control) Certificate:\n• Mandatory for all vehicles in TN\n• Available at petrol stations and authorized centres\n• Fine for no PUC: ₹1,000 (first), ₹2,000 (repeat)\n• Petrol vehicles: valid 6 months\n• Diesel vehicles: valid 3 months\n• BS-VI vehicles: valid 1 year',
    'pollution': '💨 PUC Certificate is mandatory in Tamil Nadu. Get it at any petrol station or authorised centre. Fine: ₹1,000. Petrol: 6-month validity. Diesel: 3 months. BS-VI: 1 year.',

    // ── Traffic Signals ─────────────────────────────────────────────────────
    'traffic signal': '🚦 Traffic signal rules in TN:\n• Red: Stop completely behind stop line\n• Yellow: Slow down, prepare to stop\n• Green: Proceed with caution\n• Flashing Red: Treat as STOP sign\n• Flashing Yellow: Slow down and proceed with caution\n\nJumping red light fine: ₹1,000–₹5,000',
    'red light': '🚦 Jumping a red light in Tamil Nadu:\n• Fine: ₹1,000 (first offence)\n• Repeat: ₹5,000\n• Possible licence suspension\n\nAlways stop at red — your life is worth more than a few seconds!',
    'signal': '🚦 Always obey traffic signals in Tamil Nadu. Jumping a red light can cost ₹1,000–₹5,000 fine and licence suspension.',

    // ── Emergency ───────────────────────────────────────────────────────────
    'emergency': '🆘 Emergency contacts in Tamil Nadu:\n• Police: 100\n• Ambulance: 108\n• Fire: 101\n• All emergencies: 112\n• TN Road Safety Helpline: 1033\n• Women helpline: 181\n\nSave these numbers in your phone!',
    'helpline': '📞 TN Road Safety Helpline: 1033\nAll emergencies: 112\nPolice: 100\nAmbulance: 108\nFire: 101\nWomen helpline: 181',
    'accident': '🆘 In case of an accident in TN:\n1. Call 112 (emergency) immediately\n2. Call ambulance: 108\n3. Inform police: 100\n4. TN Road Safety Helpline: 1033\n5. Don\'t move injured persons unless necessary\n6. Note witness details and vehicle numbers\n7. Good Samaritans are legally protected — help accident victims!',
    'good samaritan': '🤝 Good Samaritan Law in TN/India:\n• If you help an accident victim, you are legally protected\n• You CANNOT be detained or harassed by police for helping\n• Your personal details are kept confidential\n• You are NOT liable for the victim\'s outcome\n\nPlease help accident victims — you could save a life!',

    // ── Chennai Specific ────────────────────────────────────────────────────
    'chennai': '🏙️ Chennai-specific traffic rules:\n• No honking zones near hospitals, schools, courts\n• Peak hour restrictions on certain roads\n• Many one-way streets in city centre\n• Speed limit: 50 km/h\n• Metro corridor rules near MTC routes\n• Specific parking restrictions in T. Nagar, Anna Salai, etc.',
    'honking': '📯 Honking rules in Tamil Nadu:\n• No honking near hospitals, schools, courts\n• Unnecessary honking fine: ₹1,000\n• Chennai has designated silent zones\n• Air horns are banned on all vehicles\n\nHonk only when necessary for safety!',

    // ── Lane Discipline ─────────────────────────────────────────────────────
    'lane': '🛣️ Lane discipline in Tamil Nadu:\n• Keep left unless overtaking\n• Heavy vehicles must use left lane\n• Don\'t straddle lanes\n• Fine for wrong lane: ₹500–₹1,000\n\nProper lane discipline prevents accidents!',
    'overtaking': '🛣️ Overtaking rules in TN:\n• Always overtake from the RIGHT side\n• Never overtake on curves, hills, or junctions\n• Never overtake at zebra crossings\n• Use indicators before overtaking\n• Dangerous overtaking fine: ₹1,000–₹5,000',

    // ── Parking ─────────────────────────────────────────────────────────────
    'parking': '🅿️ Parking rules in Tamil Nadu:\n• No parking near junctions, bus stops, fire hydrants\n• No parking on footpaths or cycle tracks\n• Wrong parking fine: ₹500–₹2,000\n• Vehicle may be towed — retrieval fee applies\n• Pay-and-park zones must be used in cities\n\nAlways park in designated areas!',
    'no parking': '🚫 No-parking zone violations in TN:\n• Fine: ₹500–₹2,000\n• Vehicle towing + impound fee\n• Never park near school gates, hospitals, or fire stations',
    'towing': '🚗 Vehicle towing in Tamil Nadu:\n• Illegally parked vehicles are towed\n• Towing charges: ₹500–₹1,000\n• Impound/storage fee per day applies\n• Collect vehicle from nearest police station or municipal facility',

    // ── Pedestrian & Zebra Crossing ─────────────────────────────────────────
    'zebra crossing': '🦓 Zebra crossing rules in TN:\n• Drivers MUST stop for pedestrians at zebra crossings\n• Do NOT stop your vehicle ON the zebra crossing\n• Fine for blocking zebra crossing: ₹500\n• Pedestrians have the right of way at zebra crossings',
    'pedestrian': '🚶 Pedestrian safety rules:\n• Always use footpaths/pavements\n• Cross only at zebra crossings or designated areas\n• Obey pedestrian signals\n• Look both ways before crossing\n• Drivers: give way to pedestrians at crossings. Fine for not stopping: ₹500',
    'footpath': '🚶 Driving on footpaths or pavements is strictly prohibited in Tamil Nadu. Fine: ₹500–₹2,000 + vehicle seizure possible. Footpaths are for pedestrians only!',

    // ── Two-Wheeler Specific ────────────────────────────────────────────────
    'two wheeler': '🏍️ Two-wheeler rules in Tamil Nadu:\n• Helmet mandatory for rider + pillion\n• Max 2 persons allowed (1 rider + 1 pillion)\n• No riding on footpaths\n• Carry valid DL, RC, Insurance, PUC\n• No mobile phone use while riding\n• Headlights mandatory even during daytime',
    'bike': '🏍️ Bike/two-wheeler rules in TN:\n• Helmet mandatory (BIS-certified)\n• Max 2 persons only\n• Headlight must be on always (day & night)\n• No triple riding — fine: ₹1,000\n• No stunts on public roads — fine up to ₹5,000',
    'triple riding': '🏍️ Triple riding (3 persons on a two-wheeler) is illegal in Tamil Nadu.\n• Fine: ₹1,000\n• This applies on all roads, day and night\n\nOnly 1 rider + 1 pillion is allowed!',
    'pillion': '🏍️ Pillion rules in TN:\n• Pillion must wear helmet (BIS-certified)\n• Must sit properly — not sideways\n• Must not distract the rider\n• Fine for no helmet: ₹1,000',
    'headlight': '💡 Headlight rules in Tamil Nadu:\n• Two-wheelers: headlights must be ON at all times (day & night)\n• Cars/other vehicles: headlights mandatory at night and low visibility\n• Using high beam in city/traffic: ₹500 fine\n• DRL (Daytime Running Lights) required for new vehicles',

    // ── Heavy Vehicles ─────────────────────────────────────────────────────
    'truck': '🚛 Truck/Heavy vehicle rules in TN:\n• Must use the leftmost lane\n• No entry into city limits during peak hours (varies by city)\n• Overloading fine: ₹20,000+\n• Fitness certificate mandatory\n• Speed limit on NH: 80 km/h\n• No over-height/over-width loads without special permit',
    'bus': '🚌 Bus rules in TN:\n• Must halt only at designated bus stops\n• No stopping in the middle of road to pick/drop passengers\n• Speed limit: 80 km/h on highways\n• Must have First Aid kit, fire extinguisher\n• Fine for illegal stop: ₹1,000',
    'overloading': '⚖️ Overloading rules in Tamil Nadu:\n• Fine: ₹20,000 for first offence\n• ₹2,000 per extra tonne over limit for heavy goods vehicles\n• Vehicle impounded until excess load is removed\n• Overloaded vehicles damage roads and cause accidents',

    // ── Fatigued Driving ────────────────────────────────────────────────────
    'fatigued driving': '😴 Driving while fatigued (drowsy driving) in TN:\n• Just as dangerous as drunk driving\n• Take a break every 2 hours on long trips\n• Commercial drivers: max 8 hours driving per day by law\n• Resting at designated stops is mandatory for lorry/bus drivers\n\nIf you feel sleepy, PULL OVER. It can wait. You cannot be replaced!',
    'drowsy': '😴 Drowsy/sleepy driving is extremely dangerous. Studies show 24 hours without sleep = impairment similar to 0.10% BAC. Take a break every 2 hours. Commercial drivers must rest after 8 hours. Never drive if you feel sleepy!',
    'fatigue': '😴 Fatigue while driving:\n• Take a 15-minute break every 2 hours\n• Avoid driving between 2 AM – 6 AM (fatigue peaks)\n• Commercial drivers: legally limited to 8 hrs/day\n• Signs of fatigue: yawning, heavy eyelids, drifting out of lane\n\nStop and rest — it saves lives!',

    // ── Road Rage ───────────────────────────────────────────────────────────
    'road rage': '😡 Road rage in Tamil Nadu:\n• Aggressive driving fine: ₹1,000–₹5,000\n• Assault on other road users: criminal case under IPC\n• Licence suspension for dangerous behaviour\n• Causing injury/death: imprisonment + heavy fines\n\nStay calm on the road. No argument is worth a life!',
    'aggressive driving': '😡 Aggressive driving includes tailgating, cutting lanes, flashing lights, honking excessively. Fine: ₹1,000–₹5,000. Can lead to licence suspension and criminal charges in Tamil Nadu.',

    // ── Traffic Police & Challan ────────────────────────────────────────────
    'challan': '📝 Traffic challan (e-challan) in Tamil Nadu:\n• Challans are issued digitally via cameras + police\n• Check pending challans: echallan.parivahan.gov.in\n• Pay online or at RTO/police station\n• Unpaid challans can block licence renewal and RC transfer\n• Court challan requires appearance at Magistrate court',
    'fine': '💰 Common traffic fines in Tamil Nadu (Motor Vehicles Act 2019):\n• No helmet: ₹1,000\n• No seat belt: ₹1,000\n• Drunk driving: ₹10,000\n• Overspeeding: ₹1,000–₹2,000\n• Red light jump: ₹1,000–₹5,000\n• No licence: ₹5,000\n• No insurance: ₹2,000\n• Mobile use: ₹5,000\n• Overloading: ₹20,000+',
    'e-challan': '📱 e-Challan in Tamil Nadu:\n• Check & pay at echallan.parivahan.gov.in\n• Or via mParivahan app\n• Enter vehicle number or DL number to check dues\n• Pay via UPI, net banking, or debit card\n• Cleared challans are updated within 24–48 hrs',
    'traffic police': '👮 Tamil Nadu Traffic Police:\n• Emergency helpline: 103 (traffic)\n• Chennai Traffic Police: 044-28447777\n• Never bribe traffic police — it is a criminal offence\n• You have the right to ask for official ID\n• All challans must be given in writing (Form 49)',

    // ── Night Driving ───────────────────────────────────────────────────────
    'night driving': '🌙 Night driving safety tips for TN:\n• Use headlights (not high beam in traffic)\n• Be extra cautious on unlit rural roads\n• Reduce speed — reaction time is longer at night\n• Watch for animals crossing roads, especially on highways\n• Carry emergency reflective triangles/cones\n• Avoid night driving if fatigued',

    // ── School Zones ────────────────────────────────────────────────────────
    'school zone': '🏫 School zone rules in Tamil Nadu:\n• Speed limit: 25 km/h near schools during school hours\n• No honking zones\n• No parking within 50 metres of school gate\n• Extra caution for children crossing roads\n• Fine for violation: ₹1,000–₹2,000',
    'hospital zone': '🏥 Hospital zone rules in TN:\n• No honking near hospitals\n• Ambulance must be given way immediately — fine for blocking: ₹10,000\n• Reduced speed in hospital areas\n• Emergency vehicles have absolute right of way',

    // ── Ambulance / Emergency Vehicles ─────────────────────────────────────
    'ambulance': '🚑 Ambulance right-of-way rules in TN:\n• All vehicles MUST give way to ambulances and emergency vehicles\n• Fine for not giving way: ₹10,000\n• Move to the left and stop when you hear a siren\n• Never follow behind an ambulance to bypass traffic — it is illegal\n• Honoring ambulance passage can save a life!',
    'emergency vehicle': '🚒 Emergency vehicles (ambulance, fire engine, police) have absolute right of way in Tamil Nadu. Fine for blocking: ₹10,000. Always pull to the left and stop when you hear a siren.',

    // ── Tinted Glass ────────────────────────────────────────────────────────
    'tinted glass': '🪟 Tinted glass rules in Tamil Nadu:\n• Front windshield: min 70% light transmission (VLT)\n• Front side windows: min 70% VLT\n• Rear windshield and rear side windows: min 50% VLT\n• Illegal black films are banned\n• Fine: ₹100–₹500 + removal of film\n• VIP/security vehicles need special permits',
    'window tint': '🪟 Window tinting limits in TN: front windshield and side windows must allow ≥70% light. Rear windows must allow ≥50%. Illegal dark films are banned. Fine: ₹100–₹500.',

    // ── Number Plate ────────────────────────────────────────────────────────
    'number plate': '🔢 Number plate rules in Tamil Nadu:\n• Must use High Security Registration Plates (HSRP)\n• Standard fonts and size — no fancy/styled fonts\n• White plate (black text) for private vehicles\n• Yellow plate (black text) for commercial vehicles\n• Green plate for electric vehicles\n• Fancy/obscured number plates: fine ₹500–₹5,000',
    'fancy number plate': '🚫 Fancy, stylised, or obscured number plates are illegal in Tamil Nadu. Fine: ₹500–₹5,000. All vehicles must use HSRP (High Security Registration Plate) with standard fonts.',

    // ── Electric Vehicles ───────────────────────────────────────────────────
    'electric vehicle': '⚡ Electric vehicle (EV) rules in Tamil Nadu:\n• Green number plates mandatory\n• Follow same traffic rules as regular vehicles\n• No emission (PUC) certificate required\n• TN EV Policy 2023 promotes EVs with subsidies\n• Charging infrastructure expanding across TN\n• EV two-wheelers under 250W, 25 km/h: no licence required',
    'ev': '⚡ Electric vehicles in TN get green number plates and are exempt from PUC requirements. Follow all standard traffic rules. Gearless EVs under 25 km/h and 250W power don\'t require a driving licence.',

    // ── Road Safety Tips ────────────────────────────────────────────────────
    'road safety': '🛡️ Top road safety tips for Tamil Nadu:\n• Always wear helmet/seat belt\n• Never drink and drive\n• Follow speed limits\n• No mobile phone while driving\n• Keep safe following distance\n• Use indicators while turning/changing lanes\n• Give way to emergency vehicles\n• Stay alert — avoid fatigue\n• Follow lane discipline\n• Carry valid documents always',
    'safety tips': '🛡️ Road safety tips:\n1. Wear helmet/seat belt always\n2. Obey speed limits\n3. No drunk/drugged driving\n4. No phone while driving\n5. Use indicators\n6. Keep safe distance\n7. Give way to emergency vehicles\n8. Rest every 2 hours on long trips\n9. Follow lane discipline\n10. Check tyre pressure and lights before long trips',

    // ── Indicators / Signals ────────────────────────────────────────────────
    'indicator': '🔄 Indicator/turn signal rules in TN:\n• Must use indicator when turning, overtaking, or changing lanes\n• Use at least 30 metres before the turn in city\n• On highways: use at least 100 metres before turn\n• Fine for not using indicators: ₹500\n\nIndicators save lives — always use them!',
    'turn signal': '🔄 Use your turn signals/indicators every time you turn or change lanes. Fine for not signalling: ₹500 in Tamil Nadu. Give enough warning to vehicles behind you.',

    // ── Reverse Horn ────────────────────────────────────────────────────────
    'reverse': '📢 Vehicles reversing on public roads must:\n• Use reverse horn/beeper\n• Check all mirrors and blind spots\n• Take assistance (spotter) for large vehicles\n• Never reverse on a highway or expressway\n• Fine for reckless reversing causing accident: ₹1,000+',

    // ── Highway Safety ──────────────────────────────────────────────────────
    'highway': '🛣️ Highway safety rules in TN:\n• Speed limit: 100 km/h for cars (NHs)\n• No stopping on the highway (except emergencies)\n• Use service roads for access to towns\n• Maintain safe following distance (at least 3 seconds)\n• No U-turns on highways — use designated U-turn points\n• Use hazard lights if your vehicle breaks down',
    'breakdown': '⚠️ Vehicle breakdown on road/highway:\n• Move vehicle to the left shoulder immediately\n• Switch on hazard lights\n• Place reflective triangles behind the vehicle\n• Call TN Road Safety Helpline: 1033\n• Call National Highway helpline: 1033\n• Stay away from traffic while waiting for help',

    // ── Rash Driving ────────────────────────────────────────────────────────
    'rash driving': '⚠️ Rash/dangerous driving in Tamil Nadu:\n• Fine: ₹1,000–₹5,000\n• Imprisonment up to 6 months\n• Licence suspension\n• If it causes death: imprisonment up to 2 years under IPC Sec 304A\n\nDriving rashly puts everyone\'s life at risk!',
    'dangerous driving': '⚠️ Dangerous driving fine in TN: ₹1,000–₹5,000 + possible imprisonment. Causing death by rash driving: up to 2 years imprisonment under IPC Sec 304A + fine.',

    // ── Stunt Driving ───────────────────────────────────────────────────────
    'stunt': '🏎️ Stunts or racing on public roads in Tamil Nadu:\n• Strictly prohibited\n• Fine: up to ₹5,000\n• Imprisonment possible\n• Vehicle seized\n• Licence cancelled\n\nStunts belong on tracks, not public roads!',
    'racing': '🏎️ Street racing on public roads is illegal in Tamil Nadu. Fine: ₹5,000 + imprisonment + vehicle seizure + licence cancellation. Report illegal racing to police: 100.',

    // ── Tyre Rules ──────────────────────────────────────────────────────────
    'tyre': '🛞 Tyre rules and safety in TN:\n• Bald/worn tyres are illegal — fine: ₹1,000\n• Tyre tread depth must be at least 1.6mm\n• Check tyre pressure regularly (every 2 weeks)\n• Under/over-inflated tyres increase accident risk\n• Carry a spare tyre at all times on long trips',
    'bald tyre': '🛞 Driving on bald (worn-out) tyres is illegal in Tamil Nadu. Fine: ₹1,000. Minimum tread depth required: 1.6mm. Bald tyres significantly increase blowout and skidding risks.',

    // ── Seatbelt & Airbag ───────────────────────────────────────────────────
    'airbag': '💨 Airbags in vehicles:\n• Supplement to seat belts, NOT a replacement\n• All new cars in India must have minimum 6 airbags (from Oct 2023)\n• Airbags only deploy effectively when seat belt is worn\n• Never disable or tamper with airbags\n• Always wear seat belt — it works WITH the airbag to protect you',

    // ── Motor Vehicles Act ──────────────────────────────────────────────────
    'motor vehicles act': '📜 Motor Vehicles (Amendment) Act 2019:\n• Significantly increased fines for traffic violations\n• Introduced juvenile offence provisions\n• Mandated insurance for all vehicles\n• Electronic enforcement (speed cameras, e-challan)\n• Good Samaritan protection included\n• Applicable across all of India including Tamil Nadu',
    'mv act': '📜 The Motor Vehicles (Amendment) Act 2019 governs traffic rules across India including Tamil Nadu. It increased fines, introduced juvenile offences, and mandated electronic enforcement. All fines quoted are under this Act.',

    // ── Bye / Thanks ────────────────────────────────────────────────────────
    'bye': 'Goodbye! 👋 Drive safe and follow traffic rules. Vanakkam! 🙏',
    'goodbye': 'Take care and drive safe! 👋 Vanakkam! 🙏',
    'thank you': 'You\'re welcome! 😊 Stay safe on the roads. Remember — safe driving saves lives!',
    'thanks': 'Happy to help! 😊 Drive safely and follow TN traffic rules. Vanakkam! 🙏',
    'ok': 'Glad I could help! 😊 Stay safe on the roads!',
    'okay': 'Great! 😊 Any other road safety questions?',
    'help': 'I can help you with:\n• 🚗 Speed limits & traffic rules\n• 🪖 Helmet & seat belt laws\n• 🍺 Drunk driving penalties\n• 📱 Mobile phone rules\n• 📄 Required documents\n• 🅿️ Parking rules\n• 🚦 Traffic signals\n• 🆘 Emergency contacts\n• 💰 Traffic fines\n• 🏍️ Two-wheeler rules\n• 🚛 Heavy vehicle rules\n• ⚡ Electric vehicle info\n\nJust type your question!',
  };

  // ─── Default responses when nothing matches ───────────────────────────────
  static const List<String> _defaults = [
    'I\'m not sure about that specific query. Try asking about:\n• Speed limits\n• Helmet or seat belt rules\n• Drunk driving penalties\n• Required documents\n• Parking rules\n• Emergency contacts (type "emergency")\n• Type "help" to see all topics!',
    'Hmm, I didn\'t get that. I can help with TN traffic rules, fines, speed limits, helmet laws, documents, and more. Try rephrasing your question or type "help"!',
    'I specialise in Tamil Nadu traffic rules. Ask me about fines, speed limits, documents, parking, or emergency contacts! Type "help" for a full list of topics.',
    'Not sure I understood that. Type "help" to see everything I can assist you with — from helmet rules to EV laws! 😊',
  ];

  int _defaultIndex = 0;

  // ─── Main logic ───────────────────────────────────────────────────────────
  Future<String> sendMessage(String userMessage) async {
    // Simulate slight delay for natural feel
    await Future.delayed(const Duration(milliseconds: 500));

    final input = userMessage.toLowerCase().trim();
    _history.add({'role': 'user', 'content': userMessage});

    String reply = _findResponse(input);
    _history.add({'role': 'assistant', 'content': reply});
    return reply;
  }

  String _findResponse(String input) {
    // Direct match first
    if (_responses.containsKey(input)) {
      return _responses[input]!;
    }

    // Keyword match — check if input contains any key
    for (final entry in _responses.entries) {
      if (input.contains(entry.key)) {
        return entry.value;
      }
    }

    // Partial word match
    final inputWords = input.split(' ');
    for (final word in inputWords) {
      if (word.length > 3) {
        for (final entry in _responses.entries) {
          if (entry.key.contains(word) || word.contains(entry.key)) {
            return entry.value;
          }
        }
      }
    }

    // Default fallback
    final reply = _defaults[_defaultIndex % _defaults.length];
    _defaultIndex++;
    return reply;
  }

  void clearHistory() {
    _history.clear();
    _defaultIndex = 0;
  }
}