import xbox_def_pkg::*;
import slrx_def_pkg::*;

module conv (
  input   clk,
  input   rst_n,

  slrx_regs_intrf.xlr slrx_regs_intrf,

  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write
);

  localparam DIM_MAX_SIZE       = 32;
  localparam KERNEL_DIM         = 5;
  localparam KERNEL_SIZE        = KERNEL_DIM * KERNEL_DIM;
  localparam MAX_DOT_PROD_WIDTH = 16 + $clog2(KERNEL_SIZE);
  localparam ARR_IDX_W          = $clog2(DIM_MAX_SIZE);

  enum {IDLE, READ_KERNEL, READ_ROW0, READ_ROW1, READ_ROW2, READ_ROW3, READ_ROW4,
        CALC, WRITE, DONE} state, next_state;

  logic        conv_start;
  logic        conv_done;
  logic        clear_done_on_read;
  logic        conv_active;
  slrx_cmd_t   slrx_cmd;

  logic [XMEM_ADDR_WIDTH-1:0]           conv_kernel_addr;
  logic [XMEM_ADDR_WIDTH-1:0]           conv_arr_in_addr;
  logic [XMEM_ADDR_WIDTH-1:0]           conv_arr_out_addr;
  logic [ARR_IDX_W:0]                   conv_arr_in_dim;
  logic [ARR_IDX_W:0]                   conv_arr_out_dim;
  logic [ARR_IDX_W-1:0]                 conv_out_row_idx;
  logic [ARR_IDX_W-1:0]                 conv_out_col_idx;
  logic signed [MAX_DOT_PROD_WIDTH-1:0] conv_bias_val;

  logic [KERNEL_DIM-1:0][KERNEL_DIM-1:0][7:0] kernel_cache, kernel_cache_ps;
  logic [KERNEL_DIM-1:0][KERNEL_DIM-1:0][7:0] window, window_ps;

  logic [7:0]                 conv_out_val, conv_out_val_ps;
  logic [XMEM_ADDR_WIDTH-1:0] conv_rslt_out_addr, conv_rslt_out_addr_ps;

  assign slrx_regs_intrf.xlr_done = conv_done;

  assign slrx_cmd          = slrx_cmd_t'(slrx_regs_intrf.host_regs[XLR_START_RI][$clog2(NUM_SLRX_CMDS)-1:0]);
  assign conv_active        = (slrx_cmd == CONV_SETUP) || (slrx_cmd == CONV_WINDOW);
  assign conv_start         = slrx_regs_intrf.host_regs_valid_pulse[XLR_START_RI] && conv_active;
  assign clear_done_on_read = conv_active && slrx_regs_intrf.xlr_done_ack;

  assign conv_kernel_addr  = slrx_regs_intrf.host_regs[WGT_ADDR_RI];
  assign conv_arr_in_addr  = slrx_regs_intrf.host_regs[ARR_IN_ADDR_RI];
  assign conv_arr_out_addr = slrx_regs_intrf.host_regs[ARR_OUT_ADDR_RI];
  assign conv_arr_in_dim   = slrx_regs_intrf.host_regs[ARR_IN_DIM_RI];
  assign conv_arr_out_dim  = conv_arr_in_dim - KERNEL_DIM + 1;
  assign conv_out_row_idx  = slrx_regs_intrf.host_regs[OUT_ROW_IDX_RI];
  assign conv_out_col_idx  = slrx_regs_intrf.host_regs[OUT_COL_IDX_RI];
  assign conv_bias_val     = $signed(slrx_regs_intrf.host_regs[CONV_BIAS_VAL_RI][MAX_DOT_PROD_WIDTH-1:0]);

  always_comb begin
    next_state = state;
    kernel_cache_ps = kernel_cache;
    window_ps       = window;

    mem_intf_read.mem_req        = 0;
    mem_intf_read.mem_start_addr = 0;
    mem_intf_read.mem_size_bytes = 0;

    mem_intf_write.mem_req        = 0;
    mem_intf_write.mem_start_addr = conv_rslt_out_addr;
    mem_intf_write.mem_size_bytes = 1;
    mem_intf_write.mem_data       = conv_out_val;

    conv_rslt_out_addr_ps = conv_arr_out_addr +
                            conv_out_row_idx * conv_arr_out_dim +
                            conv_out_col_idx;
    conv_done = 0;

    case (state)
      IDLE: if (conv_start) begin
        if      (slrx_cmd == CONV_SETUP)  next_state = READ_KERNEL;
        else if (slrx_cmd == CONV_WINDOW) next_state = READ_ROW0;
      end

      READ_KERNEL: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_kernel_addr;
        mem_intf_read.mem_size_bytes = KERNEL_SIZE;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int r = 0; r < KERNEL_DIM; r++)
            for (int c = 0; c < KERNEL_DIM; c++)
              kernel_cache_ps[r][c] = mem_intf_read.mem_data[r*KERNEL_DIM + c];
          next_state = DONE;
        end
      end

      READ_ROW0: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + conv_out_row_idx * conv_arr_in_dim + conv_out_col_idx;
        mem_intf_read.mem_size_bytes = KERNEL_DIM;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < KERNEL_DIM; c++) window_ps[0][c] = mem_intf_read.mem_data[c];
          next_state = READ_ROW1;
        end
      end

      READ_ROW1: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + (conv_out_row_idx + 1) * conv_arr_in_dim + conv_out_col_idx;
        mem_intf_read.mem_size_bytes = KERNEL_DIM;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < KERNEL_DIM; c++) window_ps[1][c] = mem_intf_read.mem_data[c];
          next_state = READ_ROW2;
        end
      end

      READ_ROW2: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + (conv_out_row_idx + 2) * conv_arr_in_dim + conv_out_col_idx;
        mem_intf_read.mem_size_bytes = KERNEL_DIM;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < KERNEL_DIM; c++) window_ps[2][c] = mem_intf_read.mem_data[c];
          next_state = READ_ROW3;
        end
      end

      READ_ROW3: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + (conv_out_row_idx + 3) * conv_arr_in_dim + conv_out_col_idx;
        mem_intf_read.mem_size_bytes = KERNEL_DIM;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < KERNEL_DIM; c++) window_ps[3][c] = mem_intf_read.mem_data[c];
          next_state = READ_ROW4;
        end
      end

      READ_ROW4: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + (conv_out_row_idx + 4) * conv_arr_in_dim + conv_out_col_idx;
        mem_intf_read.mem_size_bytes = KERNEL_DIM;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < KERNEL_DIM; c++) window_ps[4][c] = mem_intf_read.mem_data[c];
          next_state = CALC;
        end
      end

      CALC: begin
        next_state = WRITE;
      end

      WRITE: begin
        mem_intf_write.mem_req = 1;
        if (mem_intf_write.mem_ack) begin
          mem_intf_write.mem_req = 0;
          next_state = DONE;
        end
      end

      DONE: begin
        conv_done = 1;
        if (clear_done_on_read) next_state = IDLE;
      end
    endcase
  end

  assign conv_out_val_ps = calc_conv_element(kernel_cache, conv_bias_val, window);

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state              <= IDLE;
      kernel_cache       <= 0;
      window             <= 0;
      conv_out_val       <= 0;
      conv_rslt_out_addr <= 0;
    end else begin
      state              <= next_state;
      kernel_cache       <= kernel_cache_ps;
      window             <= window_ps;
      conv_out_val       <= conv_out_val_ps;
      conv_rslt_out_addr <= conv_rslt_out_addr_ps;
    end
  end

  function automatic logic [7:0] calc_conv_element;
    input [KERNEL_DIM-1:0][KERNEL_DIM-1:0][7:0] kernel;
    input signed [MAX_DOT_PROD_WIDTH-1:0]        bias;
    input [KERNEL_DIM-1:0][KERNEL_DIM-1:0][7:0] win;
    logic signed [MAX_DOT_PROD_WIDTH-1:0] acc;
    logic signed [MAX_DOT_PROD_WIDTH-1:0] k_s;
    logic signed [MAX_DOT_PROD_WIDTH-1:0] w_s;
    logic signed [MAX_DOT_PROD_WIDTH-1:0] ret_val;
    integer r, c;
    begin
      acc = bias;
      for (r = 0; r < KERNEL_DIM; r++) begin
        for (c = 0; c < KERNEL_DIM; c++) begin
          k_s = {{(MAX_DOT_PROD_WIDTH-8){kernel[r][c][7]}}, kernel[r][c]};
          w_s = {{(MAX_DOT_PROD_WIDTH-8){1'b0}}, win[r][c]};
          acc = acc + (k_s * w_s);
        end
      end
      if (acc <= 0)
        ret_val = 0;
      else begin
        ret_val = acc >>> 8;
        if (ret_val > 255) ret_val = 255;
      end
      calc_conv_element = ret_val[7:0];
    end
  endfunction

endmodule
