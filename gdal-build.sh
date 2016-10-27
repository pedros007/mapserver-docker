#!/bin/bash -e

NUMCPU=$(grep --count ^processor /proc/cpuinfo)

curl http://download.osgeo.org/gdal/2.1.2/gdal-2.1.2.tar.gz | tar zxv -C /tmp
cd /tmp/gdal-2.1.2

./configure \
    --prefix=/usr \
    --with-threads \
    --with-hide-internal-symbols=yes \
    --with-rename-internal-libtiff-symbols=yes \
    --with-rename-internal-libgeotiff-symbols=yes \
    --with-libtiff=internal \
    --with-geotiff=internal \
    --with-geos \
    --with-pg \
    --with-curl \
    --with-static-proj4=yes \
    --with-ecw=no \
    --with-grass=no \
    --with-hdf5=no \
    --with-java=no \
    --with-mrsid=no \
    --with-perl=no \
    --with-python=no \
    --with-webp=no \
    --with-xerces=no

make -j ${NUMCPU}
make install
