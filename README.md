Render GeoTIFFs stored in AWS S3 via Mapserver-7.0.2 and gdal-2.1.1.

    docker run --rm -it -p 8000:80 -v /Users/pschmitt/src/vsis3mapserver/myMapfiles:/usr/src/mapfiles pedros007/mapserver-hackathon

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

    import boto3
    s3 = boto3.resource("s3")
    bucket = s3.Bucket("pschmitt-test")
    sum([obj.size for obj in bucket.objects.filter(Prefix="bucket-o-tiffs/raster_tiles/").all()]) / 1024 / 1024 / 1024

Construct tile index using VSICurl

    gdaltindex tile_index.shp $(for file in $(dbfdump tile_index.dbf | grep -o "[0-3]\{12\}.tif"); do echo /vsicurl/http://pschmitt-test.s3-website-us-east-1.amazonaws.com/bucket-o-tiffs/$file; done)
	env CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif" VSI_CACHE=TRUE VSI_CACHE_SIZE=100000000 gdaltindex tile_index.shp $(for file in $(dbfdump public/tile_index.dbf | grep -o "[0-3]\{12\}.tif"); do echo /vsis3/pschmitt-test/bucket-o-tiffs/$file; done)

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

Construct tile index using vsis3, which requires AWS credentials (Note you may also need `AWS_SESSION_TOKEN` ):

    time env AWS_ACCESS_KEY_ID=foo AWS_SECRET_ACCESS_KEY=bar CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif" VSI_CACHE=TRUE VSI_CACHE_SIZE=100000000 gdaltindex vsis3_tile_index.shp $(for file in $(dbfdump tile_index.dbf | grep -o "[0-3]\{12\}.tif"); do echo /vsis3/pschmitt-test/bucket-o-tiffs/raster_tiles/$file; done)


Performance Optimizations
=========================

#1: GeoTIFF Data layout
-----------------------

- [GeoTIFF JPEG compression](http://blog.cleverelephant.ca/2015/02/geotiff-compression-for-dummies.html)
- `gdaladdo` to add internal overviews
- Internal tiling of data.
- Create spatial index using `shptree` on tileindex shpfile.


#2: Singe GeoTIFF
-----------------

Mapserver renders a single image _much_ faster than a collection of images in a tileindex ([Read Frank Warmerdam's explanation on mapserver-users](http://osgeo-org.1560.x6.nabble.com/UMN-MAPSERVER-USERS-GeoTIFF-overviews-TILEINDEX-Large-dataset-performance-tt4301064.html#a4301084)). Here's how to generate a 16m GeoTIFF which Mapserver can render with the appropriate [MINSCALEDENOM](http://mapserver.org/mapfile/class.html#index-10)/[MAXSCALEDENOM](http://mapserver.org/mapfile/class.html#index-8):

    time env GDAL_CACHEMAX=16384 CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif" VSI_CACHE=TRUE VSI_CACHE_SIZE=100000000 gdalbuildvrt mosaic.vrt $(dbfdump ../tile_index.shp | sed 1d)
    time GDAL_CACHEMAX=16384 gdal_translate mosaic.vrt  mosaic_z13.tif -outsize 6.25% 6.25% -co BIGTIFF=YES -co COMPRESS=JPEG -co PHOTOMETRIC=YCBCR -co TILED=YES --config GDAL_TIFF_INTERNAL_MASK YES
    time gdaladdo -r average mosaic_z13.tif 2 4 8 16 32 64 128 --config COMPRESS_OVERVIEW JPEG --config PHOTOMETRIC_OVERVIEW YCBCR --config INTERLEAVE_OVERVIEW PIXEL --config GDAL_TIFF_INTERNAL_MASK YES

Choose gdaladdo resolutions such that smallest ovr is ~256x256. You need `-co BIGTIFF=YES` when resulting GeoTIFF with internal overviews is > 4 GB.

#3: VSI Curl options
--------------------

Configure the VSI driver for increased performance:
- [CPL_VSIL_CURL_ALLOWED_EXTENSIONS](https://trac.osgeo.org/gdal/wiki/ConfigOptions#CPL_VSIL_CURL_ALLOWED_EXTENSIONS).  Use this to restrict only the file extensions you expect to actually need.  Example: `CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif .ovr"`
- [VSI_CACHE](https://trac.osgeo.org/gdal/wiki/ConfigOptions#VSI_CACHE) results in less network traffic (even for simple things like `gdalinfo`)! example: `VSI_CACHE=TRUE`
- [VSI_CACHE_SIZE](https://trac.osgeo.org/gdal/wiki/ConfigOptions#VSI_CACHE) size of cache in bytes. Example 50 mb: `VSI_CACHE_SIZE=50000000`

Docs
====
-[VSI S3 File Handler in GDAL](http://www.gdal.org/cpl__vsi_8h.html#a5b4754999acd06444bfda172ff2aaa16)
-[How to use GDAL S3 drivers in MapServer?](http://osgeo-org.1560.x6.nabble.com/How-to-use-GDAL-S3-drivers-in-MapServer-td5270663.html#a5270698)
-[Virtual File System via Mapserver](http://mapserver.org/input/virtual-file.html)
-[VSI to read compressed files](https://trac.osgeo.org/gdal/wiki/UserDocs/ReadInZip#vsicurl-toreadfromHTTPorFTPfilespartialdownloading)
 
