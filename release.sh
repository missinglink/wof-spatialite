#!/bin/bash
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd );

# tessellation options
LEVEL=50
COMPLEXITY=100

# bundle dir
TODAY=`date +%Y-%m-%d`
DB_DIR="/data/build/${TODAY}"
BUNDLE_DIR="${DB_DIR}/bundles"

# create a bundle index file if one doesn't already exist
[ -f "${DIR}/bundles.txt" ] ||\
  curl -s 'https://whosonfirst.mapzen.com/bundles/index.txt' |\
    grep -Po 'wof-\K(.*)(?=-latest-bundle\.tar\.bz)' |\
      grep -vP 'address|building|venue|constituency|intersection' > "${DIR}/bundles.txt"

# Load bundles list into array
readarray -t BUNDLES < "${DIR}/bundles.txt"

# ensure dirs exists
mkdir -p "${BUNDLE_DIR}"
mkdir -p "${DB_DIR}"

function build(){
  echo "----- bundle ${1} -----"

  # download and simplify bundle
  if [ ! -d "${BUNDLE_DIR}/${1}" ]; then
    echo '-- create bundle dir --'
    mkdir -p "${BUNDLE_DIR}/${1}"

    echo '-- download bundle --'
    docker run --rm -v "${BUNDLE_DIR}/${1}:/in" 'missinglink/wof-spatialite' bundle_download "${1}" /in

    echo '-- remove empty (point) geometries'
    docker run --rm -v "${BUNDLE_DIR}/${1}:/in" 'missinglink/wof-spatialite' remove_point_geoms /in

    echo '-- simplify geometries --'
    docker run --rm -v "${BUNDLE_DIR}/${1}:/in" 'missinglink/wof-spatialite' ogr_simplify_dir /in 0.0001
  fi

  # create database file
  if [ ! -f "${DB_DIR}/${1}.sqlite" ]; then
    echo '-- init database --'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' init

    echo '-- import wof --'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" -v "${BUNDLE_DIR}/${1}:/in" 'missinglink/wof-spatialite' index_all '/in'

    echo '-- repair geometries --'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' fixify

    echo '-- create tiles --'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' tile_init
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' tile_all "${LEVEL}" "${COMPLEXITY}"

    echo '-- vacuum --'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' sql 'VACUUM'

    echo '-- fix timestamps --'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' sql 'UPDATE spatialite_history SET timestamp="0000-01-01T00:00:00.000Z"'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' sql 'UPDATE geometry_columns_time SET last_insert="0000-01-01T00:00:00.000Z"'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' sql 'UPDATE geometry_columns_time SET last_update="0000-01-01T00:00:00.000Z"'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' sql 'UPDATE geometry_columns_time SET last_delete="0000-01-01T00:00:00.000Z"'

    # remove empty databases
    docker run --rm -v "${DB_DIR}:/out" 'ubuntu:16.04' find "/out/${1}.sqlite" -maxdepth 1 -size -5615617c -delete

    echo '-- remove processed files --'
    docker run --rm -v "${BUNDLE_DIR}:/in" 'ubuntu:16.04' rm -rf "/in/${1}"
  fi
}

# execute for each bundle (in parallel)
for BUNDLE_NAME in "${BUNDLES[@]}"; do
  build "${BUNDLE_NAME}" &
done
wait

# merge all databases in to a single db
if [ ! -f "${DB_DIR}/wof.sqlite" ]; then
  docker run --rm -e "DB=/out/wof.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' init
  for BUNDLE_NAME in "${BUNDLES[@]}"; do
    echo "----- merge ${BUNDLE_NAME} -----"
    docker run --rm -e "DB=/out/wof.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' merge "/out/${BUNDLE_NAME}.sqlite"
  done
fi

echo '-- remove bundle dir --'
rm -rf "${BUNDLE_DIR}"

# compress all databases
if type pigz >/dev/null
  then find "${DB_DIR}" -type f -name '*.sqlite' | xargs pigz -n -T --best
  else find "${DB_DIR}" -type f -name '*.sqlite' | xargs gzip -n --best
fi
