#include <k5_libs.h>
#include <slr_lib.h>

//------------------------------------------------------------------------------------------------------------

static inline uint8_t relu_and_descale(int32_t x) {
      
    int32_t ret_val_int = 0 ; // by default per RELU all negative values return 0 
    
    if (x>0) {         
       ret_val_int = x/256 ;
       if (ret_val_int > 255) ret_val_int = 255; // clamp at 255 (max uint8_t)
    }
    return (uint8_t)ret_val_int ;
}

//------------------------------------------------------------------------------------------------------------

void conv(uint8_t* conv_arr_out,                 // Conv output feature-map
          uint8_t* conv_arr_in,                  // Conv Input Image  
          int      arr_in_dim,                   // Conv Input dimensions  
          int8_t   kernel_w[CONV_KERNEL_DIM][CONV_KERNEL_DIM], // Conv kernel Weights, can be negative
          int32_t  kernel_b) {                   // Conv kernel Bias, can be negative

    int out_dim = arr_in_dim - CONV_KERNEL_DIM + 1;

    for (int out_row_idx = 0; out_row_idx < out_dim; out_row_idx++) {
        for (int out_col_idx = 0; out_col_idx < out_dim; out_col_idx++) {

            int32_t acc = kernel_b;

            // convolution window
            for (int kernel_row_idx = 0; kernel_row_idx < CONV_KERNEL_DIM; kernel_row_idx++) {
                for (int kernel_col_idx = 0; kernel_col_idx < CONV_KERNEL_DIM; kernel_col_idx++) {

                    int in_row_idx = out_row_idx + kernel_row_idx;
                    int in_col_idx = out_col_idx + kernel_col_idx;

                    int arr_in_idx = (in_row_idx * arr_in_dim) + in_col_idx ;

                    uint8_t in_val = ((volatile uint8_t*)conv_arr_in)[arr_in_idx];
                    int8_t weight  = ((volatile int8_t(*)[CONV_KERNEL_DIM])kernel_w)[kernel_row_idx][kernel_col_idx];

                    acc += (int32_t)in_val * (int32_t)weight;
                }
            }
            // store with saturation
            int arr_out_idx = (out_row_idx * out_dim) + out_col_idx;
            ((volatile uint8_t*)conv_arr_out)[arr_out_idx] = relu_and_descale(acc); // TODO: APPLY MNX SCALER AND RELU
        }
    }
}

//------------------------------------------------------------------------------------------------------------

void pool_max_2x2(uint8_t* pool_arr_out,         // Pool-Max output feature-map
                  uint8_t* pool_arr_in,          // Pool-Max Input Image  
                  int     arr_in_dim) {    // Pool-Max Input dimensions 

    int out_dim = arr_in_dim/2;

    for (int out_row_idx = 0; out_row_idx < out_dim; out_row_idx++) {
        for (int out_col_idx = 0; out_col_idx < out_dim; out_col_idx++) {

            int in_row_idx = out_row_idx << 1; // out_row_idx * 2
            int in_col_idx = out_col_idx << 1; // out_col_idx * 2

            int arr_in_idx0 = (in_row_idx * arr_in_dim) + in_col_idx;
            int arr_in_idx1 = arr_in_idx0 + 1;
            int arr_in_idx2 = arr_in_idx0 + arr_in_dim;
            int arr_in_idx3 = arr_in_idx2 + 1;

            uint8_t max = ((volatile uint8_t*)pool_arr_in)[arr_in_idx0];

            if (((volatile uint8_t*)pool_arr_in)[arr_in_idx1] > max) max = ((volatile uint8_t*)pool_arr_in)[arr_in_idx1];
            if (((volatile uint8_t*)pool_arr_in)[arr_in_idx2] > max) max = ((volatile uint8_t*)pool_arr_in)[arr_in_idx2];
            if (((volatile uint8_t*)pool_arr_in)[arr_in_idx3] > max) max = ((volatile uint8_t*)pool_arr_in)[arr_in_idx3];

            ((volatile uint8_t*)pool_arr_out)[(out_row_idx * out_dim) + out_col_idx] = max;
        }
    }
}

//------------------------------------------------------------------------------------------------------------

// Linear Layer

void linear(uint8_t* lin_arr_out,  // linear output feature-map (single row)
            uint8_t* lin_arr_in,   // linear Input Image (single row)
            int      lin_in_dim,   // linear Input dimensions
            int      lin_out_dim,  // linear Input dimensions              
            int8_t*  linear_w_trn, // linear Weights Transposed, can be negative (2D matrix)
            int32_t* linear_b) {   // linear Bias, can be negative (single row)

    for (int lin_out_idx = 0; lin_out_idx < lin_out_dim; lin_out_idx++) {
        int32_t acc = linear_b[lin_out_idx];
        
        for (int lin_in_idx = 0; lin_in_idx < lin_in_dim; lin_in_idx++) {       
            int linear_w_idx = (lin_out_idx * lin_in_dim) + lin_in_idx ;
            acc += (int32_t)(lin_arr_in[lin_in_idx]) * (int32_t)(((volatile int8_t*)linear_w_trn)[linear_w_idx]);
        }
        ((volatile uint8_t*)lin_arr_out)[lin_out_idx] = relu_and_descale(acc); // TODO: APPLY MNX SCALER AND RELU
    }
}

//------------------------------------------------------------------------------------------------------------

// Get index of max value in vector

int get_max_val_idx(uint8_t*  vec_in, int vec_size) { // input vector
  
   int max_val_idx = 0 ;
   int8_t max_val = ((volatile uint8_t*)vec_in)[0] ;
   
   for (int i=1;i<vec_size;i++) {
     if (vec_in[i]>max_val) {
        max_val_idx = i ;
        max_val = ((volatile uint8_t*)vec_in)[i] ;
     }
   }
   return max_val_idx ;
}

//============================================================================================================

int infer(uint8_t slr_img [IMG_DIM][IMG_DIM],      // inferred image
          slr_model_params_t* slr_model_params_p,  // model parameters
          slr_intr_fm_t*      slr_intr_fm_p,       // intermediate feature-maps
          char                check_performance) { // enable performance monitoring 
     
        if (check_performance) reset_report_performance(); 
     
        // Perform Inference

        // Calling CONV0 Layer
        conv((uint8_t*)(slr_intr_fm_p->post_c0_fm),         // Conv0 output feature-map
             (uint8_t*)slr_img,                             // Conv0 Input Image  
             IMG_DIM,                                       // Conv0 Input dimensions       
             slr_model_params_p->conv0_w,                   // Conv0 kernel Weights
             slr_model_params_p->conv0_b);                  // Conv0 kernel Bias
             
        if (check_performance) report_task_performance("Conv0");              
        
        // Calling POOL0 Layer
        pool_max_2x2((uint8_t*)(slr_intr_fm_p->post_p0_fm), // Pool0 output feature-map
                     (uint8_t*)(slr_intr_fm_p->post_c0_fm), // Pool0 Input Image <- output of conv0 
                     POST_C0_FM_DIM);                       // Pool0 Input dimensions <- post conv0 

        if (check_performance) report_task_performance("Pool0");       
        
        // Calling CONV1 Layer
        conv((uint8_t*)(slr_intr_fm_p->post_c1_fm),         // Conv1 output feature-map <- Pool0 output feature-map
             (uint8_t*)(slr_intr_fm_p->post_p0_fm),         // Conv1 Input Image  
             POST_P0_FM_DIM,                                // Conv1 Input dimensions       
             slr_model_params_p->conv1_w,                   // Conv1 kernel Weights
             slr_model_params_p->conv1_b);                  // Conv1 kernel Bias

        if (check_performance) report_task_performance("Conv1");  
        
        // Calling POOL1 Layer
        pool_max_2x2((uint8_t*)(slr_intr_fm_p->post_p1_fm), // Pool1 output feature-map
                     (uint8_t*)(slr_intr_fm_p->post_c1_fm), // Pool1 Input Image <- output of conv1 
                     POST_C1_FM_DIM);                       // Pool1 Input dimensions <- post conv1 

        if (check_performance) report_task_performance("Pool1");  
        
        // Calling LINEAR0 Layer
        linear((uint8_t*)(slr_intr_fm_p->post_lin0_fm),     // linear output feature-map (single row) 
               (uint8_t*)(slr_intr_fm_p->post_p1_fm),       // linear Input Image (single row) <- output of pool1 (flat)
               LIN_INVEC_SIZE,                              // linear Input dimension
               LIN_HID_DIM,                                 // linear Output dimension              
               (int8_t*)(slr_model_params_p->lin0_w_trn),   // linear Weights Transposed (2D matrix)
               slr_model_params_p->lin0_b);                 // linear Bias (single row)

        if (check_performance) report_task_performance("Linear0");  
        
        // Calling LINEAR1 Layer
        linear((uint8_t*)(slr_intr_fm_p->post_lin1_fm),     // linear output feature-map (single row) 
               (uint8_t*)(slr_intr_fm_p->post_lin0_fm),     // linear Input Image (single row) <- output of pool1 (flat)
               LIN_HID_DIM,                              // linear Input dimension
               NUM_LABELS,                                  // linear Output dimensions             
               (int8_t*)(slr_model_params_p->lin1_w_trn),   // linear Weights Transposed (2D matrix)
               slr_model_params_p->lin1_b);                 // linear Bias (single row)

        if (check_performance) report_task_performance("Linear1");  
  
        // Final label selection - Performed on LINEAR1 output vector
        int max_val_idx = get_max_val_idx((uint8_t*)(slr_intr_fm_p->post_lin1_fm), NUM_LABELS); 


        if (check_performance) {
          report_task_performance("Select"); 
          report_total_performance();
          printf("\n");
        }
        
        return max_val_idx ;   
}   

//====================================================================================================

int main() {


 bm_printf("\n\nHELLO K5X SLR : Sign Language Recognition\n\n"); 
  
  alloc_init(); // Initialize XMEM memory allocator
  
  slr_model_params_t* slr_model_params_p = load_model_params();
  
  // Allocating Layers Intermediate Feature-Maps     
  int fm_total_num_bytes = sizeof(slr_intr_fm_t); 
  printf("Allocated total %d bytes of for intermediate feature -maps\n", fm_total_num_bytes);
  slr_intr_fm_t* slr_intr_fm_p = (slr_intr_fm_t*)alloc_get(fm_total_num_bytes, "slr_intr_fm");               
   
  int num_imgs_in_buf = 1 ; // Currently we load a single image per iteration
  int imgs_total_num_bytes = num_imgs_in_buf * sizeof(slr_ds_image_t);
  
  slr_ds_image_t* slr_ds_imgs = (slr_ds_image_t*)alloc_get(imgs_total_num_bytes, "slr_ds_imgs");
  
  //char* ds_test_file_path = "app_src_dir/../slr_shared/pt/workspace/slr_ds_mnx.txt" ; 
  char* ds_test_file_path = "$K5_SHARE/slrx_ref/sw/apps/slr_shared/pt/workspace/slr_ds_mnx.txt" ;  
 
 
  FILE_REF file_ref ; // assigned by load_hex_file( ... OPEN*)  
  
  printf("\n\n");
  
  for (int img_idx=0; img_idx<NUM_TEST_IMAGES; img_idx++) { 

    file_access_mode_t file_access_mode = img_idx==0 ? OPEN : CONT ;
    load_hex_file(ds_test_file_path, &file_ref, (char*)slr_ds_imgs, imgs_total_num_bytes, file_access_mode); // Keep Open
  
    char check_performance = (NUM_TEST_IMAGES==1); // check performance (tested on a single image  invocation, for now)    
    char is_last_ds_img    = slr_ds_imgs[0].is_last_img ;
    int  expected_label_id  = slr_ds_imgs[0].slr_img_label_id ; // Currently the buffer holds just one image at a time

 
    int detected_label_id = infer(slr_ds_imgs[0].slr_img, // inferred image 
                                  slr_model_params_p,     // model parameters
                                  slr_intr_fm_p,          // interm feature-maps memory space
                                  check_performance);     // enable performance check

          
    char text_mode = TRUE; // oppose to dataset bench-marking
    output_detection(detected_label_id, expected_label_id, img_idx, is_last_ds_img, text_mode);    

    if (is_last_ds_img || ((img_idx+1)>=NUM_TEST_IMAGES)) break ; 
  }
 
  fclose(file_ref);
     
  // Free all allocated memory space 
  
  alloc_free((void*)slr_model_params_p, "model_params");     
  alloc_free((void*)slr_ds_imgs,        "slr_ds_imgs"); 
  alloc_free((void*)slr_intr_fm_p,      "slr_intr_fm"); 
  
  bm_quit_app();
  return 0;

}




