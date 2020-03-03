use 5.020;
use strict;
use warnings;

use Alien::gdal;

#say join ":", Alien::gdal->dynamic_libs;
my @libs_to_pack;
my %seen;

foreach my $lib (Alien::gdal->dynamic_libs) {
    say "otool -L $lib"; 
    my $libs = system ('otool', '-L', $lib);
    my @lib_arr = split "\n", $libs;
    shift @lib_arr;  #  first result is alien dylib
    foreach my $line (@lib_arr) {
        my @fields = split /\s+/, $line;
        next if $seen{$fields[0]};
        push @libs_to_pack, $fields[0];
        $seen{$fields[0]}++;
    }
    
}

my @inc_to_pack = map {('--link' => $_)} @libs_to_pack;

system (
    'pp',
    '-u',
    '-B',
    '-x',
    @inc_to_pack,
    '-o',
    'pp_gdal_check',
    'pp_gdal_check.pl',
);
