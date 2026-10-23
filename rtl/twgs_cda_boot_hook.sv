// Experimental interception of the observed no-parameter DeskBootInit call.
// Disabled unless iigs explicitly enables TWGS_CDA_INSTALL. This recognizes
// an accepted native ToolLocator JML/X=0105 after TWGS boot handoff; it does
// not assert Desk Manager readiness or reproduce the original card's GAL.
// It never edits a CPU register, instruction, stack or return frame.
module twgs_cda_boot_hook #(
    parameter bit ENABLED = 1'b0,
    parameter integer WINDOW_CYCLES = 65536
) (
    input wire clk,
    input wire reset,
    input wire present,
    input wire boot_armed,
    input wire cpu_cycle, // CPU RDY_OUT = EN: an actually enabled bus cycle
    input wire native_fetch_accepted,
    input wire toolbox_fetch_accepted, // accepted E=M=X=0 opcode fetch
    input wire [15:0] cpu_x,
    input wire [23:0] cpu_addr,
    input wire [7:0] cpu_din,
    input wire cpu_write,
    input wire cpu_vpa,
    input wire cpu_vda,
    input wire cpu_vpb,
    output wire nmi_n,
    output wire vector_armed,
    output reg [1:0] state,
    output reg acknowledged,
    output reg timed_out
);
    localparam [1:0] IDLE = 2'd0, WAIT_TOOL = 2'd1,
                     VECTOR = 2'd2, DONE = 2'd3;
    localparam integer WIN_W = WINDOW_CYCLES > 1 ? $clog2(WINDOW_CYCLES) : 1;
    reg [WIN_W-1:0] window_count;
    reg [6:0] pulse_remaining;
    reg [7:0] last_fetch_bank;

    wire fetch_bus = cpu_cycle && !cpu_write && cpu_vpa && cpu_vda && cpu_vpb;
    wire handoff = cpu_cycle && !cpu_write && !cpu_vpa && cpu_vda &&
                   cpu_vpb && !boot_armed && cpu_addr == 24'h00FFFC &&
                   last_fetch_bank == 8'hBC;
    // Only the observed dispatch1 entry. Dispatch2 ($E10004) has a distinct
    // dual-return ABI and is deliberately outside this first experiment.
    wire tool_entry = toolbox_fetch_accepted && cpu_din == 8'h5C &&
                      cpu_x == 16'h0105 && cpu_addr == 24'hE10000;

    assign nmi_n = !ENABLED || !present || pulse_remaining == 7'd0;
    assign vector_armed = ENABLED && present && state == VECTOR;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            acknowledged <= 1'b0;
            timed_out <= 1'b0;
            window_count <= 0;
            pulse_remaining <= 0;
            last_fetch_bank <= 0;
        end else if (!ENABLED || !present) begin
            // Card removal cancels this attempt and cannot rearm it until
            // reset. A compile-time disabled instance never pulses NMI.
            state <= DONE;
            pulse_remaining <= 0;
        end else begin
            if (fetch_bus)
                last_fetch_bank <= cpu_addr[23:16];
            if (pulse_remaining != 0)
                pulse_remaining <= pulse_remaining - 7'd1;
            case (state)
                IDLE: if (handoff)
                    state <= WAIT_TOOL;
                WAIT_TOOL: if (tool_entry) begin
                    state <= VECTOR;
                    pulse_remaining <= 7'd127;
                    window_count <= 0;
                end
                VECTOR: begin
                    if (native_fetch_accepted && cpu_addr == 24'hBCFA2F) begin
                        acknowledged <= 1'b1;
                        state <= DONE;
                    end else if (cpu_cycle) begin
                        // Count enabled CPU cycles, not master clocks: RDY/CE
                        // stalls cannot expire the overlay between the vector
                        // pair or the four JML bytes. A CPU stalled forever
                        // cannot make progress or receive another attempt.
                        if (window_count == WINDOW_CYCLES - 1) begin
                            timed_out <= 1'b1;
                            state <= DONE;
                        end else
                            window_count <= window_count + 1'b1;
                    end
                end
                default: ; // one attempt per reset; no arbitrary timed retry
            endcase
        end
    end
endmodule
