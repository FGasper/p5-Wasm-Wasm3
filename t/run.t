#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Wasm::Wasm3;

use File::Slurper;

use FindBin;

my $wasm = Wasm::Wasm3->new();

my $rt = $wasm->create_runtime(1024);

my $mod = $wasm->parse_module( File::Slurper::read_binary("$FindBin::Bin/assets/perl_wasm_perl.wasm") );
$rt->load_module($mod);

my @params_to_perl;
$mod->link_function( qw(my func), 'F(ii)', sub {
    @params_to_perl = @_;
    return 2.345;
} );

my $value = $rt->call('callfunc');

is_deeply( \@params_to_perl, [0, 2], 'params WASM -> Perl callback' );

is( $value, 2.345, 'expected value from WASM -> Perl caller' );

done_testing;

1;
