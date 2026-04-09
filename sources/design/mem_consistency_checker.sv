// =============================================================================
// File        : mem_consistency_checker.sv
// Project     : Memory Consistency Model Verification Multi-Core System
// Author      : Vinayak Venkappa Pujeri (Vision)
// Description : Synthesisable RAW/WAW consistency checker.
//
//   [C1] RAW a core reads an address another core wrote;
//              read data must match the last committed write value.
//   [C2] WAW two or more cores request writes to the same address
//              in the same cycle (arbiter must serialise them;
//              final value depends on grant order flagged as conflict).
//
// WAW is detected on the REQUEST bus (req_valid+req_we+req_addr) because
// the round-robin arbiter only grants one core per cycle, so grants can
// never show two simultaneous writes.
// =============================================================================

module mem_consistency_checker #(
  parameter NUM_CORES = 4,
  parameter LOG_DEPTH = 16
)(
  input  logic        clk,
  input  logic        rstn,

  // --- Observation: completed operations (from grant/response ports) ---
  input  logic [31:0] obs_addr  [NUM_CORES],   // req_addr (stable at grant)
  input  logic [31:0] obs_data  [NUM_CORES],   // rsp_rdata
  input  logic        obs_we    [NUM_CORES],   // req_we
  input  logic        obs_valid [NUM_CORES],   // rsp_grant

  // --- WAW input: raw request bus (before arbitration) ---
  input  logic [31:0] req_addr  [NUM_CORES],
  input  logic        req_we    [NUM_CORES],
  input  logic        req_valid [NUM_CORES],

  // --- Violation outputs ---
  output logic        raw_violation,   // sticky high on RAW data mismatch
  output logic        waw_conflict,    // sticky high on simultaneous write requests

  output logic [31:0] viol_addr,
  output logic [31:0] viol_exp,
  output logic [31:0] viol_got,
  output logic [3:0]  viol_core
);


  // Operation log

  typedef struct packed {
    logic [3:0]  core_id;
    logic [31:0] addr;
    logic [31:0] data;
    logic        is_write;
    logic        valid;
  } op_entry_t;

  op_entry_t log_buf [0:LOG_DEPTH-1];
  logic [$clog2(LOG_DEPTH)-1:0] log_ptr;

  // Shadow memory: tracks expected values from committed writes
  logic [31:0] shadow_mem   [0:15];
  logic        shadow_valid  [0:15];


  // Sequential checks

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      log_ptr       <= '0;
      raw_violation <= '0;
      waw_conflict  <= '0;
      viol_addr     <= '0;
      viol_exp      <= '0;
      viol_got      <= '0;
      viol_core     <= '0;
      foreach (log_buf[i])      log_buf[i]      <= '0;
      foreach (shadow_mem[i])   shadow_mem[i]   <= '0;
      foreach (shadow_valid[i]) shadow_valid[i] <= '0;
    end else begin

      // [C2] WAW detect simultaneous write REQUESTS to the same address
      for (int a = 0; a < NUM_CORES; a++) begin
        for (int b = a + 1; b < NUM_CORES; b++) begin
          if (req_valid[a] && req_we[a] &&
              req_valid[b] && req_we[b] &&
              req_addr[a][5:2] == req_addr[b][5:2]) begin
            waw_conflict <= 1'b1;
          end
        end
      end

      // [C1] RAW + log process each completed (granted) operation
      for (int c = 0; c < NUM_CORES; c++) begin
        if (obs_valid[c]) begin
          automatic logic [3:0] widx = obs_addr[c][5:2];

          // Log the operation
          log_buf[log_ptr] <= '{
            core_id  : c[3:0],
            addr     : obs_addr[c],
            data     : obs_data[c],
            is_write : obs_we[c],
            valid    : 1'b1
          };
          log_ptr <= log_ptr + 1;

          if (obs_we[c]) begin
            // Update shadow with committed write value
            shadow_mem[widx]   <= obs_data[c];
            shadow_valid[widx] <= 1'b1;
          end else begin
            // RAW: read data must match shadow (only if shadow has been written)
            if (shadow_valid[widx] && obs_data[c] !== shadow_mem[widx]) begin
              raw_violation <= 1'b1;
              viol_addr     <= obs_addr[c];
              viol_exp      <= shadow_mem[widx];
              viol_got      <= obs_data[c];
              viol_core     <= c[3:0];
            end
          end
        end
      end

    end
  end

endmodule : mem_consistency_checker

