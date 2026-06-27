import xbox_def_pkg::*;
import slrx_def_pkg::*;

module conv (
  input   clk,
  input   rst_n,

  slrx_regs_intrf.xlr slrx_regs_intrf, // Host Registers Interface

  // muxed interfaces
  mem_intf_read.client_read   mem_intf_read,
  mem_intf_write.client_write mem_intf_write
);

  localparam DIM_MAX_SIZE       = 32;
  localparam KERNEL_DIM         = 5;
  localparam KERNEL_SIZE        = KERNEL_DIM * KERNEL_DIM;          // 25
  localparam MAX_DOT_PROD_WIDTH = 16 + $clog2(KERNEL_SIZE);         // 21
  localparam ARR_IDX_W          = $clog2(DIM_MAX_SIZE);             // 5
  localparam POOL_OUT_DIM_MAX   = (DIM_MAX_SIZE - KERNEL_DIM + 1)/2; // 14

  enum {IDLE, READ_KERNEL,
        LOAD_ROW0, LOAD_ROW1, LOAD_ROW2, LOAD_ROW3, LOAD_ROW4,
        CALC, POST_CALC, WRITE, WRITE_POOL,
        NEXT_PIXEL, LOAD_NEW_ROW,
        DONE} state, next_state;

  logic        conv_start;
  logic        conv_done;
  logic        clear_done_on_read;
  logic        conv_active;
  slrx_cmd_t   slrx_cmd;

  // Host register inputs
  logic [XMEM_ADDR_WIDTH-1:0]           conv_kernel_addr;
  logic [XMEM_ADDR_WIDTH-1:0]           conv_arr_in_addr;
  logic [XMEM_ADDR_WIDTH-1:0]           conv_arr_out_addr;
  logic [ARR_IDX_W:0]                   conv_arr_in_dim;
  logic [ARR_IDX_W:0]                   conv_arr_out_dim;
  logic signed [MAX_DOT_PROD_WIDTH-1:0] conv_bias_val;
  logic                                 fused_pool_en;   // OUT_ROW_IDX_RI[0]=1 → fused conv+pool

  // Kernel cache (25 bytes)
  logic [KERNEL_DIM-1:0][KERNEL_DIM-1:0][7:0] kernel_cache, kernel_cache_ps;

  // Row cache: 5 full input rows x DIM_MAX_SIZE bytes (1280 FFs)
  logic [KERNEL_DIM-1:0][DIM_MAX_SIZE-1:0][7:0] row_cache, row_cache_ps;

  // 5x5 window: registered to break critical path (mux + MAC in separate cycles)
  logic [KERNEL_DIM-1:0][KERNEL_DIM-1:0][7:0] window, window_ps;

  // Loop counters
  logic [ARR_IDX_W-1:0] row_cnt,     row_cnt_ps;
  logic [ARR_IDX_W-1:0] col_cnt,     col_cnt_ps;
  logic [ARR_IDX_W:0]   next_in_row, next_in_row_ps;

  // Fused pool buffers
  logic [7:0]                        prev_conv_val,  prev_conv_val_ps; // first-of-column-pair
  logic [POOL_OUT_DIM_MAX-1:0][7:0]  even_row_buf,   even_row_buf_ps;  // max of even-row pairs
  logic [7:0]                        pool_out_val,   pool_out_val_ps;  // final pool result

  // Conv output
  logic [7:0]                 conv_out_val, conv_out_val_ps;
  logic [XMEM_ADDR_WIDTH-1:0] conv_rslt_out_addr, conv_rslt_out_addr_ps;

  // Combinational helpers
  logic [ARR_IDX_W-2:0] pool_col;     // col_cnt / 2
  logic [ARR_IDX_W-2:0] pool_row_idx; // row_cnt / 2
  logic [7:0]           pool_pair_max; // max(prev_conv_val, conv_out_val) for POST_CALC

  //--------------------------------------------------------------------------------------------------------

  assign slrx_regs_intrf.xlr_done = conv_done;

  assign slrx_cmd          = slrx_cmd_t'(slrx_regs_intrf.host_regs[XLR_START_RI][$clog2(NUM_SLRX_CMDS)-1:0]);
  assign conv_active        = (slrx_cmd == CONV_SETUP);
  assign conv_start         = slrx_regs_intrf.host_regs_valid_pulse[XLR_START_RI] && conv_active;
  assign clear_done_on_read = conv_active && slrx_regs_intrf.xlr_done_ack;

  assign conv_kernel_addr  = slrx_regs_intrf.host_regs[WGT_ADDR_RI];
  assign conv_arr_in_addr  = slrx_regs_intrf.host_regs[ARR_IN_ADDR_RI];
  assign conv_arr_out_addr = slrx_regs_intrf.host_regs[ARR_OUT_ADDR_RI];
  assign conv_arr_in_dim   = slrx_regs_intrf.host_regs[ARR_IN_DIM_RI];
  assign conv_arr_out_dim  = conv_arr_in_dim - KERNEL_DIM + 1;
  assign conv_bias_val     = $signed(slrx_regs_intrf.host_regs[CONV_BIAS_VAL_RI][MAX_DOT_PROD_WIDTH-1:0]);
  assign fused_pool_en     = slrx_regs_intrf.host_regs[OUT_ROW_IDX_RI][0]; // 1 = fused conv+pool

  assign pool_col      = col_cnt[ARR_IDX_W-1:1];     // col_cnt >> 1
  assign pool_row_idx  = row_cnt[ARR_IDX_W-1:1];     // row_cnt >> 1
  assign pool_pair_max = (conv_out_val > prev_conv_val) ? conv_out_val : prev_conv_val;

  //========================================================================================================

  always_comb begin
    next_state = state;

    kernel_cache_ps   = kernel_cache;
    row_cache_ps      = row_cache;
    window_ps         = window;
    row_cnt_ps        = row_cnt;
    col_cnt_ps        = col_cnt;
    next_in_row_ps    = next_in_row;
    prev_conv_val_ps  = prev_conv_val;
    even_row_buf_ps   = even_row_buf;
    pool_out_val_ps   = pool_out_val;

    mem_intf_read.mem_req        = 0;
    mem_intf_read.mem_start_addr = 0;
    mem_intf_read.mem_size_bytes = 0;

    mem_intf_write.mem_req        = 0;
    mem_intf_write.mem_start_addr = conv_rslt_out_addr;
    mem_intf_write.mem_size_bytes = 1;
    mem_intf_write.mem_data       = conv_out_val;

    // Conv output address (used in non-fused WRITE state)
    conv_rslt_out_addr_ps = conv_arr_out_addr +
                            row_cnt * conv_arr_out_dim +
                            col_cnt;

    conv_done = 0;

    case (state)

      IDLE: if (conv_start) begin
        row_cnt_ps     = 0;
        col_cnt_ps     = 0;
        next_in_row_ps = (ARR_IDX_W+1)'(KERNEL_DIM);
        next_state     = READ_KERNEL;
      end

      // --- Read 5x5 kernel weights (25 bytes) ---
      READ_KERNEL: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_kernel_addr;
        mem_intf_read.mem_size_bytes = KERNEL_SIZE;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int r = 0; r < KERNEL_DIM; r++)
            for (int c = 0; c < KERNEL_DIM; c++)
              kernel_cache_ps[r][c] = mem_intf_read.mem_data[r*KERNEL_DIM + c];
          next_state = LOAD_ROW0;
        end
      end

      // --- Load 5 full input rows into row_cache (initial setup) ---
      LOAD_ROW0: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr;
        mem_intf_read.mem_size_bytes = conv_arr_in_dim;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < DIM_MAX_SIZE; c++) row_cache_ps[0][c] = mem_intf_read.mem_data[c];
          next_state = LOAD_ROW1;
        end
      end

      LOAD_ROW1: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + conv_arr_in_dim;
        mem_intf_read.mem_size_bytes = conv_arr_in_dim;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < DIM_MAX_SIZE; c++) row_cache_ps[1][c] = mem_intf_read.mem_data[c];
          next_state = LOAD_ROW2;
        end
      end

      LOAD_ROW2: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + 2 * conv_arr_in_dim;
        mem_intf_read.mem_size_bytes = conv_arr_in_dim;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < DIM_MAX_SIZE; c++) row_cache_ps[2][c] = mem_intf_read.mem_data[c];
          next_state = LOAD_ROW3;
        end
      end

      LOAD_ROW3: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + 3 * conv_arr_in_dim;
        mem_intf_read.mem_size_bytes = conv_arr_in_dim;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < DIM_MAX_SIZE; c++) row_cache_ps[3][c] = mem_intf_read.mem_data[c];
          next_state = LOAD_ROW4;
        end
      end

      LOAD_ROW4: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + 4 * conv_arr_in_dim;
        mem_intf_read.mem_size_bytes = conv_arr_in_dim;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int c = 0; c < DIM_MAX_SIZE; c++) row_cache_ps[4][c] = mem_intf_read.mem_data[c];
          // Precompute window for first pixel (col=0): stage 1 of 2-stage pipeline
          for (int r = 0; r < KERNEL_DIM; r++)
            for (int c = 0; c < KERNEL_DIM; c++)
              window_ps[r][c] = (r < KERNEL_DIM-1) ? row_cache[r][c] : mem_intf_read.mem_data[c];
          next_state = CALC;
        end
      end

      // --- CALC: pipeline cycle — window is registered, conv_out_val_ps settles ---
      CALC: begin
        next_state = fused_pool_en ? POST_CALC : WRITE;
      end

      // --- POST_CALC (fused mode only): buffer or max-pool based on row/col parity ---
      POST_CALC: begin
        // conv_out_val is now registered (this pixel's result)
        if (!row_cnt[0] && !col_cnt[0]) begin
          // even row, even col: store first-of-column-pair
          prev_conv_val_ps = conv_out_val;
          next_state = NEXT_PIXEL;
        end else if (!row_cnt[0] && col_cnt[0]) begin
          // even row, odd col: store max(even_col_pair) into even_row_buf
          even_row_buf_ps[pool_col] = pool_pair_max;
          next_state = NEXT_PIXEL;
        end else if (row_cnt[0] && !col_cnt[0]) begin
          // odd row, even col: store first-of-column-pair
          prev_conv_val_ps = conv_out_val;
          next_state = NEXT_PIXEL;
        end else begin
          // odd row, odd col: compute final 2x2 pool max and write
          // pool_val = max(even_row_buf[pc], max(odd_2pc, odd_2pc+1))
          pool_out_val_ps = (pool_pair_max > even_row_buf[pool_col]) ?
                             pool_pair_max : even_row_buf[pool_col];
          next_state = WRITE_POOL;
        end
      end

      // --- WRITE (normal mode): write 1 conv output byte ---
      WRITE: begin
        mem_intf_write.mem_req = 1;
        if (mem_intf_write.mem_ack) begin
          mem_intf_write.mem_req = 0;
          next_state = NEXT_PIXEL;
        end
      end

      // --- WRITE_POOL (fused mode): write 1 pool output byte ---
      WRITE_POOL: begin
        mem_intf_write.mem_req        = 1;
        mem_intf_write.mem_start_addr = conv_arr_out_addr +
                                        pool_row_idx * (conv_arr_out_dim >> 1) +
                                        pool_col;
        mem_intf_write.mem_data       = pool_out_val;
        if (mem_intf_write.mem_ack) begin
          mem_intf_write.mem_req = 0;
          next_state = NEXT_PIXEL;
        end
      end

      // --- Advance to next output pixel ---
      NEXT_PIXEL: begin
        if (col_cnt < conv_arr_out_dim - 1) begin
          col_cnt_ps = col_cnt + 1;
          // Precompute window for next column: stage 1 of 2-stage pipeline
          for (int r = 0; r < KERNEL_DIM; r++)
            for (int c = 0; c < KERNEL_DIM; c++)
              window_ps[r][c] = row_cache[r][(col_cnt + 1) + c];
          next_state = CALC;
        end else if (row_cnt < conv_arr_out_dim - 1) begin
          col_cnt_ps = 0;
          row_cnt_ps = row_cnt + 1;
          next_state = LOAD_NEW_ROW;
        end else begin
          next_state = DONE;
        end
      end

      // --- Slide row cache: drop oldest row, load next input row into slot [4] ---
      LOAD_NEW_ROW: begin
        mem_intf_read.mem_req        = 1;
        mem_intf_read.mem_start_addr = conv_arr_in_addr + next_in_row * conv_arr_in_dim;
        mem_intf_read.mem_size_bytes = conv_arr_in_dim;
        if (mem_intf_read.mem_valid) begin
          mem_intf_read.mem_req = 0;
          for (int r = 0; r < KERNEL_DIM-1; r++) row_cache_ps[r] = row_cache[r+1];
          for (int c = 0; c < DIM_MAX_SIZE; c++) row_cache_ps[KERNEL_DIM-1][c] = mem_intf_read.mem_data[c];
          // Precompute window for col=0 of next row: stage 1 of 2-stage pipeline
          for (int r = 0; r < KERNEL_DIM; r++)
            for (int c = 0; c < KERNEL_DIM; c++)
              window_ps[r][c] = (r < KERNEL_DIM-1) ? row_cache[r+1][c] : mem_intf_read.mem_data[c];
          next_in_row_ps = next_in_row + 1;
          next_state = CALC;
        end
      end

      DONE: begin
        conv_done = 1;
        if (clear_done_on_read) next_state = IDLE;
      end

    endcase
  end // always_comb

  //-----------------------------------------------------------------------------------------------------
  // Stage 2: MAC on registered window (critical path: window FFs → 25 MACs → register)
  assign conv_out_val_ps = calc_conv_element(kernel_cache, conv_bias_val, window);

  //-----------------------------------------------------------------------------------------------------

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state              <= IDLE;
      kernel_cache       <= 0;
      row_cache          <= 0;
      window             <= 0;
      row_cnt            <= 0;
      col_cnt            <= 0;
      next_in_row        <= 0;
      prev_conv_val      <= 0;
      even_row_buf       <= 0;
      pool_out_val       <= 0;
      conv_out_val       <= 0;
      conv_rslt_out_addr <= 0;
    end else begin
      state              <= next_state;
      kernel_cache       <= kernel_cache_ps;
      row_cache          <= row_cache_ps;
      window             <= window_ps;
      row_cnt            <= row_cnt_ps;
      col_cnt            <= col_cnt_ps;
      next_in_row        <= next_in_row_ps;
      prev_conv_val      <= prev_conv_val_ps;
      even_row_buf       <= even_row_buf_ps;
      pool_out_val       <= pool_out_val_ps;
      conv_out_val       <= conv_out_val_ps;
      conv_rslt_out_addr <= conv_rslt_out_addr_ps;
    end
  end

  //-----------------------------------------------------------------------------------------------------
  // Combinational function: 5x5 dot product, ReLU, descale by 8 bits

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
