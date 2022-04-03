#include "easyxs/easyxs.h"

#include "wasm3/source/wasm3.h"

#include <stdint.h>
#include <inttypes.h>

#define PERL_NS "Wasm::Wasm3"
#define PERL_ENV_CLASS (PERL_NS "::Environment")
#define PERL_RT_CLASS (PERL_NS "::Runtime")

typedef struct {
    IM3Environment env;
    pid_t pid;
    uint32_t refcount;
} ww3_environ_s;

static void _free_ww3_environ_s (ww3_environ_s* env_sp) {
    if (!--env_sp->refcount) {
        m3_FreeEnvironment(env_sp->env);
    }
}

typedef struct {
    IM3Runtime rt;
    pid_t pid;

    /* Only one of these gets set: */
    SV* env_sv;
    IM3Environment own_env;
} ww3_runtime_s;

SV* _create_runtime (pTHX_ const char* classname, SV* stacksize_sv, SV* env_sv) {
    uint32_t stacksize = exs_SvUV(stacksize_sv);
    if (stacksize > 0xffffffff) {
        croak("Stack size (%" PRIu32 ") exceeds max allowed (%u)", stacksize, 0xffffffffU);
    }

    IM3Environment env;

    if (env_sv) {
        SvREFCNT_inc(env_sv);

        ww3_environ_s* env_sp = exs_structref_ptr(env_sv);
        env = env_sp->env;
    }
    else {
        env = m3_NewEnvironment();
    }

    SV* self_sv = exs_new_structref(ww3_runtime_s, classname);
    ww3_runtime_s* rt_sp = exs_structref_ptr(self_sv);

    *rt_sp = (ww3_runtime_s) {
        .rt = m3_NewRuntime(env, stacksize, NULL),
        .pid = getpid(),
        .env_sv = env_sv,
        .own_env = env_sv ? env : NULL,
    };

    return self_sv;
}

/* ---------------------------------------------------------------------- */

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3

PROTOTYPES: DISABLE

# ----------------------------------------------------------------------

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3::Runtime

SV*
new (const char* classname, SV* stacksize_sv)
    CODE:
        RETVAL = _create_runtime(aTHX_ classname, stacksize_sv, NULL);
    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        ww3_runtime_s* rt_sp = exs_structref_ptr(self_sv);

        if (PL_dirty && rt_sp->pid == getpid()) {
            warn("%" SVf " destroyed at global destruction; memory leak likely!", self_sv);
        }

        m3_FreeRuntime(rt_sp->rt);

        if (rt_sp->env_sv) SvREFCNT_dec(rt_sp->env_sv);

# ----------------------------------------------------------------------

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3::Environment

SV*
new (const char* classname)
    CODE:
        SV* env_sv = exs_new_structref(ww3_environ_s, classname);
        ww3_environ_s* env_sp = exs_structref_ptr(env_sv);

        *env_sp = (ww3_environ_s) {
            .env = m3_NewEnvironment(),
            .pid = getpid(),
        };

        RETVAL = env_sv;

    OUTPUT:
        RETVAL

SV*
create_runtime (SV* self_sv, SV* stacksize_sv)
    CODE:
        RETVAL = _create_runtime(aTHX_ PERL_RT_CLASS, stacksize_sv, self_sv);
    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        ww3_environ_s* env_sp = exs_structref_ptr(self_sv);

        if (PL_dirty && env_sp->pid == getpid()) {
            warn("%" SVf " destroyed at global destruction; memory leak likely!", self_sv);
        }

        _free_ww3_environ_s(env_sp);
