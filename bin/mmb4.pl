#  Build a Biodiverse binary for OS X
#  Unlike previous iterations of the script,
#  we package the dmg later.  This allows code signing.

use 5.010;
use strict;
use warnings;
use English qw { -no_match_vars };
use Carp;

local $| = 1;

use Config;
use File::Copy;
use Cwd 'abs_path';
use File::Basename;
use File::BaseDir qw/xdg_data_dirs/;
use Path::Tiny qw/ path /;
use Module::ScanDeps;
use File::Find::Rule ();
use File::Which qw /which/;



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

my $pixbuf_loader = `which gdk-pixbuf-query-loaders`;
chomp $pixbuf_loader;
#say STDERR "HHHHHH $pixbuf_loader";
my @tmp = grep {/LoaderDir/} `$pixbuf_loader`;
my $pixbuf_loader_dir = shift @tmp;
$pixbuf_loader_dir =~ s/^.+= //;
chomp $pixbuf_loader_dir;

#say STDERR "kkkkk $pixbuf_base";


my $script            = $opt->script;
my $verbose           = !!$opt->verbose;
my $execute           = $opt->execute ? '-x' : q{};
my $pixbuf_loaders    = $opt->pixbuf_loaders || $pixbuf_loader_dir;
my $pixbuf_query_loader     = $opt->pixbuf_query_loader || $pixbuf_loader;
my $gdk_pixbuf_dir    = $opt->gdk_pixbuf_dir || path ($pixbuf_loader_dir)->parent->parent;
my $hicolor_dir       = $opt->hicolor || "$ENV{HOMEBREW_PREFIX}/share/icons/hicolor";
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
my $script_root_dir = path ($script)->parent->parent;
my $root_dir = path($0)->parent->parent->absolute;
say "Root dir is $root_dir";
my $bin_folder = path ("$script_root_dir/bin");
my $icon_file  = $opt->icon_file // path ($bin_folder, 'Biodiverse_icon.ico')->realpath;
say "Icon file is $icon_file";

#  ISSUES HERE - THE BUILD NEEDS THE SECOND OPTION
my $out_folder   = $opt->out_folder // path ($root_dir, 'builds','Biodiverse.app','Contents','MacOS');

my $script_fullname = path ($script)->absolute;
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
$ENV{BD_NO_GUI_DEV_WARN} = 1;


#  gtk3 is not detected by the pp_autolink scan so
#  hard code until then
#  first one won't be in the cellar
my @tmpgtk3 = `find $ENV{HOMEBREW_PREFIX}/lib -name libgtk-3.0.dylib`;
my $gtk3_dylib = shift @tmpgtk3;
chomp $gtk3_dylib;

#  homebrew gdal depends on the homebrew sqlite, but proj uses the system sqlite.
#  pp_autolink finds the system sqlite so does not pack it, so pack the homebrew version
# use FFI::CheckLib;
# my $sqlite3_dylib = find_lib_or_die(
#     lib => 'libsqlite3'
# );
# say STDERR $sqlite3_dylib;

#my @tmp_gdal_deps = map {s/\s\(.+$//r} map {s/^\s+//r} grep {/sqlite3/} `otool -L $ENV{HOMEBREW_PREFIX}/lib/libgdal.dylib`;
#my $sqlite3_dylib = shift @tmp_gdal_deps;
#chomp $sqlite3_dylib;
# use DDP; p $sqlite3_dylib;
# exit;


my @hard_coded_dylibs = (
    $gtk3_dylib,
    # $sqlite3_dylib,
    #  hard code for now
    # '/usr/local/Cellar/openssl/1.0.2p/lib/libssl.1.0.0.dylib',
    # '"/usr/local/Cellar/openssl@1.1/1.1.1d/lib/libssl.1.1.dylib"',
    # '"/usr/local/Cellar/openssl@1.1/1.1.1d/lib/libcrypto.1.0.0.dylib"',
    #"$root_dir/libssl.1.1.dylib",
    #"$root_dir/libcrypto.1.1.dylib",
    #'$ENV{HOMEBREW_PREFIX}/Cellar/libgnomecanvas/2.30.3_5/lib/libgnomecanvas-2.0.dylib',
);

@hard_coded_dylibs = map {; '--link' => $_} @hard_coded_dylibs;



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

#  hack for now
{
    use Alien::proj;
    if (Alien::proj->is_system_install) {
        push @add_files, ('-a', "$ENV{HOMEBREW_PREFIX}/share/proj/proj.db\;proj/proj.db");
        push @add_files, ('-a', "$ENV{HOMEBREW_PREFIX}/share/proj/proj.ini\;proj/proj.ini");
    }
}

say "\n-----\n";

# Add the hicolor directory
# my $hicolor_dir_abs  = path ($hicolor_dir)->realpath->basename;

my @xxx;
push @xxx, ('-a', "$pixbuf_query_loader\;" . path ($pixbuf_query_loader)->basename);
foreach my $dir ($pixbuf_loaders, $gdk_pixbuf_dir) {
    my $path = path ($dir)->realpath;
    my $basename = path ($dir)->basename;
    push @xxx, ('-a', "$path\;$basename");
}
my $girepo = path ($ENV{HOMEBREW_PREFIX}, 'lib', 'girepository-1.0');
push @xxx, ('-a', "$girepo\;girepository-1.0");
my $gdbus = `which gdbus`;
chomp $gdbus;
push @xxx, ('-a', "$gdbus\;" . path ($gdbus)->basename);

#  might not be needed now it is in the share dirs
# push @xxx, ('-a', "$hicolor_dir\;icons/$hicolor_dir_abs");
my @share_dirs;
foreach my $dir (qw /gtk-3.0 gir-1.0 glib-2.0 icons themes/) {
    my $path = path ($ENV{HOMEBREW_PREFIX}, 'share', $dir);
    push @share_dirs, ("-a", "$path\;share/$dir");
}

#  clunky, but previous approach was sneaking a 1 into the array
@add_files = (@add_files, @xxx, @share_dirs);

say join ' ', @add_files;
say "-----\n";
# my $zz = <>;


# Add the ui directory
my @ui_arg = ();

if ($script =~ 'BiodiverseGUI.pl') {
    my $ui_dir = path ($bin_folder, 'ui')->absolute;
    @ui_arg = ('-a', "$ui_dir\;ui");
}

my $output_binary_fullpath = path ($out_folder, $output_binary)->absolute;

#  the biodiverse icon
my $icon_file_base = $icon_file ? basename ($icon_file) : '';
my @icon_file_arg  = $icon_file ? ('-a', "$icon_file\;$icon_file_base") : ();

# ###########################################
# #
# # Run the constructed pp command.
# #
# ###########################################
#


my @verbose_command = $verbose ? ("-v") : ();
push @rest_of_pp_args, (qw /-M URI::/);  #  or the help won't open

my $pp_autolink = `which pp_autolink.pl`;
chomp $pp_autolink;
die 'Cannot find pp_autolink.pl' if !$pp_autolink;
my @pp_cmd = ($^X, $pp_autolink);
my @cmd = (
    @pp_cmd,
    @verbose_command,
    # '-u', # not needed post perl 5.31.6
    '-B',
    '-z',
    9,
    @ui_arg,
    @icon_file_arg,
    $execute,
    @hard_coded_dylibs,
    # @inc_to_pack,
    @add_files,
    @rest_of_pp_args,
    '-o',
    $output_binary_fullpath,
    $script_fullname,
);


say join ' ', "\nCOMMAND TO RUN:\n", @cmd;

system @cmd;
die $? if $?;

say "Output binary size (MB) is: " . sprintf "%.3f", ((-s $output_binary_fullpath) / (1024 ** 2));


# say 'Updating binary in preparation for code signing';
# system ("pp_osx_codesign_fix", $output_binary_fullpath);

#  not sure this works
sub icon_into_app_file {
    #  also see
    #  https://stackoverflow.com/questions/8371790/how-to-set-icon-on-file-or-directory-using-cli-on-os-x
    #  https://apple.stackexchange.com/questions/6901/how-can-i-change-a-file-or-folder-icon-using-the-terminal
    my $target = "$root_dir/builds/Biodiverse.app/Icon";
    system ('fileicon', 'set', $target, 'images/icon.icns');
    warn $@ if $@;
}


# icon_into_app_file ();


###########################################
#
# Build the dmg image.
#
###########################################
# sub build_dmg(){
#     print "[build_dmg] Building dmg image...\n" if ($verbose);
#     my $builddmg = path ($root_dir,'bin', 'builddmg.pl' )->absolute->stringify;
#     print "[build_dmg] build_dmg: $builddmg\n" if ($verbose);
#     say "script root dir is $script_root_dir";
#     say "PERL5LIB env var is " . ($ENV{PERL5LIB} // '');
#     local $ENV{PERL5LIB} = "$script_root_dir/lib:" . ($ENV{PERL5LIB} // "");
#     system ($^X, $builddmg);
# }
#
# build_dmg();
#
#
