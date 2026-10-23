// =============================================================================
// gen_step_emu.cpp - Plain-C wrapper of gen_step for a PC-side DLL.
//
// Lets script/pc_side.py run the co-simulation with the *bit-accurate* HLS
// model instead of the board (--backend emu). All words are raw Q8.24 int32,
// exactly as on the UART.
//   in [13] : V, theta, Vref, Pref, delta, omega, Eq', Ed', Efd, Pm, x7, x8, x9
//   out[11] : delta, omega, Eq', Ed', Efd, Pm, x7, x8, x9 (k+1), Pg, Qg (k)
// Build: script/build_emu.bat
// =============================================================================
#include <stdint.h>
#include "gen_step.h"
#include "gen_params.h"

static q8_24_t from_raw(int32_t r)
{
    q8_24_t v;
    v.range(31, 0) = (uint32_t)r;
    return v;
}

static int32_t to_raw(q8_24_t v)
{
    return (int32_t)(uint32_t)v.range(31, 0).to_uint();
}

extern "C" __declspec(dllexport) void gen_step_raw(const int32_t *in, int32_t *out)
{
    q8_24_t o[11];
    gen_step(from_raw(in[0]), from_raw(in[1]), from_raw(in[2]), from_raw(in[3]),
             from_raw(in[4]), from_raw(in[5]), from_raw(in[6]), from_raw(in[7]),
             from_raw(in[8]), from_raw(in[9]), from_raw(in[10]), from_raw(in[11]),
             from_raw(in[12]),
             &o[0], &o[1], &o[2], &o[3], &o[4], &o[5], &o[6], &o[7], &o[8],
             &o[9], &o[10]);
    for (int i = 0; i < 11; i++)
        out[i] = to_raw(o[i]);
}

extern "C" __declspec(dllexport) int gen_step_id(void)
{
    return GEN_ID;
}
