# SLRX Hackathon — All Changes Log
**Team:** Eyal Shomrai + Jessica Malem | **Date:** June 27, 2026

---

## Baseline (no accelerators)
- **Total:** 800,781 cycles/character
- Conv0: 636,099 | Conv1: 82,639 | Pool0: 11,554 | Pool1: 1,602 | Lin0: 32,964 | Lin1: 35,230

---

## Stage 1 — Linear Accelerator (branch: `stage1-linear`)
**Files changed:** `hw/xlrs/slrx/linear/linear.sv` (done before this hackathon session)

### What changed
Implemented `linear.sv` with a state machine: `IDLE → READ_KERNEL → READ_INPUT → CALC → WRITE → DONE`.
- Reads weight vector (up to 32 bytes) + input vector in two XMEM transactions
- Computes dot product + ReLU + descale using `calc_lin_element` function
- SW calls once per output neuron

### Results
- Lin0: 32,964 → 1,182 | Lin1: 35,230 → 1,017
- **Total: 800,781 → 734,786 cycles (1.09× — Linear only 8% of workload)**
- Synthesis: **56.67 MHz** ✅

---

## Stage 2 — Basic Conv Accelerator (branch: `stage2-conv-basic`)
**Files changed:** `hw/xlrs/slrx/conv/conv.sv`, `sw/apps/slrx/conv.c`

### What changed
**conv.sv:** New state machine: `IDLE → READ_KERNEL → READ_ROW0..4 → CALC → WRITE → DONE`
- `READ_KERNEL`: reads 25-byte kernel in one XMEM transaction
- `READ_ROW0..4`: reads 5 bytes per row (5 transactions)
- `CALC`: one pipeline cycle for 25-element MAC to settle
- `WRITE`: writes 1 output byte
- SW calls HW once per output pixel (784 calls for Conv0)

**conv.c:** Added `conv_xlr_setup()` function; `conv()` loops over all pixels calling HW.

### Results (ALL_XON, -stm)
- Conv0: 636,099 → 35,813 | Conv1: 82,639 → ~5,000
- **Total: 800,781 → 44,305 cycles (18×)**
- Synthesis: **53.72 MHz** ✅

---

## Stage 3 — HW Looping Conv (branch: `stage3-conv-hwloop`)
**Files changed:** `hw/xlrs/slrx/conv/conv.sv`, `sw/apps/slrx/conv.c`

### What changed
**conv.sv:** Added `row_cnt`, `col_cnt` counters and `NEXT_PIXEL` state.
- After WRITE, instead of DONE, goes to NEXT_PIXEL
- NEXT_PIXEL: increments col, or increments row + resets col, or goes to DONE
- SW now calls HW **once per layer** (not once per pixel)
- 784 SW→HW round trips → 1

**conv.c:** Removed per-pixel loop; single `conv_xlr_setup()` call.

### Results (ALL_XON, -stm)
- Conv0: 35,813 → 11,092 (3.2×) | Conv1: 1,488
- **Total: 44,305 → 16,315 cycles (49× vs baseline)**

---

## Stage 4 — Sliding Row Cache (branch: `stage4-conv-rowcache`)
**Files changed:** `hw/xlrs/slrx/conv/conv.sv`

### What changed
**conv.sv:** Replaced 5×5 window buffer with 5×32 full-row cache (1280 FFs).

- Removed `READ_ROW0..4` states (5 reads × 5 bytes per pixel)
- Added `LOAD_ROW0..4` states: load 5 **full rows** once at startup
- Added `LOAD_NEW_ROW` state: slide cache by 1 row when advancing output row
  - Shifts row_cache[0..3] = row_cache[1..4], loads new row into [4]
- `window` becomes combinational: `window[r][c] = row_cache[r][col_cnt + c]`
- XMEM reads: 784×25=19,600 → 32 reads per layer (~600× reduction)

**Timing fix (Phase 3b):** Registered `window` to break critical path:
- `window_ps` precomputed in LOAD_ROW4 / NEXT_PIXEL / LOAD_NEW_ROW
- Stage 1: `col_cnt → 32:1 mux → window FF` (fast)
- Stage 2: `window → 25 MACs → conv_out_val FF` (existing CALC cycle)

### Results (ALL_XON, -stm)
- Conv0: 11,092 → **3,312** (3.4×) | Conv1: 1,488 → **518**
- **Total: 16,315 → 7,565 cycles (106× vs baseline)**
- Synthesis: **55.33 MHz** ✅ (archive: `qsyn_conv_eyalsho_270626_1604.tgz`)

---

## Stage 5 — Fused Conv+Pool (branch: `stage5-fused-pool`) ← IN PROGRESS
**Files changed:** `hw/xlrs/slrx/conv/conv.sv`, `sw/apps/slrx/conv.c`, `sw/apps/slrx/slrx.c`

### What changes
**conv.sv:** Fused mode activated by `host_regs[OUT_ROW_IDX_RI][0] = 1`.
- CALC now branches: fused → POST_CALC, normal → WRITE (backward compatible)
- New POST_CALC state handles buffering/maxing:
  - even row + even col: store in `prev_conv_val`
  - even row + odd col: max(prev, curr) → `even_row_buf[pool_col]` (14-byte buffer)
  - odd row + even col: store in `prev_conv_val`
  - odd row + odd col: max(even_row_buf[pc], prev, curr) → WRITE_POOL
- New WRITE_POOL state: writes 1 pool byte to `pool_addr + pool_row * pool_out_dim + pool_col`
- Pool row/col derived from conv row_cnt/col_cnt by dividing by 2

**conv.c:** Added `conv_xlr_setup_fused(pool_arr_out, ...)` function.

**slrx.c:** Under `FUSED_XON`:
- Call `conv_xlr_setup_fused(pool0_out, conv0_in, ...)` instead of `conv()` + `pool()`
- Skip pool layer calls

### Expected results
- Conv0: 3,312 → ~2,843 | Conv1: 518 → ~377
- Pool0: 570 → 0 (skipped) | Pool1: 273 → 0 (skipped)
- **Total: ~6,112 cycles → ~131× vs baseline**
- Expected synthesis: >50 MHz (minor changes to critical path)

---

## Performance Summary

| Stage | Branch | Cycles | Speedup | Synthesis |
|-------|--------|--------|---------|-----------|
| Baseline | — | 800,781 | 1× | — |
| Linear | stage1-linear | 734,786 | 1.09× | 56.67 MHz ✅ |
| Conv Basic | stage2-conv-basic | 44,305 | 18× | 53.72 MHz ✅ |
| Conv HW Loop | stage3-conv-hwloop | 16,315 | 49× | — |
| Conv Row Cache | stage4-conv-rowcache | **7,565** | **106×** | **55.33 MHz ✅** |
| Fused Conv+Pool | stage5-fused-pool | ~6,112 | ~131× | TBD |
