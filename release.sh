#!/bin/bash

# tessellation options
LEVEL=50
COMPLEXITY=100

# bundle dir
TODAY=`date +%Y-%m-%d`
DB_DIR="/data/build/${TODAY}"
BUNDLE_DIR="${DB_DIR}/bundles"

# placetypes
PLACETYPES=( 'neighbourhood' 'macrohood' 'borough' 'locality' 'localadmin' 'county' 'macrocounty' 'region'
  'macroregion' 'disputed' 'dependency' 'country' 'empire' 'marinearea' 'continent' 'ocean' )

# ensure dirs exists
mkdir -p "${BUNDLE_DIR}"
mkdir -p "${DB_DIR}"

function build(){
  echo "----- placetype ${1} -----"

  # download and simplify bundle
  if [ ! -d "${BUNDLE_DIR}/${1}" ]; then
    echo '-- create bundle dir --'
    mkdir -p "${BUNDLE_DIR}/${1}"

    echo '-- download bundle --'
    docker run --rm -v "${BUNDLE_DIR}/${1}:/in" 'missinglink/wof-spatialite' bundle_download "${1}" /in

    echo '-- simplify geometries --'
    docker run --rm -v "${BUNDLE_DIR}/${1}:/in" 'missinglink/wof-spatialite' ogr_simplify_dir /in 0.0001

    echo '-- remove processed files --'
    rm -rf "${BUNDLE_DIR}/${1}"
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
  fi
}

# execute for each placetype (in parallel)
for PT in "${PLACETYPES[@]}"; do
  build "${PT}" &
done
wait

# merge all databases in to a single db
if [ ! -f "${DB_DIR}/wof.sqlite" ]; then
  docker run --rm -e "DB=/out/wof.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' init
  for PT in "${PLACETYPES[@]}"; do
    echo "----- merge ${PT} -----"
    docker run --rm -e "DB=/out/wof.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' merge "/out/${PT}.sqlite"
  done
fi

echo '-- remove bundle dir --'
rm -rf "${BUNDLE_DIR}"
