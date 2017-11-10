#!/bin/bash
DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

# http://www.gaia-gis.it/spatialite-3.0.0-BETA1/WorldBorders.pdf
# north america: 102191575

# download some example files
[ -d "${DIR}/data" ] || mkdir "${DIR}/data"
[ -f "${DIR}/data/102191575.geojson" ] || curl -so "${DIR}/data/102191575.geojson" \
  'https://whosonfirst.mapzen.com/data/102/191/575/102191575.geojson'

# in/out
INDIR="${DIR}/data"
OUTDIR="${DIR}"

# usa test coords
LON=${LON:-'-73.990373'}
LAT=${LAT:-'40.74421'}

# do build
. build.sh
