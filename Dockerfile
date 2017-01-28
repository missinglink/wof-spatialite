# base image
FROM missinglink/gis
ENV DEBIAN_FRONTEND noninteractive
ENV LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib;

# dependencies
# RUN apt-get update && apt-get install -y python sqlite3

# create app directory
RUN mkdir -p /usr/src/repos/wof-spatialite
WORKDIR /usr/src/repos/wof-spatialite

# copy source code
COPY ./spatialite.sh /usr/src/repos/wof-spatialite

# data dirs
VOLUME "/in"
VOLUME "/out"
ENV INDIR "/in"
ENV OUTDIR "/out"

# set entry point
WORKDIR /usr/src/repos/wof-spatialite
ENTRYPOINT [ "./spatialite.sh" ]
