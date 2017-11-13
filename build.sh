#!/bin/bash

# build image
docker build -t 'missinglink/wof-spatialite' .

# clean up
INDIR=${INDIR:-'/data/whosonfirst-data/data'}
OUTDIR=${OUTDIR:-'/data/wof-spatialite'}
mkdir -p "${OUTDIR}"
rm -rf "${OUTDIR}/wof.sqlite"

# tessellation options
LEVEL=50
COMPLEXITY=100

# default coords
LON=${LON:-'50'}
LAT=${LAT:-'1'}

echo '-- init database --'
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' init

echo '-- import wof --'
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${INDIR}:/in" -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' index_all '/in'

echo '-- repair geometries --'
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' fixify

# echo '-- simplify geometries --'
# docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' simplify '0.1'

echo '-- create tiles --'
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' tile_init
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' tile_all "${LEVEL}" "${COMPLEXITY}"

echo '-- run point-in-polygon tests --'
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' pip "${LON}" "${LAT}"
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' pipfast "${LON}" "${LAT}"
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' piptile "${LON}" "${LAT}"

echo '-- run server --'
docker run --rm -it -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" -p '8080:8080' 'missinglink/wof-spatialite' server
