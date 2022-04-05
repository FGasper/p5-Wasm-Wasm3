package Wasm::Wasm3;

use strict;
use warnings;

=encoding utf-8

=head1 NAME

Wasm::Wasm3 - L<WebAssembly|https://webassembly.org/> in Perl via L<wasm3|https://github.com/wasm3/wasm3>

=head1 SYNOPSIS

    my $env = Wasm::Wasm3->new();
    my $module = $env->parse_module($wasm_binary);
    my $runtime = $env->create_runtime(1024)->load_module($module);

    my $global = $module->get_global('some-value');
    $module->set_global('some-value', 1234);

    my @out = $runtime->call('some-func', @args);

=head1 DESCRIPTION

WebAssembly runtimes like L<Wasmer|https://wasmer.io>,
L<Wasmtime|https://wasmtime.dev>, or L<WAVM|https://github.com/wavm/wavm>
often have build processes that take a long time or fail easily. The
resulting library can be quite large, too.

Enter L<wasm3|https://github.com/wasm3/wasm3>, which takes a different
approach from the “big dogs”: whereas the above are all JIT compilers,
wasm3 is a WebAssembly I<interpreter>. This makes it quite small and
fast/simple to build. Runtime performance suffers accordingly, of course,
but that’s not always the worst of things.

=head1 DOCUMENTATION

This module generally documents only those aspects of its usage that
are germane to this module specifically. For more details, see
wasm3’s documentation.

=cut

#----------------------------------------------------------------------

use XSLoader;

our $VERSION = '0.01_01';

XSLoader::load( __PACKAGE__, $VERSION );

#----------------------------------------------------------------------

=head1 STATIC FUNCTIONS

=head2 ($MAJOR, $MINOR, $REV) = m3_version()

Returns wasm3’s version as 3 integers.

=head2 $STRING = m3_version_string()

Returns wasm3’s version as a string.

=head1 METHODS

=head2 $WASM3_ENV = I<CLASS>->new()

Instanties I<CLASS>.
Creates a new wasm3 environment and binds it to the returned object.

=head2 $RUNTIME = I<OBJ>->create_runtime( $STACKSIZE )

Creates a new wasm3 runtime from I<OBJ>.
Returns a L<Wasm::Wasm3::Runtime> instance.

=head2 $MODULE = I<OBJ>->parse_module( $WASM_BINARY )

Loads a WebAssembly module from I<binary> (F<*.wasm>) format.
Returns a L<Wasm::Wasm3::Module> instance.

If your WebAssembly module is in text format rather than binary,
you’ll need to convert it first. Try
L<wabt|https://github.com/webassembly/wabt> if you need such a tool.

=cut

1;
