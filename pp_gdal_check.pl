use 5.020;
use strict;
use warnings;

use Alien::gdal;

#say join ":", Alien::gdal->dynamic_libs;
my @libs_to_pack;
my %seen;

foreach my $lib (Alien::gdal->dynamic_libs, '/usr/local/opt/libffi/lib/libffi.6.dylib') {
    say "otool -L $lib"; 
    my $libs = `otool -L $lib`;
    my @lib_arr = split "\n", $libs;
    shift @lib_arr;  #  first result is alien dylib
    foreach my $line (@lib_arr) {
        $line =~ /^\s+(.+?)\s/;
        my $dylib = $1;
        next if $seen{$dylib};
        next if $dylib =~ m{^/System};
        say "adding $dylib for $lib";
        push @libs_to_pack, $dylib;
        $seen{$dylib}++;
    }
}

my @inc_to_pack = map {('--link' => $_)} @libs_to_pack;
push @inc_to_pack, ('--link' => '/usr/local/opt/libffi/lib/libffi.6.dylib');

my @pp_cmd = (
    'pp',
    '-v',
    '-u',
    '-B',
    '-x',
    @inc_to_pack,
    '-o',
    'pp_gdal_check',
    'test_script.pl',
);


say join ' ', @pp_cmd;
system (@pp_cmd);
