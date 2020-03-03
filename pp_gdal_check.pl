use 5.020;
use strict;
use warnings;

use Alien::gdal;

#say join ":", Alien::gdal->dynamic_libs;

foreach my $lib (Alien::gdal->dynamic_libs) {
    say "otool -L $lib"; 
    system ('otool', '-L', $lib);
}

eval 'require Geo::GDAL::FFI'
  or warn 'could not load Geo::GDAL::FFI';
