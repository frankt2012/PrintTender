/// The starter library of maintenance jobs shipped with the app.
///
/// The names, groupings and suggested intervals mirror the task list curated in
/// the author's earlier web app (MIT licensed) so the two agree on what "the
/// usual suspects" are. A handful of entries carry BOTH an hour interval and a
/// calendar interval where hours are a genuinely better trigger (nozzles, fans,
/// lead screws, PTFE tube, linear rods); whichever limit is reached first wins.
///
/// Everything here is editable and deletable once seeded.
library;

class LibraryEntry {
  const LibraryEntry({
    required this.name,
    required this.category,
    required this.sortOrder,
    this.description,
    this.intervalHours,
    this.intervalDays,
    this.intervalMonths,
    this.isDefault = false,
  });

  final String name;
  final String category;
  final int sortOrder;
  final String? description;
  final double? intervalHours;
  final int? intervalDays;
  final int? intervalMonths;

  /// Part of the "eight essentials" a new printer can be seeded with.
  final bool isDefault;

  Map<String, Object?> toMap() => <String, Object?>{
        'name': name,
        'description': description,
        'interval_hours': intervalHours,
        'interval_days': intervalDays,
        'interval_months': intervalMonths,
        'category': category,
        'sort_order': sortOrder,
        'is_default': isDefault ? 1 : 0,
      };
}

/// The eight jobs a brand-new printer is offered, taken verbatim from the
/// reference app's `COMMON` list. Intervals count from the day the printer is
/// added, so a fresh machine does not open with a board full of red.
const List<LibraryEntry> defaultTaskLibrary = <LibraryEntry>[
  LibraryEntry(
    name: 'Carbon rods',
    category: 'Essentials',
    sortOrder: 1,
    isDefault: true,
    intervalMonths: 6,
    description:
        'Clean and re-lubricate. Never put grease on carbon rods — it attracts grit.',
  ),
  LibraryEntry(
    name: 'Linear rods',
    category: 'Essentials',
    sortOrder: 2,
    isDefault: true,
    intervalHours: 250,
    intervalMonths: 3,
    description: 'Wipe off the old grease and apply a thin, even layer.',
  ),
  LibraryEntry(
    name: 'Lead screws',
    category: 'Essentials',
    sortOrder: 3,
    isDefault: true,
    intervalHours: 300,
    intervalMonths: 3,
    description: 'Apply PTFE grease along the Z screws.',
  ),
  LibraryEntry(
    name: 'Belts',
    category: 'Essentials',
    sortOrder: 4,
    isDefault: true,
    intervalMonths: 6,
    description: 'Pluck the belts — a low bass note means good tension.',
  ),
  LibraryEntry(
    name: 'Cutter',
    category: 'Essentials',
    sortOrder: 5,
    isDefault: true,
    intervalMonths: 3,
    description: 'Inspect the filament cutter blade and clear out debris.',
  ),
  LibraryEntry(
    name: 'Extruder',
    category: 'Essentials',
    sortOrder: 6,
    isDefault: true,
    intervalMonths: 6,
    description: 'Check gear wear and clean out accumulated filament dust.',
  ),
  LibraryEntry(
    name: 'Fans',
    category: 'Essentials',
    sortOrder: 7,
    isDefault: true,
    intervalHours: 100,
    intervalMonths: 6,
    description: 'Blow out dust and confirm every fan spins freely.',
  ),
  LibraryEntry(
    name: 'Nozzle',
    category: 'Essentials',
    sortOrder: 8,
    isDefault: true,
    intervalHours: 200,
    intervalMonths: 3,
    description:
        'Cold-pull or swap the nozzle when extrusion becomes inconsistent.',
  ),

  // -- Motion and frame -----------------------------------------------------
  LibraryEntry(
    name: 'Pulleys and idlers',
    category: 'Motion and frame',
    sortOrder: 10,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Stepper motors',
    category: 'Motion and frame',
    sortOrder: 11,
    intervalMonths: 12,
  ),
  LibraryEntry(
    name: 'Linear bearings',
    category: 'Motion and frame',
    sortOrder: 12,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Frame screws',
    category: 'Motion and frame',
    sortOrder: 13,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Z axis and gantry alignment',
    category: 'Motion and frame',
    sortOrder: 14,
    intervalMonths: 6,
  ),

  // -- Extruder and hotend --------------------------------------------------
  LibraryEntry(
    name: 'Hotend',
    category: 'Extruder and hotend',
    sortOrder: 20,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'PTFE tube',
    category: 'Extruder and hotend',
    sortOrder: 21,
    intervalHours: 500,
    intervalMonths: 12,
    description: 'Inspect the tube for wear where it enters the coupler.',
  ),
  LibraryEntry(
    name: 'Thermistor and heater cartridge',
    category: 'Extruder and hotend',
    sortOrder: 22,
    intervalMonths: 12,
  ),
  LibraryEntry(
    name: 'Heater block and nozzle torque',
    category: 'Extruder and hotend',
    sortOrder: 23,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'Hotend silicone sock',
    category: 'Extruder and hotend',
    sortOrder: 24,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Nozzle wiper and purge area',
    category: 'Extruder and hotend',
    sortOrder: 25,
    intervalMonths: 3,
  ),

  // -- Bed and build plate --------------------------------------------------
  LibraryEntry(
    name: 'Build plate',
    category: 'Bed and build plate',
    sortOrder: 30,
    intervalMonths: 1,
    description:
        'Wash with warm water and dish soap, then dry. Avoid touching the surface.',
  ),
  LibraryEntry(
    name: 'Replace build plate',
    category: 'Bed and build plate',
    sortOrder: 31,
    intervalMonths: 12,
  ),
  LibraryEntry(
    name: 'Bed leveling and probe',
    category: 'Bed and build plate',
    sortOrder: 32,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'Bed springs and leveling knobs',
    category: 'Bed and build plate',
    sortOrder: 33,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Bed heater and wiring',
    category: 'Bed and build plate',
    sortOrder: 34,
    intervalMonths: 12,
  ),
  LibraryEntry(
    name: 'Z offset check',
    category: 'Bed and build plate',
    sortOrder: 35,
    intervalMonths: 3,
  ),

  // -- Filament handling ----------------------------------------------------
  LibraryEntry(
    name: 'Filament sensor',
    category: 'Filament handling',
    sortOrder: 40,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Filament path and PTFE tubing',
    category: 'Filament handling',
    sortOrder: 41,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Spool holders and bearings',
    category: 'Filament handling',
    sortOrder: 42,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Desiccant and dry box',
    category: 'Filament handling',
    sortOrder: 43,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'Filament dryer',
    category: 'Filament handling',
    sortOrder: 44,
    intervalMonths: 6,
  ),

  // -- Electronics and software --------------------------------------------
  LibraryEntry(
    name: 'Wiring and connectors',
    category: 'Electronics and software',
    sortOrder: 50,
    intervalMonths: 6,
    description: 'Look for chafing, loose plugs, or heat damage.',
  ),
  LibraryEntry(
    name: 'Power supply and electronics',
    category: 'Electronics and software',
    sortOrder: 51,
    intervalMonths: 12,
  ),
  LibraryEntry(
    name: 'Mainboard fans and heatsinks',
    category: 'Electronics and software',
    sortOrder: 52,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Firmware updates',
    category: 'Electronics and software',
    sortOrder: 53,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Config backup',
    category: 'Electronics and software',
    sortOrder: 54,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Calibration print',
    category: 'Electronics and software',
    sortOrder: 55,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Camera lens and lights',
    category: 'Electronics and software',
    sortOrder: 56,
    intervalMonths: 6,
  ),

  // -- Enclosure and safety -------------------------------------------------
  LibraryEntry(
    name: 'Enclosure filter',
    category: 'Enclosure and safety',
    sortOrder: 60,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Chamber heater and fan',
    category: 'Enclosure and safety',
    sortOrder: 61,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Enclosure panels and door seals',
    category: 'Enclosure and safety',
    sortOrder: 62,
    intervalMonths: 12,
  ),
  LibraryEntry(
    name: 'Smoke detector and fire safety',
    category: 'Enclosure and safety',
    sortOrder: 63,
    intervalMonths: 6,
  ),

  // -- Multi-material systems ----------------------------------------------
  LibraryEntry(
    name: 'CFS feed gears and rollers',
    category: 'Multi-material systems',
    sortOrder: 70,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'CFS filament path and PTFE tubes',
    category: 'Multi-material systems',
    sortOrder: 71,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'CFS desiccant',
    category: 'Multi-material systems',
    sortOrder: 72,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'AMS Lite feed rollers',
    category: 'Multi-material systems',
    sortOrder: 73,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'AMS Lite filament path and PTFE tubes',
    category: 'Multi-material systems',
    sortOrder: 74,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'AMS Lite spool holders',
    category: 'Multi-material systems',
    sortOrder: 75,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'AMS feed rollers and gears',
    category: 'Multi-material systems',
    sortOrder: 76,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'AMS filament path and PTFE tubes',
    category: 'Multi-material systems',
    sortOrder: 77,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'AMS desiccant',
    category: 'Multi-material systems',
    sortOrder: 78,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'MMU selector and pulleys',
    category: 'Multi-material systems',
    sortOrder: 79,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'MMU PTFE tubes',
    category: 'Multi-material systems',
    sortOrder: 80,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Tool changer docking and couplings',
    category: 'Multi-material systems',
    sortOrder: 81,
    intervalMonths: 6,
  ),

  // -- Resin printers -------------------------------------------------------
  LibraryEntry(
    name: 'Resin vat and FEP film',
    category: 'Resin printers',
    sortOrder: 90,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'LCD screen inspection',
    category: 'Resin printers',
    sortOrder: 91,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Resin build plate leveling',
    category: 'Resin printers',
    sortOrder: 92,
    intervalMonths: 6,
  ),
  LibraryEntry(
    name: 'Air filter and carbon',
    category: 'Resin printers',
    sortOrder: 93,
    intervalMonths: 3,
  ),
  LibraryEntry(
    name: 'Wash and cure station',
    category: 'Resin printers',
    sortOrder: 94,
    intervalMonths: 3,
  ),
];

/// The names the very first release seeded, and what they became once the full
/// library arrived. Used by the v1→v2 migration to rename in place so any
/// schedules pointing at them keep working.
const Map<String, String> legacySeedNames = <String, String>{
  'Clean build plate': 'Build plate',
  'Clean or replace nozzle': 'Nozzle',
  'Lubricate Z lead screws': 'Lead screws',
  'Check belt tension': 'Belts',
  'Clean hotend cooling fan': 'Fans',
  'Check or replace PTFE tube': 'PTFE tube',
  'Grease linear rails': 'Linear rods',
  'Inspect wiring and connectors': 'Wiring and connectors',
};

/// Suggested nozzle materials, offered as quick picks in the printer form.
const List<String> nozzleTypes = <String>[
  'Brass',
  'Hardened steel',
  'Stainless steel',
  'Tungsten carbide',
  'Ruby-tipped',
  'Plated copper',
];

/// Suggested build-plate surfaces, offered as quick picks in the printer form.
const List<String> buildPlateTypes = <String>[
  'Smooth PEI',
  'Textured PEI',
  'Double-sided PEI',
  'Glass',
  'Garolite (G10)',
  'Spring steel',
  'Magnetic flex plate',
  'BuildTak',
];
