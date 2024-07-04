`timescale 1ns / 1ps
// This module attempts to generate the upper address capture flag.
//
// MEMCLK_PHASE MUST BE HIGH IN PHASE 1/2
// MOST LIKELY YOU WANT TO REMAP 0/1/2/3 to 0/1/3/2 AND JUST USE TOP BIT
//
// Note that the delays in the other channels get handled by
// chaining up the upper addresses. If we switch back to a 2-clock
// delay, this handles 1 of the clocks, and if we delay running
// by 1 additional clock for each, that means the upper addresses
// just have a 3-clock multicycle period rather than a 4-clock 
// multicycle period, which is fine.
//
// This means that the upper 8 bits only take half a slice
// and the clock enable just eats the upper half control set.
// Essentially the entire address logic should fit in a slice
//
// The timer pattern here is to generate a 5/6/5 pattern
// => in 16 clocks we capture 12 addresses since 16*6 = 12*8
module uram_event_timer(
        input memclk_i,
        input memclk_phase_i,
        input running_i,
        output start_o,
        output capture_o
    );
    // so this takes a grand total of 3 LUTs and 3 FFs    
    wire delay_done;
    reg phase_toggle = 0;    
    reg running_rereg = 0;
    reg pulse_in = 0;
    
    // we swap between 3/4 using phase_toggle
    // phase_toggle gets flipped by pulse_in because it allows the shift register to clear past
    // itself.
    // so phase_toggle = 1 means 3, phase_toggle = 0 means 4
    // therefore A0=phase_toggle, A1=phase_toggle, A2=~phase_toggle.
    // The *first* delay doesn't matter - it gets aligned to the capture
    // by delaying running properly. After that we want 6/5/6/5/etc.
    // clk  running_i   pulse_in    phase_toggle    A   SR     delay_done  count    action          lo_addr up_addr_in  up_addr
    // 0    0           0           0               3   00000  0           X                        0       0           0
    // 1    1           0           0               3   00000  0           X                        0       0           0

    // 2    1           1           0               3   00000  0           0        increment       0       0           0
    // 3    1           0           0               3   00001  0           1        no increment    1       0           0   0
    // 4    1           0           0               3   00010  0           2        increment       1       4           0   1
    // 5    1           0           0               3   00100  0           3        increment       2       4           0   2
    
    // 6    1           0           0               3   01000  1           4        increment       3       4           0   3
    // 7    1           1           0               3   10000  0           0        no increment    0       4           0   0
    // 8    1           0           1               4   00001  0           1        increment       0       8           4   1
    // 9    1           0           1               4   00010  0           2        increment       1       8           4   2
    
    // 10   1           0           1               4   00100  0           3        increment       2       8           4   3
    // 11   1           0           1               4   01000  0           4        no increment    3       8           4   0
    // 12   1           0           1               4   10000  1           5        increment       3       8           4   1
    // 13   1           1           1               4   00000  0           0        increment       0       12          8   2
    
    // 14   1           0           0               3   00001  0           1        increment       1       12          8   3
    // 15   1           0           0               3   00010  0           2        no increment    2       12          8   0
    // 16   1           0           0               3   00100  0           3        increment       2       12          8   1
    // 17   1           0           0               3   01000  1           4        increment       3       12          8   2
    //
    // 18   1           1           0               3   10000  0           0        increment       0       16          12  3         
    //    
    // So this logic works if we have a counter-encoded phase.
    // With a one-hot encoded phase, we can ALSO do it with one select: this time we *avoid* toggling
    // the only time it happens (phase[3]).
    SRL16E u_delay(.D(pulse_in),
                   .CE(1'b1),
                   .CLK(memclk_i),
                   .A0(~phase_toggle),
                   .A1(~phase_toggle),
                   .A2(phase_toggle),
                   .A3(1'b0),
                   .Q(delay_done));
    
    // this *might* have too high a fanout with running:
    // however, we can actually avoid that by generating a local
    // running which is only captured at a certain memclk phase
    // and which is launched earlier. We'll see.
    // Probably will end up doing this, because the addresses
    // need to be delayed as well.    
    always @(posedge memclk_i) begin
        if (!running_i) phase_toggle <= 0;
        else if (pulse_in && memclk_phase_i) phase_toggle <= ~phase_toggle;
        
        running_rereg <= running_i;
        pulse_in <= running_i && (!running_rereg || delay_done);
    end
    
    assign capture_o = pulse_in;
    assign start_o = (running_i && !running_rereg);
endmodule
