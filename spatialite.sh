#!/bin/bash
# set -e;
export LC_ALL=en_US.UTF-8;

# location of the input data directory
INDIR=${INDIR:-"/whosonfirst-data"};
if [ ! -d $INDIR ]; then
  echo "input data dir does not exist";
  exit 1;
fi

# location of the output data directory
OUTDIR=${OUTDIR:-"/whosonfirst-data"};
if [ ! -d $OUTDIR ]; then
  echo "output data dir does not exist";
  exit 1;
fi

# location of sqlite database file
DB="$OUTDIR/wof.sqlite3";

## init - set up a new database
function init(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
SELECT InitSpatialMetaData(1);
CREATE TABLE IF NOT EXISTS place (
  id INTEGER NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  placetype TEXT
);
CREATE INDEX IF NOT EXISTS place_idx ON place(placetype);
SELECT AddGeometryColumn('place', 'geom', 4326, 'GEOMETRY', 'XY', 1);
SQL
}

## json - print a json property from file
## $1: geojson path: eg. '/tmp/test.geojson'
## $2: property to extract: eg. '$.geometry'
function json(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
WITH file AS ( SELECT readfile('$1') as json )
SELECT json_extract(( SELECT json FROM file ), '$2' );
SQL
}

## index - add a geojson polygon to the database
## $1: geojson path: eg. '/tmp/test.geojson'
function index(){
  echo $1;
  sqlite3 $DB <<SQL
PRAGMA foreign_keys=OFF;
PRAGMA page_size=4096;
PRAGMA cache_size=-2000;
PRAGMA synchronous=OFF;
PRAGMA journal_mode=OFF;
PRAGMA temp_store=MEMORY;

SELECT load_extension('mod_spatialite');
WITH file AS ( SELECT readfile('$1') AS json )
INSERT INTO place ( id, name, placetype, geom )
VALUES (
  json_extract(( SELECT json FROM file ), '$.properties."wof:id"'),
  json_extract(( SELECT json FROM file ), '$.properties."wof:name"'),
  json_extract(( SELECT json FROM file ), '$.properties."wof:placetype"'),
  SetSRID( GeomFromGeoJSON( json_extract(( SELECT json FROM file ), '$.geometry') ), 4326 )
);
SQL
}

## bboxify - create the rtree index required by the 'pipfast' function
function bboxify(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
CREATE VIRTUAL TABLE IF NOT EXISTS box USING rtree(
   id INTEGER NOT NULL PRIMARY KEY,
   minX REAL, maxX REAL,
   minY REAL, maxY REAL
);
INSERT OR REPLACE INTO box ( id, minX, maxX, minY, maxY )
SELECT id, MbrMinX( geom ), MbrMaxX( geom ), MbrMinY( geom ), MbrMaxY( geom )
FROM place;
SQL
}

## fixify - fix broken geometries
function fixify(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
UPDATE place SET geom = MakeValid( geom );
SQL
}

## index_all - add all geojson polygons in $1 to the database
## $1: data path: eg. '/tmp/polygons'
function index_all(){
  find "$1" -type f -name '*.geojson' -print0 | while IFS= read -r -d $'\0' file; do
    index $file;
  done
}

## pip - point-in-polygon test
## $1: longitude: eg. '151.5942043'
## $2: latitude: eg. '-33.013441'
function pip(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
SELECT * FROM place
WHERE within( GeomFromText('POINT( $1 $2 )', 4326 ), geom );
SQL
}

## pipfast - point-in-polygon test optimized with an rtree index
## $1: longitude: eg. '151.5942043'
## $2: latitude: eg. '-33.013441'
function pipfast(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
SELECT * FROM place
WHERE id IN (
  SELECT id FROM box
  WHERE minX<=$1
    AND maxX>=$1
    AND minY<=$2
    AND maxY>=$2
)
AND within( GeomFromText( 'POINT( $1 $2 )', 4326 ), geom );
SQL
}

## contains - find all child polygons contained by: $1
## $1: id: eg. '2316741'
function contains(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
SELECT * FROM place
WHERE id IN (
  SELECT id FROM box
  WHERE minX>=( SELECT minX FROM box WHERE id=$1 )
    AND maxX<=( SELECT maxX FROM box WHERE id=$1 )
    AND minY>=( SELECT minY FROM box WHERE id=$1 )
    AND maxY<=( SELECT maxY FROM box WHERE id=$1 )
  AND id != $1
)
AND CONTAINS(( SELECT geom FROM place WHERE id=$1 ), geom );
SQL
}

## within - find all parent polygons containing id: $1
## $1: id: eg. '2316741'
function within(){
  sqlite3 $DB <<SQL
SELECT load_extension('mod_spatialite');
SELECT * FROM place
WHERE id IN (
  SELECT id FROM box
  WHERE minX<=( SELECT minX FROM box WHERE id=$1 )
    AND maxX>=( SELECT maxX FROM box WHERE id=$1 )
    AND minY<=( SELECT minY FROM box WHERE id=$1 )
    AND maxY>=( SELECT maxY FROM box WHERE id=$1 )
  AND id != $1
)
AND WITHIN(( SELECT geom FROM place WHERE id=$1 ), geom );
SQL
}

## extract - copy database records within id: $2
## $1: new db name: eg. 'extract.db'
## $2: id: eg. '2316741'
function extract(){

  # switch db var
  MAINDB="$DB";
  DB="$1";

  init; # init new db

  sqlite3 $MAINDB <<SQL
PRAGMA foreign_keys=OFF;
PRAGMA page_size=4096;
PRAGMA cache_size=-2000;
PRAGMA synchronous=OFF;
PRAGMA journal_mode=OFF;
PRAGMA temp_store=MEMORY;

SELECT load_extension('mod_spatialite');
ATTACH DATABASE '$1' AS 'extract';
WITH base AS ( SELECT * FROM place JOIN box ON place.id = box.id WHERE place.id=$2 )
INSERT INTO extract.place SELECT * FROM main.place
WHERE id IN (
  SELECT id FROM box WHERE
  minX>=( SELECT minX FROM base ) AND
  maxX<=( SELECT maxX FROM base ) AND
  minY>=( SELECT minY FROM base ) AND
  maxY<=( SELECT maxY FROM base )
)
AND (
  id=$2 OR
  CONTAINS(( SELECT geom FROM base ), geom )
);
SQL

  bboxify; # create rtree for new db
}

# --- standard build process ---
# init;
# index_all "$DIR/data";
# fixify;
# bboxify;

# --- berlin test data ---
# index '/data/boundaries/data/000/016/347/000016347.geojson';
# index '/data/boundaries/data/000/016/566/000016566.geojson';
# index '/data/boundaries/data/000/051/477/000051477.geojson';
# index '/data/boundaries/data/000/062/422/000062422.geojson';
# pipfast '13.402247' '52.50952';
# 16347|Mitte|9|borough|
# 16566|Mitte|10|suburb|
# 51477|Deutschland|2||
# 62422|Berlin|4|state|

# cli runner
case "$1" in
'init') init;;
'json') json "$2" "$3";;
'index') index "$2";;
'index_all') index_all "$2";;
'bboxify') bboxify;;
'fixify') fixify;;
'pip') pip "$2" "$3";;
'pipfast') pipfast "$2" "$3";;
'contains') contains "$2";;
'within') within "$2";;
'extract') extract "$2" "$3";;
*)
  BR='-------------------------------------------------------------------------'
  printf "%s\n" $BR
  grep -C0 --group-separator=$BR '##' $0 | grep -v 'grep' | sed 's/##//g';
  ;;
esac
