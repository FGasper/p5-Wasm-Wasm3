#include "easyxs/easyxs.h"

#include "wasm3/source/wasm3.h"

#include <stdint.h>
#include <inttypes.h>

#define PERL_NS "Wasm::Wasm3"
#define PERL_ENV_CLASS (PERL_NS "::Environment")

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

/* ---------------------------------------------------------------------- */

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3

PROTOTYPES: DISABLE

# ----------------------------------------------------------------------

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3::Runtime

SV*
new (const char* classname, SV* stacksize_sv, SV* env_sv=NULL)
    CODE:
        uint32_t stacksize = exs_SvUV(stacksize_sv);
        if (stacksize > 0xffffffff) {
            croak("Stack size (%" PRIu32 ") exceeds max allowed (%u)", stacksize, 0xffffffffU);
        }

        IM3Environment env;

        if (env_sv) {
            if (!SvROK(env_sv) || !sv_derived_from_pv(env_sv, PERL_ENV_CLASS, 0)) {
                croak("Environment object must be a %s instance, not %" SVf, PERL_ENV_CLASS, env_sv);
            }

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

# ----------------------------------------------------------------------

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3::Environment

SV*
new (const char* classname)
    CODE:
        ww3_environ_s* env_sp;
        Newx(env_sp, 1, ww3_environ_s);

        *env_sp = (ww3_environ_s) {
            .env = m3_NewEnvironment(),
            .pid = getpid(),
            .refcount = 1,
        };

        RETVAL = newSV(0);
        sv_setref_pv(RETVAL, classname, env_sp);

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        ww3_environ_s* env_sp = exs_sv_getref_pv(self_sv, PERL_ENV_CLASS);

        if (PL_dirty && env_sp->pid == getpid()) {
            warn("%" SVf " destroyed at global destruction; memory leak likely!", self_sv);
        }

        _free_ww3_environ_s(env_sp);
