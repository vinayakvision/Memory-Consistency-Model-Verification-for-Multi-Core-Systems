# Memory Consistency Model Verification — Multi-Core System

**Author:** Vinayak Venkappa Pujeri (Vision)
**Tool:** Cadence Xcelium / irun 15.20
**Cores modelled:** 4 (parametrisable)

---

## Overview

Verifies that a shared memory accessible by 4 independent cores maintains
sequential consistency — every core observes the most recent write to any
address it reads, and same-cycle write conflicts (WAW) are detected and flagged.

---

## Project Structure

```
mem_consistency/
├── rtl/
│   ├── shared_mem.sv              # 4-core shared memory with round-robin arbiter
│   └── mem_consistency_checker.sv # Synthesisable RAW/WAW violation detector
├── tb/
│   └── mem_consistency_tb.sv      # Self-checking testbench (5 test cases)
├── Makefile
└── README.md
```

---

## Design: shared_mem

| Feature | Detail |
|---|---|
| Cores | 4 (NUM_CORES parameter) |
| Depth | 16 × 32-bit words |
| Arbitration | Round-robin; one grant per cycle |
| Access | Simultaneous R/W requests queued; no starvation |

## Design: mem_consistency_checker

Maintains a **shadow memory** (expected values from committed writes) and compares
every read response against it.

| Check | Condition | Output |
|---|---|---|
| **RAW** | Read returns data ≠ last committed write to same addr | `raw_violation` high |
| **WAW** | Two cores granted writes to same address same cycle | `waw_conflict` high |

Both outputs are level signals (sticky until reset) so the testbench can poll
them after any transaction.

---

## Test Cases

| TC | Scenario | Expected |
|---|---|---|
| TC1 | Core0 writes 0xDEADBEEF → Core1 reads addr 0x00 | Read-back correct, no violation |
| TC2 | Core2 writes addr 0x04, Core3 reads addr 0x08 | No violation on different addresses |
| TC3 | Core0 & Core1 both write addr 0x0C same cycle | `waw_conflict` asserted |
| TC4 | All 4 cores write unique addresses, then read back | 4/4 read-backs match |
| TC5 | Read address never written (shadow_valid=0) | No false RAW flag |

---

## How to Run

```bash
# On Cadence server
make sim

# Manual
irun -access +rwc -timescale 1ns/1ps -sv \
     rtl/shared_mem.sv rtl/mem_consistency_checker.sv tb/mem_consistency_tb.sv

make clean
```
