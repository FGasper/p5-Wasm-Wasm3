#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::FailWarnings;

use Wasm::Wasm3::Environment ();

my $env = Wasm::Wasm3::Environment->new();

isa_ok($env, 'Wasm::Wasm3::Environment', 'new() result');

undef $env;

done_testing;
