use strict;
use warnings;

use ExtUtils::MakeMaker::CPANfile;
use ExtUtils::CBuilder;
use File::Temp;
use File::Spec;

my $uvwasi_inc = File::Spec->catdir( qw( wasm3 _deps uvwasi-src include ) );

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Wasm::Wasm3',
    VERSION_FROM      => 'lib/Wasm/Wasm3.pm', # finds $VERSION
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Wasm/Wasm3.pm', # retrieve abstract from module
       AUTHOR         => [
            'Felipe Gasper (FELIPE)',
        ],
      ) : ()
    ),
    INC               => "-I$uvwasi_inc -Wall -std=c99",
    LICENSE           => "perl_5",

    DEFINE => '-Dd_m3HasUVWASI',

    OBJECT => join(
        q< >,
        '$(BASEEXT)$(OBJ_EXT)',
        File::Spec->catfile( qw(wasm3 source libm3.a) ),
        File::Spec->catfile( qw(wasm3 _deps uvwasi-build libuvwasi_a.a) ),
        File::Spec->catfile( qw(wasm3 _deps libuv-build libuv_a.a) ),
    ),

    PMLIBDIRS => ['lib'],

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url => 'git://github.com/FGasper/p5-Wasm-Wasm3.git',
                web => 'https://github.com/FGasper/p5-Wasm-Wasm3',
            },
            bugtracker => {
                web => 'https://github.com/FGasper/p5-Wasm-Wasm3/issues',
            },
        },
    },
);

# ----------------------------------------------------------------------

package MY;

use Alien::cmake3;
use Config;

sub postamble {
    my $cmake_path = File::Spec->catfile(
        Alien::cmake3->bin_dir(),
        Alien::cmake3->exe(),
    );

    my @cmake_opts = (
        #-D => 'BUILD_WASI=none',

        # _XOPEN_SOURCE is for Cygwin to have ptsname():
        -D => q/CMAKE_C_FLAGS='-fPIC -D_XOPEN_SOURCE=500'/,

        -D => "APP_DIR='../wasm3-dummy-app-dir'",
    );

    if ($^O eq 'MSWin32') {
        push @cmake_opts, -G => q<'MinGW Makefiles'>,
    }

    return <<"MAKE_FRAG"

.PHONY:
build-wasm3:
\t$cmake_path @cmake_opts -S wasm3 -B wasm3
\t\$(MAKE) -C wasm3
MAKE_FRAG
}

my $orig_top_targets;
BEGIN {
$orig_top_targets = __PACKAGE__->can('top_targets');
}

sub top_targets {
    my $out = $orig_top_targets->(@_);

    $out =~ s<^(all\s*:+s*)><$1 build-wasm3 >;

    return $out;
}
