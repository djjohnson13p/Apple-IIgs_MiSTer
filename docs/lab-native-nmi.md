# TransWarp GS native NMI diagnostic

Date: 2026-10-23. Upstream baseline:
`9adbba8622f378253765b7d438b6cbcc4d03fc57` (initial public release,
2026-07-12). Local branch: `lab/native-nmi-trampoline`.

**Result: no CPU defect demonstrated; CDA integration remains deferred.**
The production CPU passes all 16 synthetic diagnostic cases below. No RTL
behavior was changed, `TWGS_CDA_INSTALL` remains disabled, and this is not a
working-CDA or hardware-compatibility claim.

A later full-system investigation found a separate phase-dependent NMI edge
delivery defect, reproduced without system ROMs. Its isolated fix and evidence
are in [lab-nmi-delivery.md](lab-nmi-delivery.md). The 16 frame tests below also
pass with that fix; the conclusion about the proposed frame/RTI defect remains.

## Candidate and evidence

[Upstream issue 1](https://github.com/MiSTer-devel/Apple-IIgs_MiSTer/issues/1)
reports TransWarp GS CDA installation failing and proposes incorrect native
NMI frame layout, stack-relative addressing, or PLA width as possible causes.
The initial source still contains the guarded integration path at
`rtl/iigs.sv`, near `twgs_nmi_state`. The observed RTI return to interrupted
code is not, by itself, evidence of one of those CPU defects.

The [firmware disassembly](https://github.com/digarok/TransWarpGS-ROM/blob/main/src/twgs_1.8s/twgs.3.s)
at `LFA2F` copies the original interrupt frame down the stack and places a
three-byte long return *above* the copied frame. The
[WDC W65C816S data sheet](https://www.westerndesigncenter.com/wdc/documentation/w65c816s.pdf),
Table 5-7, distinguishes RTI's status/PC/PBR pops from RTL's three-byte long
return. These operations imply this stack layout after PHB/PHA/PHA, where S
is the current stack pointer:

| Stack offsets | Contents before rewrite | Contents after rewrite |
| --- | --- | --- |
| S+1, S+2 | saved A | saved A |
| S+3, S+4 | saved A | original P, original PCL |
| S+5, S+6 | DBR, original P | original PCH, original PBR |
| S+7, S+8, S+9 | original PCL, PCH, PBR | inserted RTL address |

PLA consumes S+1/S+2. RTI then consumes S+3 through S+6 and therefore
**must resume the original PC**, leaving the inserted long return at the
top of the stack. A later RTL can consume that address and enter the detour.
Changing the CPU to make RTI jump to the inserted RTL address would change
the documented CPU semantics.

## Reproduction and validation

`tests/native_nmi_tb.sv` instantiates the unmodified production CPU and every
production CPU dependency, with a simple 24-bit RAM model. Its program and
handler are synthetic and contain no system ROM or commercial firmware.

Run on Windows with the lab's OSS CAD Suite and w64devkit installed:

```powershell
./tests/run_native_nmi.ps1
# Reuse the built simulator:
./tests/run_native_nmi.ps1 -NoBuild
```

Tool: Verilator 5.053 devel, revision `v5.052-555-g043f7aa51` from the lab
toolchain. The bench compiles the CPU SystemVerilog, executes real opcodes,
delivers an external NMI edge, and checks actual memory/register results.
It does not reimplement a CPU model.

The 16 cases span 8-bit and 16-bit accumulator entry modes, four native
stack pointers (`1ff0`, `0103`, `0004`, `ffff`), and two continuations:

- Retaining the interrupted loop proves RTI preserves P, A, PC, and PBR,
  and leaves the correctly ordered inserted RTL return at S.
- Replacing the interrupted instruction with a synthetic RTL proves that
  RTL reaches the detour at `$BC9100` and restores the original S.

The stack positions include native page crossing and 16-bit stack wrapping.
The bench also checks the four-byte native interrupt frame size and exact
P/PC/PBR byte order. All 16 cases passed. Build diagnostics and test output
are saved in ignored `tests/native_nmi_build.log` and
`tests/native_nmi_results.log`; `+TRACE` on the built executable adds the
first 149 bus cycles.

## Limits and next useful experiment

This isolates the CPU hypothesis. It does not reproduce the complete
TransWarp GS/Apple ROM boot, `_InstallCDA`, IIgs memory mapping, firmware
acknowledgment reads, clock-enable stalls, or the ROM1 crash. It cannot
establish the complete integration root cause. A controlled next experiment
would inspect the actual interrupted firmware context and its later return
instruction in ROM1 and ROM3 simulation, before enabling the existing NMI
path on hardware. There is no justified CPU patch from this result.

## Remote-write boundary

The local `upstream` remote is fetch-only by configuration: its push URL is
disabled and a local `pre-push` hook rejects pushes. No remote fork, PR,
issue, message, author contact, or upstream modification was made.
