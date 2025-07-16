`timescale 1ns / 1ps
// aclk -> ifclk
module trig_cc_stretch #(parameter NBEAMS=2)(
        input aclk,
        input aclk_phase_i,
        input [NBEAMS-1:0] trig_i,
        input ifclk,
        output [NBEAMS-1:0] trig_o        
    );
    
    reg [1:0] aclk_phase_buf = {2{1'b0}};
    wire next_clock_is_ifclk = aclk_phase_buf[1];
    always @(posedge aclk) begin
        aclk_phase_buf <= { aclk_phase_buf[0], aclk_phase_i };
    end
    generate
        genvar i;
        for (i=0;i<NBEAMS;i=i+1) begin : LP
            reg trig_rereg = 0;
            reg trig_stretch = 0;
            (* CUSTOM_MC_SRC_TAG = "TRIG_TO_IFCLK", CUSTOM_MC_MIN = "0.0", CUSTOM_MC_MAX = "3.0" *)
            reg trig_to_ifclk = 0;
            (* CUSTOM_MC_DST_TAG = "TRIG_TO_IFCLK" *)
            reg trig_in_ifclk = 0;
            
            always @(posedge aclk) begin
                trig_rereg <= trig_i[i];
                if (next_clock_is_ifclk) trig_stretch <= trig_rereg;
                else if (trig_rereg) trig_stretch <= 1;
                
                if (next_clock_is_ifclk)
                    trig_to_ifclk <= trig_stretch;
            end
            always @(posedge ifclk) begin
                trig_in_ifclk <= trig_to_ifclk;
            end
            assign trig_o[i] = trig_in_ifclk;
        end
    endgenerate    
endmodule
