import xbox_def_pkg::*;
import slrx_def_pkg::*;

module linear (
  input   clk,
  input   rst_n,  
 
  slrx_regs_intrf.xlr slrx_regs_intrf, // Host Registers Interface
 
  // muxed interfaces
  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write
);

  enum {IDLE, READ_BIAS_VAL, READ_WGT_VEC, READ_IN_VEC, CALC, WRITE, DONE} next_state, state; //state machine 
  
  localparam DIM_MAX_SIZE = 32 ; // In this project it is assumed thart all dimensions are less or equal to 32
  localparam MAX_DOT_PROD_WIDTH = 16+$clog2(DIM_MAX_SIZE) ; // multiplied byte width (8+8) + numb elements

  localparam ARR_IDX_W = $clog2(DIM_MAX_SIZE);// defined by top/slrx_enums.svh
  
  logic lin_start;  
  logic lin_done;  
  logic clear_done_on_read;

  logic [DIM_MAX_SIZE-1:0] [7:0] wgt_vec  ;       // wgt_vec
  logic [DIM_MAX_SIZE-1:0] [7:0] wgt_vec_ps  ;    // wgt_vec pre-sampled
  logic [DIM_MAX_SIZE-1:0] [7:0] in_vec  ;    // buffer for current lin window
  logic [DIM_MAX_SIZE-1:0] [7:0] in_vec_ps  ; // buffer for current lin window pre-sampled 

  logic [XMEM_ADDR_WIDTH-1:0] lin_wgt_arr_addr;
  logic [XMEM_ADDR_WIDTH-1:0] lin_arr_in_addr;  
  logic [XMEM_ADDR_WIDTH-1:0] lin_arr_out_addr; 
  logic [XMEM_ADDR_WIDTH-1:0] lin_bias_vec_addr;
  logic [XMEM_ADDR_WIDTH-1:0] bias_val_addr;
  
  logic [XMEM_ADDR_WIDTH-1:0] lin_rslt_out_addr, lin_rslt_out_addr_ps;  
  
  //logic signed [MAX_DOT_PROD_WIDTH-1:0] lin_bias_val ;     
  logic signed [31:0] bias_val, bias_val_ps ;    

  logic [ARR_IDX_W:0] lin_arr_in_dim ;
  logic [ARR_IDX_W:0] lin_arr_out_dim;   
  logic [ARR_IDX_W-1:0] lin_out_col_idx;
  
  logic [XMEM_ADDR_WIDTH-1:0] wgt_vec_addr_ps, wgt_vec_addr ;
  
  logic [7:0] lin_out_val ;    // Calculated lin value to be written back to memory 
  logic [7:0] lin_out_val_ps ; // pre-sampled calculated lin value to be written back to memory  
  
  logic lin_active ;
   
  //--------------------------------------------------------------------------------------------------------
    
  // Host Regs Interface 
  
  assign slrx_regs_intrf.xlr_done = lin_done ;
    
  slrx_cmd_t slrx_cmd ;// Command type, defined at slrx_enums.svh
  
  assign slrx_cmd            = slrx_cmd_t'(slrx_regs_intrf.host_regs[XLR_START_RI][$clog2(NUM_SLRX_CMDS)-1:0])  ;
  assign lin_active          = (slrx_cmd==LIN_SETUP) || (slrx_cmd==LIN_CALC) ;
  assign lin_start           = slrx_regs_intrf.host_regs_valid_pulse[XLR_START_RI] && lin_active ;  
  assign clear_done_on_read  = lin_active && slrx_regs_intrf.xlr_done_ack ; 
  
  assign lin_wgt_arr_addr    = slrx_regs_intrf.host_regs[WGT_ADDR_RI];       // Weights, can be negative,  Reg Index
  assign lin_bias_vec_addr   = slrx_regs_intrf.host_regs[LIN_BIAS_ADDR_RI];  // Weights, can be negative,  Reg Index  

  assign lin_arr_in_addr     = slrx_regs_intrf.host_regs[ARR_IN_ADDR_RI];     // Input Image  Reg Index  
  assign lin_arr_out_addr    = slrx_regs_intrf.host_regs[ARR_OUT_ADDR_RI];    // output feature-map Reg Index
  assign lin_arr_in_dim      = slrx_regs_intrf.host_regs[ARR_IN_DIM_RI];      // Input array dimension
  assign lin_arr_out_dim     = slrx_regs_intrf.host_regs[ARR_OUT_DIM_RI];     // Input array dimension  
  assign lin_out_col_idx     = slrx_regs_intrf.host_regs[OUT_COL_IDX_RI];     // output array column index ,  Reg Index
   
  //======================================================================================================== 
 
  //State Machine Comb (most simple non-piped implementation)  
  always_comb begin
  
   // State-Machine Comb logic outputs defaults 

   next_state = state;
   
   bias_val_ps = bias_val ;
   in_vec_ps = in_vec ;

   mem_intf_read.mem_size_bytes  = 0;   // default
   mem_intf_read.mem_start_addr  = 0 ;  // default   

   mem_intf_write.mem_size_bytes = 1;   
   mem_intf_write.mem_data       = lin_out_val;
   mem_intf_write.mem_start_addr = lin_rslt_out_addr;
   
   lin_rslt_out_addr_ps = lin_arr_out_addr + lin_out_col_idx  ; 
   
   mem_intf_read.mem_req = 0;
   mem_intf_write.mem_req = 0;   
   lin_done = 0;  

   wgt_vec_ps = wgt_vec  ;    
   
   wgt_vec_addr_ps = lin_wgt_arr_addr + (lin_out_col_idx * lin_arr_in_dim) ;  

   bias_val_addr = lin_bias_vec_addr + (4*lin_out_col_idx) ; // 4 bytes per bias element
      

   case (state) // State Machine case
   
      IDLE: if (lin_start) begin
       lin_done = 0;
       if      (slrx_cmd==LIN_SETUP)   next_state = READ_IN_VEC; // Setup only, pending for execution
       else if (slrx_cmd==LIN_CALC) next_state = READ_WGT_VEC;  // Proceed to execution                
      end

    
      READ_IN_VEC: begin
        mem_intf_read.mem_req = 1;
        mem_intf_read.mem_start_addr = lin_arr_in_addr;
        mem_intf_read.mem_size_bytes = lin_arr_in_dim ;  // Assuming entire wgt_vec is less than 32 max mem size fetch)            
        if (mem_intf_read.mem_valid) begin
               for (int i=0;i<DIM_MAX_SIZE;i++) 
                 in_vec_ps[i] = (i<lin_arr_in_dim) ? mem_intf_read.mem_data[i] : 0 ; 
               mem_intf_read.mem_req = 0;   
               next_state = DONE ; // Setup only, pending for execution
        end        
      end 

      READ_WGT_VEC: begin
        mem_intf_read.mem_req = 1; 
        mem_intf_read.mem_start_addr = wgt_vec_addr ;    
        mem_intf_read.mem_size_bytes = lin_arr_in_dim ;
        if (mem_intf_read.mem_valid) begin
          integer i;
          for (i=0;i<DIM_MAX_SIZE;i++) 
            wgt_vec_ps[i] = (i<lin_arr_in_dim) ? mem_intf_read.mem_data[i] : 0 ; 
            next_state = READ_BIAS_VAL; 
            mem_intf_read.mem_req = 0;
        end 
      end

      READ_BIAS_VAL: begin
        mem_intf_read.mem_req = 1;
        mem_intf_read.mem_start_addr = bias_val_addr;
        mem_intf_read.mem_size_bytes = 4 ;  // we allocate four bytes per bias value          
        if (mem_intf_read.mem_valid) begin
               mem_intf_read.mem_req = 0;
               bias_val_ps[31:0] =  mem_intf_read.mem_data[3:0] ; 
               next_state = CALC ; // Setup only, pending for execution (stationed input single vec)
        end 
      end 
      

      CALC : begin        
        next_state = WRITE ; 
      end

      WRITE: begin
        mem_intf_write.mem_req = 1;
        if (mem_intf_write.mem_ack) begin
          next_state = DONE;
          mem_intf_write.mem_req = 0;         
        end
      end 

      DONE: begin
        lin_done = 1;
        if (clear_done_on_read) next_state = IDLE; 
      end 
 
   endcase
   
  end // always

  //-----------------------------------------------------------------------------------------------------
        
  assign lin_out_val_ps = calc_lin_element(wgt_vec, bias_val[MAX_DOT_PROD_WIDTH-1:0], in_vec) ;
  
  //------------------------------------------------------------------------

 // Sequential
  always @(posedge clk or negedge rst_n) begin
  
    if(!rst_n) begin  
      state <= IDLE ;    
      wgt_vec_addr <= 0 ;
      wgt_vec <= 0;
      in_vec <= 0;
      lin_out_val <= 0;
      lin_rslt_out_addr <=0;
      bias_val <=0;
    end else begin     
      state <= next_state ;
      wgt_vec_addr <= wgt_vec_addr_ps ;
      wgt_vec <= wgt_vec_ps ;
      in_vec <= in_vec_ps; 
      lin_out_val <= lin_out_val_ps ; 
      lin_rslt_out_addr <= lin_rslt_out_addr_ps; 
      bias_val <= bias_val_ps ;          
    end    
  end
   
  //------------------------------------------------------------------------
 
  // Comb Function to calculate lin output element

// Comb Function to calculate lin output element

function automatic logic [7:0] calc_lin_element;

    input        [DIM_MAX_SIZE-1:0][7:0] wgt_vec;
    input signed [MAX_DOT_PROD_WIDTH-1:0] bias_val;
    input        [DIM_MAX_SIZE-1:0][7:0] in_vec;

    integer i;

    logic signed [MAX_DOT_PROD_WIDTH-1:0] acc;
    logic signed [MAX_DOT_PROD_WIDTH-1:0] wgt_s;
    logic signed [MAX_DOT_PROD_WIDTH-1:0] in_s;
    logic signed [MAX_DOT_PROD_WIDTH-1:0] ret_val_int;

    begin
        acc = bias_val;

        for (i = 0; i < DIM_MAX_SIZE; i = i + 1) begin
            // weights are signed int8
            wgt_s = {{(MAX_DOT_PROD_WIDTH-8){wgt_vec[i][7]}}, wgt_vec[i]};

            // input is unsigned uint8
            in_s = {{(MAX_DOT_PROD_WIDTH-8){1'b0}}, in_vec[i]};

            acc = acc + (in_s * wgt_s);
        end

        // ReLU + descale by 8 bits
        if (acc <= 0) begin
            ret_val_int = 0;
        end else begin
            ret_val_int = acc >>> 8;

            if (ret_val_int > 255)
                ret_val_int = 255;
        end

        calc_lin_element = ret_val_int[7:0];
    end

endfunction
 //--------------------------------------------------------------

endmodule
