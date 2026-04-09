// =============================================================================
// File        : shared_mem.sv
// Project     : Memory Consistency Model Verification Multi-Core System
// Author      : Vinayak Venkappa Pujeri (Vision)
// Description : 16-word shared memory with 4 core ports.
//               Each core can issue one read or write per cycle.
//               Write-invalidate: last write wins on same-cycle conflict.
//               Outputs RDATA per core and a GRANT flag when access completes.
// =============================================================================

module shared_mem #(
  parameter NUM_CORES = 4,
  parameter MEM_DEPTH = 16          // 16 × 32-bit words
)(
  input  logic        clk,
  input  logic        rstn,

  // Per-core request ports
  input  logic [31:0] req_addr  [NUM_CORES],
  input  logic [31:0] req_wdata [NUM_CORES],
  input  logic        req_we    [NUM_CORES],   // 1=write, 0=read
  input  logic        req_valid [NUM_CORES],

  // Per-core response ports
  output logic [31:0] rsp_rdata [NUM_CORES],
  output logic        rsp_grant [NUM_CORES]    // pulse: access completed
);

  logic [31:0] mem [0:MEM_DEPTH-1];


  // Simple round-robin arbiter: one grant per cycle

  logic [$clog2(NUM_CORES)-1:0] rr_ptr;

  always_ff @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      rr_ptr <= '0;
      foreach (mem[i]) mem[i] <= '0;
      foreach (rsp_grant[c]) rsp_grant[c] <= '0;
      foreach (rsp_rdata[c]) rsp_rdata[c] <= '0;
    end else begin
      // Default: clear all grants
      foreach (rsp_grant[c]) rsp_grant[c] <= '0;

      // Scan from rr_ptr for a valid requester
      for (int i = 0; i < NUM_CORES; i++) begin
        automatic int idx = (rr_ptr + i) % NUM_CORES;
        if (req_valid[idx]) begin
          automatic logic [3:0] word_idx = req_addr[idx][5:2]; // word-aligned
          if (req_we[idx]) begin
            mem[word_idx]      <= req_wdata[idx];
            rsp_rdata[idx]     <= req_wdata[idx];
          end else begin
            rsp_rdata[idx]     <= mem[word_idx];
          end
          rsp_grant[idx] <= 1'b1;
          rr_ptr         <= (idx + 1) % NUM_CORES;
          break;                      // one grant per cycle
        end
      end
    end
  end

endmodule : shared_mem

