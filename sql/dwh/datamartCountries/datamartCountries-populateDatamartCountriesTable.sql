-- Populates datamart for countries.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2023-12-08

DO /* Notes-datamartCountries-processCountries */
$$
DECLARE
 r RECORD;
 max_date DATE;
BEGIN
 SELECT /* Notes-datamartCountries */ date
  INTO max_date
 FROM dwh.max_date_countries_processed;
 IF (max_date < CURRENT_DATE) THEN
  RAISE NOTICE 'Moving activites';
  -- Updates all countries, moving a day.
  UPDATE dwh.datamartCountries
   SET last_year_activity = dwh.move_day(last_year_activity);
  UPDATE dwh.max_date_countries_processed
   SET date = CURRENT_DATE;
 END IF;

 FOR r IN
  -- Process the datamart only for modified countries.
  SELECT /* Notes-datamartCountries */
   f.dimension_id_country AS dimension_id_country
  FROM dwh.facts f
   JOIN dwh.dimension_countries c
   ON (f.dimension_id_country = c.dimension_country_id)
  WHERE c.modified = TRUE
  GROUP BY f.dimension_id_country
  ORDER BY MAX(f.action_at) DESC
 LOOP
  RAISE NOTICE 'Processing country %', r.dimension_id_country;
  CALL dwh.update_datamart_country(r.dimension_id_country);

  UPDATE dwh.dimension_countries
   SET modified = FALSE
   WHERE dimension_country_id = r.dimension_id_country;

  COMMIT;
 END LOOP;
END
$$;
