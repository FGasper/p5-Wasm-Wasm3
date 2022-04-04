#include "easyxs/easyxs.h"

#include "wasm3/source/wasm3.h"

#include <stdint.h>
#include <inttypes.h>

#define PERL_NS "Wasm::Wasm3"
#define PERL_ENV_CLASS (PERL_NS "::Environment")
#define PERL_RT_CLASS (PERL_NS "::Runtime")
#define PERL_MODULE_CLASS (PERL_NS "::Module")

#define MAX_UINT32 0xffffffff
#define MAX_MEMSIZE MAX_UINT32

typedef struct {
    IM3Environment env;
    pid_t pid;
    uint32_t refcount;
} ww3_environ_s;

typedef struct {
    IM3Runtime rt;
    pid_t pid;

    /* Only one of these gets set: */
    SV* env_sv;
    IM3Environment own_env;
} ww3_runtime_s;

typedef struct {
    pid_t pid;
    const uint8_t* bytes;
    STRLEN len;
    IM3Module module;
} ww3_module_s;

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

IM3Global _get_module_sv_global (pTHX_ SV* self_sv, SV* name_sv) {
    const char* name = exs_SvPVutf8_nolen(name_sv);

    ww3_module_s* mod_sp = exs_structref_ptr(self_sv);

    return m3_FindGlobal(mod_sp->module, name);
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
call_function (SV* self_sv, SV* name_sv, ...)
    PPCODE:
        ww3_runtime_s* rt_sp = exs_structref_ptr(self_sv);

        const char* name = exs_SvPVutf8_nolen(name_sv);

        IM3Function o_function;
        M3Result res = m3_FindFunction( &o_function, rt_sp->rt, name );
        if (res) croak("Failed to find function %s: %s", name, res);

        uint32_t args_count = m3_GetArgCount(o_function);

        int given_args_count = items - 2;
        if (given_args_count != args_count) {
            croak("%s needs %d argument%s; %d given", name, args_count, (args_count > 1) ? "s" : "", given_args_count);
        }

        /*
            List & void contexts are always OK.
            Scalar is OK as long as there aren’t multiple returns.
        */
        uint32_t returns_count = m3_GetRetCount(o_function);
        if (returns_count > 1) {
            if (GIMME_V == G_SCALAR) {
                croak("%s returns %d arguments and so must be called in list or void context, not scalar", name, returns_count);
            }
        }

        void* argptrs[args_count];
        int64_t args[args_count];

        for (unsigned a=0; a<args_count; a++) {
            argptrs[a] = (args + a);

            switch (m3_GetArgType(o_function, a)) {
                case c_m3Type_none:
                    croak("%s: Argument #%u’s type is unknown!", name, 1 + a);

                case c_m3Type_i32:
                    *( (int32_t*) (args + a) ) = SvIV( ST(2 + a) );
                    break;

                case c_m3Type_i64:
                    args[a] = SvIV( ST(2 + a) );
                    break;

                case c_m3Type_f32:
                    *( (float*) (args + a) ) = SvNV( ST(2 + a) );
                    break;

                case c_m3Type_f64:
                    *( (double*) (args + a) ) = SvNV( ST(2 + a) );
                    break;

                default:
                    croak("%s: Argument #%u’s type (%d) is unexpected!", name, 1 + a, m3_GetArgType(o_function, a));
            }
        }

        res = m3_Call( o_function, args_count, (const void **) argptrs );
        if (res) croak("%s(): %s", name, res);

        void* retptrs[returns_count];
        res = m3_GetResults( o_function, returns_count, (const void **) retptrs );
        if (res) croak("%s (m3_GetResults): %s", name, res);

        EXTEND(SP, returns_count);
        for (unsigned r=0; r<returns_count; r++) {
            SV* newret;

            switch (m3_GetRetType(o_function, r)) {
                case c_m3Type_none:
                    croak("%s: Return #%u’s type is unknown!", name, 1 + r);

                case c_m3Type_i32:
                    newret = newSViv( *( (int32_t*) retptrs[r] ) );
                    break;

                case c_m3Type_i64:
                    newret = newSViv( *( (int64_t*) retptrs[r] ) );
                    break;

                case c_m3Type_f32:
                    newret = newSVnv( *( (float*) retptrs[r] ) );
                    break;

                case c_m3Type_f64:
                    newret = newSVnv( *( (double*) retptrs[r] ) );
                    break;

                default:
                    croak("%s: Return #%u’s type (%d) is unexpected!", name, 1 + r, m3_GetRetType(o_function, r));
            }

            mPUSHs(newret);
        }

SV*
load_module (SV* self_sv, SV* module_sv)
    CODE:
        if (!SvROK(module_sv) || !sv_derived_from(module_sv, PERL_MODULE_CLASS)) {
            croak("Need %s instance, not %" SVf, PERL_MODULE_CLASS, module_sv);
        }

        ww3_runtime_s* rt_sp = exs_structref_ptr(self_sv);
        ww3_module_s* mod_sp = exs_structref_ptr(module_sv);

        M3Result res = m3_LoadModule(rt_sp->rt, mod_sp->module);

        if (res) croak("%s", res);

        /* m3_LoadModule transfers ownership of the module, so we ...
        */
        mod_sp->bytes = NULL;

        RETVAL = SvREFCNT_inc(self_sv);
    OUTPUT:
        RETVAL

SV*
get_memory (SV* self_sv, SV* offset_sv, SV* wantlen_sv)
    CODE:
        UV offset = exs_SvUV(offset_sv);
        UV wantlen = exs_SvUV(wantlen_sv);

        ww3_runtime_s* rt_sp = exs_structref_ptr(self_sv);

        uint32_t memsize;
        uint8_t* mem = m3_GetMemory(rt_sp->rt, &memsize, 0);

        if (offset > memsize) {
            croak("offset (%" UVf ") exceeds memory size (%" PRIu32 ")", offset, memsize);
        }

        if (wantlen > (memsize - offset)) {
            wantlen = (memsize - offset);
        }

        RETVAL = newSVpvn((char*) (mem + offset), wantlen);

    OUTPUT:
        RETVAL

UV
get_memory_size (SV* self_sv)
    CODE:
        ww3_runtime_s* rt_sp = exs_structref_ptr(self_sv);

        uint32_t memsize = 0;
        m3_GetMemory(rt_sp->rt, &memsize, 0);

        RETVAL = memsize;

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

MODULE = Wasm::Wasm3        PACKAGE = Wasm::Wasm3::Module

SV*
set_name (SV* self_sv)
    CODE:
        RETVAL = SvREFCNT_inc(self_sv);

    OUTPUT:
        RETVAL

SV*
get_global_type (SV* self_sv, SV* name_sv)
    CODE:
        IM3Global i_global = _get_module_sv_global(aTHX_ self_sv, name_sv);

        if (i_global) {
            RETVAL = newSVuv( m3_GetGlobalType(i_global) );
        }
        else {
            RETVAL = &PL_sv_undef;
        }

    OUTPUT:
        RETVAL

SV*
get_global (SV* self_sv, SV* name_sv)
    CODE:
        IM3Global i_global = _get_module_sv_global(aTHX_ self_sv, name_sv);

        if (i_global) {
            M3TaggedValue tagged;
            M3Result res = m3_GetGlobal(i_global, &tagged);
            if (res) croak("%s", res);

            switch (tagged.type) {
                case c_m3Type_none:
                    croak("Global “%" SVf "” is untyped!", name_sv);

                case c_m3Type_i32:
                    RETVAL = newSViv( tagged.value.i32 );
                    break;

                case c_m3Type_i64:
                    RETVAL = newSViv( tagged.value.i64 );
                    break;

                case c_m3Type_f32:
                    RETVAL = newSVnv( tagged.value.f32 );
                    break;

                case c_m3Type_f64:
                    RETVAL = newSVnv( tagged.value.f64 );
                    break;

                default:
                    croak("Global “%" SVf "” is of unexpected type (%d)!", name_sv, tagged.type);
            }
        }
        else {
            RETVAL = &PL_sv_undef;
        }

    OUTPUT:
        RETVAL

void
DESTROY (SV* self_sv)
    CODE:
        ww3_module_s* mod_sp = exs_structref_ptr(self_sv);

        if (PL_dirty && mod_sp->pid == getpid()) {
            warn("%" SVf " destroyed at global destruction; memory leak likely!", self_sv);
        }

        if (mod_sp->bytes) {
            Safefree(mod_sp->bytes);
            m3_FreeModule(mod_sp->module);
        }

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

SV* parse_module (SV* self_sv, SV* modbytes_sv)
    CODE:
        ww3_environ_s* env_sp = exs_structref_ptr(self_sv);

        STRLEN modlen;
        const char* modbytes_orig = SvPVbyte(modbytes_sv, modlen);

        const uint8_t* modbytes;
        Newx(modbytes, modlen, uint8_t);
        Copy(modbytes_orig, modbytes, modlen, uint8_t);

        IM3Module mod;
        M3Result err = m3_ParseModule(env_sp->env, &mod, modbytes, modlen);

        if (err) {
            Safefree(modbytes);
            croak("%s", err);
        }

        RETVAL = exs_new_structref(ww3_module_s, PERL_MODULE_CLASS);
        ww3_module_s* mod_sp = exs_structref_ptr(RETVAL);

        *mod_sp = (ww3_module_s) {
            .pid = getpid(),
            .bytes = modbytes,
            .len = modlen,
            .module = mod,
        };

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
