use 5.020;
use strict;
use warnings;
use Carp;

use Alien::gdal;

my $target_script = 'test_script.pl';


say '+++++';
my @bundle_list = get_dep_dlls($target_script);
say join ' ', @bundle_list;
system ('otool', '-L', $bundle_list[0]);
say '+++++';


#say join ":", Alien::gdal->dynamic_libs;
my @libs_to_pack;
my %seen;

my @target_libs = (Alien::gdal->dynamic_libs, '/usr/local/opt/libffi/lib/libffi.6.dylib');
while (my $lib = shift @target_libs) {
    say "otool -L $lib"; 
    my $libs = `otool -L $lib`;
    my @lib_arr = split "\n", $libs;
    shift @lib_arr;  #  first result is alien dylib
    foreach my $line (@lib_arr) {
        $line =~ /^\s+(.+?)\s/;
        my $dylib = $1;
        next if $seen{$dylib};
        next if $dylib =~ m{^/System};
        next if $dylib =~ m{^/usr/lib/system};
        next if $dylib =~ m{^/usr/lib/libsystem};
        next if $dylib =~ m{darwin-thread-multi-2level/auto/share/dist/Alien};  #  another alien
        say "adding $dylib for $lib";
        push @libs_to_pack, $dylib;
        $seen{$dylib}++;
        #  be paranoid in case otool does not get the full set
        push @target_libs, $dylib;
    }
}

my @inc_to_pack
  = map {('--link' => $_)}
    (@libs_to_pack, '/usr/local/opt/libffi/lib/libffi.6.dylib');

my @pp_cmd = (
    'pp',
    '-v',
    '-u',
    '-B',
    '-x',
    @inc_to_pack,
    '-o',
    'pp_gdal_check',
    $target_script,
);


say join ' ', @pp_cmd;
system (@pp_cmd);



#  find dependent dlls
#  could also adapt some of Module::ScanDeps::_compile_or_execute
#  as it handles more edge cases
sub get_dep_dlls {
    my ($script, $no_execute_flag) = @_;

    #  This is clunky:
    #  make sure $script/../lib is in @INC
    #  assume script is in a bin folder
    my $rlib_path = (path ($script)->parent->stringify) . '/lib';
    #say "======= $rlib_path/lib ======";
    local @INC = (@INC, $rlib_path)
      if -d $rlib_path;
    
    my $deps_hash = scan_deps(
        files   => [ $script ],
        recurse => 1,
        execute => !$no_execute_flag,
        #cache_file => $cache_file,
    );
    
    my @lib_paths
      = reverse sort {length $a <=> length $b}
        map {path($_)->absolute}
        @INC;

    my $paths = join '|', map {quotemeta} @lib_paths;
    my $inc_path_re = qr /^($paths)/i;
    #say $inc_path_re;
    
    my $RE_DLL_EXT = qr/\.$Config::Config{so}/i;
    $RE_DLL_EXT = qr/\.bundle$/;

    my %dll_hash;
    foreach my $package (keys %$deps_hash) {
        #  could access {uses} directly, but this helps with debug
        my $details = $deps_hash->{$package};
        my $uses    = $details->{uses};
        next if !$uses;
        
        foreach my $dll (grep {$_ =~ $RE_DLL_EXT} @$uses) {
            my $dll_path = $deps_hash->{$package}{file};
            #  Remove trailing component of path after /lib/
            if ($dll_path =~ m/$inc_path_re/) {
                $dll_path = $1 . '/' . $dll;
            }
            else {
                #  fallback, get everything after /lib/
                $dll_path =~ s|(?<=/lib/).+?$||;
                $dll_path .= $dll;
            }
            #say $dll_path;
            croak "either cannot find or cannot read $dll_path "
                . "for package $package"
              if not -r $dll_path;
            $dll_hash{$dll_path}++;
        }
    }
    
    my @dll_list = sort keys %dll_hash;
    return wantarray ? @dll_list : \@dll_list;
}

