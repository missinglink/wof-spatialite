#!/bin/bash
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd );

# tessellation options
LEVEL=30
COMPLEXITY=100

# bundle dir
TODAY=`date +%Y-%m-%d`
DB_DIR="/data/build/${TODAY}"
BUNDLE_DIR="${DB_DIR}/bundles"

BUNDLE_HOST='https://dist.whosonfirst.org/bundles'
# BUNDLE_HOST='http://missinglink.mapzen.s3.amazonaws.com/whosonfirst.mapzen.com/bundles'

# create a bundle index file if one doesn't already exist
[ -f "${DIR}/bundles.txt" ] ||\
  curl -s "${BUNDLE_HOST}/index.txt" |\
    grep -Po 'wof-\K(.*)(?=-latest-bundle\.tar\.bz2)' |\
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
    docker run --rm -v "${BUNDLE_DIR}/${1}:/in" -e "BUNDLE_HOST=${BUNDLE_HOST}" 'missinglink/wof-spatialite' bundle_download "${1}" /in

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

    echo '-- remove empty databases --'
    docker run --rm -e "DB=/out/${1}.sqlite" -v "${DB_DIR}:/out" --entrypoint '/bin/bash' -e 'SQL=SELECT COUNT(*) FROM place' 'missinglink/wof-spatialite' -c 'if [[ $(sqlite3 ${DB} "${SQL}") -eq 0 ]]; then rm ${DB}; fi'

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
    if [ -f "${DB_DIR}/${BUNDLE_NAME}.sqlite" ]; then
      echo "----- merge ${BUNDLE_NAME} -----"
      docker run --rm -e "DB=/out/wof.sqlite" -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' merge "/out/${BUNDLE_NAME}.sqlite"
    fi
  done
fi

echo '-- remove bundle dir --'
rm -rf "${BUNDLE_DIR}"

echo '-- generate jsonl export --'
docker run --rm -e 'DB=/out/wof.sqlite' -v "${DB_DIR}:/out" 'missinglink/wof-spatialite' jsonlines | gzip > "${DB_DIR}/wof.polys.jsonl.gz"

# compress all databases
if type pigz >/dev/null
  then find "${DB_DIR}" -type f -name '*.sqlite' | xargs pigz -n -T --best
  else find "${DB_DIR}" -type f -name '*.sqlite' | xargs gzip -n --best
fi

# upload to s3 (only if over 2GB)
find "${DB_DIR}/wof.sqlite.gz" -maxdepth 1 -size +2G | while read file; do
  echo "----- upload wof.sqlite.gz to s3 -----"
  aws s3 cp "${file}" s3://missinglink.geo/ --acl public-read
done

# upload to s3 (only if over 800M)
find "${DB_DIR}/wof.polys.jsonl.gz" -maxdepth 1 -size +800M | while read file; do
  echo "----- upload wof.polys.jsonl.gz to s3 -----"
  aws s3 cp "${file}" s3://missinglink.geo/ --acl public-read
done
