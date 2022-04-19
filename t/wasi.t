#!/usr/bin/env perl

use strict;
use warnings;

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

done_testing();
