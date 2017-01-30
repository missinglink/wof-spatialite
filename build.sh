#!/bin/bash

# build image
docker build -t 'missinglink/wof-spatialite' .;

# clean up
INDIR=${INDIR:-'/data/whosonfirst-data/data'};
OUTDIR=${OUTDIR:-'/data/wof-spatialite'};
mkdir -p "$OUTDIR";
rm -rf "$OUTDIR/wof.sqlite3";

# grid extent
GRID_SIZE=${GRID_SIZE:-'20'}
GRID_XMIN=${GRID_XMIN:-'-180'}
GRID_YMIN=${GRID_YMIN:-'-90'}
GRID_XMAX=${GRID_XMAX:-`expr 180 - $GRID_SIZE`}
GRID_YMAX=${GRID_YMAX:-`expr  90 - $GRID_SIZE`}

# test coords
LON=${LON:-'-73.990373'}
LAT=${LAT:-'40.74421'}

echo '-- init database --';
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' init;

echo '-- import wof --';
time docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' index_all '/in';

echo '-- repair geometries --';
time docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' fixify;

echo '-- simplify geometries --';
time docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' simplify '0.1';

echo '-- create grid --';
time docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' grid_all "$GRID_XMIN" "$GRID_YMIN" "$GRID_XMAX" "$GRID_YMAX" "$GRID_SIZE";

echo '-- run point-in-polygon tests --';
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' pip "$LON" "$LAT";
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' pipfast "$LON" "$LAT";
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' pipturbo "$LON" "$LAT";
