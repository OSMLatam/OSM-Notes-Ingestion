-- Creates data warehouse relations.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2024-01-17

-- Primrary keys
SELECT /* Notes-ETL */ CURRENT_TIMESTAMP AS Processing,
 'Creating primary keys' AS Task;

ALTER TABLE dwh.facts
 ADD CONSTRAINT pk_facts
 PRIMARY KEY (fact_id);

-- Foreign keys.
SELECT /* Notes-ETL */ CURRENT_TIMESTAMP AS Processing,
 'Creating foreign keys' AS Task;

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_country
 FOREIGN KEY (dimension_id_country)
 REFERENCES dwh.dimension_countries (dimension_country_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_day_action
 FOREIGN KEY (action_dimension_id_date)
 REFERENCES dwh.dimension_days (dimension_day_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_hour_of_week_action
 FOREIGN KEY (action_dimension_id_hour_of_week)
 REFERENCES dwh.dimension_hours_of_week (dimension_how_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_users_action
 FOREIGN KEY (action_dimension_id_user)
 REFERENCES dwh.dimension_users (dimension_user_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_day_opened
 FOREIGN KEY (opened_dimension_id_date)
 REFERENCES dwh.dimension_days (dimension_day_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_time_opened
 FOREIGN KEY (opened_dimension_id_hour_of_week)
 REFERENCES dwh.dimension_hours_of_week (dimension_how_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_users_opened
 FOREIGN KEY (opened_dimension_id_user)
 REFERENCES dwh.dimension_users (dimension_user_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_day_closed
 FOREIGN KEY (closed_dimension_id_date)
 REFERENCES dwh.dimension_days (dimension_day_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_time_closed
 FOREIGN KEY (closed_dimension_id_hour_of_week)
 REFERENCES dwh.dimension_hours_of_week (dimension_how_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_users_closed
 FOREIGN KEY (closed_dimension_id_user)
 REFERENCES dwh.dimension_users (dimension_user_id);

ALTER TABLE dwh.facts
 ADD CONSTRAINT fk_application_created
 FOREIGN KEY (dimension_application_creation)
 REFERENCES dwh.dimension_applications (dimension_application_id);

SELECT /* Notes-ETL */ CURRENT_TIMESTAMP AS Processing,
 'Creating indexes' AS Task;

-- Unique keys

CREATE INDEX facts_action_date ON dwh.facts (action_at);
COMMENT ON INDEX dwh.facts_action_date IS
  'Improves queries by action timestamp';

CREATE INDEX action_idx
 ON dwh.facts (action_dimension_id_user, action_comment, id_note);
COMMENT ON INDEX dwh.action_idx IS 'Improves queries by user and action type';

CREATE INDEX open_user_idx
 ON dwh.facts (opened_dimension_id_user);
COMMENT ON INDEX dwh.open_user_idx IS 'Improves queries by creating user';

CREATE INDEX open_idnote_idx
 ON dwh.facts (opened_dimension_id_user, id_note);
COMMENT ON INDEX dwh.open_idnote_idx IS 'Improves queries by creating user';

CREATE INDEX open_user_date_idx
 ON dwh.facts (opened_dimension_id_date, opened_dimension_id_user);
COMMENT ON INDEX dwh.open_user_date_idx IS
  'Improves queries by creating date and user';

CREATE INDEX open_date_user_idx
 ON dwh.facts (opened_dimension_id_user, opened_dimension_id_date);
COMMENT ON INDEX dwh.open_date_user_idx IS
  'Improves queries by creating user and date';

CREATE INDEX closed_user_idx
ON dwh.facts (closed_dimension_id_user);
COMMENT ON INDEX dwh.closed_user_idx IS 'Improves queries by closing user';

CREATE INDEX closed_idnote_idx
ON dwh.facts (closed_dimension_id_user, id_note);
COMMENT ON INDEX dwh.closed_idnote_idx IS 'Improves queries by closing user';

CREATE INDEX closed_user_date_idx
ON dwh.facts (closed_dimension_id_date, closed_dimension_id_user);
COMMENT ON INDEX dwh.closed_user_date_idx IS
  'Improves queries by closing date and user';

CREATE INDEX closed_date_user_idx
ON dwh.facts (closed_dimension_id_user, closed_dimension_id_date);
COMMENT ON INDEX dwh.closed_date_user_idx IS
  'Improves queries by closing user and date';

CREATE INDEX country_open_user_idx
ON dwh.facts (dimension_id_country, opened_dimension_id_user);
COMMENT ON INDEX dwh.country_open_user_idx IS
  'Improves queries by country and opening user';

CREATE INDEX country_closed_user_idx
ON dwh.facts (dimension_id_country, closed_dimension_id_user);
COMMENT ON INDEX dwh.country_closed_user_idx IS
  'Improves queries by country and closing user';

CREATE INDEX hours_opening_idx
ON dwh.facts (opened_dimension_id_hour_of_week, opened_dimension_id_user);
COMMENT ON INDEX dwh.hours_opening_idx IS
  'Improves queries by opening hour and user';

CREATE INDEX hours_commenting_idx
ON dwh.facts (action_dimension_id_hour_of_week, action_dimension_id_user);
COMMENT ON INDEX dwh.hours_commenting_idx IS
  'Improves queries by action hour and user';

CREATE INDEX hours_closing_idx
ON dwh.facts (closed_dimension_id_hour_of_week, closed_dimension_id_user);
COMMENT ON INDEX dwh.hours_closing_idx IS
  'Improves queries by closing hour and user';

CREATE INDEX user_dateidx
ON dwh.facts (action_dimension_id_user, action_dimension_id_date);
COMMENT ON INDEX dwh.user_dateidx IS
  'Improves queries by action user and date';

CREATE INDEX date_user_action_idx
ON dwh.facts (action_dimension_id_date, action_dimension_id_user,
 action_comment);
COMMENT ON INDEX dwh.date_user_action_idx IS
  'Improves queries by action date, user and type';

CREATE INDEX date_action_country_idx
ON dwh.facts (dimension_id_country, action_dimension_id_date, action_comment);
COMMENT ON INDEX dwh.date_action_country_idx IS
  'Improves queries by action country, date and type';

CREATE INDEX date_action_open_idx
ON dwh.facts (dimension_id_country, action_dimension_id_date,
  opened_dimension_id_user);
COMMENT ON INDEX dwh.date_action_open_idx IS
  'Improves queries by action country, date and user open';

CREATE INDEX date_action_close_idx
ON dwh.facts (dimension_id_country, action_dimension_id_date,
  closed_dimension_id_user);
COMMENT ON INDEX dwh.date_action_close_idx IS
  'Improves queries by action country, date and user close';

CREATE INDEX action_country_idx
ON dwh.facts (dimension_id_country, action_comment);
COMMENT ON INDEX dwh.action_country_idx IS
  'Improves queries by country and action type';

CREATE INDEX recent_opened_idx
 ON dwh.facts (recent_opened_dimension_id_date);
COMMENT ON INDEX dwh.recent_opened_idx IS 'Improves queries for reopened notes';

CREATE INDEX resolution_idx
 ON dwh.facts (id_note, fact_id);
COMMENT ON INDEX dwh.resolution_idx IS 'Improves queries to get resolve notes';

CREATE INDEX user_note_idx
 ON dwh.facts (id_note, fact_id);
COMMENT ON INDEX dwh.user_note_idx IS 'Improves queries to get resolve notes';

SELECT /* Notes-ETL */ CURRENT_TIMESTAMP AS Processing,
 'Creating triggers' AS Task;

CREATE OR REPLACE FUNCTION dwh.update_days_to_resolution()
  RETURNS TRIGGER AS
 $$
 DECLARE
  m_open_date DATE;
  m_reopen_date DATE;
  m_close_date DATE;
  m_days INTEGER;
 BEGIN
  IF (NEW.action_comment = 'closed') THEN
   -- Days between initial open and most recent close.
   SELECT /* Notes-ETL */ date_id
    INTO m_open_date
    FROM dwh.dimension_days
    WHERE dimension_day_id = NEW.opened_dimension_id_date;

   SELECT /* Notes-ETL */ date_id
    INTO m_close_date
    FROM dwh.dimension_days
    WHERE dimension_day_id = NEW.action_dimension_id_date;

   m_days := m_close_date - m_open_date;
   UPDATE dwh.facts
    SET days_to_resolution = m_days
     WHERE fact_id = NEW.fact_id;

   -- Days between last reopen and most recent close.
   SELECT /* Notes-ETL */ MAX(date_id)
    INTO m_reopen_date
   FROM dwh.facts f
    JOIN dwh.dimension_days d
    ON f.action_dimension_id_date = d.dimension_day_id
    WHERE id_note = NEW.id_note
    AND action_comment = 'reopened';
   --RAISE NOTICE 'Reopen date: %.', m_reopen_date;
   IF (m_reopen_date IS NOT NULL) THEN
    -- Days from the last reopen.
    m_days := m_close_date - m_reopen_date;
    --RAISE NOTICE 'Difference dates %-%: %.', m_close_date, m_reopen_date, m_days;
    UPDATE dwh.facts
     SET days_to_resolution_from_reopen = m_days
     WHERE fact_id = NEW.fact_id;

    -- Days in open status
    SELECT /* Notes-ETL */ SUM(days_difference)
     INTO m_days
    FROM (
     SELECT /* Notes-ETL */ dd.date_id - dd2.date_id days_difference
     FROM dwh.facts f
     JOIN dwh.dimension_days dd
     ON f.action_dimension_id_date = dd.dimension_day_id
     JOIN dwh.dimension_days dd2
     ON f.recent_opened_dimension_id_date = dd2.dimension_day_id
     WHERE f.id_note = NEW.id_note
     AND f.action_comment <> 'closed'
    ) AS t
    ;
    UPDATE dwh.facts
     SET days_to_resolution_active = m_days
     WHERE fact_id = NEW.fact_id;

   END IF;
  END IF;
  RETURN NEW;
 END;
 $$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION dwh.update_days_to_resolution IS
  'Sets the number of days between the creation and the resolution dates';

CREATE OR REPLACE TRIGGER update_days_to_resolution
  AFTER INSERT ON dwh.facts
  FOR EACH ROW
  EXECUTE FUNCTION dwh.update_days_to_resolution()
;
COMMENT ON TRIGGER update_days_to_resolution ON dwh.facts IS
  'Updates the number of days between creation and resolution dates';

