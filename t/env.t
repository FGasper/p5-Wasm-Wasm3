#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Wasm::Wasm3::Environment ();

{
    my $env = Wasm::Wasm3::Environment->new();

    isa_ok($env, 'Wasm::Wasm3::Environment', 'new() result');
}

{
    my $rt = Wasm::Wasm3::Environment->new()->create_runtime(1234);
    isa_ok($rt, 'Wasm::Wasm3::Runtime', 'create_runtime() result');
}

done_testing;
