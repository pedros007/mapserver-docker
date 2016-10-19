FROM debian:jessie
MAINTAINER Peter Schmitt "pschmitt@gmail.com"

# Inspired by
#  - https://hub.docker.com/r/nopz/mapserver/
#  - https://github.com/srounet/docker-mapserver

RUN apt-get update && apt-get upgrade -y
RUN apt-get install -y \
    ca-certificates \
    build-essential cmake curl libcurl4-gnutls-dev libssl-dev openssl wget \
    shapelib libproj-dev libproj0 proj-data libgeos-3.4.2 libgeos-c1 libgeos-dev \
    libxml2-dev libpng-dev zlib1g-dev libtiff5 libjpeg-dev libtiff-dev postgis libpq-dev \
    libfcgi-dev libfribidi-dev libfreetype6-dev libharfbuzz-dev \
    make \
    nginx \
    supervisor \
    -y --no-install-recommends && rm -rf /var/lib/apt/lists/*

COPY gdal-build.sh /tmp/gdal-build.sh
RUN sh /tmp/gdal-build.sh

COPY mapserver-build.sh /tmp/mapserver-build.sh
RUN sh /tmp/mapserver-build.sh

RUN rm /etc/nginx/sites-enabled/default
ADD etc /etc

RUN mkdir -p /usr/src
COPY mapfiles /usr/src/mapfiles

EXPOSE 80
CMD sh -c "/usr/bin/supervisord"
