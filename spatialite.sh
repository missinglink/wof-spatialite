#!/bin/bash
# set -e;
export LC_ALL=en_US.UTF-8;

# location of sqlite database file
DB=${DB:-"wof.sqlite"};

## init - set up a new database
function init(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
.output /dev/null
SELECT InitSpatialMetaData(1);
.output stdout

CREATE TABLE IF NOT EXISTS place (
  id INTEGER NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  layer TEXT
);
CREATE INDEX IF NOT EXISTS layer_idx ON place(layer);

.output /dev/null
SELECT AddGeometryColumn('place', 'geom', 4326, 'GEOMETRY', 'XY', 1);
SELECT CreateSpatialIndex('place', 'geom');
.output stdout

CREATE TABLE IF NOT EXISTS properties (
  place_id INTEGER PRIMARY KEY NOT NULL,
  blob TEXT,
  CONSTRAINT fk_place FOREIGN KEY (place_id) REFERENCES place(id)
);

CREATE TABLE tiles (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 wofid INTEGER NOT NULL,
 level INTEGER NOT NULL,
 complexity INTEGER
);
CREATE INDEX IF NOT EXISTS wofid_idx ON tiles(wofid);
CREATE INDEX IF NOT EXISTS level_idx ON tiles(level);

.output /dev/null
SELECT AddGeometryColumn('tiles', 'geom', 4326, 'MULTIPOLYGON', 'XY');
SELECT CreateSpatialIndex('tiles', 'geom');
.output stdout
SQL

# set file permissions
chmod 0666 "$DB";
}

## merge - merge tables from an external database in to the main db
## $1: external db path: eg. '/tmp/external.sqlite'
function merge(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
ATTACH DATABASE '$1' AS ext;
INSERT INTO main.place( id, name, layer, geom ) SELECT id, name, layer, geom FROM ext.place;
INSERT INTO main.properties( place_id, blob ) SELECT place_id, blob FROM ext.properties;
INSERT INTO main.tiles(id, wofid, level, complexity, geom) SELECT NULL, wofid, level, complexity, geom FROM ext.tiles;
DETACH DATABASE ext;
SQL
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

## sql - run an arbitrary sql script
## $1: sql: eg. 'VACUUM'
function sql(){
  echo "${1};" | sqlite3 --init 'init.sql' ${DB}
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
  SELECT
    json_extract(json, '$.properties."wof:id"'),
    json_extract(json, '$.properties."wof:name"'),
    json_extract(json, '$.properties."wof:placetype"'),
    SetSRID( GeomFromGeoJSON( json_extract(json, '$.geometry') ), 4326 )
  FROM file
  WHERE CAST(IFNULL(json_extract(json, '$.properties."mz:is_current"'), -1) AS text) != '0'
  LIMIT 1;

INSERT INTO properties ( place_id, blob )
  SELECT
    json_extract(json, '$.properties."wof:id"'),
    json_extract(json, '$.properties')
  FROM file
  WHERE CAST(IFNULL(json_extract(json, '$.properties."mz:is_current"'), -1) AS text) != '0'
  LIMIT 1;

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

## tile_init - copy records from the place table to the tiles table
function tile_init(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
SELECT 'Initial Load';
INSERT INTO tiles (id, wofid, level, geom)
  SELECT NULL, id, 0, CastToMultiPolygon(geom) FROM place;

UPDATE tiles
SET complexity = ST_NPoints( geom )
WHERE complexity IS NULL;
SQL
}

## tile - reduce records in tiles table in to quarters
## $1: level - level to target: eg. '0'
## $2: complexity - maximum number of points allowed per level: eg. '200'
function tile(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
SELECT
  printf('Level $1 (%d/%d)',
  (SELECT COUNT(*) FROM tiles WHERE level = $1 AND complexity > $2),
  (SELECT COUNT(*) FROM tiles WHERE level = $1)
);

-- SELECT 'Top Left';
INSERT INTO tiles (id, wofid, level, geom)
  SELECT NULL, wofid, level+1, CastToMultiPolygon( Intersection( geom, BuildMbr(
    MbrMinX( geom ),
    MbrMinY( geom ),
    MbrMinX( geom ) + (( MbrMaxX( geom ) - MbrMinX( geom )) / 2),
    MbrMinY( geom ) + (( MbrMaxY( geom ) - MbrMinY( geom )) / 2)
  ))) AS quad
  FROM tiles
  WHERE level = $1
  AND complexity > $2
  AND quad IS NOT NULL;

-- SELECT 'Top Right';
INSERT INTO tiles (id, wofid, level, geom)
  SELECT NULL, wofid, level+1, CastToMultiPolygon( Intersection( geom, BuildMbr(
    MbrMinX( geom ) + (( MbrMaxX( geom ) - MbrMinX( geom )) / 2),
    MbrMinY( geom ),
    MbrMaxX( geom ),
    MbrMinY( geom ) + (( MbrMaxY( geom ) - MbrMinY( geom )) / 2)
  ))) AS quad
  FROM tiles
  WHERE level = $1
  AND complexity > $2
  AND quad IS NOT NULL;

-- SELECT 'Bottom Left';
INSERT INTO tiles (id, wofid, level, geom)
  SELECT NULL, wofid, level+1, CastToMultiPolygon( Intersection( geom, BuildMbr(
    MbrMinX( geom ),
    MbrMinY( geom ) + (( MbrMaxY( geom ) - MbrMinY( geom )) / 2),
    MbrMinX( geom ) + (( MbrMaxX( geom ) - MbrMinX( geom )) / 2),
    MbrMaxY( geom )
  ))) AS quad
  FROM tiles
  WHERE level = $1
  AND complexity > $2
  AND quad IS NOT NULL;

-- SELECT 'Bottom Right';
INSERT INTO tiles (id, wofid, level, geom)
  SELECT NULL, wofid, level+1, CastToMultiPolygon( Intersection( geom, BuildMbr(
    MbrMinX( geom ) + (( MbrMaxX( geom ) - MbrMinX( geom )) / 2),
    MbrMinY( geom ) + (( MbrMaxY( geom ) - MbrMinY( geom )) / 2),
    MbrMaxX( geom ),
    MbrMaxY( geom )
  ))) AS quad
  FROM tiles
  WHERE level = $1
  AND complexity > $2
  AND quad IS NOT NULL;

-- SELECT 'Delete rows';
DELETE FROM tiles
WHERE level = $1
AND complexity > $2;

UPDATE tiles
SET complexity = ST_NPoints( geom )
WHERE complexity IS NULL;
SQL
}

## tile_all - recursively cut tiles in to quads
## $1: maxlevel - maximum level to target: eg. '50'
## $2: complexity - maximum number of points allowed per level: eg. '200'
function tile_all(){
  for i in $(seq 0 "$1"); do
    tile $i $2;
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

## piptile - point-in-polygon test optimized using tile index
## $1: longitude: eg. '151.5942043'
## $2: latitude: eg. '-33.013441'
function piptile(){
  sqlite3 --init 'init.sql' ${DB} <<SQL
.timer on

SELECT * FROM place
WHERE id IN (
  SELECT wofid
  FROM tiles
  WHERE id IN (
    SELECT pkid FROM idx_tiles_geom
    WHERE pkid MATCH RTreeIntersects( $1, $2, $1, $2 )
  )
  AND INTERSECTS( tiles.geom, MakePoint( $1, $2, 4326 ) )
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

## server - start the HTTP server
## $1: db name: eg. 'wof.sqlite'

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


## bundle_download - copy database records within id: $2
## $1: bundle name: eg. 'country'
## $2: output dir: eg. '/out/country'
function bundle_download {
  BUNDLE_HOST=${BUNDLE_HOST:-'https://whosonfirst.mapzen.com/bundles'};
  BUNDLE="wof-${1}-latest-bundle"; COMPRESSED="${BUNDLE}.tar.bz2";
  echo "download ${COMPRESSED}";
  [ -d "${2}" ] || mkdir -p "${2}"
  curl -so "/tmp/${COMPRESSED}" "${BUNDLE_HOST}/${COMPRESSED}"
  ls -lah "/tmp/${COMPRESSED}"
  tar -xj --strip-components='1' --exclude='README.txt' -C "${2}" -f "/tmp/${COMPRESSED}"
  rm "/tmp/${COMPRESSED}"
}

## ogr_simplify - use ogr2ogr to simplify geometry
## $1: geojson file name: eg. '/data/1.geojson'
## $2: Douglas-Peuker tolerance: eg. '0.0001'
function ogr_simplify {
  echo "ogr_simplify: ${1} ${2}";
  ogr2ogr -f GeoJSON -lco 'COORDINATE_PRECISION=7' '/vsistdout/' "${1}" -simplify "${2}" | jq -c -M '.features[0]' > "${1}.tmp"
  if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo "simplification failed: ${1}"
    rm -f "${1}.tmp"
  else
    mv "${1}.tmp" "${1}"
  fi
}

# export ogr_simplify function
export -f ogr_simplify

## ogr_simplify_dir - use ogr2ogr to simplify a directory of geometries
## $1: geojson directory name: eg. '/data'
## $2: Douglas-Peuker tolerance: eg. '0.0001'
function ogr_simplify_dir(){
  # simplify data (skip files under 20kb)
  find "${1}" -type f -size +20k -name '*.geojson' |\
    sed -e "s/$/ ${2}/" |\
      parallel --no-notice --line-buffer --colsep ' ' ogr_simplify
}

## remove_point_geoms - remove all geojson files with a reported area of 0.0
## $1: geojson directory name: eg. '/data'
function remove_point_geoms(){
  find "${1}" -type f -name '*.geojson' |\
    while IFS= read -r FILENAME; do
      grep --files-with-match '"geom:area":[\s|"]*0[\.0]\+[\s|"]*,' "${FILENAME}" || true;
    done |\
      xargs --no-run-if-empty rm
}

# cli runner
case "$1" in
'init') init;;
'merge') merge "$2";;
'json') json "$2" "$3";;
'sql') sql "$2";;
'index') index "$2";;
'index_all') index_all "$2";;
'fixify') fixify;;
'simplify') simplify "$2";;
'tile_init') tile_init;;
'tile') tile "$2" "$3";;
'tile_all') tile_all "$2" "$3";;
'pip') pip "$2" "$3";;
'pipfast') pipfast "$2" "$3";;
'piptile') piptile "$2" "$3";;
'contains') contains "$2";;
'within') within "$2";;
'extract') extract "$2" "$3";;
'server') ./server "${DB}";;
'bundle_download') bundle_download "$2" "$3";;
'ogr_simplify') ogr_simplify "$2" "$3";;
'ogr_simplify_dir') ogr_simplify_dir "$2" "$3";;
'remove_point_geoms') remove_point_geoms "$2";;
*)
  BR='-------------------------------------------------------------------------'
  printf "%s\n" $BR
  grep -C0 --group-separator=$BR '##' $0 | grep -v 'grep' | sed 's/##//g';
  ;;
esac
