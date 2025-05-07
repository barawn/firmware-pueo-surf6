`timescale 1ns / 1ps
// rip out portions of the turfio_bit/turfio_cin_parallel_sync from TURF
// bit different since we operate in rxclk domain
module turfio_cin_surf #(parameter INV=1'b0,
                         parameter CLKTYPE="RXCLK",
                         parameter DEBUG = "TRUE"
        )(
        // rxclk
        input rxclk_i,
        // rxclkx2
        input rxclk_x2_i,
        // iserdes reset
        input rst_i,
        // vtc enable
        input en_vtc_i,
        input delay_load_i,
        input delay_rd_i,
        input [1:0] delay_sel_i,
        input [8:0] delay_cntvaluein_i,
        output [8:0] delay_cntvalueout_o,
        // now the iserdes data
        output [3:0] data_o,
        // and this is our "we have seen nonzero data" indicator
        output data_active_o,
        // actual input
        input CIN_P,
        input CIN_N
    );
    
    (* CUSTOM_CC_SRC = CLKTYPE *)
    reg data_active = 0;
    
    // both a source and destination for cross-clock
    (* CUSTOM_CC_SRC = CLKTYPE, CUSTOM_CC_DST = CLKTYPE *)
    reg [8:0] delay_cntvalueout = {9{1'b0}};
    
    // load the IDELAY delay
    wire idelay_load = (delay_load_i && !delay_sel_i[0]);
    // load the ODELAY delay
    wire odelay_load = (delay_load_i && delay_sel_i[0]);
    // IDELAY count value output
    wire [8:0] idelay_cntvalueout;
    // ODELAY count value output
    wire [8:0] odelay_cntvalueout;
    // IDELAY monitor count value output
    wire [8:0] idelaymon_cntvalueout;
    // ODELAY monitor count value output
    wire [8:0] odelaymon_cntvalueout;
    // vector
    wire [8:0] delay_cntvalueout_vec[3:0];
    
    assign delay_cntvalueout_vec[0] = idelay_cntvalueout;
    assign delay_cntvalueout_vec[1] = odelay_cntvalueout;
    assign delay_cntvalueout_vec[2] = idelaymon_cntvalueout;
    assign delay_cntvalueout_vec[3] = odelaymon_cntvalueout;
    
    // non-inverted polarity
    wire cin_norm;
    // inverted polarity
    wire cin_cmpl;
    // correct polarity
    wire cin = (INV == 1'b1) ? cin_cmpl : cin_norm;    
    // monitor (unused)
    wire cin_monitor = (INV == 1'b1) ? cin_norm : cin_cmpl;
    
    // iserdes to oserdes
    wire cin_idelay_to_odelay;
    // final path of cascade
    wire cin_odelay_to_idelay;    
    // idelay to iserdes
    wire cin_to_iserdes;
    
    // monitor iserdes to oserdes
    wire mon_idelay_to_odelay;
    // final path of monitor
    wire mon_odelay_to_idelay;
    
    ibufds_autoinv #(.INV(INV))
        u_cin_ibuf(.I_P(CIN_P),.I_N(CIN_N),.O(cin_norm),.OB(cin_cmpl));
    (* RLOC = "X0Y0", HU_SET="cin0", CUSTOM_CC_DST=CLKTYPE, CUSTOM_CC_SRC=CLKTYPE, IODELAY_GROUP=CLKTYPE *)
    IDELAYE3 #(.DELAY_SRC("IDATAIN"),
               .CASCADE("MASTER"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(0),
               .REFCLK_FREQUENCY(300.00),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_idelay(.CASC_RETURN(cin_odelay_to_idelay),
                        .CASC_IN(),
                        .CASC_OUT(cin_idelay_to_odelay),
                        .CE(1'b0),
                        .CLK(rxclk_i),
                        .INC(1'b0),
                        .LOAD(idelay_load),
                        .CNTVALUEIN(delay_cntvaluein_i),
                        .CNTVALUEOUT(idelay_cntvalueout),
                        .DATAIN(),
                        .IDATAIN(cin),
                        .DATAOUT(cin_to_iserdes),
                        .RST(rst_i),
                        .EN_VTC(en_vtc_i));
    (* CUSTOM_CC_DST = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE, IODELAY_GROUP = CLKTYPE *)
    ODELAYE3 #(.CASCADE("SLAVE_END"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(0),
               .REFCLK_FREQUENCY(300.0),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_odelay( .CASC_RETURN(),
                         .CASC_IN(cin_idelay_to_odelay),
                         .CASC_OUT(),
                         .CE(1'b0),
                         .CLK(rxclk_i),
                         .INC(1'b0),
                         .LOAD(odelay_load),
                         .CNTVALUEIN(delay_cntvaluein_i),
                         .CNTVALUEOUT(odelay_cntvalueout),
                         .ODATAIN(),
                         .DATAOUT(cin_odelay_to_idelay),
                         .RST(rst_i),
                         .EN_VTC(en_vtc_i));
    // now the ISERDES
    (* RLOC = "X0Y0", HU_SET="cin0" *)
    ISERDESE3 #(.DATA_WIDTH(4),
                .FIFO_ENABLE("FALSE"),
                .FIFO_SYNC_MODE("FALSE"),
                .IS_CLK_INVERTED(1'b0),
                .IS_CLK_B_INVERTED(1'b1),
                .IS_RST_INVERTED(1'b0),
                .SIM_DEVICE("ULTRASCALE_PLUS"))
        u_iserdes(.CLK(rxclk_x2_i),
                  .CLK_B(rxclk_x2_i),
                  .CLKDIV(rxclk_i),
                  .FIFO_RD_CLK(1'b0),
                  .FIFO_RD_EN(1'b0),
                  .FIFO_EMPTY(),
                  .D(cin_to_iserdes),
                  .Q(data_o),
                  .RST(rst_i));                            
    // now the monitors
    (* IODELAY_GROUP = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE *)
    IDELAYE3 #(.DELAY_SRC("IDATAIN"),
               .CASCADE("MASTER"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(700.0),
               .REFCLK_FREQUENCY(300.00),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_idelaymon( .CASC_RETURN(mon_odelay_to_idelay),
                         .CASC_IN(),
                         .CASC_OUT(mon_idelay_to_odelay),
                         .CE(1'b0),
                         .CLK(rxclk_i),
                         .INC(1'b0),
                         .LOAD(1'b0),
                         .CNTVALUEIN(9'h000),
                         .CNTVALUEOUT(idelaymon_cntvalueout),
                         .DATAIN(),
                         .IDATAIN(cin_monitor),
                         .DATAOUT(),
                         .RST(rst_i),
                         .EN_VTC(en_vtc_i));
    (* IODELAY_GROUP = CLKTYPE, CUSTOM_CC_SRC = CLKTYPE *)
    ODELAYE3 #(.CASCADE("SLAVE_END"),
               .DELAY_TYPE("VAR_LOAD"),
               .DELAY_VALUE(700.0),
               .REFCLK_FREQUENCY(300.0),
               .DELAY_FORMAT("TIME"),
               .UPDATE_MODE("ASYNC"),
               .SIM_DEVICE("ULTRASCALE_PLUS"))
               u_odelaymon( .CASC_RETURN(),
                         .CASC_IN(mon_idelay_to_odelay),
                         .CASC_OUT(),
                         .CE(1'b0),
                         .CLK(rxclk_i),
                         .INC(1'b0),
                         .LOAD(1'b0),
                         .CNTVALUEIN(9'h000),
                         .CNTVALUEOUT(odelaymon_cntvalueout),
                         .ODATAIN(),
                         .DATAOUT(mon_odelay_to_idelay),
                         .RST(rst_i),
                         .EN_VTC(en_vtc_i));
                         
    always @(posedge rxclk_i) begin
        if (data_o != 4'hF) data_active <= 1;
        if (delay_rd_i) begin
            delay_cntvalueout <= delay_cntvalueout_vec[delay_sel_i];
        end
    end            

    assign delay_cntvalueout_o = delay_cntvalueout;    
    assign data_active_o = data_active;
    generate
        if (DEBUG == "TRUE") begin : ILA
            cin_ila u_ila(.clk(rxclk_i),.probe0(data_o));
        end
    endgenerate

endmodule
