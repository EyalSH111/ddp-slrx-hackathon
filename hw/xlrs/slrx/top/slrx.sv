import xbox_def_pkg::*;
import slrx_def_pkg::*;

module slrx (
  input   clk,
  input   rst_n,  
 
  // Command Status Register Interface
  input        [XBOX_NUM_REGS-1:0][31:0] host_regs,               // regs accelerator write data, reflecting logicisters content as most recently written by SW over APB
  input  logic [XBOX_NUM_REGS-1:0]       host_regs_valid_pulse,   // logic written by host (APB) (one per register)   
  output logic [XBOX_NUM_REGS-1:0][31:0] host_regs_data_out,      // regs accelerator write data,  this is what SW will read when accessing the register  
                                                                  // provided that the register specific host_regs_valid_out is asserted
  output logic [XBOX_NUM_REGS-1:0]       host_regs_valid_out,     // logic accelerator (one per register)   
  input  logic [XBOX_NUM_REGS-1:0]       host_regs_read_pulse,    // Indicate register actual read by host to allow clear on read if desired.

  // muxed interfaces
  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write);
    
  //--------------------------------------------------------------------------------------------------------
  
  // Accelerators host regs interface
  
  slrx_regs_intrf slrx_regs_intrf_conv();  
  slrx_regs_intrf slrx_regs_intrf_pool();
  slrx_regs_intrf slrx_regs_intrf_lin();
 
  //---------------------------------------------------------------------------------------------------------
  
  // Active Accelerator logic 
  
  assign acc_sel = host_regs[0];
    
  slr_xlr_t  active_xlr ;
  
  always_comb begin
    active_xlr = slr_xlr_t'(CONV) ; // default
    if  (  (host_regs[XLR_START_RI]==POOL_SETUP) 
         ||(host_regs[XLR_START_RI]==POOL_CALC)) active_xlr = slr_xlr_t'(POOL) ; 
         
    else if (  (host_regs[XLR_START_RI]==LIN_SETUP) 
             ||(host_regs[XLR_START_RI]==LIN_CALC)) active_xlr = slr_xlr_t'(LIN) ; 
  end 
             
  //---------------------------------------------------------------------------

   logic [XBOX_NUM_REGS-1:0][31:0] host_regs_data_out_ps ;  // pre-sampled  
  logic [XBOX_NUM_REGS-1:0] host_regs_valid_out_ps ; // pre-sampled 

  logic xlr_done;  
  
  always_comb begin
  
   host_regs_data_out_ps = host_regs_data_out ; // default
   host_regs_valid_out_ps = host_regs_valid_out ; // default     
 
   `ifdef XREGS_OUT_EN 
   if (active_xlr==slr_xlr_t'(CONV)) begin   
     host_regs_data_out_ps  = slrx_regs_intrf_conv.host_regs_data_out;                                                                       
     host_regs_valid_out_ps = slrx_regs_intrf_conv.host_regs_valid_out;    
   end else if (active_xlr==slr_xlr_t'(POOL)) begin      
     host_regs_data_out_ps  = slrx_regs_intrf_pool.host_regs_data_out;                                                                       
     host_regs_valid_out_ps = slrx_regs_intrf_pool.host_regs_valid_out;        
   end else if (active_xlr==slr_xlr_t'(LIN)) begin      
     host_regs_data_out_ps  = slrx_regs_intrf_lin.host_regs_data_out;                                                                       
     host_regs_valid_out_ps = slrx_regs_intrf_lin.host_regs_valid_out;  
   end
   `endif
  
   xlr_done = slrx_regs_intrf_conv.xlr_done || slrx_regs_intrf_pool.xlr_done || slrx_regs_intrf_lin.xlr_done;
   
   if (xlr_done) begin
      host_regs_data_out_ps[XLR_DONE_RI][0] = 1;
      host_regs_valid_out_ps[XLR_DONE_RI] = 1;
   end
   if (host_regs_read_pulse[XLR_DONE_RI]) begin
      host_regs_data_out_ps[XLR_DONE_RI][0] = 0;
      host_regs_valid_out_ps[XLR_DONE_RI] = 0;     
   end     
 
   if (host_regs_read_pulse[XLR_DONE_RI]) host_regs_data_out_ps[XLR_DONE_RI][0] = 0;  
   else if (xlr_done) host_regs_data_out_ps[XLR_DONE_RI][0] = 1;     
   host_regs_valid_out_ps[XLR_DONE_RI] = host_regs_data_out[XLR_DONE_RI][0];     
    
  end // always_comb
 
  //---------------------------------------------------------------------------

  //slrx_cmd_t slrx_cmd ; // Command type, defined at slrx_enums.svh
  
  always @(posedge clk, negedge rst_n) begin
     if(~rst_n) begin
       host_regs_data_out <= 0;
       host_regs_valid_out <= 0;      
     end
     else begin
       host_regs_data_out <= host_regs_data_out_ps; 
       host_regs_valid_out <= host_regs_valid_out_ps;        
     end       
  end
   
  //---------------------------------------------------------------------------  
  
  // Conv instantiate 
  
  assign slrx_regs_intrf_conv.xlr_done_ack          = host_regs_read_pulse[XLR_DONE_RI] ;
  assign slrx_regs_intrf_conv.host_regs             = host_regs;                                // input  [XBOX_NUM_REGS-1:0][31:0]
  assign slrx_regs_intrf_conv.host_regs_valid_pulse = host_regs_valid_pulse;                    // input  [XBOX_NUM_REGS-1:0]      

  `ifdef XREGS_OUT_EN 
  assign slrx_regs_intrf_conv.host_regs_read_pulse  = host_regs_read_pulse;                     // input  [XBOX_NUM_REGS-1:0]  
  `endif   
    
  mem_intf_read  mem_intf_read_conv() ;
  mem_intf_write mem_intf_write_conv() ; 

  conv conv (
    .clk (clk),
    .rst_n (rst_n),
  
    // Command Status Register Interface
    .slrx_regs_intrf       (slrx_regs_intrf_conv.xlr),
  
    .mem_intf_read         (mem_intf_read_conv.client_read),  
    .mem_intf_write        (mem_intf_write_conv.client_write)  
  );
 
  //---------------------------------------------------------------------------

  // Pool instantiate 
   
  assign slrx_regs_intrf_pool.xlr_done_ack = host_regs_read_pulse[XLR_DONE_RI] ;
  assign slrx_regs_intrf_pool.host_regs             = host_regs;                                // input  [XBOX_NUM_REGS-1:0][31:0]
  assign slrx_regs_intrf_pool.host_regs_valid_pulse = host_regs_valid_pulse;                    // input  [XBOX_NUM_REGS-1:0]      

  `ifdef XREGS_OUT_EN 
  assign slrx_regs_intrf_pool.host_regs_read_pulse  = host_regs_read_pulse;                     // input  [XBOX_NUM_REGS-1:0]  
  `endif   
    
  mem_intf_read  mem_intf_read_pool() ;
  mem_intf_write mem_intf_write_pool() ; 
             
  pool pool (
     .clk (clk),
     .rst_n (rst_n),
   
     // Command Status Register Interface
     .slrx_regs_intrf       (slrx_regs_intrf_pool.xlr),
     
     .mem_intf_read         (mem_intf_read_pool.client_read),  
     .mem_intf_write        (mem_intf_write_pool.client_write)  
   );

  //-----------------------------------------------------------------------------

  // Linear instantiate 
    
  assign slrx_regs_intrf_lin.xlr_done_ack = host_regs_read_pulse[XLR_DONE_RI] ;
  assign slrx_regs_intrf_lin.host_regs             = host_regs;                               // input  [XBOX_NUM_REGS-1:0][31:0]
  assign slrx_regs_intrf_lin.host_regs_valid_pulse = host_regs_valid_pulse;                   // input  [XBOX_NUM_REGS-1:0]      
 
  `ifdef XREGS_OUT_EN 
  assign slrx_regs_intrf_lin.host_regs_read_pulse  = host_regs_read_pulse;                     // input  [XBOX_NUM_REGS-1:0]  
  `endif   

  mem_intf_read  mem_intf_read_lin() ;
  mem_intf_write mem_intf_write_lin() ; 
        
  linear linear (
     .clk (clk),
     .rst_n (rst_n),
   
     // Command Status Register Interface
     .slrx_regs_intrf       (slrx_regs_intrf_lin.xlr),

     .mem_intf_read         (mem_intf_read_lin.client_read),  
     .mem_intf_write        (mem_intf_write_lin.client_write)  
   );

 
  //-----------------------------------------------------------------------------

 xmem_intf_mux xmem_intf_mux (

    .clk(clk),
    .rst_n(rst_n),
    
    .active_xlr(active_xlr[$clog2(NUM_XLRS)-1:0]), // SW driven
    
    // xmem muxed interface
    .mem_intf_read          (mem_intf_read.client_read),
    .mem_intf_write         (mem_intf_write.client_write),
 
    // Pool xmem interface   
    .mem_intf_read_conv  (mem_intf_read_conv),
    .mem_intf_write_conv (mem_intf_write_conv),
    
    // Linear xmem interface   
    .mem_intf_read_pool(mem_intf_read_pool),
    .mem_intf_write_pool(mem_intf_write_pool),
    
    .mem_intf_read_lin(mem_intf_read_lin),
    .mem_intf_write_lin(mem_intf_write_lin)
  );
 
endmodule