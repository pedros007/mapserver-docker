Abstract
========

Mapserver-7.0 can render imagery stored in an AWS S3 bucket using a file handler provided by GDAL-2.1. Two file handlers are available `/vsicurl/` and `/vsis3/`. These handlers make use of [HTTP GET range requests](https://tools.ietf.org/html/rfc7233) to transfer the minimum data required.  When images are properly prepared, access via the vsi drivers can be highly performant.

VSI file handlers
=================
Before configuring Mapserver to render imagery stored in an S3 bucket, ensure that gdalinfo can access the files on the command line.

- [/vsicurl/](http://gdal.org/cpl__vsi_8h.html#a4f791960f2d86713d16e99e9c0c36258) can read from a static website, for example one hosted on S3.  For example, [this Landsat scene](http://landsat-pds.s3.amazonaws.com/L8/001/003/LC80010032014272LGN00/index.html) can be accessed via its /vsicurl/ driver.

        gdalinfo /vsicurl/http://landsat-pds.s3.amazonaws.com/L8/001/003/LC80010032014272LGN00/LC80010032014272LGN00_B1.TIF

- [/vsis3/](http://www.gdal.org/cpl__vsi_8h.html#a5b4754999acd06444bfda172ff2aaa16) can be used to read from buckets which require AWS credentials.  This driver uses credentials stored in the environment variables `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and optionally `AWS_SESSION_TOKEN`.  Here is an example trying to read from the private file at `s3://pschmitt-test/121210221200.tif`:

        env AWS_ACCESS_KEY_ID=foo AWS_SECRET_ACCESS_KEY=baz AWS_SESSION_TOKEN=bam gdalinfo /vsis3/pschmitt-test/121210221200.tif

Preparing imagery
=================

The format & layout of your data have a critical impact on Mapserver performance.  This is especially important when using the vsicurl drivers. To achieve high performance, you need to miniize the amount of data that needs to be transferred.

I typically start with imagery stored as a GeoTIFF. [Lossy JPEG compression can make your data dramatically smaller with little visual impact](http://blog.cleverelephant.ca/2015/02/geotiff-compression-for-dummies.html). Internal tiling the data improves random access performance. Generating overviews (aka pyramids) minimizes the amount of data required at various zoom levels.  GDAL can be used to prepare a file with these considerations in mind:

    gdal_translate in.tif out.tif -co COMPRESS=JPEG -co PHOTOMETRIC=YCBCR -co TILED=YES
	gdaladdo -r average out.tif 2 4 8 16 32 64 128 --config COMPRESS_OVERVIEW JPEG --config PHOTOMETRIC_OVERVIEW YCBCR --config INTERLEAVE_OVERVIEW PIXEL

If you are using an mask band, you may need to add the flag `--config GDAL_TIFF_INTERNAL_MASK YES`. You can also set transparency via MAPfile parameter `OFFSITE 0 0 0` to mark (0,0,0) pixels transparent.

Layer configuration
===================

If you are using `/vsis3/`, set the `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and optionally `AWS_SESSION_TOKEN` credentials with `CONFIG key value` in the MAP object of your [mapfile](http://mapserver.org/mapfile/map.html).  As mentionned in the doc, it is for MapServer config options, but also for any GDAL config option.

Single image
------------

To have Mapserver render from a single source image, set the `DATA` to the `/vsicurl/` or `/vsis3/` path in the LAYER object of your mapfile:

    	LAYER
    		NAME		landsat_tile
    		DATA		"/vsicurl/http://landsat-pds.s3.amazonaws.com/L8/001/003/LC80010032014272LGN00/LC80010032014272LGN00_B1.TIF"
    		TYPE		RASTER
    	END

Many images
-----------

You can create a tile index locally which would mosaic those S3 images. The dbf file would look something like this: 

    Location 
      /vsis3/landsat-pds/L8/021/036/LC80210362016114LGN00/LC80210362016114LGN00_B2.TIF 
      /vsis3/landsat-pds/L8/021/036/LC80210362016114LGN00/LC80210362016114LGN00_B3.TIF 

GDAL can even generate this for you:

    gdaltindex tindex.shp /vsis3/landsat-pds/L8/021/036/LC80210362016114LGN00/LC80210362016114LGN00_B2.TIF /vsis3/landsat-pds/L8/021/036/LC80210362016114LGN00/LC80210362016114LGN00_B3.TIF

Run `shptree` on the tile index for improved performance.

Once you have the tile index, set your LAYER like so:

    	LAYER
    		NAME		landsat_tiles
    		TILEINDEX       "/usr/src/mapfiles/tile_index.shp"
    		TYPE		RASTER
    	END

Performance Improvement: Single image
======================================

Mapserver renders a single image _much_ faster than a collection of images in a tileindex ([Read Frank Warmerdam's explanation on mapserver-users](http://osgeo-org.1560.x6.nabble.com/UMN-MAPSERVER-USERS-GeoTIFF-overviews-TILEINDEX-Large-dataset-performance-tt4301064.html#a4301084)).  This is esepcially true when using the VSI drivers, as reading GeoTIFF headers via HTTP GET Range Requests is even slower than direct disk access.

Here's how to generate a single 16m GeoTIFF:

    time env GDAL_CACHEMAX=16384 CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif" VSI_CACHE=TRUE VSI_CACHE_SIZE=100000000 gdalbuildvrt mosaic.vrt $(dbfdump ../tile_index.shp | sed 1d)
    time GDAL_CACHEMAX=16384 gdal_translate mosaic.vrt  mosaic_z13.tif -outsize 6.25% 6.25% -co BIGTIFF=YES -co COMPRESS=JPEG -co PHOTOMETRIC=YCBCR -co TILED=YES --config GDAL_TIFF_INTERNAL_MASK YES
    time gdaladdo -r average mosaic_z13.tif 2 4 8 16 32 64 128 --config COMPRESS_OVERVIEW JPEG --config PHOTOMETRIC_OVERVIEW YCBCR --config INTERLEAVE_OVERVIEW PIXEL --config GDAL_TIFF_INTERNAL_MASK YES

Choose gdaladdo resolutions such that smallest ovr is ~256x256. You need `-co BIGTIFF=YES` when resulting GeoTIFF with internal overviews is > 4 GB.

Configure your Mapserver MAPFILE to use appropriate [MINSCALEDENOM](http://mapserver.org/mapfile/class.html#index-10)/[MAXSCALEDENOM](http://mapserver.org/mapfile/class.html#index-8) to render the single GeoTIFF when zoomed out and the raw data when zoomed in:

    	LAYER
    		NAME		raster_layer_lowres
    		GROUP		raster_layer
    		DATA		"/vsis3/pschmitt-test/lowres/mosaic_z13.tif"
    		TYPE		RASTER
    
    		MINSCALEDENOM 31250
    	END
    
    	LAYER
    		NAME		raster_layer_hires
    		GROUP		raster_layer
    		METADATA
    			"ows_title"	"raster_layer_hires"
    			"ows_srs"	"epsg:4326"
    		END
    		TILEINDEX       "/usr/src/mapfiles/tile_index.shp"
    		STATUS		OFF
    		TYPE		RASTER
    		MINSCALEDENOM 0
    		MAXSCALEDENOM 31249
    	END


Performance Improvement: VSI Curl options
-----------------------------------------

Configure the VSI driver for increased performance:
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

    docker build -t mapserver-docker
    docker run --rm -it -p 8000:80 -v /Users/pschmitt/src/vsis3mapserver/myMapfiles:/usr/src/mapfiles mapserver-docker

If using a private S3 bucket, you will need to [set AWS credentials in aws_credentials.inc.map](https://lists.osgeo.org/pipermail/mapserver-users/2016-October/079418.html) to use the `/vsis3/` driver.

A sample mapfile is available at `mapfiles/mapfile.map`.

Once the container is running, render images via [OpenLayers](https://openlayers.org/) or WMS request:

    http://localhost:8000/mapserv?LAYERS=raster_layer&FORMAT=image%2Fpng&MAP/usr/src/mapfiles/mapfile.map&TRANSPARENT=true&SERVICE=WMS&VERSION=1.1.1&REQUEST=GetMap&STYLES=&SRS=EPSG%3A4326&BBOX=57.00,27.05,57.01,27.06&WIDTH=256&HEIGHT=256

Handy things
============

Get temporary credentials via IAM role

    export AWS_ACCESS_KEY_ID=`curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/fpi-test-role/ | jq -r '.AccessKeyId'`
    export AWS_SECRET_ACCESS_KEY=`curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/fpi-test-role/ | jq -r '.SecretAccessKey'`
    export AWS_SESSION_TOKEN=`curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/fpi-test-role/ | jq -r '.Token'`
    export AWS_REGION=us-east-1

How big is the mosaic in S3?

    #!/bin/env python
    import boto3
    s3 = boto3.resource("s3")
    bucket = s3.Bucket("pschmitt-test")
    sum([obj.size for obj in bucket.objects.filter(Prefix="bucket-o-tiffs/raster_tiles/").all()]) / 1024 / 1024 / 1024

Update tileindex of filenames to have full /vsis3/ paths:

	ogr2ogr vsi_tindex.shp tindex.shp -sql "SELECT CONCAT('/vsis3/pschmitt-test/bucket-o-tiffs/raster_tiles/',location) as location FROM tile_index"

Bucket policy open to world.  Careful with this!  Works with the `/vsicurl/` driver.  We recommend the `/vsis3/` driver and AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,`AWS_SESSION_TOKEN`) to restrict access.

    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "PublicReadGetObject",
                "Effect": "Allow",
                "Principal": "*",
                "Action": "s3:GetObject",
                "Resource": "arn:aws:s3:::pschmitt-test/*"
            }
        ]
    }

Assorted Docs & Links
=====================

- [VSI S3 File Handler in GDAL](http://www.gdal.org/cpl__vsi_8h.html#a5b4754999acd06444bfda172ff2aaa16)
- [Virtual File System via Mapserver](http://mapserver.org/input/virtual-file.html)
- [VSI to read compressed files](https://trac.osgeo.org/gdal/wiki/UserDocs/ReadInZip#vsicurl-toreadfromHTTPorFTPfilespartialdownloading)
- [Cloud Optimized GeoTIFF](https://trac.osgeo.org/gdal/wiki/CloudOptimizedGeoTIFF)
 
Thanks to [Even Rouault](http://erouault.blogspot.com/) for his work on /vsis3/ support, the [Mapserver](http://www.mapserver.org/) team for an excellent tool and the [mapserver-users](https://lists.osgeo.org/listinfo/mapserver-users) mailing list!
