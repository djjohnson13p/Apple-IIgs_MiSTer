# Experimental CDA boot hook

The hook is disabled by default. `TWGS_CDA_INSTALL` explicitly enables this
local experiment; this is not a production-enable recommendation.

After the existing TWGS boot-chain data-read signature, the hook waits for an
accepted `$E10000` JML with X=`$0105` and E=M=X=0. It issues one ordinary
127-master-clock external NMI pulse. A tight native-vector overlay remains
armed for at most 65536 enabled CPU cycles, ending on an accepted native
fetch at exactly `$BCFA2F` or on expiry. There is no timed retry. Stalls pause
the enabled-cycle window; a fully stalled CPU can miss the pulse. Removing the
card cancels the attempt until reset. `$E10004` is excluded because its
documented dual-return ABI is outside this experiment.

The CPU additions are passive X, accepted native fetch, and accepted Toolbox
width fetch outputs. There is no instruction, interrupt-frame, stack, RTL or
RTI semantic change relative to CPU parent `8cfb6f6`.

`cda_boot_hook_tb.sv` contains original synthetic opcodes and no firmware/owned
ROM input. It runs the real CPU and production hook, with a constructed native
trampoline/frame-splice program. The 20 scenarios are run at CE=1 and CE=14:
ordinary zero-parameter dispatch, ROM1-like content-preserving frame copies,
E10004 rejection, another selector, emulation, missing handoff, captured and
missed-pulse stalls, wrong FA-page acknowledgment, vector/JML-operand stalls,
reset, stalled physical entry, IRQ-discarded entry, card off, non-JML entry,
pre-handoff entry, a constructed missing-tool error return, M8 and X8 rejection.
An instance using default parameters must remain disabled throughout.

The first hooked call and second ordinary call have separate result slots.
Both must retain the caller's `$0105` stack value, cleanup value and final S,
and the function's A/carry result. The synthetic detour saves/restores A/X/Y/P
using ordinary instructions. Code is immutable and separate from bank-zero
RAM, so reset/stack writes cannot alias a different bank's code image.

The controlled kit driver is `core-lab/scripts/run_apple_cda_boot_hook.py`.
The frozen successful preparation is
`core-lab/builds/apple-cda-boot-hook-focused-r8`: 40/40 scenarios, one job,
all C++ at O0, no precompiled headers, 600000000-byte compiler RSS cap,
bounded process execution, hash-bound source/executable/raw logs and terminal
process receipts. The committed bench is an exact copy of that input. New
attempts require fresh output directories and an explicitly reviewed source
pin; existing preparations/attempts must not be overwritten.

This proves only the constructed instruction-level contexts. The missing-tool
model preserves A=`$0911` and carry=1 while still executing the synthetic
detour; an observed request or trampoline fetch does not prove that
DeskBootInit resolved or completed. Actual private dispatcher frame behavior,
real-ROM CDA installation, Desk Manager readiness, original GAL behavior,
full-system execution and hardware safety remain unproved. No full-system or
FPGA build is part of these focused results.
