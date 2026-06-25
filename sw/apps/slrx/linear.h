#ifndef _LINEAR_H_
#define _LINEAR_H_


#include <k5_libs.h>
#include <slr_lib.h>
#include "slrx.h" 

//------------------------------------------------------------------------------------------------------------

// Linear Layer element

uint8_t lin_elem(uint8_t* lin_arr_in,   // linear Input Image (single row)
              int         lin_in_dim,   // linear Input dimensions           
              int8_t*     linear_w_trn, // linear Weights Transposed, can be negative (2D matrix)
              int32_t*    linear_b,     // linear Bias, can be negative (single row)
              int         lin_out_idx); // output vector element index


//------------------------------------------------------------------------------------------------------------

 // Linear Layer 

void linear(uint8_t* lin_arr_out,  // linear output feature-map (single row)
            uint8_t* lin_arr_in,   // linear Input Image (single row)
            int      lin_in_dim,   // linear Input dimensions
            int      lin_out_dim,  // linear Input dimensions              
            int8_t*  linear_w_trn, // linear Weights Transposed, can be negative (2D matrix)
            int32_t* linear_b);    // linear Bias, can be negative (single row)


//------------------------------------------------------------------------------------------------------------

#endif