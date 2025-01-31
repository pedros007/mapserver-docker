FROM ghcr.io/osgeo/gdal:ubuntu-full-3.10.1

RUN \
# AWS CLI can be helpful with debugging
    curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "/tmp/awscliv2.zip" && \
    unzip -q -d /tmp /tmp/awscliv2.zip && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws && \
# Use package manager to install dependencies
    apt-get update && apt-get upgrade -y && \
# don't allow tzdata to prompt the user for a setting.
    env DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends \
    nginx \
    supervisor \
# Might be helpful for debugging
    emacs-nox \
    less \
    postgresql-client \
    procps \
    strace \
# MapServer dependencies
    build-essential \
    cmake \
    libcurl4-gnutls-dev \
    libfcgi0ldbl \
    libfcgi-dev \
    libgeos-dev \
    libpq-dev \
    libxml2 \
    libxml2-dev \
    libpng-dev \
    zlib1g \
    zlib1g-dev \
    libjpeg-turbo8 \
    libjpeg-turbo8-dev \
    libgif-dev \
    libcairo2 \
    libcairo2-dev \
    librsvg2-2 \
    librsvg2-dev \
    libfribidi0 \
    libfribidi-dev \
    libfreetype6 \
    libfreetype6-dev \
    libharfbuzz0b \
    libharfbuzz-dev \
    protobuf-c-compiler \
    libprotobuf-c-dev && \
# Build MapServer using libproj from the GDAL Docker
    curl https://download.osgeo.org/mapserver/mapserver-8.4.0.tar.gz | tar zx -C /tmp && \
    mkdir /tmp/mapserver-8.4.0/build && \
    cd /tmp/mapserver-8.4.0/build && \
    cmake .. \
      -DWITH_CURL=1 \
      -DWITH_CAIRO=1 \
      -DWITH_RSVG=1 \
      -DWITH_CLIENT_WMS=1 \
      -DWITH_CLIENT_WFS=1 \
      -DPROJ_LIBRARY=/usr/local/lib/libinternalproj.so  \
      -DCMAKE_C_FLAGS=-DPROJ_RENAME_SYMBOLS && \
    make -j $(grep --count ^processor /proc/cpuinfo) && \
    make install && \
# Cleanup
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

ADD etc /etc
RUN ln -sf /etc/nginx/sites-available/mapserver_proxy.conf /etc/nginx/sites-enabled/default
COPY mapfiles /usr/src/mapfiles

EXPOSE 80

ENV MAPSERVER_CONFIG_FILE=/etc/mapserver/mapserver.conf

CMD /usr/bin/supervisord
