`timescale 1ns / 1ps
// Capture PL_SYSREF cleanly.
// PL_SYSREF comes in completely aligned with SYSCLK so any delay
// will work. Let's just try straight up and see what it says.
module rfdc_sync(
        input sysclk_i,
        input sysref_i,
        output pl_sysref_o
    );
    
    (* IOB = "TRUE" *)
    reg pl_sysref = 0;
    
    always @(posedge sysclk_i) begin
        pl_sysref <= sysref_i;
    end
        
    assign pl_sysref_o = pl_sysref;
endmodule
