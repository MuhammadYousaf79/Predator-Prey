// =============================================================================
// gen_params.h - Machine 1 parameters of the Kundur 4-machine system
//                (taken from Load_Kundur_System() in TA_Simulation.m)
//
// All per-unit values are on MVA_Base = 100 MVA. Every coefficient used by the
// hardware is pre-multiplied by the Euler step h = 1 ms, so the datapath only
// has to compute   X(k+1) = X(k) + DELTA_X(k).
// This also keeps large constants (ws = 377, KA = 200, Ksg/R = 200) out of the
// Q8.24 range limit of +/-128.
// =============================================================================
#ifndef GEN_PARAMS_H
#define GEN_PARAMS_H

// ---------------------------------------------------------------- base data --
static const double P_MVA_BASE = 100.0;
static const double P_MACH_SCALE = P_MVA_BASE / 900.0;   // machine -> system base
static const double P_PI = 3.14159265358979323846;

static const double P_H_STEP = 0.001;                    // Euler step [s] = 1 ms
static const double P_WS     = 2.0 * P_PI * 60.0;        // synchronous speed

// Synchronous machine (two-axis model)
static const double P_H       = 6.5 * 900.0 / P_MVA_BASE;
static const double P_KD      = 2.0 * 900.0 / P_MVA_BASE; // K_d Changed from 0.0 to 2.0
static const double P_XD      = 1.8    * P_MACH_SCALE;
static const double P_XQ      = 1.7    * P_MACH_SCALE;
static const double P_XD_P    = 0.3    * P_MACH_SCALE;   // xd'
static const double P_XQ_P    = 0.55   * P_MACH_SCALE;   // xq'
static const double P_RS      = 0.0025 * P_MACH_SCALE;
static const double P_TDO_P   = 8.0;                     // Tdo'
static const double P_TQO_P   = 0.4;                     // Tqo'

// Exciter
static const double P_KA      = 200.0;
static const double P_TA      = 0.01;

// Governor
static const double P_KSG     = 10.0;
static const double P_TSG     = 1.0;
static const double P_R       = 0.05;

// Power system stabiliser
static const double P_KSTAB   = 3.5;
static const double P_TW      = 10.0;
static const double P_TSTAB1  = 0.02;
static const double P_TSTAB2  = 0.05;
static const double P_TSTAB3  = 6.0;
static const double P_TSTAB4  = 5.4;

// ------------------------------------------------------ derived coefficients --
// Stator algebraic equations: Id/Iq = linear combination of (Ed'-Vd), (Eq'-Vq)
static const double P_DEN     = P_RS * P_RS + P_XD_P * P_XQ_P;
static const double C_RS_DEN  = P_RS   / P_DEN;          // Rs  / den
static const double C_XQP_DEN = P_XQ_P / P_DEN;          // xq' / den
static const double C_XDP_DEN = P_XD_P / P_DEN;          // xd' / den
static const double C_RS      = P_RS;
static const double C_XD_DIFF = P_XD - P_XD_P;           // xd - xd'
static const double C_XQ_DIFF = P_XQ - P_XQ_P;           // xq - xq'

// Differential equations (already multiplied by h)
static const double C_H_WS     = P_H_STEP * P_WS;                       // d(delta)
static const double C_H_2H     = P_H_STEP / (2.0 * P_H);                // d(omega)
static const double C_KD       = P_KD;
static const double C_H_TDO    = P_H_STEP / P_TDO_P;                    // d(Eq')
static const double C_H_TQO    = P_H_STEP / P_TQO_P;                    // d(Ed')
static const double C_H_TA     = P_H_STEP / P_TA;                       // d(Efd)
static const double C_H_KA_TA  = P_H_STEP * P_KA / P_TA;
static const double C_H_TSG    = P_H_STEP / P_TSG;                      // d(Pm)
static const double C_H_KSG    = P_H_STEP * P_KSG / P_TSG;
static const double C_H_KSG_R  = P_H_STEP * P_KSG / (P_TSG * P_R);
static const double C_H_TW     = P_H_STEP / P_TW;                       // d(x7)
static const double C_KSTAB    = P_KSTAB;
static const double C_H_T2     = P_H_STEP / P_TSTAB2;                   // d(x8)
static const double C_T1_T2    = P_TSTAB1 / P_TSTAB2;
static const double C_H_T4     = P_H_STEP / P_TSTAB4;                   // d(x9)
static const double C_T3_T4    = P_TSTAB3 / P_TSTAB4;

// Angle range reduction
static const double C_TWO_PI   = 2.0 * P_PI;
static const double C_INV_2PI  = 1.0 / (2.0 * P_PI);
static const double C_HALF_PI  = P_PI / 2.0;

#endif
