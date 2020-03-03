use 5.020;
use strict;
use warnings;

package FFICHECK {

    use Carp;
    use FFI::Platypus;
    use FFI::Platypus::Buffer;
    
    use Alien::gdal;
    
    #eval 'require Geo::GDAL::FFI'
    #  or warn "unable to load Geo::GDAL::FFI";
    
    say join "\n", Alien::gdal->dynamic_libs;
    
    
    my $ffi = FFI::Platypus->new;
    $ffi->load_custom_type('::StringPointer' => 'string_pointer');
    $ffi->lib(Alien::gdal->dynamic_libs);
    
    $ffi->type('(pointer,size_t,size_t,opaque)->size_t' => 'VSIWriteFunction');
    $ffi->type('(int,int,string)->void' => 'CPLErrorHandler');
    $ffi->type('(double,string,pointer)->int' => 'GDALProgressFunc');
    $ffi->type('(pointer,int, pointer,int,int,unsigned int,unsigned int,int,int)->int' => 'GDALDerivedPixelFunc');
    $ffi->type('(pointer,int,int,pointer,pointer,pointer,pointer)->int' => 'GDALTransformerFunc');
    $ffi->type('(double,int,pointer,pointer,pointer)->int' => 'GDALContourWriter');
    
    # from port/*.h
    eval{$ffi->attach(VSIMalloc => [qw/uint/] => 'opaque');};
    warn $@ if $@;
    croak "Can't attach to GDAL methods. Does Alien::gdal provide GDAL dynamic libs?" unless FFICHECK->can('VSIMalloc');
    
    1;

};

1;
