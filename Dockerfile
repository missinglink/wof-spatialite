# base image
FROM missinglink/gis
ENV DEBIAN_FRONTEND noninteractive
ENV LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib;

# dependencies
# RUN apt-get update && apt-get install -y python sqlite3

# create app directory
RUN mkdir -p /usr/src/repos/wof-spatialite
WORKDIR /usr/src/repos/wof-spatialite

# data dirs
VOLUME "/in"
VOLUME "/out"
ENV INDIR "/in"
ENV OUTDIR "/out"

# set entry point
WORKDIR /usr/src/repos/wof-spatialite
ENTRYPOINT [ "./spatialite.sh" ]

# install golang
ENV GOPATH=/usr/src/.go
RUN wget -O- https://redirector.gvt1.com/edgedl/go/go1.9.2.linux-amd64.tar.gz | tar -C /usr/local -xzf -
RUN mkdir -p "${GOPATH}"
ENV PATH="${PATH}:/usr/local/go/bin:${GOPATH}/bin"

# golang modules
RUN go get github.com/shaxbee/go-spatialite

# set up server
COPY ./server.go /usr/src/repos/wof-spatialite
RUN go build server.go

# copy source code
COPY ./init.sql /usr/src/repos/wof-spatialite
COPY ./spatialite.sh /usr/src/repos/wof-spatialite
