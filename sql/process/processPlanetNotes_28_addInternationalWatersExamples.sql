-- Calculates and inserts international waters areas by computing the
-- difference between the world ocean and all country areas (terrestrial
-- and maritime). This creates precise polygons that exclude any land or
-- claimed maritime zones.
--
-- Strategy:
-- 1. Partition the globe into non-overlapping ocean region boxes (full
--    coverage, no gaps between regions).
-- 2. For each region only: ST_UnaryUnion(ST_Collect(ST_Intersection(
--    country, region))) — union of countries clipped to that region, not a
--    single global union (much faster with hundreds of maritime polygons).
-- 3. International waters in the region = region box minus that union
--    (same logical result as world minus all countries, without holes at
--    region seams because each point lies in exactly one box).
-- 4. Filter small artifacts, name seas, insert.
--
-- Usage:
--   psql -d notes -f sql/process/processPlanetNotes_28_addInternationalWatersExamples.sql
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-03-23
--
-- Per-region union (no global ST_UnaryUnion on all countries) keeps
-- correctness (no gaps between coast and sea) while reducing CPU time.
-- Regions: Pacific (west/central/east), Atlantic, Indian, Arctic,
--          Southern

-- Ensure the table exists (for backward compatibility)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_name = 'international_waters'
  ) THEN
    RAISE EXCEPTION 'Table international_waters does not exist. '
      'Please run processPlanetNotes_27_createInternationalWatersTable.sql '
      'first.';
  END IF;
END $$;

-- ============================================================================
-- SPECIAL POINTS
-- ============================================================================

-- Null Island (0, 0) - Gulf of Guinea
-- Commonly used as placeholder for missing coordinates
INSERT INTO international_waters (
  name, description, point_coords, is_special_point
)
VALUES (
  'Null Island',
  'Point 0,0 in Gulf of Guinea - commonly used as placeholder for '
  'missing coordinates',
  ST_SetSRID(ST_MakePoint(0, 0), 4326),
  TRUE
) ON CONFLICT DO NOTHING;

-- ============================================================================
-- CALCULATE INTERNATIONAL WATERS (Precise polygons)
-- ============================================================================

-- Delete existing polygon areas (keep special points)
-- CRITICAL: Delete ALL polygon areas to prevent duplicates
DELETE FROM international_waters
WHERE is_special_point = FALSE;

-- International waters: per ocean region, subtract (country ∩ region)
-- union from the region box. No global country union.
WITH
  valid_countries AS (
    SELECT
      ST_MakeValid(
        CASE
          WHEN ST_SRID(geom) = 0 OR ST_SRID(geom) IS NULL THEN
            ST_SetSRID(geom, 4326)
          ELSE
            geom
        END
      ) AS geom
    FROM
      countries
    WHERE
      ST_GeometryType(geom) IN ('ST_Polygon', 'ST_MultiPolygon')
      AND geom IS NOT NULL
      AND NOT ST_IsEmpty(geom)
  ),
  ocean_regions AS (
    SELECT
      'pacific_west' AS region,
      ST_SetSRID(
        ST_MakeEnvelope(-180, -60, -100, 60, 4326),
        4326
      ) AS geom
    UNION ALL
    SELECT
      'pacific_central' AS region,
      ST_SetSRID(
        ST_MakeEnvelope(-100, -60, -70, 60, 4326),
        4326
      ) AS geom
    UNION ALL
    SELECT
      'atlantic' AS region,
      ST_SetSRID(
        ST_MakeEnvelope(-70, -60, 20, 60, 4326),
        4326
      ) AS geom
    UNION ALL
    SELECT
      'indian' AS region,
      ST_SetSRID(
        ST_MakeEnvelope(20, -60, 110, 60, 4326),
        4326
      ) AS geom
    UNION ALL
    -- CRITICAL FIX: pacific_east cannot cross 180°/-180° meridian.
    -- ST_MakeEnvelope(110, -60, -180, 60) fails because xmin > xmax.
    -- Solution: Only cover 110° to 180° (Australia, Japan, SE Asia, Pacific
    -- Islands). The area from -180° to -100° is already covered by
    -- pacific_west, so no duplication needed.
    SELECT
      'pacific_east' AS region,
      ST_SetSRID(
        ST_MakeEnvelope(110, -60, 180, 60, 4326),
        4326
      ) AS geom
    UNION ALL
    SELECT
      'arctic' AS region,
      ST_SetSRID(
        ST_MakeEnvelope(-180, 60, 180, 90, 4326),
        4326
      ) AS geom
    UNION ALL
    SELECT
      'southern' AS region,
      ST_SetSRID(
        ST_MakeEnvelope(-180, -90, 180, -60, 4326),
        4326
      ) AS geom
  ),
  countries_union_per_region AS (
    SELECT
      or_reg.region,
      or_reg.geom AS region_geom,
      (
        SELECT
          ST_MakeValid(
            ST_Simplify(
              ST_MakeValid(
                ST_UnaryUnion(
                  ST_Collect(
                    ST_MakeValid(
                      ST_Intersection(vc.geom, or_reg.geom)
                    )
                  )
                )
              ),
              0.005
            )
          )
        FROM
          valid_countries vc
        WHERE
          ST_Intersects(vc.geom, or_reg.geom)
      ) AS countries_union_in_region
    FROM
      ocean_regions or_reg
  ),
  international_waters_by_region AS (
    SELECT
      cupr.region,
      CASE
        WHEN cupr.countries_union_in_region IS NULL
          OR ST_IsEmpty(cupr.countries_union_in_region)
        THEN
          cupr.region_geom
        ELSE
          ST_MakeValid(
            ST_Difference(
              cupr.region_geom,
              cupr.countries_union_in_region
            )
          )
      END AS geom
    FROM
      countries_union_per_region cupr
  ),
  -- Step 5: Extract individual polygons from each region separately
  -- Process each region independently to avoid UNION issues with large
  -- geometries. Do NOT union regions together - process them separately
  -- to avoid precision issues and area duplication
  international_waters_by_region_dumped AS (
    SELECT
      iwr.region,
      (ST_Dump(iwr.geom)).geom AS polygon_geom
    FROM
      international_waters_by_region iwr
    WHERE
      iwr.geom IS NOT NULL
      AND NOT ST_IsEmpty(iwr.geom)
  ),
  international_waters_filtered AS (
    SELECT
      region,
      polygon_geom,
      ST_Area(polygon_geom::geography) / (111000.0 * 111000.0)
        AS area_sq_degrees
    FROM
      international_waters_by_region_dumped
    WHERE
      ST_GeometryType(polygon_geom) IN (
        'ST_Polygon',
        'ST_MultiPolygon'
      )
      -- Very small minimum size (0.0001 square degrees) to capture almost
      -- all areas. This ensures we don't lose important international
      -- waters areas. Only filters out extremely tiny precision artifacts
      -- (less than ~123 km²). Reduced from 0.001 to capture more area.
      AND ST_Area(polygon_geom::geography)
        > 111000.0 * 111000.0 * 0.0001  -- Min 0.0001 sq degree (~123 km²)
  ),
  -- Step 6: Identify specific seas and generate appropriate names
  -- Detect known seas and assign specific names instead of generic
  -- "International Waters - Atlantic X"
  seas_identification_with_numbers AS (
    SELECT
      region,
      polygon_geom,
      area_sq_degrees,
      ROW_NUMBER() OVER (
        PARTITION BY region
        ORDER BY area_sq_degrees DESC
      ) AS region_number
    FROM
      international_waters_filtered
  ),
  seas_identification AS (
    SELECT
      sin.region,
      sin.polygon_geom,
      sin.area_sq_degrees,
      CASE
        -- Baltic Sea: 10-30°E, 54-66°N
        -- Identify if polygon intersects significantly with Baltic Sea
        -- (centroid within OR >30% of polygon area within sea envelope)
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(10, 54, 30, 66, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(10, 54, 30, 66, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(10, 54, 30, 66, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'Baltic Sea - International Waters'
        -- Black Sea: 27-42°E, 41-47°N
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(27, 41, 42, 47, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(27, 41, 42, 47, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(27, 41, 42, 47, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'Black Sea - International Waters'
        -- Caspian Sea: 47-54°E, 37-47°N
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(47, 37, 54, 47, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(47, 37, 54, 47, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(47, 37, 54, 47, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'Caspian Sea - International Waters'
        -- Aegean Sea: 23-30°E, 36-41°N
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(23, 36, 30, 41, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(23, 36, 30, 41, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(23, 36, 30, 41, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'Aegean Sea - International Waters'
        -- Mediterranean Sea (central): -6-36°E, 30-46°N
        -- Exclude Aegean Sea which is handled separately
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(-6, 30, 36, 46, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(-6, 30, 36, 46, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(-6, 30, 36, 46, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
          AND NOT ST_Intersects(
            sin.polygon_geom,
            ST_MakeEnvelope(23, 36, 30, 41, 4326)
          )
        THEN
          'Mediterranean Sea - International Waters'
        -- Persian Gulf: 48-56°E, 24-30°N
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(48, 24, 56, 30, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(48, 24, 56, 30, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(48, 24, 56, 30, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'Persian Gulf - International Waters'
        -- Red Sea: 32-44°E, 12-30°N
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(32, 12, 44, 30, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(32, 12, 44, 30, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(32, 12, 44, 30, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'Red Sea - International Waters'
        -- Default: Generic name based on region
        ELSE
          'International Waters - '
            || REPLACE(INITCAP(sin.region), '_', ' ') || ' '
            || sin.region_number
      END AS area_name,
      CASE
        -- Specific sea descriptions
        -- Use same logic as area_name for consistency
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(10, 54, 30, 66, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(10, 54, 30, 66, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(10, 54, 30, 66, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'International waters in Baltic Sea. Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(27, 41, 42, 47, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(27, 41, 42, 47, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(27, 41, 42, 47, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'International waters in Black Sea. Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(47, 37, 54, 47, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(47, 37, 54, 47, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(47, 37, 54, 47, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'International waters in Caspian Sea. Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(23, 36, 30, 41, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(23, 36, 30, 41, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(23, 36, 30, 41, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'International waters in Aegean Sea. Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(-6, 30, 36, 46, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(-6, 30, 36, 46, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(-6, 30, 36, 46, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
          AND NOT ST_Intersects(
            sin.polygon_geom,
            ST_MakeEnvelope(23, 36, 30, 41, 4326)
          )
        THEN
          'International waters in Mediterranean Sea. Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(48, 24, 56, 30, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(48, 24, 56, 30, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(48, 24, 56, 30, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'International waters in Persian Gulf. Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
        WHEN ST_Intersects(
          sin.polygon_geom,
          ST_MakeEnvelope(32, 12, 44, 30, 4326)
        )
          AND (
            ST_Within(
              ST_Centroid(sin.polygon_geom),
              ST_MakeEnvelope(32, 12, 44, 30, 4326)
            )
            OR ST_Area(
              ST_Intersection(
                sin.polygon_geom,
                ST_MakeEnvelope(32, 12, 44, 30, 4326)
              )::geography
            ) / NULLIF(
              ST_Area(sin.polygon_geom::geography),
              0
            ) > 0.3
          )
        THEN
          'International waters in Red Sea. Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
        -- Default: Generic description
        ELSE
          'International waters in '
            || REPLACE(INITCAP(sin.region), '_', ' ')
            || ' Ocean. Calculated as difference between ocean region and '
            || 'all country areas (terrestrial and maritime). Area: '
            || ROUND(sin.area_sq_degrees::numeric, 2)
            || ' square degrees.'
      END AS area_description
    FROM
      seas_identification_with_numbers sin
  ),
  -- Step 7: Final naming (kept for consistency, but already done above)
  international_waters_named AS (
    SELECT
      region,
      polygon_geom,
      area_sq_degrees,
      area_name,
      area_description
    FROM
      seas_identification
  )
-- Step 7: Insert into international_waters table
-- Insert each region separately to avoid UNION issues
INSERT INTO international_waters (
  name, description, geom, is_special_point
)
SELECT
  area_name,
  area_description,
  polygon_geom,
  FALSE
FROM
  international_waters_named
ORDER BY
  region,
  area_sq_degrees DESC;

-- Remove duplicate geometries using efficient centroid + area approach
-- This is much faster than ST_Equals for large geometries
-- Round coordinates and area to detect near-duplicates efficiently
WITH duplicates AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY
        ROUND(ST_X(ST_Centroid(geom))::numeric, 3),
        ROUND(ST_Y(ST_Centroid(geom))::numeric, 3),
        ROUND(ST_Area(geom::geography)::numeric, -2)
      ORDER BY id
    ) AS rn
  FROM
    international_waters
  WHERE
    is_special_point = FALSE
    AND geom IS NOT NULL
)
DELETE FROM international_waters
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);

-- ============================================================================
-- DIAGNOSTICS
-- ============================================================================

-- Lightweight diagnostics (no second global ST_UnaryUnion on all countries)
DO $$
DECLARE
  v_country_count INTEGER;
  v_maritime_count INTEGER;
  v_world_area NUMERIC;
  v_international_area NUMERIC;
BEGIN
  SELECT COUNT(*) INTO v_country_count
  FROM countries
  WHERE geom IS NOT NULL;
  SELECT COUNT(*) INTO v_maritime_count
  FROM countries
  WHERE is_maritime = TRUE AND geom IS NOT NULL;

  v_world_area := 360.0 * 180.0;

  SELECT
    COALESCE(
      SUM(ST_Area(geom::geography) / (111000.0 * 111000.0)),
      0
    ) INTO v_international_area
  FROM
    international_waters
  WHERE
    geom IS NOT NULL
    AND is_special_point = FALSE;

  RAISE NOTICE '=== International Waters Calculation Diagnostics ===';
  RAISE NOTICE 'Total countries (terrestrial + maritime): %',
    v_country_count;
  RAISE NOTICE 'Maritime zones: %', v_maritime_count;
  RAISE NOTICE 'World bounding box area: % square degrees',
    ROUND(v_world_area, 2);
  RAISE NOTICE 'Calculated international waters area: % square degrees',
    ROUND(v_international_area, 2);
  RAISE NOTICE 'Method: per-region union (no global country union); '
    'union area skipped here to avoid extra cost';
  RAISE NOTICE '';
END $$;

-- ============================================================================
-- SUMMARY
-- ============================================================================

-- Show summary of inserted international waters
SELECT
  COUNT(*) AS total_areas,
  COUNT(CASE WHEN is_special_point THEN 1 END) AS special_points,
  COUNT(CASE WHEN geom IS NOT NULL THEN 1 END) AS polygon_areas,
  ROUND(
    SUM(
      CASE
        WHEN geom IS NOT NULL THEN
          ST_Area(geom::geography) / (111000.0 * 111000.0)
        ELSE
          0
      END
    )::numeric,
    2
  ) AS total_area_sq_degrees
FROM
  international_waters;
