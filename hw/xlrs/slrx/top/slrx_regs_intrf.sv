import xbox_def_pkg::*;
import slrx_def_pkg::*;

interface slrx_regs_intrf ;

  logic [XBOX_NUM_REGS-1:0][31:0] host_regs;               // regs accelerator write data; reflecting logicisters content as most recently written by SW over APB
  logic [XBOX_NUM_REGS-1:0]       host_regs_valid_pulse;   // logic written by host(one per register)   

  `ifdef XREGS_OUT_EN  
  logic [XBOX_NUM_REGS-1:0][31:0] host_regs_data_out;      // regs accelerator write data;  this is what SW will read when accessing the register                                                           // provided that the register specific host_regs_valid_out is asserted
  logic [XBOX_NUM_REGS-1:0]       host_regs_valid_out;     // logic accelerator (one per register)   
  logic [XBOX_NUM_REGS-1:0]       host_regs_read_pulse;    // Indicate register actual read by host to allow clear on read if desired.
  `endif

  logic xlr_start;
  logic [$clog2(NUM_SLRX_CMDS)-1:0] slrx_cmd;

  logic xlr_done;
  logic xlr_done_ack ; 

  modport host (

    output  host_regs,            
    output  host_regs_valid_pulse,
   
    `ifdef XREGS_OUT_EN    
    input   host_regs_data_out,                       
    input   host_regs_valid_out, 
    output  host_regs_read_pulse,     
    `endif
  
    output xlr_start,
    output /* [$clog2(NUM_SLRX_CMDS)-1:0]*/ slrx_cmd,
    
    input  xlr_done,
    output xlr_done_ack  
  
  );

  modport xlr (

    input  host_regs,            
    input  host_regs_valid_pulse,
  

    `ifdef XREGS_OUT_EN
    output host_regs_data_out,     
    output host_regs_valid_out,  
    input  host_regs_read_pulse,
    `endif    
    
    input xlr_start,
    input /* [XLR_START_RI][$clog2(NUM_SLRX_CMDS)-1:0] */ slrx_cmd,
    
    output xlr_done,
    input  xlr_done_ack
  
  );

endinterface