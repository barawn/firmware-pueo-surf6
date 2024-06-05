`timescale 1ns / 1ps
// takes in 8 channels worth of gt/lts and accumulates them
// NBITS needs to be log2(nsamples)+1 - nsamples, NOT nclocks
module probit_accumulator #(parameter NBITS=21,
                            parameter CLKTYPE="NONE")(
        input clk_i,
        input ce_i,
        input rst_i,
        input [7:0] gt_i,
        input [7:0] lt_i,
        output [NBITS-1:0] gt_sum_o,
        output [NBITS-1:0] lt_sum_o
    );
    
    // we first pop gt/lt through a 3:2 and 5:3 compressor before accumulating them
    wire sum32_gt, carry32_gt;
    wire sum53_gt, carry53_gt, ccarry53_gt;
    // NOTE NOTE NOTE
    // these DO NOT USE the ce/reset bits!
    // They are providing a *constant stream* of inputs to the
    // accumulator (2-bit and 3-bit) to be added.
    // ce/reset are for the ACCUMULATOR: it needs to count
    // EXACTLY over the required period!!
    // If you use the ce/reset bits here, it screws up the
    // period counting!
    fast_csa32_adder #(.NBITS(1)) u_gt32(.CLK(clk_i),.CE(1'b1),.RST(1'b0),
                                          .A(gt_i[0]),.B(gt_i[1]),.C(gt_i[2]),
                                          .SUM(sum32_gt),.CARRY(carry32_gt));
    fast_csa53_adder #(.NBITS(1)) u_gt53(.CLK(clk_i),.CE(1'b1),.RST(1'b0),
                                         .A(gt_i[3]),.B(gt_i[4]),.C(gt_i[5]),
                                         .D(gt_i[6]),.E(gt_i[7]),
                                         .SUM(sum53_gt),.CARRY(carry53_gt),
                                         .CCARRY(ccarry53_gt));                                          

    wire sum32_lt, carry32_lt;
    wire sum53_lt, carry53_lt, ccarry53_lt;
    fast_csa32_adder #(.NBITS(1)) u_lt32(.CLK(clk_i),.CE(1'b1),.RST(1'b0),
                                          .A(lt_i[0]),.B(lt_i[1]),.C(lt_i[2]),
                                          .SUM(sum32_lt),.CARRY(carry32_lt));
    fast_csa53_adder #(.NBITS(1)) u_lt53(.CLK(clk_i),.CE(1'b1),.RST(1'b0),
                                         .A(lt_i[3]),.B(lt_i[4]),.C(lt_i[5]),
                                         .D(lt_i[6]),.E(lt_i[7]),
                                         .SUM(sum53_lt),.CARRY(carry53_lt),
                                         .CCARRY(ccarry53_lt));                                          
    
    wire [2:0] ternary_in0_gt = { 1'b0, carry32_gt , sum32_gt };
    wire [2:0] ternary_in1_gt = { ccarry53_gt, carry53_gt, sum53_gt };

    wire [2:0] ternary_in0_lt = { 1'b0, carry32_lt , sum32_lt };
    wire [2:0] ternary_in1_lt = { ccarry53_lt, carry53_lt, sum53_lt };
    
    wire [NBITS-1:0] accum_gt = gt_sum_o;
    wire [NBITS-1:0] accum_lt = lt_sum_o;   
    // do 4 bits of a ternary adder
    wire [3:0] gt_sum;
    wire [3:0] lt_sum;
    wire [2:0] gt_any2;
    wire [3:0] lt_any2;
    // these are here because we don't *actually* need to feed them into the
    // carry chain, we can use the accumulator instead.
    wire gt_any2_tmp2;
    wire lt_any2_tmp2;
	LUT6_2 #(.INIT(64'h96969696e8e8e8e8))  u_gt0(.I0(ternary_in0_gt[0]),
	                                             .I1(ternary_in1_gt[0]),
	                                             .I2(accum_gt[0]),
	                                             .I5(1'b1),
												 .O6(gt_sum[0]),.O5(gt_any2[0]));
	LUT6_2 #(.INIT(64'h96969696e8e8e8e8))  u_lt0(.I0(ternary_in0_lt[0]),
	                                             .I1(ternary_in1_lt[0]),
	                                             .I2(accum_lt[0]),
	                                             .I5(1'b1),
												 .O6(lt_sum[0]),.O5(lt_any2[0]));


    LUT6_2 #(.INIT(64'h69966996e8e8e8e8)) u_gt1(.I0(ternary_in0_gt[1]),
                                                 .I1(ternary_in1_gt[1]),
                                                 .I2(accum_gt[1]),
                                                 .I3(gt_any2[0]),
                                                 .I5(1'b1),
                                                 .O6(gt_sum[1]),.O5(gt_any2[1]));
    LUT6_2 #(.INIT(64'h69966996e8e8e8e8))  u_lt1(.I0(ternary_in0_lt[1]),
                                                 .I1(ternary_in1_lt[1]),
                                                 .I2(accum_lt[1]),
                                                 .I3(lt_any2[0]),
                                                 .I5(1'b1),
                                                 .O6(lt_sum[1]),.O5(lt_any2[1]));

    LUT6_2 #(.INIT(64'h69966996e8e8e8e8)) u_gt2(.I0(ternary_in0_gt[2]),
                                                 .I1(ternary_in1_gt[2]),
                                                 .I2(accum_gt[2]),
                                                 .I3(gt_any2[1]),
                                                 .I5(1'b1),
                                                 .O6(gt_sum[2]),.O5(gt_any2_tmp2));
    LUT6_2 #(.INIT(64'h69966996e8e8e8e8))  u_lt2(.I0(ternary_in0_lt[2]),
                                                 .I1(ternary_in1_lt[2]),
                                                 .I2(accum_lt[2]),
                                                 .I3(lt_any2[1]),
                                                 .I5(1'b1),
                                                 .O6(lt_sum[2]),.O5(lt_any2_tmp2));


    // ok, this last ternary adder is now simple, so it doesn't even need a LUT
    assign gt_sum[3] = accum_gt[3] ^ gt_any2_tmp2;
    assign lt_sum[3] = accum_lt[3] ^ lt_any2_tmp2;
    // and this is *fake*, it's just here to make the logic look better
    // this is because our last bit is actually just a straight add,
    // so either of the two products can go into the carry chain to form the full-adder and.
    assign gt_any2[2] = accum_gt[3];
    assign lt_any2[2] = accum_lt[3];
    
    wire [3:0] gt_carry_di = { gt_any2[2], gt_any2[1], gt_any2[0], 1'b0 };
    wire [3:0] gt_carry_s =  { gt_sum[3], gt_sum[2], gt_sum[1], gt_sum[0] };
    wire [3:0] gt_carry_co;
    wire [3:0] gt_carry_o;
    CARRY4 u_gt_carry4(.DI(gt_carry_di),
                       .S(gt_carry_s),
                       .O(gt_carry_o),
                       .CO(gt_carry_co),
                       .CYINIT(1'b0));
    wire [3:0] lt_carry_di = { lt_any2[2], lt_any2[1], lt_any2[0], 1'b0 };
    wire [3:0] lt_carry_s =  { lt_sum[3], lt_sum[2], lt_sum[1], lt_sum[0] };
    wire [3:0] lt_carry_co;
    wire [3:0] lt_carry_o;
    CARRY4 u_lt_carry4(.DI(lt_carry_di),
                       .S(lt_carry_s),
                       .O(lt_carry_o),
                       .CO(lt_carry_co),
                       .CYINIT(1'b0));
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [3:0] gt_bot_register = {4{1'b0}};
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [3:0] lt_bot_register = {4{1'b0}};                       
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [NBITS-4-1:0] gt_top_register = {(NBITS-4){1'b0}};
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg [NBITS-4-1:0] lt_top_register = {(NBITS-4){1'b0}};
    always @(posedge clk_i) begin
        if (rst_i) begin
            gt_top_register <= {(NBITS-4){1'b0}};
            gt_bot_register <= {4{1'b0}};
            
            lt_top_register <= {(NBITS-4){1'b0}};
            lt_bot_register <= {4{1'b0}};
        end else if (ce_i) begin
            gt_top_register <= gt_top_register + gt_carry_co[3];
            gt_bot_register <= gt_carry_o;
            
            lt_top_register <= lt_top_register + lt_carry_co[3];
            lt_bot_register <= lt_carry_o;
        end
    end
    assign gt_sum_o = { gt_top_register, gt_bot_register };
    assign lt_sum_o = { lt_top_register, lt_bot_register };
endmodule
