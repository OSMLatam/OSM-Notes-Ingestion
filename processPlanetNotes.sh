#!/bin/bash

# This script prepares a database for note analysis.
# The script structure is:
# * Creates the database structure.
# * Downloads the list of country ids (overpass).
# * Downloads the country boundaries (overpass).
# * Downloads the list of maritime area ids (overpass).
# * Downloads the maritime area boundaries (overpass).
# * Imports the boundaries into the db.
# * Downloads the planet notes.
# * Converts the notes into flat CSV files.
# * Imports the notes into the db.
# * Sets the order for countries by zones.
# * Creates a function to get the country of a position using the order by
#   zones.
# * Runs the function against all notes.
#
# If the download fails with "Too many requests", you can check this page:
# http://overpass-api.de/api/status and increase the sleep time between loops.
#
# Known errors:
# * Austria has an issue to be imported with ogr2ogr for a particular thing in
#   the geometry. A simplification is done to upload it.
# * Taiwan has an issue to be imported with ogr2ogr for a very long row. Some
#   fields are removed.
# * The Gaza Strip is not at the same level as a country. The ID is hardcoded.
#
# The following files are for tests or prepare the environment.
# setopt interactivecomments
# https://github.com/tyrasd/osmtogeojson
# npm install -g osmtogeojson
# https://sourceforge.net/projects/saxon/files/Saxon-HE/11/Java/SaxonHE11-4J.zip/download
#
# You need to create a database called 'notes':
#   CREATE DATABASE notes;
# You need to install postgis and add the extension:
#   CREATE EXTENSION postgis;
# You also need to log into the database with the current user ${USER}
#   createuser myuser
#   CREATE ROLE myuser WITH LOGIN
# You need to check the access to PostgreSQL with the following without
# password:
#   psql -d notes
# This could be an option:
#   export PGPASSWORD='password'
# Or change the pg_hba.conf file.
# Also you need to give permissions to create objects in public schema:
#   GRANT USAGE ON SCHEMA public TO myuser
#
# To specify the Saxon location, you can do something like; otherwise, it will
# the current location:
#  export SAXON_CLASSPATH=~/saxon/
#
# Some interesting queries to track the process:
#
# select country_name_en, americas, europe, russia_middle_east, asia_oceania
# from countries
# order by americas nulls last, europe nulls last,
#  russia_middle_east nulls last, asia_oceania nulls last;
#
# select iter, area, count(1)
# from tries
# group by iter, area 
# order by ITER desc;
#
# select t.*, country_name_en
# from tries t join countries c on (t.id_country = c.country_id)
# where iter = 121;
#
# select iter, area, count(1), country_name_en
# from tries t join countries c on (t.id_country = c.country_id)
# group by iter, area, country_name_en
# order by area, ITER desc;
#
# Author: Andres Gomez (AngocA)
# Version: 2022-11-12

set -xv
set -euo pipefail
CLEAN=true

DBNAME=notes
LOG_FILE=processPlanetNotes.log
COUNTRIES_FILE=countries
MARITIMES_FILE=maritimes
QUERY_FILE=query
XSLT_NOTES_FILE=notes-csv.xslt
XSLT_NOTE_COMMENTS_FILE=note_comments-csv.xslt
OUTPUT_NOTES_FILE=output-notes.csv
OUTPUT_NOTE_COMMENTS_FILE=output-note_comments.csv
PLANET_NOTES_FILE=planet-notes-latest.osn
SAXON_JAR=${SAXON_CLASSPATH:-.}/saxon-he-11.4.jar
SECONDS_TO_WAIT=5
MAX_NOTE_ID=3500000
BASE_LOAD=${1:-}

function checkPrereqs {
 if [ "${BASE_LOAD}" != "" ] && [ "${BASE_LOAD}" != "--base" ]  ; then
  echo "ERROR: Invalid parameter. It should be empty or --base."
  exit 2
 fi
 set +e
 # Checks prereqs.
 ## PostgreSQL
 if ! psql --version > /dev/null 2>&1 ; then
  echo "ERROR: PostgreSQL is missing."
  exit 1
 fi
 ## Wget
 if ! wget --version > /dev/null 2>&1 ; then
  echo "ERROR: Wget is missing."
  exit 1
 fi
 ## osmtogeojson
 if ! osmtogeojson --version > /dev/null 2>&1 ; then
  echo "ERROR: osmtogeojson is missing."
  exit 1
 fi
 ## gdal ogr2ogr
 if ! ogr2ogr --version > /dev/null 2>&1 ; then
  echo "ERROR: ogr2ogr is missing."
  exit 1
 fi
 ## cURL
 if ! curl --version > /dev/null 2>&1 ; then
  echo "ERROR: curl is missing."
  exit 1
 fi
 ## Block-sorting file compressor
 if ! bzip2 --help > /dev/null 2>&1 ; then
  echo "ERROR: bzip2 is missing."
  exit 1
 fi
 ## Java
 if ! java --version > /dev/null 2>&1 ; then
  echo "ERROR: Java JRE is missing."
  exit 1
 fi
 ## Saxon Jar
 if [ ! -r "${SAXON_JAR}" ] ; then
  echo "ERROR: Saxon jar is missing at ${SAXON_JAR}."
  exit 1
 fi
 set -e
}

function dropBaseTables {
 echo "Droping tables."
 psql -d "${DBNAME}" << EOF
  DROP TABLE tries;
  DROP TABLE note_comments;
  DROP TABLE notes;
  DROP TYPE note_event_enum;
  DROP TYPE note_status_enum;
  DROP TABLE countries;
EOF
}

function dropSyncTables {
 echo "Droping tables."
 psql -d "${DBNAME}" << EOF
  DROP TABLE note_comments_sync;
  DROP TABLE notes_sync;
EOF
}

function createBaseTables {
 echo "Creating tables"
 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  CREATE TABLE countries (
   country_id INTEGER NOT NULL,
   country_name VARCHAR(100) NOT NULL,
   country_name_es VARCHAR(100),
   country_name_en VARCHAR(100),
   geom GEOMETRY NOT NULL,
   americas INTEGER, 
   europe INTEGER, 
   russia_middle_east INTEGER, 
   asia_oceania INTEGER
  );

  ALTER TABLE countries
   ADD CONSTRAINT pk_countries
   PRIMARY KEY (country_id);

  CREATE TYPE note_status_enum AS ENUM (
    'open',
    'close',
    'hidden'
    );
 
  CREATE TYPE note_event_enum AS ENUM (
   'opened',
   'closed',
   'reopened',
   'commented',
   'hidden'
   );
 
  CREATE TABLE notes (
   note_id INTEGER NOT NULL,
   latitude DECIMAL NOT NULL,
   longitude DECIMAL NOT NULL,
   created_at TIMESTAMP NOT NULL,
   closed_at TIMESTAMP,
   status note_status_enum,
   id_country INTEGER
  );
 
  ALTER TABLE notes
   ADD CONSTRAINT pk_notes
   PRIMARY KEY (note_id);
 
  CREATE TABLE note_comments (
   note_id INTEGER NOT NULL,
   event note_event_enum NOT NULL,
   created_at TIMESTAMP NOT NULL,
   user_id INTEGER,
   username VARCHAR(256)
  );
 
  ALTER TABLE note_comments
   ADD CONSTRAINT fk_notes
   FOREIGN KEY (note_id)
   REFERENCES notes (note_id);

  CREATE TABLE tries (
   area VARCHAR(20),
   iter INTEGER,
   id_note INTEGER,
   id_country INTEGER
  );
EOF
}

function createSyncTables {
 echo "Creating tables"
 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF 
  CREATE TABLE notes_sync (
   note_id INTEGER NOT NULL,
   latitude DECIMAL NOT NULL,
   longitude DECIMAL NOT NULL,
   created_at TIMESTAMP NOT NULL,
   closed_at TIMESTAMP,
   status note_status_enum,
   id_country INTEGER
  );
 
  ALTER TABLE notes_sync
   ADD CONSTRAINT pk_notes_sync
   PRIMARY KEY (note_id);
 
  CREATE TABLE note_comments_sync (
   note_id INTEGER NOT NULL,
   event note_event_enum NOT NULL,
   created_at TIMESTAMP NOT NULL,
   user_id INTEGER,
   username VARCHAR(256)
  );
 
  ALTER TABLE note_comments_sync
   ADD CONSTRAINT fk_notes_sync
   FOREIGN KEY (note_id)
   REFERENCES notes (note_id);
EOF
}

function processCountries {
 echo "DELETE FROM countries" | psql -d ${DBNAME} -v ON_ERROR_STOP=1 

 # Extracts ids of all country relations into a JSON.
 echo "Obtaining the countries ids."
 cat << EOF > "${QUERY_FILE}"
  [out:csv(::id)];
  (
    relation["type"="boundary"]["boundary"="administrative"]["admin_level"="2"];
  );
  out ids;
EOF

 set +e
 wget -O "${COUNTRIES_FILE}" --post-file="${QUERY_FILE}" \
   "https://overpass-api.de/api/interpreter"
 RET=${?}
 set -e
 if [ ${RET} -ne 0 ] ; then
  echo "ERROR: Country list could not be downloaded."
  exit 1
 fi
 
 tail -n +2 "${COUNTRIES_FILE}" > "${COUNTRIES_FILE}.tmp"
 mv "${COUNTRIES_FILE}.tmp" "${COUNTRIES_FILE}"
 
 # Adds the Gaza Strip, as it is not at country level.
 echo "1703814" "${COUNTRIES_FILE}"
 
 echo "Retrieving the countries' boundaries."
 while read -r LINE ; do
  ID=$(echo "${LINE}" | awk '{print $1}')
  echo "----> ${ID} $(date)"
  cat << EOF > "${QUERY_FILE}"
   [out:json];
   rel(${ID});
   (._;>;);
   out; 
EOF
  echo "Retrieving shape."
  wget -O "${ID}.json" --post-file="${QUERY_FILE}" \
    "https://overpass-api.de/api/interpreter"
 
  echo "Converting into geoJSON."
  osmtogeojson "${ID}.json" > "${ID}.geojson"
  set +e
  COUNTRY=$(grep "\"name\":" "${ID}.geojson" | head -1 \
    | awk -F\" '{print $4}' | sed "s/'/''/")
  COUNTRY_ES=$(grep "\"name:es\":" "${ID}.geojson" | head -1 \
    | awk -F\" '{print $4}' | sed "s/'/''/")
  COUNTRY_EN=$(grep "\"name:en\":" "${ID}.geojson" | head -1 \
    | awk -F\" '{print $4}' | sed "s/'/''/")
  set -e
 
  # Taiwan cannot be imported directly. Thus, a simplification is done.
  # ERROR:  row is too big: size 8616, maximum size 8160
  grep -v "official_name" "${ID}.geojson" | \
    grep -v "alt_name" > "${ID}.geojson-new"
  mv "${ID}.geojson-new" "${ID}.geojson"
 
  echo "Importing into Postgres."
  ogr2ogr -f "PostgreSQL" PG:"dbname=${DBNAME} user=${USER}" "${ID}.geojson" \
    -nln import -overwrite
 
  echo "Inserting into final table."
  if [ "${ID}" -ne 16239 ] ; then
   STATEMENT="INSERT INTO countries (country_id, country_name, country_name_es, 
     country_name_en, geom) select ${ID}, '${COUNTRY}', '${COUNTRY_ES}', 
     '${COUNTRY_EN}', ST_Union(wkb_geometry) 
     from import group by 1"
  else # This case is for Austria.
   # GEOSUnaryUnion: TopologyException: Input geom 1 is invalid: 
   # Self-intersection at or near point 10.454439900000001 47.555796399999998 
   # at 10.454439900000001 47.555796399999998
   STATEMENT="INSERT INTO countries (country_id, country_name, country_name_es, 
     country_name_en, geom) select ${ID}, '${COUNTRY}', '${COUNTRY_ES}', 
     '${COUNTRY_EN}', ST_Union(ST_Buffer(wkb_geometry,0.0)) 
     from import group by 1"
  fi
  echo "${STATEMENT}" | psql -d "${DBNAME}" -v ON_ERROR_STOP=1 
 
  if [ -n "${CLEAN}" ] && [ "${CLEAN}" = true ] ; then
   rm -f "${ID}.json" "${ID}.geojson"
  fi
  echo "Waiting ${SECONDS_TO_WAIT} seconds..."
  sleep ${SECONDS_TO_WAIT}
 done < "${COUNTRIES_FILE}"
}

function processMaritimes {
 # Extracts ids of all EEZ relations into a JSON.
 echo "Obtaining the eez ids."
 cat << EOF > ${QUERY_FILE}
  [out:csv(::id)];
  (
    relation["border_type"]["border_type"~"contiguous|eez"];
  );
  out ids;
EOF

 set +e
 wget -O "${MARITIMES_FILE}" --post-file="${QUERY_FILE}" \
   "https://overpass-api.de/api/interpreter"
 RET=${?}
 set -e
 if [ ${RET} -ne 0 ] ; then
  echo "ERROR: Maritimes border list could not be downloaded."
  exit 1
 fi
 
 tail -n +2 "${MARITIMES_FILE}" > "${MARITIMES_FILE}.tmp"
 mv "${MARITIMES_FILE}.tmp" "${MARITIMES_FILE}"
 
 echo "Retrieving the maritimes' boundaries."
 while read -r LINE ; do
  ID=$(echo "${LINE}" | awk '{print $1}')
  echo "----> ${ID} $(date)" 
  cat << EOF > "${QUERY_FILE}"
   [out:json];
   rel(${ID});
   (._;>;);
   out; 
EOF
  echo "Retrieving shape."
  wget -O "${ID}.json" --post-file="${QUERY_FILE}" \
    "https://overpass-api.de/api/interpreter"
 
  echo "Converting into geoJSON."
  osmtogeojson "${ID}.json" > "${ID}.geojson"
  set +e
  NAME=$(grep "\"name\":" "${ID}.geojson" | head -1 \
    | awk -F\" '{print $4}' | sed "s/'/''/")
  NAME_ES=$(grep "\"name:es\":" "${ID}.geojson" | head -1 \
    | awk -F\" '{print $4}' | sed "s/'/''/")
  NAME_EN=$(grep "\"name:en\":" "${ID}.geojson" | head -1 \
    | awk -F\" '{print $4}' | sed "s/'/''/")
  set -e
 
  echo "Importing into Postgres."
  ogr2ogr -f "PostgreSQL" PG:"dbname=${DBNAME} user=${USER}" "${ID}.geojson" \
    -nln import -overwrite
 
  echo "Inserting into final table."
  STATEMENT="INSERT INTO countries (country_id, country_name, country_name_es, 
    country_name_en, geom) select ${ID}, '${NAME}', '${NAME_ES:-${NAME}}', 
    '${NAME_EN:-${NAME}}', ST_Union(wkb_geometry) from import group by 1"
  echo "${STATEMENT}" | psql -d "${DBNAME}" -v ON_ERROR_STOP=1 
 
  if [ -n "${CLEAN}" ] && [ "${CLEAN}" = true ] ; then
   rm -f "${ID}.json" "${ID}.geojson"
  fi
  echo "Waiting ${SECONDS_TO_WAIT} seconds..."
  sleep ${SECONDS_TO_WAIT}
 done < "${MARITIMES_FILE}"
}

function cleanPartial {
 if [ -n "${CLEAN}" ] && [ "${CLEAN}" = true ] ; then
  rm query "${COUNTRIES_FILE}" "${MARITIMES_FILE}"
  echo "DROP TABLE import" | psql -d "${DBNAME}" -v ON_ERROR_STOP=1 
 fi
}

function downloadPlanetNotes {
 # Download Planet notes.
 echo "Retrieving Planet notes file... $(date)"
 curl --output planet-notes-latest.osn.bz2 \
   https://planet.openstreetmap.org/notes/${PLANET_NOTES_FILE}.bz2
 
 echo "Extracting Planet notes..."
 bzip2 -d "${PLANET_NOTES_FILE}.bz2"
 mv "${PLANET_NOTES_FILE}" "${PLANET_NOTES_FILE}.xml"
}

function convertPlanetNotesToFlatFile {
 # Process the notes file.
 # XSLT transformations.
 cat << EOF > "${XSLT_NOTES_FILE}"
 <?xml version="1.0" encoding="UTF-8"?>
 <xsl:stylesheet version="1.0"
 xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
 <xsl:output method="text" />
  <xsl:template match="/">
   <xsl:for-each select="osm-notes/note"><xsl:value-of select="@id"/>,<xsl:value-of select="@lat"/>,<xsl:value-of select="@lon"/>,"<xsl:value-of select="@created_at"/>",<xsl:choose><xsl:when test="@closed_at != ''">"<xsl:value-of select="@closed_at"/>","close"
 </xsl:when><xsl:otherwise>,"open"<xsl:text>
 </xsl:text></xsl:otherwise></xsl:choose>
   </xsl:for-each>
  </xsl:template>
 </xsl:stylesheet>
EOF

 cat << EOF > "${XSLT_NOTE_COMMENTS_FILE}"
 <?xml version="1.0" encoding="UTF-8"?>
 <xsl:stylesheet version="1.0"
 xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
 <xsl:output method="text" />
  <xsl:template match="/">
   <xsl:for-each select="osm-notes/note">
   <xsl:variable name="note_id"><xsl:value-of select="@id"/></xsl:variable>
    <xsl:for-each select="comment">
 <xsl:choose> <xsl:when test="@uid != ''"> <xsl:copy-of select="\$note_id" />,"<xsl:value-of select="@action" />","<xsl:value-of select="@timestamp"/>",<xsl:value-of select="@uid"/>,"<xsl:value-of select="@username"/>"<xsl:text>
 </xsl:text></xsl:when><xsl:otherwise>
  <xsl:copy-of select="\$note_id" />,"<xsl:value-of select="@action" />","<xsl:value-of select="@timestamp"/>",,<xsl:text>
 </xsl:text></xsl:otherwise> </xsl:choose>
    </xsl:for-each>
   </xsl:for-each>
  </xsl:template>
 </xsl:stylesheet>
EOF

 # Converts the XML into a flat file in CSV format.
 java -Xmx6000m -cp "${SAXON_JAR}" net.sf.saxon.Transform \
   -s:"${PLANET_NOTES_FILE}.xml" -xsl:${XSLT_NOTES_FILE} -o:"${OUTPUT_NOTES_FILE}"
 java -Xmx5000m -cp "${SAXON_JAR}" net.sf.saxon.Transform \
   -s:"${PLANET_NOTES_FILE}.xml" -xsl:"${XSLT_NOTE_COMMENTS_FILE}" \
  -o:"${OUTPUT_NOTE_COMMENTS_FILE}"
}

function loadBaseNotes {
 # Loads the data in the database.
 # Adds a column to include the country where it belongs.
 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  copy notes from '$(pwd)/${OUTPUT_NOTES_FILE}' csv;
  copy note_comments from '$(pwd)/${OUTPUT_NOTE_COMMENTS_FILE}' csv;
EOF
}

function loadSyncNotes {
 # Loads the data in the database.
 # Adds a column to include the country where it belongs.
 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  copy notes_sync from '$(pwd)/${OUTPUT_NOTES_FILE}' csv;
  copy note_comments_sync from '$(pwd)/${OUTPUT_NOTE_COMMENTS_FILE}' csv;
EOF
}

function removeDuplicates {
 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  DELETE FROM notes_sync WHERE note_id IN (SELECT note_id FROM notes);
  INSERT INTO notes SELECT * FROM notes_sync;
EOF
}

function cleanNotesFiles {
 if [ -n "${CLEAN}" ] && [ "${CLEAN}" = true ] ; then
  rm "${XSLT_NOTES_FILE}" "${XSLT_NOTE_COMMENTS_FILE}" \
    "${PLANET_NOTES_FILE}.xml" "${OUTPUT_NOTES_FILE}" \
    "${OUTPUT_NOTE_COMMENTS_FILE}" 
 fi
}

function organizeAreas {
 # Insert values for representative countries in each area.

 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  -- More than 200K
  UPDATE countries SET americas = 1 WHERE country_name_en IN ('United States');
  -- More than 50K
  UPDATE countries SET americas = 2 WHERE country_name_en IN ('Brazil',
    'Canada');
  -- More than 20K
  UPDATE countries SET americas = 3 WHERE country_name_en IN ('Argentina',
    'Mexico', 'Ecuador');
  -- More than 10K
  UPDATE countries SET americas = 4 WHERE country_name_en IN ('Peru',
    'Colombia', 'Chile', 'Cuba', 'Nicaragua', 'Bolivia');
  -- More than 5K
  UPDATE countries SET americas = 5 WHERE country_name_en IN ('Venezuela',
    'Haiti');
  -- More than 2K
  UPDATE countries SET americas = 6 WHERE country_name_en IN ('Costa Rica',
    'Guatemala', 'Dominican Republic', 'Uruguay', 'Paraguay');
  -- More than 1K
  UPDATE countries SET americas = 7 WHERE country_name_en IN (
    'Trinidad and Tobago', 'Panama', 'Puerto Rico', 'Honduras', 'El Salvador');
  -- Less than 1K
  UPDATE countries SET americas = 8 WHERE country_name_en IN ('Greenland',
    'Portugal', 'Netherlands', 'British Overseas Territories',
    'French Polynesia', 'French Guiana', 'Aruba', 'France', 'New Zealand',
    'Russia');
  -- Less than 500
  UPDATE countries SET americas = 9 WHERE country_name_en IN ('Tonga',
    'Falkland Islands', 'Cayman Islands', 'Anguilla',
    'South Georgia and the South Sandwich Islands', 'Samoa', 'Dominica',
    'Belize', 'Guyana', 'Suriname', 'British Virgin Islands', 'Cook Islands',
    'Pitcairn Islands', 'Bermuda', 'Fiji', 'Kiribati', 'Jamaica', 'Saint Lucia',
    'Grenada', 'Saint Vincent and the Grenadines', 'Barbados',
    'Turks and Caicos Islands', 'Niue', 'The Bahamas', 'Saint Kitts and Nevis',
    'Montserrat', 'Antigua and Barbuda');
EOF

 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  -- More than 500K
  UPDATE countries SET europe = 1 WHERE country_name_en IN ('Germany');
  -- More than 200K
  UPDATE countries SET europe = 2 WHERE country_name_en IN ('France');
  -- More than 100K
  UPDATE countries SET europe = 3 WHERE country_name_en IN ('Spain',
    'United Kingdom', 'Italy', 'Poland');
  -- More than 50K
  UPDATE countries SET europe = 4 WHERE country_name_en IN ('Netherlands',
    'Ukraine');
  -- More than 20K
  UPDATE countries SET europe = 5 WHERE country_name_en IN ('Belgium',
    'Austria', 'Switzerland', 'Croatia', 'Sweden', 'Czechia', 'Belarus');
  -- More than 10K
  UPDATE countries SET europe = 6 WHERE country_name_en IN ('Greece',
    'Ireland', 'Romania', 'Hungary', 'Portugal', 'Finland', 'Slovakia',
    'Denmark', 'Côte d''Ivoire', 'Algeria');
  -- More than 5K
  UPDATE countries SET europe = 7 WHERE country_name_en IN ('Norway',
    'Congo-Kinshasa','South Africa', 'Latvia', 'Bulgaria', 'Libya', 'Egypt',
    'Serbia');
  -- More than 2K
  UPDATE countries SET europe = 8 WHERE country_name_en IN ('Estonia',
    'Lithuania', 'Bosnia and Herzegovina', 'Ghana', 'Slovenia', 'Kosovo',
    'Iceland', 'Albania', 'Montenegro', 'Luxembourg', 'Angola', 'Tunisia',
    'Morocco', 'Russia');
  -- More than 1K
  UPDATE countries SET europe = 9 WHERE country_name_en IN ('Namibia',
    'Nigeria', 'Togo', 'Macedonia', 'Jersey', 'Cameroon', 'Burkina Faso',
    'Senegal', 'Namibia', 'Mali');
  -- Less than 1K
  UPDATE countries SET europe = 10 WHERE country_name_en IN ('Sudan',
    'South Sudan', 'Central African Republic', 'Zambia', 'Botswana',
    'Greenland', 'Zimbabwe', 'Malta', 'Sudan', 'Benin', 'Niger', 'Guadeloupe',
    'Guinea');
  -- Less than 500
  UPDATE countries SET europe = 11 WHERE country_name_en IN (
    'São Tomé and Príncipe', 'Cape Verde', 'Guernsey',
    'Democratic Republic of the Congo', 'Congo-Brazzaville', 'Gabon',
    'Equatorial Guinea', 'Liberia', 'Sierra Leone', 'Guinea-Bissau',
    'The Gambia', 'Mauritania', 'Isle of Man', 'San Marino', 'North Macedonia',
    'Faroe Islands', 'Vatican City', 'Andorra',
    'Sahrawi Arab Democratic Republic', 'Chad',
    'Saint Helena, Ascension and Tristan da Cunha', 'Gibraltar',
    'Liechtenstein', 'Monaco', 'Brazil', 'São Tomé and Príncipe');
EOF

 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  -- More than 200K
  UPDATE countries SET russia_middle_east = 1 WHERE country_name_en IN (
    'Russia');
  -- More than 50K
  UPDATE countries SET russia_middle_east = 2 WHERE country_name_en IN ('Iran',
    'Ukraine');
  -- More than 20K
  UPDATE countries SET russia_middle_east = 3 WHERE country_name_en IN (
    'Belarus', 'Iraq', 'Turkey');
  -- More than 10K
  UPDATE countries SET russia_middle_east = 4 WHERE country_name_en IN (
    'Greece', 'Uzbekistan', 'Finland', 'Romania');
  -- More than 5K
  UPDATE countries SET russia_middle_east = 5 WHERE country_name_en IN (
    'Norway', 'Saudi Arabia', 'Georgia', 'South Africa', 'Latvia', 'Armenia',
    'Pakistan', 'Egypt', 'Bulgaria', 'Libya', 'Congo-Kinshasa', 'Kazakhstan',
    'Azerbaijan', 'Israel');
  -- More than 2K
  UPDATE countries SET russia_middle_east = 6 WHERE country_name_en IN (
    'Estonia', 'Lithuania', 'Moldova', 'United Arab Emirates', 'Cyprus',
    'Tanzania', 'Yemen', 'West Bank', 'Syria', 'Uganda', 'Tajikistan',
    'Ethiopia', 'Jordan', 'United States', 'France');
  -- More than 1K
  UPDATE countries SET russia_middle_east = 7 WHERE country_name_en IN (
    'Namibia', 'Turkmenistan', 'Reunion', 'Oman', 'Kenya', 'Gaza Strip',
    'Lebanon', 'Madagascar', 'Zimbabwe');
  -- Less than 1K
  UPDATE countries SET russia_middle_east = 8 WHERE country_name_en IN ('Sudan',
     'South Sudan', 'Central African Republic', 'Zambia', 'Botswana',
     'Afghanistan', 'Sudan', 'Kuwait', 'Somalia', 'Mozambique', 'Qatar',
     'Mayotte', 'Mauritius');
  -- Less than 500
  UPDATE countries SET russia_middle_east = 9 WHERE country_name_en IN (
    'Comoros', 'Bahrain', 'Eritrea', 'Malawi', 'Burundi', 'Djibouti',
    'Democratic Republic of the Congo', 'Rwanda', 'Eswatini',
    'British Sovereign Base Areas', 'Lesotho', 'Seychelles');
EOF

 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
  -- More than 20K
  UPDATE countries SET asia_oceania = 1 WHERE country_name_en IN ('Russia',
    'Australia', 'India', 'China', 'Philippines', 'Japan', 'Taiwan',
    'Indonesia');
  -- More than 10K
  UPDATE countries SET asia_oceania = 2 WHERE country_name_en IN ('Thailand',
    'South Korea', 'Vietnam', 'Kazakhstan', 'Malaysia', 'Uzbekistan');
  -- More than 5K
  UPDATE countries SET asia_oceania = 3 WHERE country_name_en IN ('New Zealand',
    'Myanmar', 'Nepal', 'Pakistan');
  -- More than 2K
  UPDATE countries SET asia_oceania = 4 WHERE country_name_en IN ('Kyrgyzstan',
    'Cambodia', 'Sri Lanka', 'Bangladesh', 'Laos', 'Hong Kong', 'Singapore',
    'Tajikistan', 'United States', 'France');
  -- More than 1K
  UPDATE countries SET asia_oceania = 5 WHERE country_name_en IN ('Mongolia',
    'Turkmenistan');
  -- Less than 1K
  UPDATE countries SET asia_oceania = 6 WHERE country_name_en IN ('Afghanistan',
    'New Caledonia');
  -- Less than 500
  UPDATE countries SET asia_oceania = 7 WHERE country_name_en IN ('North Korea',
    'Bhutan', 'East Timor', 'Vanuatu', 'Brunei', 'Solomon Islands', 'Palau',
    'Tuvalu', 'Federated States of Micronesia', 'Marshall Islands', 'Fiji',
    'Kiribati', 'Maldives', 'Nauru', 'Papua New Guinea');
EOF
}

function createsFunctionToGetCountry {
 # Creates a function that performs a basic triage according to its longitude:
 # * -180 - -30: Americas.
 # * -30 - 25: West Europe and West Africa.
 # * 25 - 65: Middle East, East Africa and Russia.
 # * 65 - 180: Southeast Asia and Oceania.
 psql -d "${DBNAME}" -v ON_ERROR_STOP=1 << EOF
 CREATE OR REPLACE FUNCTION get_country (
   lon DECIMAL,
   lat DECIMAL,
   id_note INTEGER
 ) RETURNS INTEGER
 LANGUAGE plpgsql
 AS \$func\$
  DECLARE
   id_country INTEGER;
   f RECORD;
   contains BOOLEAN;
   iter INTEGER;
   area VARCHAR(20);
  BEGIN
   id_country := -1;
   iter := 1;
   IF (-5 < lat AND lat < 5 AND 4 > lon AND lon > -4) THEN
    area := 'Null Island';
   ELSIF (lon < -30) THEN -- Americas
    area := 'Americas';
    FOR f IN
      SELECT geom, country_id
      FROM countries
      ORDER BY americas NULLS LAST
     LOOP
      contains := ST_Contains(f.geom, ST_SetSRID(ST_Point(lon, lat), 4326));
      IF (contains) THEN
       id_country := f.country_id;
       EXIT;
      END IF;
      iter := iter + 1;
     END LOOP;
   ELSIF (lon < 25) THEN -- Europe & part of Africa
    area := 'Europe/Africa';
    FOR f IN
      SELECT geom, country_id
      FROM countries
      ORDER BY europe NULLS LAST
     LOOP
      contains := ST_Contains(f.geom, ST_SetSRID(ST_Point(lon, lat), 4326));
      IF (contains) THEN
       id_country := f.country_id;
       EXIT;
      END IF;
      iter := iter + 1;
     END LOOP;
   ELSIF (lon < 65) THEN -- Russia, Middle East & part of Africa
    area := 'Russia/Middle east';
    FOR f IN
      SELECT geom, country_id
      FROM countries
      ORDER BY russia_middle_east NULLS LAST
     LOOP
      contains := ST_Contains(f.geom, ST_SetSRID(ST_Point(lon, lat), 4326));
      IF (contains) THEN
       id_country := f.country_id;
       EXIT;
      END IF;
      iter := iter + 1;
     END LOOP;
   ELSE
    area := 'Asia/Oceania';
    FOR f IN
      SELECT geom, country_id
      FROM countries
      ORDER BY asia_oceania NULLS LAST
     LOOP
      contains := ST_Contains(f.geom, ST_SetSRID(ST_Point(lon, lat), 4326));
      IF (contains) THEN
       id_country := f.country_id;
       EXIT;
      END IF;
      iter := iter + 1;
     END LOOP;
   END IF;
   INSERT INTO tries VALUES (area, iter, id_note, id_country);
   RETURN id_country;
  END
 \$func\$
EOF
} 

function getLocationNotes {
 for i in $(seq 0 1000 ${MAX_NOTE_ID}) ; do
  echo "${i} $(date)"
  echo "UPDATE notes
    SET id_country = get_country(longitude, latitude, note_id)
    WHERE note_id <= ${i}
    AND id_country IS NULL" | psql -d "${DBNAME}" -v ON_ERROR_STOP=1 
 done
}

checkPrereqs
{
 echo "$(date) Starting process"
 if [ "${BASE_LOAD}" == "--base" ] ; then
  dropSyncTables
  dropBaseTables
  createBaseTables
 else
  dropSyncTables
  createSyncTables
 fi
 processCountries
 processMaritimes
 cleanPartial
 downloadPlanetNotes
 convertPlanetNotesToFlatFile
 if [ "${BASE_LOAD}" == "--base" ] ; then
  loadBaseNotes
 else
  loadSyncNotes
  removeDuplicates
  dropSyncTables
 fi
 cleanNotesFiles
 organizeAreas
 createsFunctionToGetCountry
 getLocationNotes
 echo "$(date) Ending process"
} >> "${LOG_FILE}" 2>&1

if [ -n "${CLEAN}" ] && [ "${CLEAN}" = true ] ; then
 rm -f "${LOG_FILE}"
fi
