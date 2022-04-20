#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use Test::More;
use Test::Deep;
use Test::FailWarnings;

use Wasm::Wasm3;

use File::Spec;
use File::Temp;
use Scope::Guard;

use File::Slurper;

use FindBin;

my $wasm = Wasm::Wasm3->new();

my $wasm_bin = File::Slurper::read_binary(
    File::Spec->catfile($FindBin::Bin, qw(assets wasi-demo.wasm) ),
);

{
last;
    my $mod = $wasm->parse_module($wasm_bin);
    my $rt = $wasm->create_runtime(102400)->load_module($mod);

    my $tfh = File::Temp::tempfile();

    {
        open my $dupe_stdout, '>&', \*STDOUT;
        close \*STDOUT;
        open \*STDOUT, '>&', $tfh;

        my $guard = Scope::Guard->new( sub {
            close \*STDOUT;
            open \*STDOUT, '>&', $dupe_stdout;
        } );

        $mod->link_wasi_default();

        $rt->call('_start');
    }

    sysseek $tfh, 0, 0;

    my $got = do { local $/; <$tfh> };

    like($got, qr<hello.+world>i, 'WASI ran');
}

#----------------------------------------------------------------------

SKIP: {
    skip "Needs uvwasi", 1 if Wasm::Wasm3::WASI_BACKEND ne 'uvwasi';

    my $mod = $wasm->parse_module($wasm_bin);
    my $rt = $wasm->create_runtime(102400)->load_module($mod);

    my $in = File::Temp::tempfile();
    syswrite( $in, 'this is stdin' );
    sysseek( $in, 0, 0 );

    my $out = File::Temp::tempfile();
    my $err = File::Temp::tempfile();

    my $dir = File::Temp::tempdir( CLEANUP => 1 );
    mkdir "$dir/ü";
    do {
        open my $a, '>', "$dir/ü/abc";
        open my $b, '>', "$dir/ü/é";
        open my $c, '>', "$dir/ü/ø";
    };

    $mod->link_wasi(
        in => fileno($in),
        out => fileno($out),
        err => fileno($err),

        #argv => [qw( this is argv )],

        env => [
            THIS => 'is',
            ENV => 'wasm::wasm3',
        ],

        preopen => {
            "/\x{e9}p\xe9e" => "$dir/ü",
        },
    );

    $rt->call('_start');

    sysseek $out, 0, 0;
    my $got = do { local $/; <$out> };
    like($got, qr<hello.+world>i, 'WASI ran');
    like($got, qr<THIS.*is>, 'env 1');
    like($got, qr<ENV.*wasm::wasm3>, 'env 2');
    like($got, qr<épée.*abc.*é.*ø>, 'preopen & printout');

    sysseek $err, 0, 0;
    my $got2 = do { local $/; <$err> };
    like( $got2, qr<stdin.*this is stdin>, 'read from stdin, wrote to stderr' );
}

done_testing();
