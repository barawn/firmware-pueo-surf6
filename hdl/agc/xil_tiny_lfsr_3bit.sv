`timescale 1ns / 1ps
// based on xil_tiny_lfsr type stuff
// uses a larger LFSR tho
// we don't handle all the parameters and such b/c I don't care
module xil_tiny_lfsr_3bit(
        input clk_i,
        input rst_i,
        input start_i,
        output [3:0] out_o
    );
    
    reg [2:0] tail_ff = {3{1'b0}};
    wire [2:0] srl_xor;
    wire [2:0] shift_in;
    
    assign shift_in[2] = (!rst_i) && (start_i || srl_xor[2]);
    assign shift_in[1] = !rst_i && srl_xor[1];
    assign shift_in[0] = !rst_i && srl_xor[0];
    
    // this is a 35-bit LFSR, so 33 registers in the chain
    // and 3 outside (the last tail_ff is delayed by 1 clock)
    // the initial value is x[34:0] = 35'h1, and the input is
    // x[34] ^ x[32]
    wire [3:0] addr = 4'd10;
    wire [2:0] tap;
    
    generate
        genvar i;
        for (i=0;i<3;i=i+1) begin : SL
            // these should merge
            SRL16E u_sr(.D(shift_in[i]),
                        .Q(tap[i]),
                        .CLK(clk_i),
                        .CE(1'b1),
                        .A3(addr[3]),
                        .A2(addr[2]),
                        .A1(addr[1]),
                        .A0(addr[0]));
        end
    endgenerate
    
    // actual feedback logic
    assign srl_xor[2] = tail_ff[1] ^ tap[2];
    assign srl_xor[1] = tail_ff[0] ^ tap[1];
    assign srl_xor[0] = tap[2] ^ tap[0];
    
    always @(posedge clk_i) begin
        tail_ff <= tap;        
    end
    assign out_o = tail_ff;
endmodule
