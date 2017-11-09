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
  sqlite3 --init 'init.sql' ${DB} <<SQL
SELECT InitSpatialMetaData(1);

CREATE TABLE IF NOT EXISTS place (
  id INTEGER NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  layer TEXT
);
CREATE INDEX IF NOT EXISTS layer_idx ON place(layer);
SELECT AddGeometryColumn('place', 'geom', 4326, 'GEOMETRY', 'XY', 1);
SELECT CreateSpatialIndex('place', 'geom');

CREATE TABLE IF NOT EXISTS properties (
  place_id INTEGER PRIMARY KEY NOT NULL,
  blob TEXT,
  CONSTRAINT fk_place FOREIGN KEY (place_id) REFERENCES place(id)
);

CREATE TABLE grid (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 place_id INTEGER NOT NULL,
 CONSTRAINT fk_place FOREIGN KEY (place_id) REFERENCES place(id)
);
CREATE INDEX IF NOT EXISTS place_id_idx ON grid(place_id);
SELECT AddGeometryColumn('grid', 'geom', 4326, 'MULTIPOLYGON', 'XY');
SELECT CreateSpatialIndex('grid', 'geom');
SQL

# set file permissions
chmod 0666 "$DB";
}

## json - print a json property from file
## $1: geojson path: eg. '/tmp/test.geojson'
## $2: property to extract: eg. '$.geometry'
function json(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
WITH file AS ( SELECT readfile('$1') as json )
SELECT json_extract(( SELECT json FROM file ), '$2' );
SQL
}

## index - add a geojson polygon to the database
## $1: geojson path: eg. '/tmp/test.geojson'
function index(){
  echo $1;
  sqlite3 --init 'init.sql' ${DB} <<SQL
BEGIN;

CREATE TEMP TABLE file ( json TEXT );
INSERT INTO file SELECT readfile('$1') AS json;

INSERT INTO place ( id, name, layer, geom )
VALUES (
  json_extract(( SELECT json FROM file ), '$.properties."wof:id"'),
  json_extract(( SELECT json FROM file ), '$.properties."wof:name"'),
  json_extract(( SELECT json FROM file ), '$.properties."wof:placetype"'),
  SetSRID( GeomFromGeoJSON( json_extract(( SELECT json FROM file ), '$.geometry') ), 4326 )
);

INSERT INTO properties ( place_id, blob )
VALUES (
  json_extract(( SELECT json FROM file ), '$.properties."wof:id"'),
  json_extract(( SELECT json FROM file ), '$.properties')
);

DROP TABLE file;
COMMIT;
SQL
}

## index_all - add all geojson polygons in $1 to the database
## $1: data path: eg. '/tmp/polygons'
function index_all(){
  find "$1" -type f -name '*.geojson' -print0 | while IFS= read -r -d $'\0' file; do
    index $file;
  done
}

## fixify - fix broken geometries
function fixify(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
UPDATE place SET geom = MakeValid( geom );
SQL
}

## simplify - perform Douglas-Peuker simplification on all polygons
## $1: tolerance: eg. '0.1'
function simplify(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
UPDATE place SET geom = SimplifyPreserveTopology( geom, $1 );
SQL
}

## grid - create a grid cutout for a 1deg x 1deg section
## $1: minLat: eg. '-180'
## $2: minLon: eg. '-90'
## $3: size: eg. '1'
function grid(){
echo 'grid' "$1" "$2" "($1+$3)" "($2+$3)";

sqlite3 --init 'init.sql' "$DB" <<SQL
INSERT INTO grid (id, place_id, geom)
SELECT NULL, id, CastToMultiPolygon(Intersection(geom, BuildMbr($1, $2, ($1+$3), ($2+$3), 4326))) as piece
FROM place
WHERE id IN (
  SELECT pkid FROM idx_place_geom
  WHERE pkid MATCH RTreeIntersects( $1, $2, $1+$3, $2+$3 )
)
AND piece IS NOT NULL;
SQL
}

# grid_all - create multiple grid sections
## $1: minLat: eg. '-180'
## $2: minLon: eg. '-90'
## $3: maxLat: eg. '179'
## $4: maxLon: eg. '89'
## $5: size: eg. '1'
function grid_all(){
  for y in $(seq "$2" "$5" "$4"); do
    for x in $(seq "$1" "$5" "$3"); do
      grid "$x" "$y" "$5";
    done
  done
}

## pip - point-in-polygon test
## $1: longitude: eg. '151.5942043'
## $2: latitude: eg. '-33.013441'
function pip(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
.timer on

SELECT * FROM place
WHERE within( MakePoint( $1, $2, 4326 ), geom );
SQL
}

## pipfast - point-in-polygon test optimized with an rtree index
## $1: longitude: eg. '151.5942043'
## $2: latitude: eg. '-33.013441'
function pipfast(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
.timer on

SELECT * FROM place
WHERE id IN (
  SELECT pkid FROM idx_place_geom
  WHERE pkid MATCH RTreeIntersects( $1, $2, $1, $2 )
)
AND within( MakePoint( $1, $2, 4326 ), geom );
SQL
}

## pipturbo - point-in-polygon test optimized using grid index
## $1: longitude: eg. '151.5942043'
## $2: latitude: eg. '-33.013441'
function pipturbo(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
.timer on

SELECT * FROM place
WHERE id IN (
  SELECT place_id FROM grid
  WHERE id IN (
    SELECT pkid FROM idx_grid_geom
    WHERE pkid MATCH RTreeIntersects( $1, $2, $1, $2 )
  )
  AND Intersects( grid.geom, MakePoint( $1, $2, 4326 ) )
);
SQL
}

## contains - find all child polygons contained by: $1
## $1: id: eg. '2316741'
function contains(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
SELECT * FROM place
WHERE id IN (
  SELECT pkid FROM idx_place_geom
  WHERE xmin>=( SELECT xmin FROM idx_place_geom WHERE pkid=$1 )
    AND xmax<=( SELECT xmax FROM idx_place_geom WHERE pkid=$1 )
    AND ymin>=( SELECT ymin FROM idx_place_geom WHERE pkid=$1 )
    AND ymax<=( SELECT ymax FROM idx_place_geom WHERE pkid=$1 )
  AND id != $1
)
AND CONTAINS(( SELECT geom FROM place WHERE id=$1 ), geom );
SQL
}

## within - find all parent polygons containing id: $1
## $1: id: eg. '2316741'
function within(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
SELECT * FROM place
WHERE id IN (
  SELECT pkid FROM idx_place_geom
  WHERE xmin<=( SELECT xmin FROM idx_place_geom WHERE pkid=$1 )
    AND xmax>=( SELECT xmax FROM idx_place_geom WHERE pkid=$1 )
    AND ymin<=( SELECT ymin FROM idx_place_geom WHERE pkid=$1 )
    AND ymax>=( SELECT ymax FROM idx_place_geom WHERE pkid=$1 )
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
  MAINDB="${DB}";
  DB="${1}";

  init; # init new db

  sqlite3 ${MAINDB} <<SQL
ATTACH DATABASE '$1' AS 'extract';
WITH base AS ( SELECT * FROM place JOIN idx_place_geom ON place.id = idx_place_geom.pkid WHERE place.id=$2 )
INSERT INTO extract.place SELECT * FROM main.place
WHERE id IN (
  SELECT pkid FROM idx_place_geom WHERE
  xmin>=( SELECT xmin FROM base ) AND
  xmax<=( SELECT xmax FROM base ) AND
  ymin>=( SELECT ymin FROM base ) AND
  ymax<=( SELECT ymax FROM base )
)
AND (
  id=$2 OR
  CONTAINS(( SELECT geom FROM base ), geom )
);
SQL
}

# copy all records enveloping point
# time sqlite3 --init 'init.sql' $"$OUTDIR/wof.sqlite3" <<SQL
# .timer on
#
# ATTACH DATABASE '/media/flash/wof.sqlite3.backup' as 'source';
#
# INSERT INTO main.place SELECT * FROM source.place
# WHERE id IN (
#   SELECT pkid FROM source.idx_place_geom
#   WHERE xmin<=$LON
#     AND xmax>=$LON
#     AND ymin<=$LAT
#     AND ymax>=$LAT
# );
#
# DETACH DATABASE 'source';

# cli runner
case "$1" in
'init') init;;
'json') json "$2" "$3";;
'index') index "$2";;
'index_all') index_all "$2";;
'fixify') fixify;;
'simplify') simplify "$2";;
'grid') grid "$2" "$3";;
'grid_all') grid_all "$2" "$3" "$4" "$5" "$6";;
'pip') pip "$2" "$3";;
'pipfast') pipfast "$2" "$3";;
'pipturbo') pipturbo "$2" "$3";;
'contains') contains "$2";;
'within') within "$2";;
'extract') extract "$2" "$3";;
*)
  BR='-------------------------------------------------------------------------'
  printf "%s\n" $BR
  grep -C0 --group-separator=$BR '##' $0 | grep -v 'grep' | sed 's/##//g';
  ;;
esac
