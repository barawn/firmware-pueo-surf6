`timescale 1ns / 1ps
// mode1 monitor
// the way the automated bringup works is
// 1. TURFIO has RACKCLK off, SURF has DOUT force low, SURF in mode0, TURFIO in invalid SURF
// 2. TURFIO sets output in train
// 3. TURFIO starts RACKCLK
// 4. SURF sees RACKCLK, does clock reset, clock program, clock enable, RXCLK alignment, eye center.
// 5. SURF sets output in train
// 6. TURFIO sees nonzero DOUT and sets invalid SURF -> SURF valid, TURFIO exits train
// 7. TURFIO sends mode1reset
// 8. SURF sees mode1reset, mode0->mode1, exits train
//
// All of this sticks around until RACKCLK goes away again, which kicks us back to mode 0.
// Note that RACKCLK going away is forced by a TURFIO reprogram: SYSCLK is not. So we use RACKCLK.
module surf6_mode1_monitor(
        input wb_clk_i,
        input sysclk_i,
        input rackclk_ok_i,
        input mode1rst_i,
        output mode1_ready_o
    );

    reg mode1_ready = 0;
    
    FDCE #(.INIT(1'b0),.IS_CLR_INVERTED(1'b1))
        u_mode1_ready(.D(1'b1),.CE(mode1rst_i),.CLR(rackclk_ok_i),.C(sysclk_i));

    assign mode1_ready_o = mode1_ready;
endmodule
