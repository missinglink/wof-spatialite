
docker container to load [whosonfirst](https://github.com/whosonfirst-data/whosonfirst-data) in to spatialite.

#### quick start

```bash
./example.sh
```

#### how can run this container?

first you need to fetch the whosonfirst data and put it in a directory on disk, the directory should have one or more subdirectories containing the .geojson files you wish to import:

```bash
$ ls /tmp/inputdir

data  meta
```

create another directory where you would like to store the output sqlite database:

```bash
$ mkdir -p /tmp/outputdir
```

initialize the database:

```bash
$ docker run -e 'DB=/out/wof.sqlite' -v '/tmp/outputdir:/out' 'missinglink/wof-spatialite' init
```

make sure that worked:

```bash
$ ls /tmp/outputdir

wof.sqlite
```

import all the things:

```bash
$ docker run -e 'DB=/out/wof.sqlite' -v '/tmp/inputdir:/in' -v '/tmp/outputdir:/out' 'missinglink/wof-spatialite' index_all '/in'
```

see ./spatialite.sh in this repo for a full list of supported commands

#### how can I rebuild the image?

clone this repository, cd in the directory and run:

```bash
docker build -t 'missinglink/wof-spatialite' .
```
