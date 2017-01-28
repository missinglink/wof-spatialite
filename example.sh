#!/bin/bash

# http://www.gaia-gis.it/spatialite-3.0.0-BETA1/WorldBorders.pdf
# north america: 102191575

# in/out
INDIR='/data/whosonfirst-data/data/102/191/575';
OUTDIR='/tmp/north_america';

# grid extent
GRID_XMIN='-75'; GRID_XMAX='-75';
GRID_YMIN='35'; GRID_YMAX='35';
GRID_SIZE='10';

# do build
. build.sh;
