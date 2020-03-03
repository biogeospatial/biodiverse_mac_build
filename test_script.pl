use 5.020;
use strict;
use warnings;

use Alien::gdal;

eval 'require Geo::GDAL::FFI'
  or warn "unable to load Geo::GDAL::FFI";

say join "\n", Alien::gdal->dynamic_libs;

1;
