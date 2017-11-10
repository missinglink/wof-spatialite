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
time docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' init

echo '-- import wof --'
time docker run -e 'DB=/out/wof.sqlite' -v "${INDIR}:/in" -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' index_all '/in'

echo '-- repair geometries --'
time docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' fixify

# echo '-- simplify geometries --'
# time docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' simplify '0.1'

echo '-- create tiles --'
time docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' tile_init
time docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' tile_all "${LEVEL}" "${COMPLEXITY}"

echo '-- run point-in-polygon tests --'
docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' pip "${LON}" "${LAT}"
docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' pipfast "${LON}" "${LAT}"
docker run -e 'DB=/out/wof.sqlite' -v "${OUTDIR}:/out" 'missinglink/wof-spatialite' piptile "${LON}" "${LAT}"
