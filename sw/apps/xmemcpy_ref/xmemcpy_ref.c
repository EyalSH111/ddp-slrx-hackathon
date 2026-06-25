
#include <k5_libs.h>

/****************************** MACROS ******************************/

// NOTICE following must be compliant with the relative used address in the accelerator code, this is NOT automated.

// XBOX APB REGISTERS ADDRESS MACROS

#define SM_REGS_BASE_IDX 0

#define XMEM_SRC_ADDR_REG_IDX (SM_REGS_BASE_IDX + 0) 
#define XMEM_DST_ADDR_REG_IDX (SM_REGS_BASE_IDX + 1)
#define SM_LEN_REG_IDX        (SM_REGS_BASE_IDX + 2) 
#define SM_START_REG_IDX      (SM_REGS_BASE_IDX + 3) 
#define SM_DONE_REG_IDX       (SM_REGS_BASE_IDX + 4) 

#define XMEM_SRC_ADDR_REG ((volatile unsigned int *) (XBOX_REGS_BASE_ADDR + (4*XMEM_SRC_ADDR_REG_IDX))) 
#define XMEM_DST_ADDR_REG ((volatile unsigned int *) (XBOX_REGS_BASE_ADDR + (4*XMEM_DST_ADDR_REG_IDX))) 
#define SM_LEN_REG        ((volatile unsigned int *) (XBOX_REGS_BASE_ADDR + (4*SM_LEN_REG_IDX))) 
#define SM_START_REG      ((volatile unsigned int *) (XBOX_REGS_BASE_ADDR + (4*SM_START_REG_IDX))) 
#define SM_DONE_REG       ((volatile unsigned int *) (XBOX_REGS_BASE_ADDR + (4*SM_DONE_REG_IDX))) 

//---------------------------------------------------------------------------------------------

// Configuration Structure

typedef struct xmc_config {
    unsigned char * xmem_src_addr;
    unsigned char * xmem_dst_addr;
    int             xmc_num_bytes;    
} xmc_config_t;

//---------------------------------------------------------------------------------------------

void dump_xmem_dst(int dump_f, xmc_config_t* xmc_config_p) {
   
   bm_printf("Dumping xmem data at address: 0x%08x , byte length %d (decimal)\n",xmc_config_p->xmem_dst_addr, xmc_config_p->xmc_num_bytes);
   // Starting a SOC level file to memory copy transfer
   int num_bytes_per_output_line = 32 ;
   bm_start_soc_store_hex_file (dump_f, xmc_config_p->xmc_num_bytes, num_bytes_per_output_line, xmc_config_p->xmem_dst_addr) ;  // Store to dump file
   // Polling till transfer completed (SW may also do other stuff mean while)
   int num_dumped = 0 ;
   while (num_dumped==0) {
       num_dumped = bm_check_soc_store_hex_file () ; // num_dumped!=0 indicates completion.
   }
   bm_printf("Dumped %d bytes\n",num_dumped) ; 
}

//---------------------------------------------------------------------------------------------

void load_xmc_config(int  xmc_config_f, xmc_config_t *xmc_config_p) { 
                        
 bm_printf("\nLoading Configuration file\n\n");
 // Starting a SOC level file to memory copy transfer
 bm_start_soc_load_hex_file (xmc_config_f, sizeof(xmc_config_t), (unsigned char *)xmc_config_p) ; 
 // Polling till transfer completed (SW may also do other stuff mean while)
 int num_loaded = 0 ;
 while (num_loaded==0) num_loaded = bm_check_soc_load_hex_file () ; // num_loaded!=0 indicates completion.
 bm_printf("Loaded %d bytes\n",num_loaded) ;
 
 bm_printf("xmem_src_addr: 0x%08x\n",xmc_config_p->xmem_src_addr);
 bm_printf("xmem_dst_addr: 0x%08x\n",xmc_config_p->xmem_dst_addr);
 bm_printf("xmc_num_bytes: 0x%08x (%d decimal)\n\n",xmc_config_p->xmc_num_bytes,xmc_config_p->xmc_num_bytes);
  
}

//-----------------------------------------------------------------------------------------------

void load_xmemcpy_data(int data_f, xmc_config_t *xmc_config_p) { 
                      
 bm_printf("Loading input test data: to xmem address %8x , byte length : %d\n", xmc_config_p->xmem_src_addr, xmc_config_p->xmc_num_bytes);
 bm_start_soc_load_hex_file (data_f, xmc_config_p->xmc_num_bytes, xmc_config_p->xmem_src_addr) ; 
 // Polling till transfer completed (SW may also do other stuff mean while)
 int num_loaded = 0 ;
 while (num_loaded==0) num_loaded = bm_check_soc_load_hex_file () ; // num_loaded!=0 indicates completion.
 bm_printf("Loaded %d bytes\n",num_loaded) ;
}
//---------------------------------------------------------------------------------------------

// Non accelerated reference 

void xmemcpy_nox(xmc_config_t *xmc_config_p) {

   for  (int i=0 ; i < xmc_config_p->xmc_num_bytes ; i++) {
      xmc_config_p->xmem_dst_addr[i] = xmc_config_p->xmem_src_addr[i] ;       
   }
}
                
//-----------------------------------------------------------------------------------------------

// Accelerated reference 

void xmemcpy_xlr(xmc_config_t *xmc_config_p) {

    // HW registers hold unsigned integers regardless of usage
    
    *XMEM_SRC_ADDR_REG = (unsigned int) xmc_config_p->xmem_src_addr; 
    *XMEM_DST_ADDR_REG = (unsigned int) xmc_config_p->xmem_dst_addr;
    *SM_LEN_REG =        (unsigned int) xmc_config_p->xmc_num_bytes;   
    
    *SM_START_REG = 1; // Trigger Start    
    while(!*SM_DONE_REG){
       // bm_printf("Pending SM_DONE_REG\n") ; // Uncomment for debug
    }
}

//-----------------------------------------------------------------------------------------------

void xmemcpy(xmc_config_t *xmc_config_p, boolean is_xlr_enabled) {
  
  bm_printf("Starting xmem copy of %d bytes from addr 0x%08x to addr 0x%08x\n", 
             xmc_config_p->xmc_num_bytes, xmc_config_p->xmem_src_addr, xmc_config_p->xmem_dst_addr);
  
  // Performance time stamping initialize 
  int start_cycle,end_cycle ;            // For performance checking.  
  ENABLE_CYCLE_COUNT ;                   // Enable the cycle counter
  RESET_CYCLE_COUNT  ;                   // Reset counter to ensure 32 bit counter does not wrap in-between start and end.   
  GET_CYCLE_COUNT_START(start_cycle) ;   // Capture the cycle count before the operation.
  
  if (is_xlr_enabled) xmemcpy_xlr(xmc_config_p); 
  else                xmemcpy_nox(xmc_config_p);

  // Performance time stamping report
  GET_CYCLE_COUNT_END(end_cycle) ;  // Capture the cycle count after the operation.
  int cycle_cnt = end_cycle-start_cycle ; // Calculate consumed cycles.  

  #ifndef XON
   cycle_cnt=cycle_cnt/8 ; // Factor single thread mode (Other 7 threads unutilized)
  #endif

  bm_printf("\n\n *** Measured execution time: %d K5 effective cycles ***\n\n",cycle_cnt); // Report
}

//-----------------------------------------------------------------------------------------------

int main() {
  
 bm_printf("\nHELLO MEM COPY REFERENCE\n"); 

  char gen_test_per_run=FALSE ;
  #ifdef REGEN
  gen_test_per_run = TRUE ;
  #endif 
  
  if (gen_test_per_run) {
    bm_printf("\nSystem call for generating a random test case\n") ;
    bm_sys_call("python3 app_src_dir/gen_xmemcpy_test.py");
  }
  else {
    bm_printf("\nNew test not generated, you may generate new test from runspace prompt by:\n") ;
    bm_printf("python3 app_src_dir/gen_xmemcpy_test.py:\n") ;
  }

  int data_f       = bm_fopen_r("xmemcpy_test_in.txt") ;        // Generated test source data
  int xmc_config_f = bm_fopen_r("xmemcpy_test_config.txt") ;    // Generated test xmc_configuration
  int dout_f       = bm_fopen_w("xmemcpy_test_out.txt") ;       // Output file generated at run space

  xmc_config_t xmc_config ;
  
  boolean is_xlr_enabled = FALSE ; // Is Accelerator Enabled , default (can be changed)
  // Overwrite default controlled from shell invocation line 

  #ifdef XON
  is_xlr_enabled = TRUE ;
  #endif 
  #ifdef XOFF
  is_xlr_enabled = FALSE ;
  #endif
  
  if (is_xlr_enabled) bm_printf("\nAccelerator Enabled\n") ;
  else bm_printf("\nAccelerator Disabled\n") ;
    
  load_xmc_config(xmc_config_f, &xmc_config); // Load Configuration info
  
  load_xmemcpy_data(data_f, &xmc_config); // Load Generated data file
  

  xmemcpy(&xmc_config, is_xlr_enabled);

 
  dump_xmem_dst(dout_f, &xmc_config) ;
  
  bm_fclose(data_f) ;  
  bm_fclose(xmc_config_f) ;     
  bm_fclose(dout_f) ;  

  bm_printf("\nCheck values at xmemcpy_test_out.txt vs. xmemcpy_test_in.txt\n") ;
  bm_sys_call("python3 app_src_dir/check_xmemcpy.py");

  bm_quit_app();  // flag to trigger execution termination   
  return 0;
}

//-----------------------------------------------------------------------------------------------