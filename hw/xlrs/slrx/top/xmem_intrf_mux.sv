import slrx_def_pkg::*;

module xmem_intf_mux (

    input clk,
    input rst_n,
    
    input [$clog2(NUM_XLRS)-1:0] active_xlr,
    
    // XMEM muxed interface
    mem_intf_read.client_read   mem_intf_read,
    mem_intf_write.client_write mem_intf_write,    

   // conv read from xmem ports   
    mem_intf_read.memory_read   mem_intf_read_conv,  
    mem_intf_write.memory_write mem_intf_write_conv,  

    // pool read from xmem ports   
    mem_intf_read.memory_read   mem_intf_read_pool,  
    mem_intf_write.memory_write mem_intf_write_pool,   

    // linear read from xmem ports
	mem_intf_read.memory_read    mem_intf_read_lin,
    mem_intf_write.memory_write  mem_intf_write_lin
);
      
 always_comb begin 

    // default
    mem_intf_read.mem_req        = mem_intf_read_conv.mem_req ;
    mem_intf_read.mem_start_addr = mem_intf_read_conv.mem_start_addr ;
    mem_intf_read.mem_size_bytes = mem_intf_read_conv.mem_size_bytes ;  
   
    if (active_xlr==POOL) begin    
          mem_intf_read.mem_req        = mem_intf_read_pool.mem_req ;
          mem_intf_read.mem_start_addr = mem_intf_read_pool.mem_start_addr ;
          mem_intf_read.mem_size_bytes = mem_intf_read_pool.mem_size_bytes ;                 
   
    end else if (active_xlr==LIN) begin    
          mem_intf_read.mem_req        = mem_intf_read_lin.mem_req ;
          mem_intf_read.mem_start_addr = mem_intf_read_lin.mem_start_addr ;
          mem_intf_read.mem_size_bytes = mem_intf_read_lin.mem_size_bytes ;                 
    end
        
  end // always 
 
 always_comb begin
  mem_intf_read_conv.mem_data = mem_intf_read.mem_data; 
  mem_intf_read_pool.mem_data = mem_intf_read.mem_data;   
  mem_intf_read_lin.mem_data  = mem_intf_read.mem_data;                  
 end

 always_comb begin 
   // Default Linear 
   mem_intf_write.mem_req        =  mem_intf_write_conv.mem_req;        
   mem_intf_write.mem_start_addr =  mem_intf_write_conv.mem_start_addr; 
   mem_intf_write.mem_size_bytes =  mem_intf_write_conv.mem_size_bytes; 
   mem_intf_write.mem_data       =  mem_intf_write_conv.mem_data;  
   
   if (active_xlr==POOL) begin

      mem_intf_write.mem_req        =  mem_intf_write_pool.mem_req;        
      mem_intf_write.mem_start_addr =  mem_intf_write_pool.mem_start_addr; 
      mem_intf_write.mem_size_bytes =  mem_intf_write_pool.mem_size_bytes; 
      mem_intf_write.mem_data       =  mem_intf_write_pool.mem_data;       

   end else if (active_xlr==LIN) begin

      mem_intf_write.mem_req        =  mem_intf_write_lin.mem_req;        
      mem_intf_write.mem_start_addr =  mem_intf_write_lin.mem_start_addr; 
      mem_intf_write.mem_size_bytes =  mem_intf_write_lin.mem_size_bytes; 
      mem_intf_write.mem_data       =  mem_intf_write_lin.mem_data;       

   end   
 end 
 
 always_comb begin 
   mem_intf_read_conv.mem_valid = (active_xlr==CONV) && mem_intf_read.mem_valid;
   mem_intf_write_conv.mem_ack  = (active_xlr==CONV) && mem_intf_write.mem_ack;
   mem_intf_read_pool.mem_valid = (active_xlr==POOL) && mem_intf_read.mem_valid;
   mem_intf_write_pool.mem_ack  = (active_xlr==POOL) && mem_intf_write.mem_ack;
   mem_intf_read_lin.mem_valid  = (active_xlr==LIN) && mem_intf_read.mem_valid;
   mem_intf_write_lin.mem_ack   = (active_xlr==LIN) && mem_intf_write.mem_ack;
 end
 
endmodule