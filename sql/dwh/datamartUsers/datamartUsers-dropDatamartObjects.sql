-- Drop datamart for users tables.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2023-10-29

DROP PROCEDURE IF EXISTS dwh.update_datamart_user;

DROP PROCEDURE IF EXISTS dwh.update_datamart_user_activity_year;

DROP PROCEDURE IF EXISTS dwh.insert_datamart_user;

DROP TABLE IF EXISTS dwh.badges_per_users;

DROP TABLE IF EXISTS dwh.badges;

DROP TABLE IF EXISTS dwh.datamartUsers;

DROP TABLE IF EXISTS dwh.contributor_types;
