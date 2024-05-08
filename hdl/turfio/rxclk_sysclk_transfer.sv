`timescale 1ns / 1ps
// This is the module that transfers from RXCLK over to SYSCLK.
// It also includes a capture-tracking mechanism.
// Basically, what we need to do is guarantee that we go from
// RXCLK to SYSCLK in exactly one clock cycle - so the way
// we do that is
// 1) create a toggle flop in SYSCLK
// 2) capture in RXCLK
// 3) recapture in SYSCLK
// 4) XOR the toggle flop and the recapture, which should be identical.
//
// Because setup/hold times on FPGA FFs are negligible (more typically
// around 200 ps, regardless of what the datasheet says) this imposes
// an alignment between the two clocks roughly equal to or better than the
// data path delay between the two. That is, the data change has to be *in flight*
// between the launch FF and the target FF, otherwise you won't end up
// with the correct propagation delay.
//
// The flops in the RXCLK and SYSCLK domain are all constrained to be in
// the same slice here, and we change the minimum datapath delay to
// 2 ns, leaving the setup constraint the same.
module rxclk_sysclk_transfer(
        input rxclk_i,
        input [3:0] data_i,
        input sysclk_i,
        output [3:0] data_o,
        output capture_err_o
    );
    
    wire sysclk_toggle;
    wire rxclk_capture;
    wire sysclk_recapt;    
    wire [3:0] rxclk_data;

    // sysclk-side
    (* RLOC = "X0Y0", HU_SET = "syscap0", CUSTOM_SYSCLK_SOURCE = "TRUE" *)
    FD u_sys_tog(.C(sysclk_i),.D(~sysclk_toggle),.Q(sysclk_toggle));
    (* RLOC = "X0Y0", HU_SET = "syscap0", CUSTOM_SYSCLK_TARGET = "TRUE" *)
    FD u_sys_rcp(.C(sysclk_i),.D(rxclk_capture),.Q(sysclk_recapt));
    (* RLOC = "X0Y0", HU_SET = "syscap0", CUSTOM_SYSCLK_TARGET = "TRUE" *)
    FD u_sys_cd0(.C(sysclk_i),.D(rxclk_data[0]),.Q(data_o[0]));
    (* RLOC = "X0Y0", HU_SET = "syscap0", CUSTOM_SYSCLK_TARGET = "TRUE" *)
    FD u_sys_cd1(.C(sysclk_i),.D(rxclk_data[1]),.Q(data_o[1]));
    (* RLOC = "X0Y0", HU_SET = "syscap0", CUSTOM_SYSCLK_TARGET = "TRUE" *)
    FD u_sys_cd2(.C(sysclk_i),.D(rxclk_data[2]),.Q(data_o[2]));
    (* RLOC = "X0Y0", HU_SET = "syscap0", CUSTOM_SYSCLK_TARGET = "TRUE" *)
    FD u_sys_cd3(.C(sysclk_i),.D(rxclk_data[3]),.Q(data_o[3]));
    // rxclk-side
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_SYSCLK_SOURCE = "TRUE", CUSTOM_SYSCLK_TARGET = "TRUE" *)
    FD u_rxc_cap(.C(rxclk_i),.D(sysclk_toggle),.Q(rxclk_capture));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_SYSCLK_SOURCE = "TRUE" *)
    FD u_rxc_cd0(.C(rxclk_i),.D(data_i[0]),.Q(rxclk_data[0]));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_SYSCLK_SOURCE = "TRUE" *)
    FD u_rxc_cd1(.C(rxclk_i),.D(data_i[1]),.Q(rxclk_data[1]));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_SYSCLK_SOURCE = "TRUE" *)
    FD u_rxc_cd2(.C(rxclk_i),.D(data_i[2]),.Q(rxclk_data[2]));
    (* RLOC = "X0Y0", HU_SET = "rxcap0", CUSTOM_SYSCLK_SOURCE = "TRUE" *)
    FD u_rxc_cd3(.C(rxclk_i),.D(data_i[3]),.Q(rxclk_data[3]));
    
    reg sysclk_rxclk_biterr = 0;
    always @(posedge sysclk_i) sysclk_rxclk_biterr <= sysclk_toggle ^ sysclk_recapt;
    
    assign capture_err_o = sysclk_rxclk_biterr;
endmodule
