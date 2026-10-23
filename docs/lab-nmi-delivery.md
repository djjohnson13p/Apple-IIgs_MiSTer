# NMI edge delivery diagnostic and local fix

Baseline: `6318f07b81a84a6eb4bb89da274dbe8a6660b47b`, whose production CPU is
unchanged from upstream `9adbba8622f378253765b7d438b6cbcc4d03fc57`.
Date: 2026-10-23. Branch: `lane/nmi-delivery`.

The CPU can lose an external NMI edge at particular instruction phases.
This is separate from the proposed native interrupt frame defect: the original
16 stack/frame diagnostics still pass and do not justify changing RTI semantics.

## Independent expected behavior

[WDC W65C816S datasheet, section 2.21](https://www.westerndesigncenter.com/wdc/documentation/w65c816s.pdf)
specifies that a falling NMIB edge starts an interrupt after the current
instruction completes. Holding NMIB low does not request additional interrupts;
a new falling edge during an interrupt can request another interrupt.

The ROM-free bench executes the production CPU and a synthetic PHA/SBC/BNE/PLA
delay loop. That instruction sequence was observed when the first NMI was lost
in a separate real-ROM system trace. The bench contains no system ROM image or
firmware data. Its handler preserves A, increments a marker, and executes RTI.
Its oracle counts handler markers, actual vector reads, and unexpected BRKs;
it does not implement the CPU or its interrupt decision logic.

## Failure and change

`NMI_ACTIVE` samples `NMI_SYNC` one enabled cycle later. Previously, any enabled
`LAST_CYCLE` cleared `NMI_SYNC`, even if the interrupt decision still saw
`NMI_ACTIVE=0`. On the next non-final cycle, the active stage could return to
zero before an instruction boundary consumed the edge. A pin remaining low
cannot generate another falling edge.

An original-CPU failing trace shows:

| Cycle | Instruction state | SYNC | ACTIVE | Accepted interrupt |
| --- | --- | --- | --- | --- |
| 22 | Last PHA cycle | 1 | 0 | 0 |
| 23 | Following opcode fetch | 0 | 1 | 0 |
| 24 | Last immediate-SBC cycle | 0 | 0 | 0 |

The change clears the pending latch only when `NMI_ACTIVE` is consumed at an
enabled final cycle with `GotInterrupt=0`. It preserves the existing active
pipeline, vector selection, frame layout, instruction execution, and IRQ logic.

## Results

| Check | Original CPU | Candidate |
| --- | ---: | ---: |
| 784 held-edge phase cases | 460 pass, 324 lose the edge | 784 pass |
| 112 second-edge-during-handler cases | Not measured | 112 pass |
| Original native frame/RTI/RTL cases | 16 pass | 16 pass |

The held-edge sweep covers emulation/native mode, one CPU cycle per clock or
per 14 clocks, and all 196 consecutive system-clock phases from loop entry.
Each low pulse lasts 127 system clocks, matching the integration pulse duration.
The nested cases use a shorter first pulse and a second 127-clock pulse during
the first handler. Each must execute two handlers with exactly four vector reads.
The first edge is phase-swept; the second edge is one CE after handler entry,
so these are not a sweep of every possible nested-edge phase.

The portable runner was also executed end to end: all 896 delivery cases pass.
Build tool: Verilator 5.053 devel, GCC 16.2.0, one job with O0 C++ compilation.
The lab receipts retain input hashes, source diffs, executables, build logs,
case results, and the original failed phase trace. The original source inputs
and the separately running full-system baseline were not modified.

Run from this checkout on the lab's Windows toolchain:

```powershell
./tests/run_nmi_delivery.ps1
./tests/run_native_nmi.ps1
```

`-NoBuild` reuses an existing corresponding executable. The delivery runner
stops on the first failure and preserves the command and output in its log.

## Remaining acceptance

This is a CPU simulation fix. The candidate has not yet been run in the complete
real-ROM system, fitted with Quartus, or tested on MiSTer. It does not establish
a working TransWarp CDA installation. The independent system baseline reaches
the NMI trampoline and correctly returns to the interrupted PC, but does not
enter the later CDA installer during the observed interval.

Asynchronous edge capture while CE/RDY prevents all input sampling is unchanged.
Shorter pulses entirely between enabled samples, simultaneous IRQ behavior,
reset interactions, and full CPU conformance are outside this phase test's claim.
No remote push, PR, issue, publication, or author contact occurred.
