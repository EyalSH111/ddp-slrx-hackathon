import xbox_def_pkg::*;
import slrx_def_pkg::*;

module conv (
  input   clk,
  input   rst_n,  
 
  // Command Status Register Interface

  slrx_regs_intrf.xlr slrx_regs_intrf, // Host Registers Interface

  // muxed interfaces
  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write
);

  localparam DIM_MAX_SIZE = 32 ; // In this project it is assumed that all dimensions are less or equal to 32
  localparam KERNEL_DIM = 5;
  localparam KERNEL_SIZE = KERNEL_DIM*KERNEL_DIM ;    
  localparam MAX_DOT_PROD_WIDTH = 16+$clog2(KERNEL_SIZE) ; // multiplied byte width (8+8) + numb elements

  localparam ARR_IDX_W = $clog2(DIM_MAX_SIZE);// defined by top/slrx_enums.svh
  
  logic conv_start;  
  logic conv_done;  
  logic clear_done_on_read;

  logic [XMEM_ADDR_WIDTH-1:0] conv_kernel_addr;
  logic [XMEM_ADDR_WIDTH-1:0] conv_arr_in_addr;  
  logic [XMEM_ADDR_WIDTH-1:0] conv_arr_out_addr;  

  logic [MAX_DOT_PROD_WIDTH-1:0] conv_bias_val;     

  logic [ARR_IDX_W:0] conv_arr_in_dim ;
  logic [ARR_IDX_W:0] conv_arr_out_dim;  
  
  logic conv_active;

  //--------------------------------------------------------------------------------------------------------
   
  // Host Regs Interface
  
  assign slrx_cmd            = slrx_cmd_t'(slrx_regs_intrf.host_regs[XLR_START_RI][$clog2(NUM_SLRX_CMDS)-1:0])  ;
  assign conv_start          = slrx_regs_intrf.host_regs_valid_pulse[XLR_START_RI] && conv_active ;  
  assign clear_done_on_read  = conv_active && slrx_regs_intrf.xlr_done_ack ;  
  assign conv_kernel_addr    = slrx_regs_intrf.host_regs[WGT_ADDR_RI]; // Conv kernel Weights, can be negative,  Reg Index                             
  assign conv_arr_in_addr    = slrx_regs_intrf.host_regs[ARR_IN_ADDR_RI];     // Conv Input Image  Reg Index  
  assign conv_arr_out_addr   = slrx_regs_intrf.host_regs[ARR_OUT_ADDR_RI];    // Conv output feature-map Reg Index
  assign conv_arr_in_dim     = slrx_regs_intrf.host_regs[ARR_IN_DIM_RI];      // Conv Input array dimension            
  assign conv_out_row_idx    = slrx_regs_intrf.host_regs[OUT_ROW_IDX_RI];     // output array row index ,  Reg Index
  assign conv_out_col_idx    = slrx_regs_intrf.host_regs[OUT_COL_IDX_RI];     // output array column index ,  Reg Index
  assign conv_arr_out_dim    = conv_arr_in_dim-KERNEL_DIM+1 ;
  
  assign conv_bias_val       = $signed(slrx_regs_intrf.host_regs[CONV_BIAS_VAL_RI][MAX_DOT_PROD_WIDTH-1:0]); // Conv Bias, Reg Index 

  //======================================================================================================== 
 
  // TEMPORARILY DRIVING ALL OUTPUTS TO ZERO
  
    assign slrx_regs_intrf.xlr_done = 0 ;

  always_comb begin
  
    mem_intf_read.mem_start_addr  = 0 ;
    mem_intf_read.mem_size_bytes  = 0;   
    mem_intf_write.mem_req = 0;  
 
    mem_intf_write.mem_start_addr = 0;
    mem_intf_write.mem_size_bytes = 0;   
    mem_intf_write.mem_data       = 0;
    mem_intf_read.mem_req = 0;
   

    // STUDENT CODE TO BE PROVIDED

    assign conv_active = 0 ; // TEMP, Need to indicate

  end // always

 
 //--------------------------------------------------------------

endmodule
