#include <k5_libs.h>
#include <slr_lib.h>
#include "slrx.h" 

//---------------------------------------------------------------------------------------------------------------------------------

void conv_window_nox(uint8_t* conv_arr_out,                               // Conv output feature-map
                     uint8_t* conv_arr_in,                                // Conv Input Image
                     int      arr_in_dim,                                 // Conv Input array dimensions                    
                     int      out_row_idx,                                // output array row index
                     int      out_col_idx,                                // output array column index
                     int8_t*  kernel_w, // kernel_w[CONV_KERNEL_DIM][CONV_KERNEL_DIM], // Conv kernel Weights, can be negative
                     int32_t  kernel_b) {                                 // Conv kernel Bias, can be negative

    //printf("%x,%x\n",out_row_idx,out_col_idx);// DBG
    
    int out_dim = arr_in_dim - CONV_KERNEL_DIM + 1;

    int32_t acc = kernel_b;            

    for (int kernel_row_idx = 0; kernel_row_idx < CONV_KERNEL_DIM; kernel_row_idx++) {
        for (int kernel_col_idx = 0; kernel_col_idx < CONV_KERNEL_DIM; kernel_col_idx++) {

            int in_row_idx = out_row_idx + kernel_row_idx;
            int in_col_idx = out_col_idx + kernel_col_idx;

            int arr_in_idx = (in_row_idx * arr_in_dim) + in_col_idx ;

            uint8_t in_val = ((volatile uint8_t*)conv_arr_in)[arr_in_idx];
            int8_t weight  = ((volatile int8_t(*)[CONV_KERNEL_DIM])kernel_w)[kernel_row_idx][kernel_col_idx];

            acc += (int32_t)in_val * (int32_t)weight;
            
            // printf("DBG: [%d,%d];[%d,%d] : acc(%d) +=  weight(%d) * in_val(%d)\n",
            // out_row_idx,out_col_idx,kernel_row_idx,kernel_col_idx,acc,(int32_t)weight,in_val); // DBG
        }
    }
    // store with saturation
    int arr_out_idx = (out_row_idx * out_dim) + out_col_idx;
    ((volatile uint8_t*)conv_arr_out)[arr_out_idx] = relu_and_descale(acc); 
}

//------------------------------------------------------------------------------------------------------------

void conv_xlr_setup(uint8_t* conv_arr_out,                               // Conv output feature-map
                    uint8_t* conv_arr_in,                                // Conv Input Image
                    int      arr_in_dim,                                 // Conv Input array dimensions                    
                    int8_t*  kernel_w, // int8_t   kernel_w[CONV_KERNEL_DIM][CONV_KERNEL_DIM], // Conv kernel Weights, can be negative
                    int32_t  kernel_b) {                                 // Conv kernel Bias, can be negative

    #ifdef HLCM    
    printf("HLCM does not support HW acceleration, quitting\n\n");
    bm_quit_app();
    #else
    HOST_REG(WGT_ADDR_RI) = (unsigned int)kernel_w;
    HOST_REG(CONV_BIAS_VAL_RI)        = kernel_b;
    HOST_REG(ARR_IN_ADDR_RI)          = (unsigned int)conv_arr_in;
    HOST_REG(ARR_OUT_ADDR_RI)         = (unsigned int)conv_arr_out;
    HOST_REG(ARR_IN_DIM_RI)           = arr_in_dim;

    HOST_REG(XLR_START_RI) = CONV_SETUP ; // CONV_SETUP is defined at included ../../../hw/top/slrx_enums.svh
    
    while (!HOST_REG(XLR_DONE_RI)) {
       //printf("Conv setup Polling ...\n"); // comment for quite execution
    }
    
    #endif 
}

//------------------------------------------------------------------------------------------------------------

void conv_window_xlr(int out_row_idx,   // output array row index
                     int out_col_idx){  // output array column index 

    #ifdef HLCM    
    printf("HLCM does not support HW acceleration, quitting\n\n");
    bm_quit_app();
    #else

    HOST_REG(OUT_ROW_IDX_RI)     = out_row_idx; 
    HOST_REG(OUT_COL_IDX_RI)     = out_col_idx; 
    HOST_REG(XLR_START_RI) = CONV_WINDOW ; // CONV_WINDOW is defined at included ../../../hw/top/slrx_enums.svh
  
    while (!HOST_REG(XLR_DONE_RI)) {
       //printf("Conv window Polling ...\n"); // comment for quite execution
    }
    
    #endif 
}

//------------------------------------------------------------------------------------------------------------


void conv(uint8_t* conv_arr_out,                               // Conv output feature-map
          uint8_t* conv_arr_in,                                // Conv Input Image  
          int      arr_in_dim,                                 // Conv Input dimensions  
          int8_t*  kernel_w, ///  int8_t   kernel_w[CONV_KERNEL_DIM][CONV_KERNEL_DIM], // Conv kernel Weights, can be negative
          int32_t  kernel_b) {                                 // Conv kernel Bias, can be negative

    int out_dim = arr_in_dim - CONV_KERNEL_DIM + 1;

    #ifdef CONV_XON
    conv_xlr_setup(conv_arr_out, conv_arr_in, arr_in_dim, kernel_w, kernel_b);       
    #endif
   
    for (int out_row_idx = 0; out_row_idx < out_dim; out_row_idx++){
      for (int out_col_idx = 0; out_col_idx < out_dim; out_col_idx++){   
                  
        #ifdef CONV_XON
        conv_window_xlr(out_row_idx, out_col_idx); // assume setup called once per execution    
        #else
        conv_window_nox(conv_arr_out, conv_arr_in, arr_in_dim, out_row_idx, out_col_idx, kernel_w, kernel_b);
        #endif 
      }
    } 
    
}




