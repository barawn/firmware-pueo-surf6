`timescale 1ns / 1ps
// Handle generating the read address for URAM read.
// The reason this exists is because we're running at 500M
// so it makes sense to use a DSP, and in fact we can
// use a DSP configured in TWO24 mode to handle both
// the address generation and the count termination.
`include "dsp_macros.vh"
module uram_read_counter #(parameter COUNT_MAX = 171,
                           parameter ADDR_BITS = 14)(
        input clk_i,
        input [ADDR_BITS-1:0] start_addr_i,
        input run_i,
        output addr_valid_o,
        output [ADDR_BITS-1:0] addr_o,
        output complete_o
    );
    
    // Both counters get configured as up accumulators adding 1,
    // but the top counter initially loads start_addr_i and the
    // bottom counter loads (16777216 - COUNT_MAX - 2).
    // e.g. 16,777,043.
    // This lets us avoid using the pattern detector and just use
    // the carry output.
    // the "-1" here comes b/c we want to roll over on the last one
    // e.g. if COUNT_MAX is 4 we start at 16,777,213
    // 16,777,213
    // 16,777,214
    // 16,777,215
    // 16,777,216 -> CARRYOUT is set
    localparam [23:0] COUNTER_START = (1<<24) - (COUNT_MAX - 1);

    wire [47:0] dsp_AB;
    wire [47:0] dsp_C;
    wire [29:0] dsp_A = `DSP_AB_A( dsp_AB );
    wire [17:0] dsp_B = `DSP_AB_B( dsp_AB );
    
    assign dsp_AB[0     +: 24] = 24'd1;
    assign dsp_AB[24    +: 24] = 24'd1;
    
    assign dsp_C[0 +: 24] = COUNTER_START;
    assign dsp_C[24 +: 24] = { {(24-ADDR_BITS){1'b0}}, start_addr_i };
    
    wire [3:0] dsp_ALUMODE = `ALUMODE_SUM_ZXYCIN;
    // seriously need to add the W opmodes
    wire [6:0] dsp_OPMODE = { 2'b00, `Z_OPMODE_P, `Y_OPMODE_C, `X_OPMODE_AB };
    // inmode doesn't matter
    wire [4:0] dsp_INMODE = {5{1'b0}};
    // zero
    wire [2:0] dsp_CARRYINSEL = {3{1'b0}};

    reg running = 0;
    reg valid = 0;
    wire done;
    always @(posedge clk_i) begin
        if (done) running <= 0;
        else if (run_i) running <= 1;
        
        if (done) valid <= 1'b0;
        else valid <= running;
    end        
    // the sequencing is a little tricky here
    // basically run_i loads the C register for 1 clock
    // then running enables the P register and the AB registers.
    //
    // we can start up again right afterwards, I think, but this needs to be
    // modified with the event buffer, I think, since we need to line up our
    // readouts at a certain memory phase
    //
    // Imagine if COUNT_MAX was 4
    //
    // clk  run_i   running     valid   AB      C       Plow    Phigh       rstC    rstP    rstAB   complete
    // 0    0       0           0       0       0       0       0           1       1       1       0
    // 1    1       0           0       0       0       0       0           0       1       1       0
    // 2    0       1           0       0       START   0       0           1       0       0       0
    // 3    0       1           1       1       0       START   16777213    1       0       0       0
    // 4    0       1           1       1       0       START+1 16777214    1       0       0       0
    // 5    0       1           1       1       0       START+2 16777215    1       0       0       0
    // 6    0       1           1       1       0       START+3 0           1       0       0       1
    // 7    1       0           0       1       0       START+4 1           0       1       1       0
    // 8    0       1           0       0       START   0       0           1       0       0       0
    // 9    0       1           1       1       0       START   16777213    1       0       0       0
    //
    // so clearly RSTC is !run_i and RSTP/RSTA/RSTB are !running
    wire dsp_RSTC = !run_i;
    wire dsp_RSTABP = !running;
    wire [47:0] dsp_P;
    wire [3:0] dsp_CARRYOUT;
    assign done = dsp_CARRYOUT[`DUAL_DSP_CARRY0];
    
    
    DSP48E2 #(.USE_SIMD("TWO24"),
              `CONSTANT_MODE_ATTRS,
              `NO_MULT_ATTRS,
              `DE2_UNUSED_ATTRS,
              .CREG(1),
              .AREG(1),
              .BREG(1),
              .PREG(1),
              .CARRYINREG(0))
              u_counter( .CLK(clk_i),
                         .CEA2(!dsp_RSTABP),
                         .CEB2(!dsp_RSTABP),
                         .CEP(!dsp_RSTABP),
                         .CEC(!dsp_RSTC),
                         .RSTA(dsp_RSTABP),
                         .RSTB(dsp_RSTABP),
                         .RSTP(dsp_RSTABP),
                         .RSTC(dsp_RSTC),
                         .A(dsp_A),
                         .B(dsp_B),
                         .C(dsp_C),
                         .OPMODE(dsp_OPMODE),
                         .INMODE(dsp_INMODE),
                         .ALUMODE(dsp_ALUMODE),
                         .CARRYINSEL(dsp_CARRYINSEL),
                         .CARRYIN(1'b0),
                         `D_UNUSED_PORTS,
                         .P( dsp_P ),
                         .CARRYOUT( dsp_CARRYOUT ) );
              
    assign addr_o = dsp_P[24 +: ADDR_BITS];
    assign addr_valid_o = valid;
    assign complete_o = done;
    
endmodule
