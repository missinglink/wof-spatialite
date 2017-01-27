#!/bin/bash

# http://www.gaia-gis.it/spatialite-3.0.0-BETA1/WorldBorders.pdf
# north america: 102191575

# in/out
INDIR='/data/whosonfirst-data/data/102/191/575';
OUTDIR='/tmp/north_america';

# grid extent
XMIN='-75'; XMAX='-70';
YMIN='38'; YMAX='43';

# do build
. build.sh;
