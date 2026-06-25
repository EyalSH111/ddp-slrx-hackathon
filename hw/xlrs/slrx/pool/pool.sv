import xbox_def_pkg::*;
import slrx_def_pkg::*;

//--------------------------------------------------------------------------------------------------------

module pool (
  input   clk,
  input   rst_n,  
 
  slrx_regs_intrf.xlr slrx_regs_intrf, // Host Registers Interface

  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write
);

  enum {IDLE, SETUP, READ_ROWS, CALC, WRITE, DONE} next_state, state; //state machine 
  
  localparam POOL_IN_MAX_ROW_SIZE = 28 ; // In this project it is assumed that all dimensions are less or equal to 28
  localparam POOL_OUT_MAX_ROW_SIZE = POOL_IN_MAX_ROW_SIZE/2 ;
  
  localparam ARR_IDX_W = $clog2(POOL_IN_MAX_ROW_SIZE);
  
  logic pool_start;  
  logic pool_done;  
  logic clear_done_on_read;

  logic [1:0] [POOL_IN_MAX_ROW_SIZE-1:0]  [7:0] pool_in_buf, pool_in_buf_ps ;  // Two rows for 2 rows pool iteration
  logic       [POOL_OUT_MAX_ROW_SIZE-1:0] [7:0] pool_out_buf, pool_out_buf_ps ; // Single row output
  
  logic [XMEM_ADDR_WIDTH-1:0] pool_arr_in_addr;  
  logic [XMEM_ADDR_WIDTH-1:0] pool_arr_out_addr;  
  logic [XMEM_ADDR_WIDTH-1:0] pool_rslt_out_addr, pool_rslt_out_addr_ps;  

  logic [ARR_IDX_W:0] pool_arr_in_dim ;
  logic [ARR_IDX_W:0] pool_arr_out_dim;  
  
  logic [ARR_IDX_W-1:0] pool_out_row_idx;  

  logic [XMEM_ADDR_WIDTH-1:0] arr_in_row_addr_ps, arr_in_row_addr, arr_in_next_row_addr, arr_in_next_row_addr_s ;

  logic [ARR_IDX_W-1:0] load_row_idx, load_next_row_idx;
  
  logic pool_active;

  //--------------------------------------------------------------------------------------------------------
  
  // Host Regs Interface 
   
  assign slrx_regs_intrf.xlr_done = pool_done ;

  slrx_cmd_t slrx_cmd ;

  assign slrx_cmd            = slrx_cmd_t'(slrx_regs_intrf.host_regs[XLR_START_RI][$clog2(NUM_SLRX_CMDS)-1:0])  ;
  assign pool_active         = (slrx_cmd==POOL_SETUP) || (slrx_cmd==POOL_CALC) ;
  assign pool_start          = slrx_regs_intrf.host_regs_valid_pulse[XLR_START_RI] && pool_active ;  
  assign clear_done_on_read  = pool_active && slrx_regs_intrf.xlr_done_ack ; 

  assign pool_arr_in_addr    = slrx_regs_intrf.host_regs[ARR_IN_ADDR_RI];  // Conv Input Image  Reg Index  
  assign pool_arr_out_addr   = slrx_regs_intrf.host_regs[ARR_OUT_ADDR_RI]; // Conv output feature-map Reg Index
  assign pool_arr_in_dim     = slrx_regs_intrf.host_regs[ARR_IN_DIM_RI];   // Conv Input array dimension
  assign pool_out_row_idx    = slrx_regs_intrf.host_regs[OUT_ROW_IDX_RI];  // output array row index ,  Reg Index  
  
  assign pool_arr_out_dim = pool_arr_in_dim/2 ;
 
  assign arr_in_next_row_addr = arr_in_row_addr + pool_arr_in_dim ;
 
  //======================================================================================================== 
 
  //State Machine Comb (most simple non-piped implementation)  
  always_comb begin
  
   // State-Machine Comb logic outputs defaults 

   next_state = state;

   mem_intf_read.mem_size_bytes  = pool_arr_in_dim;   // default
   mem_intf_read.mem_start_addr  = 0 ;                // default   

   mem_intf_write.mem_size_bytes = pool_arr_out_dim;   
   mem_intf_write.mem_data       = pool_out_buf ;
   mem_intf_write.mem_start_addr = pool_rslt_out_addr ;
   
   pool_rslt_out_addr_ps = pool_arr_out_addr + (pool_out_row_idx*pool_arr_out_dim)  ; 
   
   mem_intf_read.mem_req = 0;
   mem_intf_write.mem_req = 0;   
   pool_done = 0;  
   load_next_row_idx = load_row_idx;         
   pool_in_buf_ps  = pool_in_buf  ; 

    arr_in_row_addr_ps = pool_arr_in_addr + (pool_out_row_idx*2*pool_arr_in_dim)  ;     

   case (state) // State Machine case
    
      IDLE: if (pool_start) begin
       pool_done = 0;
       if      (slrx_cmd==POOL_SETUP)  next_state = SETUP;    // Setup only, pending for execution
       else if (slrx_cmd==POOL_CALC) next_state = READ_ROWS;  // Proceed to execution           
       load_next_row_idx = 0;       
      end
      
      SETUP: begin
       next_state = DONE; 
      end     
      
      READ_ROWS: begin

        mem_intf_read.mem_req = 1;          
        mem_intf_read.mem_start_addr = arr_in_row_addr ;               
        arr_in_row_addr_ps = arr_in_next_row_addr ; 
        
        if (mem_intf_read.mem_valid) begin
          integer i;
          for (i=0;i<POOL_IN_MAX_ROW_SIZE;i++) 
            pool_in_buf_ps[load_row_idx][i] = (i<pool_arr_in_dim) ? mem_intf_read.mem_data[i] : 0 ; 
          if (load_row_idx==1) begin // Loading always two rows
             next_state = CALC ;  
             mem_intf_read.mem_req = 0;
          end else begin
             load_next_row_idx = load_row_idx+1;
             next_state = READ_ROWS;
          end 
        end
        
      end // READ_ROWS
 
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
        pool_done = 1;
        if (clear_done_on_read) next_state = IDLE; 
      end 
 
   endcase
   
  end // always

  //------------------------------------------------------------------------
       
  assign pool_out_buf_ps = calc_pool_win(pool_in_buf) ;

  //------------------------------------------------------------------------

 // Sequential
  always @(posedge clk or negedge rst_n) begin
  
    if(!rst_n) begin  
      state                  <= IDLE;    
      arr_in_row_addr        <= 0 ;
      arr_in_next_row_addr_s <= 0;
      load_row_idx           <= 0;
      pool_in_buf            <= 0;
      pool_out_buf           <= 0;
      pool_rslt_out_addr     <= 0;
    end else begin     
      state <= next_state ;
      arr_in_row_addr        <= arr_in_row_addr_ps ;
      arr_in_next_row_addr_s <= arr_in_next_row_addr ;     
      load_row_idx           <= load_next_row_idx;
      pool_in_buf            <= pool_in_buf_ps; 
      pool_out_buf           <= pool_out_buf_ps; 
      pool_rslt_out_addr     <= pool_rslt_out_addr_ps;      
    end    
  end
   
  //------------------------------------------------------------------------

  // Comb Function to calculate pool window
  
  function automatic logic [POOL_OUT_MAX_ROW_SIZE-1:0][7:0] calc_pool_win  ;
      
      input [1:0][POOL_IN_MAX_ROW_SIZE-1:0][7:0] pool_in_buf ;   // Current two rows pool window
    
      integer col ;       
      for (col = 0; col < POOL_IN_MAX_ROW_SIZE; col=col+2) begin       
        calc_pool_win[col/2] = max4_pool(pool_in_buf[0][col], pool_in_buf[0][col+1], 
                                         pool_in_buf[1][col], pool_in_buf[1][col+1]);
      end
 
  endfunction  

 //--------------------------------------------------------------

  function automatic logic [7:0] max4_pool  ;
      
      input[7:0] val0,val1,val2,val3 ;
     
         logic [7:0] max01 , max23 ;

         // Semi-Final
         max01 = val0 > val1 ? val0 : val1 ;
         max23 = val2 > val3 ? val2 : val3 ;  
         // Final
         max4_pool = max01 > max23 ? max01 : max23 ;
     
  endfunction  

 //--------------------------------------------------------------


endmodule
