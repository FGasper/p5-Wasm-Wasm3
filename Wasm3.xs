#include "easyxs/easyxs.h"

#include "wasm3/source/wasm3.h"

typedef struct {
    IM3Environment env;
    pid_t pid;
} ww3_environ_s;

/* ---------------------------------------------------------------------- */

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3

PROTOTYPES: DISABLE

# ----------------------------------------------------------------------

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3::Environment

SV*
new (const char* classname)
    CODE:
        SV* env_sv = exs_new_structref(ww3_environ_s, "Wasm::Wasm3::Environment");
        ww3_environ_s* env_sp = exs_structref_ptr(env_sv);

        *env_sp = (ww3_environ_s) {
            .env = m3_NewEnvironment(),
            .pid = getpid(),
        };

        RETVAL = env_sv;
    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        ww3_environ_s* env_sp = exs_structref_ptr(self_sv);
        if (PL_dirty && env_sp->pid == getpid()) {
            warn("%" SVf " destroyed at global destruction; memory leak likely!", self_sv);
        }

        m3_FreeEnvironment(env_sp->env);
