`timescale 1ns / 1ps
`include "debug_enable.vh"

// Capture PL_SYSREF cleanly.
// PL_SYSREF comes in completely aligned with SYSCLK so any delay
// will work. Let's just try straight up and see what it says.
module rfdc_sync(
        input sysclk_i,
        input ifclk_i,
        input sysclk_sync_i,
        output [15:0] sysref_phase_o,
        input sysref_i,
        output pl_sysref_o
    );
    parameter DEBUG = "TRUE";
    
    (* IOB = "TRUE" *)
    reg pl_sysref = 0;
    reg pl_sysref_sysclk = 0;
    
    // sysclk is 48 long god I hate this    
    reg [46:0] sysclk_phase_buf = {47{1'b0}};
    (* CUSTOM_CC_SRC = "SYSREFCLK" *)
    reg [15:0] sysref_phase = {16{1'b0}};
    
    always @(posedge ifclk_i) begin
        pl_sysref <= sysref_i;
    end
        
    integer i;
    always @(posedge sysclk_i) begin
        sysclk_phase_buf <= { sysclk_phase_buf[45:0], sysclk_sync_i };
        // phase buf is sync delayed by 1, pl_sysref is also delayed by 1
        for (i=0;i<16;i=i+1) begin
            if (sysclk_phase_buf[3*i]) sysref_phase[i] <= pl_sysref_sysclk;
        end
        pl_sysref_sysclk <= pl_sysref;
    end

    `ifdef USING_DEBUG
    generate
        if (DEBUG == "TRUE") begin : ILA
            rfdc_sync_ila u_ila(.clk(sysclk_i),
                                .probe0( sysclk_phase_buf[0] ),
                                .probe1( sysref_phase ),
                                .probe2( pl_sysref_sysclk ) );
        end
    endgenerate                
    `endif
    
    assign pl_sysref_o = pl_sysref_sysclk;
    assign sysref_phase_o = sysref_phase;
endmodule
