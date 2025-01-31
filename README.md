Abstract
========

Mapserver >= 7.0 can render imagery stored in an AWS S3 bucket using a
file handler provided by GDAL >= 2.1. Two file handlers are available
`/vsicurl/` and `/vsis3/`. These handlers make use of [HTTP GET range
requests](https://tools.ietf.org/html/rfc7233) to transfer the minimum
data required.  When images are properly prepared, access via the vsi
drivers can be highly performant.

VSI file handlers
=================
Before configuring Mapserver to render imagery stored in an S3 bucket,
ensure that `gdalinfo` can access the files on the command line.

- [/vsicurl/](http://gdal.org/cpl__vsi_8h.html#a4f791960f2d86713d16e99e9c0c36258)
  can read from a static website, for example one hosted on S3.  For
  example, [this file from the GDAL test suite](https://github.com/OSGeo/gdal/blob/master/autotest/gdrivers/data/gtiff/int8.tif)
  can be accessed via its /vsicurl/ driver.

        gdalinfo /vsicurl/https://github.com/OSGeo/gdal/raw/86193bf5942fb63b91b06a18df78efc73a2d869b/autotest/gdrivers/data/gtiff/int8.tif

- [/vsis3/](https://gdal.org/en/stable/user/virtual_file_systems.html#vsis3)
  can be used to read from buckets which require AWS credentials.  The
  vsis3 driver should fetch properly configured
  credentials. Credential management is out of scope for this
  document.

Preparing imagery
=================

The format & layout of your data have a critical impact on Mapserver
performance.  This is especially important when using the vsicurl
drivers. To achieve high performance, you need to minimize the amount
of data that needs to be transferred.  The [GDAL COG
driver](https://gdal.org/en/stable/drivers/raster/cog.html) puts
GeoTIFF data in the optimal format for random access over /vsicurl/.
Details of this format are outside the scope of this document.
 
Layer configuration
===================

This section documents how to configure a
[mapfile](http://mapserver.org/mapfile/map.html) for /vsicurl/ data.

Single image
------------

To have Mapserver render from a single source image, set the `DATA` to
the `/vsicurl/` or `/vsis3/` path in the LAYER object of your mapfile:

    	LAYER
    		NAME		landsat_tile
    		DATA		"/vsicurl/https://github.com/OSGeo/gdal/raw/86193bf5942fb63b91b06a18df78efc73a2d869b/autotest/gdrivers/data/gtiff/int8.tif"
    		TYPE		RASTER
    	END

Many images
-----------

[gdaltindex](https://gdal.org/en/stable/programs/gdaltindex.html) can
point to files having `/vsicurl/` paths.  For example:

    gdaltindex tindex.gpkg /vsis3/landsat-pds/L8/021/036/LC80210362016114LGN00/LC80210362016114LGN00_B2.TIF /vsis3/landsat-pds/L8/021/036/LC80210362016114LGN00/LC80210362016114LGN00_B3.TIF

Once you have the tile index, set your LAYER like so:

    	LAYER
    		NAME		landsat_tiles
    		TILEINDEX       "/usr/src/mapfiles/tile_index.gpkg"
    		TYPE		RASTER
    	END

Performance Improvement: VSI Curl options
-----------------------------------------

Some GDAL config options have an outsized impact on performance.
These are well summarized at [TiTiler Performance
Tuning](https://developmentseed.org/titiler/advanced/performance_tuning/).


For example, consider:
- [CPL_VSIL_CURL_ALLOWED_EXTENSIONS](https://trac.osgeo.org/gdal/wiki/ConfigOptions#CPL_VSIL_CURL_ALLOWED_EXTENSIONS).  Use this to restrict only the file extensions you expect to actually need.
- [VSI_CACHE](https://trac.osgeo.org/gdal/wiki/ConfigOptions#VSI_CACHE) results in less network traffic (even for simple things like `gdalinfo`)!
- [VSI_CACHE_SIZE](https://trac.osgeo.org/gdal/wiki/ConfigOptions#VSI_CACHE) size of cache in bytes.
- [GDAL_DISABLE_READDIR_ON_OPEN](https://trac.osgeo.org/gdal/wiki/ConfigOptions#GDAL_DISABLE_READDIR_ON_OPEN) might result in fewer HTTP GET requests when opening the GeoTIFF header.

Example configuration for the MAP object of your MAPFILE:

	CONFIG "CPL_VSIL_CURL_ALLOWED_EXTENSIONS" ".tif"
	CONFIG "VSI_CACHE" "TRUE"
	# cache size in bytes
	CONFIG "VSI_CACHE_SIZE" "50000000"
	CONFIG "GDAL_DISABLE_READDIR_ON_OPEN" "TRUE"

Docker Image
============

This repo includes a Docker image that can be used to render GeoTIFFs stored in AWS S3 via Mapserver-7.0.2 and gdal-2.1.1.

    docker build -t mapserver-docker:latest
    docker run --rm -it -p 8000:80 -v /Users/pschmitt/src/mapserver-docker/mapfiles:/usr/src/mapfiles mapserver-docker:latest

A sample mapfile is available at `mapfiles/mapfile.map`.

Once the container is running

Render imagery with a WMS client like QGIS, OpenLayers or manually issue a request for a single tile:

    http://localhost:8000/mapserv?LAYERS=raster_layer&FORMAT=image%2Fpng&MAP=/usr/src/mapfiles/mapfile.map&TRANSPARENT=true&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=57.00,27.05,57.01,27.06&WIDTH=256&HEIGHT=256

Assorted Docs & Links
=====================

- [GDAL Virtual File Systems](https://gdal.org/en/stable/user/virtual_file_systems.html)
- [GDAL Cloud Optimized GeoTIFF driver](https://gdal.org/en/stable/drivers/raster/cog.html)
- [TiTiler GDAL Performance Tuning](https://developmentseed.org/titiler/advanced/performance_tuning/)
- [Mapserver Virtual File System](http://mapserver.org/input/virtual-file.html)
 
Thanks to [Even Rouault](http://erouault.blogspot.com/) for his work
on /vsis3/ support, the [Mapserver](http://www.mapserver.org/) team
for an excellent tool and the
[mapserver-users](https://lists.osgeo.org/listinfo/mapserver-users)
mailing list!
