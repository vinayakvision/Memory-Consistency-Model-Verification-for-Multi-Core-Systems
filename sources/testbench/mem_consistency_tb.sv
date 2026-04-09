// =============================================================================
// File        : mem_consistency_tb.sv
// Project     : Memory Consistency Model Verification Multi-Core System
// Author      : Vinayak Venkappa Pujeri (Vision)
// Test Cases:
//   TC1 Core 0 writes, Core 1 reads back              (clean RAW)
//   TC2 Read different address                         (no violation)
//   TC3 WAW: two cores request same address same cycle (waw_conflict)
//   TC4 All 4 cores write unique addresses, read back  (4/4 match)
//   TC5 Read unwritten location                        (no false RAW)
// =============================================================================


module mem_consistency_tb;

  localparam NUM_CORES = 4;

  logic clk  = 0;
  logic rstn = 0;
  always #5 clk = ~clk;

  // DUT signals
  logic [31:0] req_addr  [NUM_CORES];
  logic [31:0] req_wdata [NUM_CORES];
  logic        req_we    [NUM_CORES];
  logic        req_valid [NUM_CORES];
  logic [31:0] rsp_rdata [NUM_CORES];
  logic        rsp_grant [NUM_CORES];

  // Checker outputs
  logic        raw_violation, waw_conflict;
  logic [31:0] viol_addr, viol_exp, viol_got;
  logic [3:0]  viol_core;

  // --- DUTs ---
  shared_mem #(.NUM_CORES(NUM_CORES), .MEM_DEPTH(16)) u_mem (
    .clk(clk), .rstn(rstn),
    .req_addr(req_addr), .req_wdata(req_wdata),
    .req_we(req_we),     .req_valid(req_valid),
    .rsp_rdata(rsp_rdata), .rsp_grant(rsp_grant)
  );

  mem_consistency_checker #(.NUM_CORES(NUM_CORES), .LOG_DEPTH(16)) u_chk (
    .clk(clk), .rstn(rstn),
    // Completed-operation observation (address stable at grant cycle)
    .obs_addr(req_addr),   .obs_data(rsp_rdata),
    .obs_we(req_we),       .obs_valid(rsp_grant),
    // Raw request bus WAW detected here before arbitration
    .req_addr(req_addr),   .req_we(req_we),  .req_valid(req_valid),
    // Outputs
    .raw_violation(raw_violation), .waw_conflict(waw_conflict),
    .viol_addr(viol_addr), .viol_exp(viol_exp),
    .viol_got(viol_got),   .viol_core(viol_core)
  );

  // --- Scoreboard ---
  int pass_cnt = 0, fail_cnt = 0;

  task automatic chk(input string name, input logic got, input logic exp);
    if (got === exp) begin $display("  [PASS] %s", name); pass_cnt++; end
    else             begin $display("  [FAIL] %s  got=%0b exp=%0b", name, got, exp); fail_cnt++; end
  endtask

  task automatic chk32(input string name, input logic [31:0] got, exp);
    if (got === exp) begin $display("  [PASS] %s  got=0x%08h", name, got); pass_cnt++; end
    else             begin $display("  [FAIL] %s  got=0x%08h exp=0x%08h", name, got, exp); fail_cnt++; end
  endtask

  task automatic idle_all();
    foreach (req_valid[c]) begin req_valid[c]=0; req_we[c]=0; req_addr[c]=0; req_wdata[c]=0; end
  endtask

  // Drive one core request; wait for grant; return read data
  task automatic do_op(input int core, input logic [31:0] addr, wdata,
                       input logic we, output logic [31:0] rdata_out);
    @(posedge clk);
    req_addr[core]  <= addr;
    req_wdata[core] <= wdata;
    req_we[core]    <= we;
    req_valid[core] <= 1;
    @(posedge clk);
    while (!rsp_grant[core]) @(posedge clk);
    rdata_out = rsp_rdata[core];
    @(posedge clk);
    req_valid[core] <= 0;
    @(posedge clk);
  endtask

  initial begin
    idle_all();
    $dumpfile("mem_consistency.vcd");
    $dumpvars(0, mem_consistency_tb);
  end

  initial begin
    logic [31:0] rd;

    rstn = 0; repeat(4) @(posedge clk); rstn = 1;
    repeat(2) @(posedge clk);
    $display("\n[%0t ns] Reset released", $time/1000);


    // TC1 Core0 write Core1 read-back

    $display("\n TC1: Core0 Write, Core1 Read-back ");
    do_op(0, 32'h00, 32'hDEAD_BEEF, 1, rd);
    do_op(1, 32'h00, 32'h0,         0, rd);
    chk32("TC1 read-back",       rd,            32'hDEAD_BEEF);
    chk  ("TC1 no RAW violation", raw_violation, 1'b0);


    // TC2 Different addresses, no violation

    $display("\n TC2: Read Different Address, No Violation ");
    do_op(2, 32'h04, 32'hCAFE_BABE, 1, rd);
    do_op(3, 32'h08, 32'h0,         0, rd);
    chk("TC2 no RAW violation", raw_violation, 1'b0);
    chk("TC2 no WAW conflict",  waw_conflict,  1'b0);


    // TC3 WAW: Core0 & Core1 request same address same cycle
    //        Both req_valid & req_we high simultaneously ? checker flags it

    $display("\n TC3: WAW, Two Cores Write Same Address ");
    @(posedge clk);
    req_addr[0]  <= 32'h0C; req_wdata[0] <= 32'hAAAA_AAAA;
    req_we[0]    <= 1;      req_valid[0] <= 1;
    req_addr[1]  <= 32'h0C; req_wdata[1] <= 32'hBBBB_BBBB;
    req_we[1]    <= 1;      req_valid[1] <= 1;
    // Hold for one full clock so checker samples the simultaneous requests
    @(posedge clk);
    // Now deassert arbiter will serialise the grants over next cycles
    req_valid[0] <= 0; req_valid[1] <= 0;
    repeat(4) @(posedge clk);
    chk("TC3 WAW conflict detected", waw_conflict, 1'b1);


    // TC4 4-core write + read-back

    $display("\n TC4: 4-Core Write + Read-back ");
    do_op(0, 32'h10, 32'h1111_1111, 1, rd);
    do_op(1, 32'h14, 32'h2222_2222, 1, rd);
    do_op(2, 32'h18, 32'h3333_3333, 1, rd);
    do_op(3, 32'h1C, 32'h4444_4444, 1, rd);
    do_op(0, 32'h10, 0, 0, rd); chk32("TC4 Core0", rd, 32'h1111_1111);
    do_op(1, 32'h14, 0, 0, rd); chk32("TC4 Core1", rd, 32'h2222_2222);
    do_op(2, 32'h18, 0, 0, rd); chk32("TC4 Core2", rd, 32'h3333_3333);
    do_op(3, 32'h1C, 0, 0, rd); chk32("TC4 Core3", rd, 32'h4444_4444);


    // TC5 Read unwritten location, no false RAW

    $display("\n TC5: Read Unwritten Addr, No False RAW ");
    do_op(2, 32'h3C, 0, 0, rd);
    chk("TC5 no false RAW", raw_violation, 1'b0);

    // Summary
    repeat(4) @(posedge clk);
    
    $display("  SIMULATION COMPLETE  |  PASS: %0d  |  FAIL: %0d", pass_cnt, fail_cnt);

    if (fail_cnt == 0) $display("   ALL TESTS PASSED - DESIGN VERIFIED \n");
    else               $display("   %0d TEST(S) FAILED \n", fail_cnt);
    $stop;
  end

  initial begin #50000; $display("[WATCHDOG] Timeout"); $finish; end

initial begin
        $shm_open("wave.shm");
        $shm_probe("ACTMF");
    end

endmodule : mem_consistency_tb

