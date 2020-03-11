#  Build a Biodiverse binary for OS X

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

local $| = 1;

use Config;
use File::Copy;
use Path::Class;
use Cwd;
use Cwd 'abs_path';
use File::Basename;
use File::Find;
use File::BaseDir qw/xdg_data_dirs/;
use Path::Tiny qw/ path /;
use Module::ScanDeps;


use Getopt::Long::Descriptive;

my ($opt, $usage) = describe_options(
  '%c <arguments>',
  [ 'script|s=s',              'The input script', { required => 1 } ],
  [ 'out_folder|out_dir|o=s',  'The output directory where the binary will be written'],
  [ 'icon_file|i=s',           'The location of the icon file to use'],
  [ 'lib_paths|l=s@',          'Paths to search for dynamic libraries'],
  [ 'pixbuf_loaders|p=s',      'The pixbuf loaders directory'],
  [ 'pixbuf_query_loader|q=s', 'The pixbuf query loader'],
  [ 'gdk_pixbuf_dir=s',        'gdk_pixbuf_dir location'],
  [ 'hicolor|h=s',             'The hicolor shared directory'],
  [ 'verbose|v!',              'Verbose building?', {default => 0} ],
  [ 'execute|x!',              'Execute the script to find dependencies?', {default => 1} ],
  [ '-', 'Any arguments after this will be passed through to pp'],
  [],
  [ 'help|?',       "print usage message and exit" ],
);

if ($opt->help) {
    print($usage->text);
    exit;
}

my $pixbuf_base = q{/usr/local/Cellar/gdk-pixbuf/2.38.0};
# $pixbuf_base = q{/usr/local/Cellar/gdk-pixbuf/2.36.11};
$pixbuf_base = q{/usr/local/opt/gdk-pixbuf};


my $script            = $opt->script;
my $verbose           = !!$opt->verbose;
my $lib_paths         = $opt->lib_paths || [q{/usr/local/opt}];
my $execute           = $opt->execute ? '-x' : q{};
my $pixbuf_loaders    = $opt->pixbuf_loaders || qq{$pixbuf_base/lib/gdk-pixbuf-2.0/2.10.0/loaders}; # need a way of finding this.
my $pixbuf_query_loader     = $opt->pixbuf_query_loader || qq{$pixbuf_base/bin/gdk-pixbuf-query-loaders}; # need a way of finding this.
my $gdk_pixbuf_dir    = $opt->gdk_pixbuf_dir || qq{$pixbuf_base/lib/gdk-pixbuf-2.0};
my $hicolor_dir       = $opt->hicolor || q{/usr/local/share/icons/hicolor}; # need a way of finding this.
my @rest_of_pp_args   = @ARGV;

die "Cannot find pixbuf loader $pixbuf_loaders"
  if !-d $pixbuf_loaders;
die "Cannot find pixbuf loader location $gdk_pixbuf_dir"
  if !-d $gdk_pixbuf_dir;
die "Cannot find pixbuf query loader location $pixbuf_query_loader"
  if !-e $pixbuf_query_loader;
die "Cannot find pixbuf query loader location $hicolor_dir"
  if !-d $hicolor_dir;


#die "Script file $script does not exist or is unreadable" if !-r $script;

#  assume bin folder is at parent folder level
my $script_root_dir = Path::Class::file ($script)->dir->parent;
my $root_dir = Path::Class::file ($0)->dir->parent;
say "Root dir is " . Path::Class::dir ($root_dir)->absolute->resolve;
my $bin_folder = Path::Class::dir ($script_root_dir, 'bin');
my $icon_file  = $opt->icon_file // Path::Class::file ($bin_folder, 'Biodiverse_icon.ico')->absolute->resolve;
say "Icon file is $icon_file";

my $out_folder   = $opt->out_folder // Path::Class::dir ($root_dir, 'builds','Biodiverse.app','Contents','MacOS');

my $perlpath     = $EXECUTABLE_NAME;

my $script_fullname = Path::Class::file($script)->absolute;
my $output_binary = basename ($script_fullname, '.pl', qr/\.[^.]*$/);

if (!-d $out_folder) {
    die "$out_folder does not exist or is not a directory";
}

###########################################
#
# Add libraries
#
###########################################

#  File::BOM dep are otherwise not found
$ENV{BDV_PP_BUILDING}              = 1;
$ENV{BIODIVERSE_EXTENSIONS_IGNORE} = 1;


use File::Find::Rule ();
our %dylib_files_hash;

my @hard_coded_dylibs = (
    #  hard code for now
    # '/usr/local/Cellar/openssl/1.0.2p/lib/libssl.1.0.0.dylib',
    # '"/usr/local/Cellar/openssl@1.1/1.1.1d/lib/libssl.1.1.dylib"',
    # '"/usr/local/Cellar/openssl@1.1/1.1.1d/lib/libcrypto.1.0.0.dylib"',
    "$root_dir/libssl.1.1.dylib",
    "$root_dir/libcrypto.1.1.dylib",
    '/usr/local/Cellar/libgnomecanvas/2.30.3_2/lib/libgnomecanvas-2.0.dylib',
);

my @links;
my @dylibs;

# Find the absolute paths to each supplied
# dynamic library. Each library is supplied
# to pp with a -a and uses an alias. The alias
# packs the library at the top level of the
# Par:Packer archive. This is where the
# Biodiverse binary will be able to find it.
print "finding dynamic library paths\n";
my %checked_dylib;
for my $name (sort @dylibs) {
    next if $checked_dylib{$name};
    say "Checking location of $name";
    my $lib = find_dylib_in_path($name, @$lib_paths);
    my $filename = Path::Class::file ($name)->basename;
    push @links, '-a', "$lib\;../$filename";
    print "library $lib will be included as ../$filename\n" if ($verbose);
    $checked_dylib{$name}++;
}

# Use otools the get the name proper of the dynamic
# library.
sub get_name_from_dynamic_lib {
    my $lib = shift;

    my $name;

    chomp(my @ot = qx( otool -D $lib ));
    if ($? == 0) {
        $name = $ot[1];
        print "otool: library $lib has install name $name\n" if ($verbose);
    }
    return $name;
}


# Search for a dynamic library
# in the paths supplied.
sub find_dylib_in_path {
    my ($file, @path) = @_;


    # If $file is an absolute path
    # then return with a fully resolved
    # file and path.
    #return get_name_from_dynamic_lib($file) if -f $file;
    return $file if -f $file;

    return $dylib_files_hash{$file} if $dylib_files_hash{$file};

    #  fallback search
    say "Searching for file $file";

    my $abs = "";
    my $dlext = $^O eq 'darwin' ? 'dylib' : $Config{dlext};

    # setup regular expressions variables
    # Example of patterns
    # Search pattern for finding dynamic libraries.
    #  <PREFIX><NAME><DELIMITER><VERSION><EXTENSION>
    # Examples:
    # for name without anything:               ffi
    # for name pattern prefix:name             libffi
    # for name pattern name:version:           ffi.6
    # for name pattern prefix:name:version:    libffi.6
    # for name pattern prefix:name:version:ext libffi.6.dylib
    for my $dir (@path) {
        next if (! -d $dir);
        $file  = substr $file, 0, -6 if $file =~ m/$dlext$/;
        find ({wanted => sub {return unless /^(lib)*$file(\.|-)[\d*\.]*\.$dlext$/; $abs = $File::Find::name}, follow=>1, follow_skip=>2 },$dir );
        find ({wanted => sub {return unless /^(lib)*$file\.$dlext$/; $abs = $File::Find::name}, follow=>1, follow_skip=>2 },$dir ) if ! $abs;
        return $abs if $abs;
        #print "could not file: $file\n" if (! $abs);
    }
    print "could not find file: $file\n" if (! $abs);
    return $abs;
}


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
        execute => 1, #!$no_execute_flag,
        #cache_file => $cache_file,
    );

    my @lib_paths
      = reverse sort {length $a <=> length $b}
        map {path($_)->absolute}
        @INC;

    my $paths = join '|', map {quotemeta} @lib_paths;
    my $inc_path_re = qr /^($paths)/i;
    #say $inc_path_re;

    my $RE_DLL_EXT = qr/\.($Config::Config{so}|bundle)$/i;
    # $RE_DLL_EXT = qr/\.bundle$/;

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

sub find_so_files {
    my $target_dir = shift or die;

    my @files = File::Find::Rule->extras({ follow => 1, follow_skip=>2 })
                             ->file()
                             ->name( qr/\.so$/ )
                             ->in( $target_dir );
    return wantarray ? @files : \@files;
}

sub get_inc_to_pack {
    my $target_script = shift;

    say '+++++';
    say 'Finding XS bundle files';
    my @bundle_list = get_dep_dlls($target_script);
    #say join ' ', @bundle_list;
    #system ('otool', '-L', $bundle_list[0]);
    say '+++++';

    my @libs_to_pack = (
        @hard_coded_dylibs,
    );
    my %seen;

    my @target_libs = (
        @hard_coded_dylibs,
        Alien::gdal->dynamic_libs,
        @bundle_list,
        '/usr/local/opt/libffi/lib/libffi.6.dylib',
        $pixbuf_query_loader,
        find_so_files ($gdk_pixbuf_dir),
    );
    while (my $lib = shift @target_libs) {
        say "otool -L $lib";
        my @lib_arr = qx /otool -L $lib/;
        warn qq["otool -L $lib" failed\n]
          if not $? == 0;
        shift @lib_arr;  #  first result is dylib we called otool on
        foreach my $line (@lib_arr) {
            $line =~ /^\s+(.+?)\s/;
            my $dylib = $1;
            next if $seen{$dylib};
            next if $dylib =~ m{^/System};  #  skip system libs
            #next if $dylib =~ m{^/usr/lib/system};
            next if $dylib =~ m{^/usr/lib/libSystem};
            next if $dylib =~ m{^/usr/lib/};
            next if $dylib =~ m{\Qdarwin-thread-multi-2level/auto/share/dist/Alien\E};  #  another alien
            say "adding $dylib for $lib";
            push @libs_to_pack, $dylib;
            $seen{$dylib}++;
            #  be paranoid in case otool does not get the full set
            push @target_libs, $dylib;
        }
    }

    #my @inc_to_pack
    #  = map {('--link' => $_)}
    #    (@libs_to_pack, '/usr/local/opt/libffi/lib/libffi.6.dylib');
    my @inc_to_pack;
    foreach my $file (@libs_to_pack) {
        my $basename = Path::Tiny::path($file)->basename;
        while (-l $file) {
            my $linked_file = readlink ($file);
            say "$file is a symbolic link that points to $linked_file";
            #$file = _chase_lib_darwin($file);

            #  handle relative paths, or symlinks to sibling files
            if (!path($linked_file)->is_absolute) {

                my $file_path = path($file)->parent->stringify;
                $linked_file = path("$file_path/$linked_file")->stringify;
            }
            $file = $linked_file;
        }
        push @inc_to_pack, ("-a" => "$file\;../" . $basename);
    }

    return @inc_to_pack;

}


###########################################
#
# Add file section
#
###########################################
my @add_files;
my @mime_dirs;


for my $dir (@mime_dirs) {
    my $mime_dir_abs  = path ($dir)->basename;
    push @add_files, ('-a', "$dir\;$mime_dir_abs");
}

say "\n-----\n";

# Add the hicolor directory
my $hicolor_dir_abs  = path ($hicolor_dir)->realpath->basename;

my @xxx;
push @xxx, ('-a', "$pixbuf_query_loader\;" . path ($pixbuf_query_loader)->basename);
foreach my $dir ($pixbuf_loaders, $gdk_pixbuf_dir) {
    my $path = path ($dir)->realpath;
    my $basename = path ($dir)->basename;
    push @xxx, ('-a', "$path\;$basename");
}
push @xxx, ('-a', "$hicolor_dir\;icons/$hicolor_dir_abs");

#  clunky, but previous approach was sneaking a 1 into the array
@add_files = (@add_files, @xxx);

say join ' ', @add_files;
say "-----\n";
# my $zz = <>;


# Add the ui directory
my @ui_arg = ();

if ($script =~ 'BiodiverseGUI.pl') {
    my $ui_dir = Path::Class::dir ($bin_folder, 'ui')->absolute;
    @ui_arg = ('-a', "$ui_dir\;ui");
}

my $output_binary_fullpath = Path::Class::file ($out_folder, $output_binary)->absolute;

my $icon_file_base = $icon_file ? basename ($icon_file) : '';
my @icon_file_arg  = $icon_file ? ('-a', "$icon_file\;$icon_file_base") : ();

###########################################
#
# Run the constructed pp command.
#
###########################################

#  we need to use -M with the aliens,
#  and possibly some others
my @aliens = qw /
    Alien::gdal       Alien::geos::af
    Alien::proj       Alien::sqlite
    File::ShareDir
/;
#    Alien::spatialite Alien::freexl
#/;
#  we don't always have all of the aliens installed
foreach my $alien (@aliens) {
    if (eval "require $alien") {
        push @rest_of_pp_args, '-M' => $alien;
    }
}

my @inc_to_pack = get_inc_to_pack ($script_fullname);

my @cmd = (
    'pp',
    #$verbose,
    '-u',
    '-B',
    '-z',
    9,
    @ui_arg,
    @icon_file_arg,
    $execute,
    #@links,
    @inc_to_pack,
    @add_files,
    @rest_of_pp_args,
    '-o',
    $output_binary_fullpath,
    $script_fullname,
);

if ($verbose) {
    my @verbose_command = $verbose ? ("-v") : ();
    splice @cmd, 1, 0, @verbose_command;
}

say join ' ', "\nCOMMAND TO RUN:\n", @cmd;

system @cmd;


#  not sure this works
sub icon_into_app_file {
    #  also see
    #  https://stackoverflow.com/questions/8371790/how-to-set-icon-on-file-or-directory-using-cli-on-os-x
    #  https://apple.stackexchange.com/questions/6901/how-can-i-change-a-file-or-folder-icon-using-the-terminal
    my $target = "$root_dir/builds/Biodiverse.app/Icon\r";
    #    return if -e $target;
    File::Copy::copy "$root_dir/images/icon.icns", $target
      or warn "Unable to copy icon file, $@";
}


icon_into_app_file ();


###########################################
#
# Build the dmg image.
#
###########################################
sub build_dmg(){
    print "[build_dmg] Building dmg image...\n" if ($verbose);
    my $builddmg = Path::Class::dir ($root_dir,'bin', 'builddmg.pl' );
    print "[build_dmg] build_dmg: $builddmg\n" if ($verbose);
    say "script root dir is $script_root_dir";
    say "PERL5LIB env var is " . ($ENV{PERL5LIB} // '');
    local $ENV{PERL5LIB} = "$script_root_dir/lib:" . ($ENV{PERL5LIB} // "");
    system ($^X, $builddmg);
}

build_dmg();
