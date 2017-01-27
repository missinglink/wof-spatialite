#!/bin/bash

# build image
docker build -t 'missinglink/wof-spatialite' .;

# clean up
INDIR=${INDIR:-'/data/whosonfirst-data/data'};
OUTDIR=${OUTDIR:-'/data/wof-spatialite'};
mkdir -p "$OUTDIR";
rm -rf "$OUTDIR/wof.sqlite3";

# grid extent
XMIN=${XMIN:-'-180'}
YMIN=${YMIN:-'-90'}
XMAX=${XMAX:-'179'}
YMAX=${YMAX:-'89'}

# test coords
LON=${LON:-'-73.990373'}
LAT=${LAT:-'40.74421'}

# init db
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' init;

# import wof
time docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' index_all '/in';

# create grid
time docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' grid_all "$XMIN" "$YMIN" "$XMAX" "$YMAX";

# test
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' pip "$LON" "$LAT";
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' pipfast "$LON" "$LAT";
docker run -i -v "$INDIR:/in" -v "$OUTDIR:/out" 'missinglink/wof-spatialite' pipturbo "$LON" "$LAT";
