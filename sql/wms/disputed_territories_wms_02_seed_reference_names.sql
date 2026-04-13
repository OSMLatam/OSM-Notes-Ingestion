-- Seed canonical names for disputed_territories_wms (geom NULL until refresh).
-- Keep rows aligned with data/disputed_territories_wms_names.json (same kind + name).
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-05

INSERT INTO disputed_territories_wms (kind, name, description, reference_url)
VALUES
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Ems-Dollard mouth',
    'Overlapping admin claims around Ems estuary (NL/DE).',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Mont Blanc summit',
    'Competing FR/IT summit boundary representations.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Oyster Pond',
    'Saint-Martin / Sint Maarten overlapping claims.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Carlingford Lough and Lough Foyle',
    'IE/UK maritime boundary context.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Lake Constance',
    'DE/AT/CH boundary through lake.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Croatia-Serbia border (Danube sector)',
    'River-shift and island claims along Danube.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Island of Vukovar',
    'Competing HR/RS boundary representations.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Gulf of Piran',
    'SI/HR maritime delimitation disputes.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Machias Seal Island',
    'CA/US competing sovereignty.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Dixon Entrance',
    'CA/US competing maritime representations.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'country_maritime_intersection'::disputed_territory_kind,
    'Olivenza region',
    'PT historical claim vs ES administration (country polygon intersection).',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'disputed_tagged'::disputed_territory_kind,
    'Western Sahara',
    'Sahrawi / Morocco competing claims.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'disputed_tagged'::disputed_territory_kind,
    'Kashmir region',
    'IN/PK/CN context.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'disputed_tagged'::disputed_territory_kind,
    'South Ossetia',
    'GE/RU context.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'disputed_tagged'::disputed_territory_kind,
    'Abkhazia',
    'GE/RU context.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'disputed_tagged'::disputed_territory_kind,
    'Mar de Grau (Peru maritime claim)',
    'Peru constitutional maritime claim context.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  ),
  (
    'unclaimed_territory'::disputed_territory_kind,
    'Bir Tawil',
    'Land between EG/SD claims often mapped as claimed by neither.',
    'https://wiki.openstreetmap.org/wiki/Disputed_territories'
  )
ON CONFLICT (kind, name) DO NOTHING;
