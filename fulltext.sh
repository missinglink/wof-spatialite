#!/bin/bash
# set -e;
export LC_ALL=en_US.UTF-8;

# location of this file in filesystem
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd );

# location of sqlite database file
DB=${DB:-"$DIR/fts.sqlite3"};

# location of admin source database file
SOURCE=${SOURCE:-"/data/wof-spatialite/wof.admin.sqlite3"};

# note: requires libspatialite to be compiled with librttopo
export LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib;

## init - set up a new database
function init(){
  sqlite3 "$DB" <<SQL
DROP TABLE IF EXISTS place;
CREATE TABLE place (
  wofid INTEGER NOT NULL PRIMARY KEY,
  placetype TEXT NOT NULL,
  iso TEXT NOT NULL,
  area REAL
);
CREATE INDEX IF NOT EXISTS wofid_idx ON place(wofid);
CREATE INDEX IF NOT EXISTS iso_idx ON place(iso);

DROP TABLE IF EXISTS place_name;
CREATE VIRTUAL TABLE place_name USING fts5 (
  name,
  key UNINDEXED,
  wofid UNINDEXED,
  prefix='1 2 3 4 5 6 7 8 9 10'
);
SQL
}

## index data
function index(){
  sqlite3 "$DB" <<SQL
PRAGMA foreign_keys=OFF;
PRAGMA page_size=4096;
PRAGMA cache_size=-2000;
PRAGMA synchronous=OFF;
PRAGMA journal_mode=OFF;
PRAGMA temp_store=MEMORY;

ATTACH DATABASE '$SOURCE' as 'source';

INSERT INTO place SELECT
  json_extract( blob, '$.wof:id' ) as wofid,
  json_extract( blob, '$.wof:placetype' ) as placetype,
  json_extract( blob, '$.iso:country' ) as iso,
  json_extract( blob, '$.geom:area' ) as area
FROM source.properties;
SQL
}

## index names
function index_names(){
  sqlite3 "$DB" <<SQL
PRAGMA foreign_keys=OFF;
PRAGMA page_size=4096;
PRAGMA cache_size=-2000;
PRAGMA synchronous=OFF;
PRAGMA journal_mode=OFF;
PRAGMA temp_store=MEMORY;

ATTACH DATABASE '$SOURCE' as 'source';
BEGIN;

INSERT INTO place_name SELECT
  json_extract( blob, '$.wof:name' ) as name,
  'default' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:chi_x_preferred[0]' ) as name,
  'chi' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:spa_x_preferred[0]' ) as name,
  'spa' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:eng_x_preferred[0]' ) as name,
  'eng' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:hin_x_preferred[0]' ) as name,
  'hin' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:ara_x_preferred[0]' ) as name,
  'ara' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:por_x_preferred[0]' ) as name,
  'por' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:ben_x_preferred[0]' ) as name,
  'ben' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:rus_x_preferred[0]' ) as name,
  'rus' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:jpn_x_preferred[0]' ) as name,
  'jpn' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

INSERT INTO place_name SELECT
  json_extract( blob, '$.name:kor_x_preferred[0]' ) as name,
  'kor' as key,
  place_id as wofid
FROM source.properties
WHERE name IS NOT NULL;

COMMIT;
SQL
}

echo 'clear';
rm -f "$DB";

echo 'init';
init;

echo 'index';
index;

echo 'index_names';
index_names;

echo 'table counts';
sqlite3 "$DB" "SELECT count(*) FROM place";
sqlite3 "$DB" "SELECT count(*) FROM place_name";
sqlite3 "$DB" "SELECT * FROM place_name LIMIT 10";

echo 'debug';
sqlite3 "$DB" 'SELECT * FROM place_name WHERE place_name MATCH "new york" GROUP BY wofid';
sqlite3 "$DB" 'SELECT * FROM place_name WHERE place_name MATCH "londres" GROUP BY wofid';

echo 'search'
sqlite3 "$DB" 'SELECT * FROM place JOIN place_name ON place.wofid = place_name.wofid WHERE place_name MATCH "lond*" GROUP BY place.wofid ORDER BY place.area DESC;';
