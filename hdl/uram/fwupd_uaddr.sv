`timescale 1ns / 1ps
// fwupd adder
// less complicated once I realized that marking needs to flop banks, duh
module fwupd_uaddr(
        input clk_i,
        input ce_i,
        input [1:0] bank_ce_i,
        input rstb_i,
        output [7:0] uaddr_o
    );
    
    reg [6:0] uaddr_reg = {7{1'b0}};
    reg bank = 0;
    
    always @(posedge clk_i) begin
        if (!rstb_i || (bank && bank_ce_i[1])) bank <= 0;
        else if (!bank && bank_ce_i[0]) bank <= 1;
        
        if (!rstb_i) uaddr_reg <= {7{1'b0}};
        else if (ce_i) uaddr_reg <= uaddr_reg + 1;
    end
    assign uaddr_o = { bank, uaddr_reg };
endmodule
