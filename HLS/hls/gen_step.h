// =============================================================================
// gen_step.h - One forward-Euler step (h = 1 ms) of generator GEN_ID of the Kundur
//              system: two-axis machine + exciter + governor + PSS (9 states).
//
// Port / state / UART format : Q8.24 (signed 32 bit, 8 integer, 24 fraction)
// =============================================================================
#ifndef GEN_STEP_H
#define GEN_STEP_H

#include <ap_fixed.h>

// Q8.24: the format of every port, every state and every UART word
typedef ap_fixed<32, 8>                   q8_24_t;
// Same bit format, but rounds to nearest and saturates on assignment
typedef ap_fixed<32, 8, AP_RND, AP_SAT>   q8_24_rnd_t;

// Internal types (extra guard bits so h-scaled increments do not vanish
// before they are added to the Q8.24 state)
typedef ap_fixed<36, 8>                   alg_t;    // Vd, Vq, Id, Iq, Pg ...
typedef ap_fixed<48, 12>                  wide_t;   // state increments
typedef ap_fixed<32, 6>                   kc_t;     // coefficients |c| < 32
typedef ap_ufixed<32, -10>                ks_t;     // coefficients 0 < c < 2^-10
typedef ap_fixed<32, 3>                   cordic_t; // sin / cos datapath

#define GEN_NSTATE 9

void gen_step(
    // ---- algebraic inputs from the CPU (network solution, every step) ----
    q8_24_t  v_mag,      // terminal bus voltage magnitude   [pu]
    q8_24_t  v_ang,      // terminal bus voltage angle       [rad]
    // ---- set-points from the CPU (sent once with the initial state) ----
    q8_24_t  v_ref,
    q8_24_t  p_ref,
    // ---- present state X(k) ----
    q8_24_t  delta,      // x1  rotor angle               [rad]
    q8_24_t  omega,      // x2  rotor speed               [pu]
    q8_24_t  eq_p,       // x3  Eq'
    q8_24_t  ed_p,       // x4  Ed'
    q8_24_t  efd,        // x5  field voltage
    q8_24_t  pm,         // x6  mechanical power (Psg)
    q8_24_t  x7,         // x7  PSS washout
    q8_24_t  x8,         // x8  PSS lead-lag 1
    q8_24_t  x9,         // x9  PSS lead-lag 2
    // ---- next state X(k+1) ----
    q8_24_t *delta_n,
    q8_24_t *omega_n,
    q8_24_t *eq_p_n,
    q8_24_t *ed_p_n,
    q8_24_t *efd_n,
    q8_24_t *pm_n,
    q8_24_t *x7_n,
    q8_24_t *x8_n,
    q8_24_t *x9_n,
    // ---- generator injections at step k (needed by the CPU network solver) --
    q8_24_t *pg,
    q8_24_t *qg);

#endif
