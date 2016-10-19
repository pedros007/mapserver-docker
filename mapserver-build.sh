#!/bin/bash -e

NUMCPU=$(grep --count ^processor /proc/cpuinfo)


curl http://download.osgeo.org/mapserver/mapserver-7.0.2.tar.gz | tar zxv -C /tmp
mkdir -p /tmp/mapserver-7.0.2/build
cd /tmp/mapserver-7.0.2/build

cmake .. -DWITH_GDAL=1 -DWITH_CURL=1 -DWITH_CAIRO=0 -DWITH_GIF=0

make -j ${NUMCPU}
make install
