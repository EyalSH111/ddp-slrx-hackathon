#include <k5_libs.h>
#include <slr_lib.h>
#include "slrx.h"

void conv_window_nox(uint8_t* conv_arr_out,
                     uint8_t* conv_arr_in,
                     int      arr_in_dim,
                     int      out_row_idx,
                     int      out_col_idx,
                     int8_t*  kernel_w,
                     int32_t  kernel_b) {

    int out_dim = arr_in_dim - CONV_KERNEL_DIM + 1;
    int32_t acc = kernel_b;

    for (int kernel_row_idx = 0; kernel_row_idx < CONV_KERNEL_DIM; kernel_row_idx++) {
        for (int kernel_col_idx = 0; kernel_col_idx < CONV_KERNEL_DIM; kernel_col_idx++) {
            int in_row_idx = out_row_idx + kernel_row_idx;
            int in_col_idx = out_col_idx + kernel_col_idx;
            int arr_in_idx = (in_row_idx * arr_in_dim) + in_col_idx;
            uint8_t in_val = ((volatile uint8_t*)conv_arr_in)[arr_in_idx];
            int8_t weight  = ((volatile int8_t(*)[CONV_KERNEL_DIM])kernel_w)[kernel_row_idx][kernel_col_idx];
            acc += (int32_t)in_val * (int32_t)weight;
        }
    }
    int arr_out_idx = (out_row_idx * out_dim) + out_col_idx;
    ((volatile uint8_t*)conv_arr_out)[arr_out_idx] = relu_and_descale(acc);
}

// Normal conv HW setup (Phase 3): loops over entire conv layer, writes conv output
void conv_xlr_setup(uint8_t* conv_arr_out,
                    uint8_t* conv_arr_in,
                    int      arr_in_dim,
                    int8_t*  kernel_w,
                    int32_t  kernel_b) {
    #ifdef HLCM
    printf("HLCM does not support HW acceleration, quitting\n\n");
    bm_quit_app();
    #else
    HOST_REG(WGT_ADDR_RI)      = (unsigned int)kernel_w;
    HOST_REG(CONV_BIAS_VAL_RI) = kernel_b;
    HOST_REG(ARR_IN_ADDR_RI)   = (unsigned int)conv_arr_in;
    HOST_REG(ARR_OUT_ADDR_RI)  = (unsigned int)conv_arr_out;
    HOST_REG(ARR_IN_DIM_RI)    = arr_in_dim;
    HOST_REG(OUT_ROW_IDX_RI)   = 0;  // normal mode (not fused)
    HOST_REG(XLR_START_RI) = CONV_SETUP;
    while (!HOST_REG(XLR_DONE_RI)) {}
    #endif
}

// Fused conv+pool HW setup (Phase 4):
// Loops over entire conv layer AND computes 2x2 MaxPool internally.
// pool_arr_out: address of the pool output buffer (HW writes directly here).
// arr_in_dim:   input dimension (conv input, e.g. 32 for Conv0 or 14 for Conv1).
// Result: pool_arr_out is filled with (arr_in_dim-4)/2 x (arr_in_dim-4)/2 pool outputs.
// SW must skip the pool() call for this layer when using fused mode.
void conv_xlr_setup_fused(uint8_t* pool_arr_out,
                           uint8_t* conv_arr_in,
                           int      arr_in_dim,
                           int8_t*  kernel_w,
                           int32_t  kernel_b) {
    #ifdef HLCM
    printf("HLCM does not support HW acceleration, quitting\n\n");
    bm_quit_app();
    #else
    HOST_REG(WGT_ADDR_RI)      = (unsigned int)kernel_w;
    HOST_REG(CONV_BIAS_VAL_RI) = kernel_b;
    HOST_REG(ARR_IN_ADDR_RI)   = (unsigned int)conv_arr_in;
    HOST_REG(ARR_OUT_ADDR_RI)  = (unsigned int)pool_arr_out;  // pool output, not conv output
    HOST_REG(ARR_IN_DIM_RI)    = arr_in_dim;
    HOST_REG(OUT_ROW_IDX_RI)   = 1;  // fused pool mode enable
    HOST_REG(XLR_START_RI) = CONV_SETUP;
    while (!HOST_REG(XLR_DONE_RI)) {}
    HOST_REG(OUT_ROW_IDX_RI)   = 0;  // reset fused flag after done
    #endif
}

void conv(uint8_t* conv_arr_out,
          uint8_t* conv_arr_in,
          int      arr_in_dim,
          int8_t*  kernel_w,
          int32_t  kernel_b) {

    int out_dim = arr_in_dim - CONV_KERNEL_DIM + 1;

    #ifdef CONV_XON
    conv_xlr_setup(conv_arr_out, conv_arr_in, arr_in_dim, kernel_w, kernel_b);
    #else
    for (int out_row_idx = 0; out_row_idx < out_dim; out_row_idx++){
      for (int out_col_idx = 0; out_col_idx < out_dim; out_col_idx++){
        conv_window_nox(conv_arr_out, conv_arr_in, arr_in_dim, out_row_idx, out_col_idx, kernel_w, kernel_b);
      }
    }
    #endif
}
