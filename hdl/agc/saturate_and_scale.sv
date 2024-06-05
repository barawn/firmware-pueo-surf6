`timescale 1ns / 1ps
// form the 5-bit saturated and scaled output, and also
// output the SYMMETRIC "greater than" and "less than"
// flags.
//
// The LSB parameter basically sets an overall rough
// scaling. We scale to max/min value = +/-3.875 sigma
// (which is equivalent to 0.258 on Xie's plots).
// This means LSB=0.25 sigma, so if we put that at LSB=4 (16),
// it means our base input has sigma=64. Overall this doesn't
// really matter though because even if it's smaller it'll just
// scale up.
//
// The 'greater than' and 'less than' flags effectively
// calculate > 1.875*sigma and < -1.875*sigma.
//
// The AGC block then counts GT/LT counts, takes the
// sum and difference, and uses the sum to gain-correct and
// the difference to DC balance and symmetrize.
//
// LSB *cannot* be zero. We need one bit to round.
//
// Outputs are in OFFSET BINARY to feed properly into the beams and L1 storage.
module saturate_and_scale #(parameter LSB=4)(
        input clk_i,
        input [47:0] in_i,
        input patternmatch_i,
        input patternbmatch_i,
        output [4:0] out_o,
        output [3:0] abs_o,
        output gt_o,
        output lt_o
    );
    
    // Rounding requires the extra bit.
    // Basically we add (!out_o[0] && in_i[LSB-1]).
    // This is a convergent rounding (round-to-even) scheme.
    // Convergent rounding is both bias free and has no saturation
    // considerations.
       
    wire in_bounds = (patternmatch_i || patternbmatch_i);
    wire [4:0] base_output = in_i[LSB +: 5];
    reg [4:0] rounded_output = {5{1'b0}};    

    // absolute value, for the RMS computation.
    // Can be computed easier here. Not exactly an abs b/c of symmetric rep.
    reg [3:0] abs = {4{1'b0}};

    reg gt_reg = 0;
    reg lt_reg = 0;
    
    always @(posedge clk_i) begin
        // rounded_output[4] is the inverted sign bit. It ALWAYS follows
        // the sign of the output, and has no dependencies.
        // It is inverted because we're in offset binary representation.
        rounded_output[4] <= ~in_i[47];
        
        // The outputs here go to the beamformer so they have
        // large fanout. We therefore branch gt/lt regs from
        // the AGC DSP itself.
        if (!in_bounds) begin
            rounded_output[3:0] <= {4{in_i[47]}};
            // If we're overflowing, we set one of these two
            // no matter what.
            gt_reg <= !in_i[47];
            lt_reg <= in_i[47];
            // if out of bounds this is always 15
            abs <= 4'd15;
        end else begin
            // Because we're in bounds, base_output[4] is actually
            // a copy of in_i[47]. We already depend on in_i[47]
            // so drop the dependence on base_output[4].
            gt_reg <= !in_i[47] && base_output[3];
            lt_reg <= in_i[47] && !base_output[3];
            // OK, here's our dumbass trick. Look at the way rounding works:
            // xxxx00 => xxxx0 (don't need to round)
            // xxxx01 => xxxx1 (round up)
            // xxxx10 => xxxx1 (don't need to round)
            // xxxx11 => xxxx1 (round down)
            // We never carry. This is just a rederive of the bottom bit.
            rounded_output[3:1] <= base_output[3:1];
            // sadly this is going to eat up an entire LUT b/c
            // it now requires 5 inputs (in_i[LSB], in_i[LSB-1], patdet/patdetb/in_i[47])
            // oh well. Technically convergent rounding could use ANY
            // set bit, but whatever. Let's do it by the book.            
            rounded_output[0] <= in_i[LSB-1] | base_output[0];
            
            // abs needs to flip bits and add 1 if negative.
            // NO, IDIOT
            // This is now the SYMMETRIC REPRESENTATION, which means the abs
            // is JUST A CONDITIONAL BIT FLIP
            // Consider 3 bit signed:
            // -4 => 3  3 => 3
            // -3 => 2  2 => 2
            // -2 => 1  1 => 1
            // -1 => 0  0 => 0
            // this is just "flip the bottom bits if negative."
            if (in_i[47])
                abs <= ~{base_output[3:1],(in_i[LSB-1] | base_output[0])};
            else
                abs <= { base_output[3:1], in_i[LSB-1] | base_output[0] };
//            if (in_i[47]) begin
//                abs <= {~base_output[3:1],~(in_i[LSB-1]|base_output[0])} + 1;
//            end else begin
//                abs <= {base_output[3:1],in_i[LSB-1]|base_output[0]};
//            end
        end
    end
    assign abs_o = abs;
    assign out_o = rounded_output;
    assign gt_o = gt_reg;
    assign lt_o = lt_reg;    
endmodule
