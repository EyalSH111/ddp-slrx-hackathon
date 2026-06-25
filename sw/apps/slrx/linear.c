#include <k5_libs.h>
#include <slr_lib.h>
#include "slrx.h" 

//------------------------------------------------------------------------------------------------------------

void lin_elem_setup(uint8_t* lin_arr_out,  // linear output feature-map (single row)
                    uint8_t* lin_arr_in,   // linear Input Image (single row)
                    int      lin_in_dim,   // linear Input dimensions 
                    int      lin_out_dim,   // linear Output dimensions                     
                    int8_t*  linear_w_trn, // linear Weights Transposed, can be negative (2D matrix)
                    int32_t* linear_b) {   // linear Bias, can be negative (single row)

    #ifdef HLCM    
    printf("HLCM does not support HW acceleration, quitting\n\n");
    bm_quit_app();
    #else

    HOST_REG(ARR_OUT_ADDR_RI)  = (unsigned int)lin_arr_out;
    HOST_REG(ARR_IN_ADDR_RI)   = (unsigned int)lin_arr_in;
    HOST_REG(ARR_IN_DIM_RI)    = lin_in_dim;
    HOST_REG(ARR_OUT_DIM_RI)   = lin_out_dim;    
    HOST_REG(WGT_ADDR_RI)      = (unsigned int)linear_w_trn;
    HOST_REG(LIN_BIAS_ADDR_RI) = (unsigned int)linear_b;
    HOST_REG(XLR_START_RI) = LIN_SETUP ; // POOL_SETUP is defined at included ../../../hw/top/slrx_enums.svh
    
    while (!HOST_REG(XLR_DONE_RI)) {
       //printf("Pool setup Polling ...\n"); // comment for quite execution
    }   
    #endif 
}

//------------------------------------------------------------------------------------------------------------

void lin_elem_xlr(int lin_out_idx) {   // output vector element index

    #ifdef HLCM    
    printf("HLCM does not support HW acceleration, quitting\n\n");
    bm_quit_app();
    #else

    HOST_REG(OUT_COL_IDX_RI) = lin_out_idx; 
    HOST_REG(XLR_START_RI)   = LIN_CALC ; // LIN_CALC is defined at included ../../../hw/top/slrx_enums.svh
  
    while (!HOST_REG(XLR_DONE_RI)) {
       //printf("Pool window Polling ...\n"); // comment for quite execution
    }
    #endif
}

//------------------------------------------------------------------------------------------------------------

void lin_elem_nox(uint8_t* lin_arr_out,   // linear output feature-map (single row)
                  uint8_t* lin_arr_in,    // linear Input Image (single row)
                  int      lin_in_dim,    // linear Input dimensions           
                  int8_t*  linear_w_trn,  // linear Weights Transposed, can be negative (2D matrix)
                  int32_t* linear_b,      // linear Bias, can be negative (single row)
                  int      lin_out_idx) { // output vector element index
         
         int32_t acc = linear_b[lin_out_idx];
         
         for (int lin_in_idx = 0; lin_in_idx < lin_in_dim; lin_in_idx++) {       
             int linear_w_idx = (lin_out_idx * lin_in_dim) + lin_in_idx ;
             acc += (int32_t)(lin_arr_in[lin_in_idx]) * (int32_t)(((volatile int8_t*)linear_w_trn)[linear_w_idx]);
         }
         
         uint8_t lin_elem_out = relu_and_descale(acc); 
         ((volatile uint8_t*)lin_arr_out)[lin_out_idx] = lin_elem_out ;
}

//------------------------------------------------------------------------------------------------------------

 // Linear Layer 

void linear(uint8_t* lin_arr_out,     // linear output feature-map (single row)
            uint8_t* lin_arr_in,      // linear Input Image (single row)
            int      lin_in_dim,      // linear Input dimensions
            int      lin_out_dim,     // linear Input dimensions              
            int8_t*  linear_w_trn,    // linear Weights Transposed, can be negative 
            int32_t* linear_b) {      // linear Bias, can be negative (single row)


    #ifdef LIN_XON
    lin_elem_setup(lin_arr_out, lin_arr_in, lin_in_dim, lin_out_dim, linear_w_trn, linear_b);    
    #endif


    for (int lin_out_idx = 0; lin_out_idx < lin_out_dim; lin_out_idx++) {
        int32_t acc = linear_b[lin_out_idx];
        
        #ifndef LIN_XON
        lin_elem_nox(lin_arr_out, lin_arr_in, lin_in_dim, linear_w_trn, linear_b, lin_out_idx);   

        #else
        lin_elem_xlr(lin_out_idx); // output vector element index
        #endif
    }
}

//------------------------------------------------------------------------------------------------------------
