`timescale 1ns / 1ps
`include "interfaces.vh"

module pueo_surf6 #(parameter IDENT="SURF",
                    parameter [3:0] VER_MAJOR = 4'd0,
                    parameter [3:0] VER_MINOR = 4'd0,
                    parameter [7:0] VER_REV = 4'd1,
                    // this gets autofilled by pre_synthesis.tcl
                    parameter [15:0] FIRMWARE_DATE = {16{1'b0}})
                    (
        // This clock is always running, no matter what.
        // The PS figures out what clocks are available at startup
        // and selects them.
        // This is 375 MHz, and is stepped down to 62.5 MHz internally
        // for registers, and used to run all the trigger logic.
        // It's 375 MHz because we can't afford the jitter from the MMCM.        
        input SYSREFCLK_P,  // revA AG17
        input SYSREFCLK_N,  // revA AH17
        // sysref input, not always running
        input PL_SYSREF_P,  // revA F14 single ended
        input PL_SYSREF_N,  // revA F13 unused
        // input refclk from TURFIO. Not even sure if we'll use it.
        input RXCLK_P,      // L12N AK16
        input RXCLK_N,      // L12P AJ17
        // output refclk to TURFIO. again not sure if we'll use it.
        output TXCLK_P,     // L6P AN18
        output TXCLK_N,     // L6N AP17
        // input commands from TURFIO
        input CIN_P,        // L4N AM16
        input CIN_N,        // L4P AL17
        // output responses/trigger data
        output COUT_P,      // L3P AP16
        output COUT_N,      // L3N AP15
        // data output
        output DOUT_P,      // L5N AN17
        output DOUT_N,      // L5P AM17
        // UART commanding path input. These can be piped through EMIO too.
        input CMD_RX,       // revA D13
        output CMD_TX       // revA C13
        // lots o' stuff still missing
    );

    localparam INV_COUT = 1'b0;
    localparam INV_CIN = 1'b1;
    localparam INV_DOUT = 1'b1;
    localparam INV_RXCLK = 1'b1;
    localparam INV_TXCLK = 1'b0;

    localparam [15:0] FIRMWARE_VERSION = { VER_MAJOR, VER_MINOR, VER_REV };
    localparam [31:0] DATEVERSION = { FIRMWARE_DATE, FIRMWARE_VERSION };
    
    // 375 MHz
    wire sysclk;
    // sigh handle this with a startup reset properly
    wire sysclk_reset = 1'b0;
    // 62.5 MHz or slower if we need it
    wire regclk;
    wire regclk_locked;    
    IBUFDS u_ibuf(.I(SYSREFCLK_P),.IB(SYSREFCLK_N),.O(sysclk));
    sysclk_wiz u_sysclk(.clk_in1(sysclk),.reset(sysclk_reset),
                        .clk_out1(regclk),.locked(regclk_locked));
    // Note that we DO NOT use the PS's AXI4 interface!
    // Why? Because it both costs quite a bit of logic, and we would need
    // to mux in our own interface from the SFC to access the same space.
    //
    // Because *none* of this is speed critical, we instead implement
    // a simple WISHBONE-style register space using the serial port.
    // The PS can read/write our internal registers by setting an EMIO GPIO
    // and writing the same packets to the serial port that the SFC
    // can send.

    // we have a 22-bit address space, so we can be generous

    // WISHBONE BUSSES
    // MASTERS
    `DEFINE_WB_IF( bm_ , 22, 32 );    // serial
    `DEFINE_WB_IF( tc_ , 22, 32 );    // TURF command
    // SLAVES
    

    //
    // Note that the UART path is a secondary commanding path, only for use
    // before the high-speed commanding path works. It is also an *addressed*
    // path because it is *common* between all the SURFs in a crate.

    // The SURFs get their address from USR_ACCESSE2 which is set in the firmware,
    // and nominally gets derived from the UUID in the PS. However in standalone
    // mode or early testing it'll just be whatever it's set to (typically zero).
    
    // only bottom 8 bits of address are used since we don't have >256 SURFs
    wire [31:0] my_full_address;
    wire [7:0] my_address = my_full_address[7:0];
    USR_ACCESSE2 u_addr_store(.DATA(my_address));
    
    // from the PS
    wire emio_rx;
    wire emio_tx;
    wire emio_sel;
    
    wire bm_tx;
    wire bm_rx;

    // Handle the output from the boardman_wrapper    
    assign emio_rx = (emio_sel) ? bm_tx : 1'b0;
    // TX is open drain and inverted UART, w/pull at TURFIO
    // so we drive only when emio_sel is low (no PS access)
    // and bm_tx is high, producing a low.
    // note that RX is standard uart polarity, deal with it
    OBUFT u_tx_obuf(.I(1'b0),.T(emio_sel || ~bm_tx),.O(CMD_TX));
    
    // handle the input to the boardman wrapper
    // the flop here is b/c the EMIO is a transmitter, we're a receiver
    assign bm_rx = (emio_sel) ? emio_tx : CMD_RX;

    // NOTE: FOR INITIAL TESTING ONLY -
    // NEED TO CREATE A SWITCHING BAUD RATE THINGY
    boardman_wrapper #(.USE_ADDRESS("TRUE"),
                       .CLOCK_RATE(62500000),
                       .BAUD_RATE(1000000))
        u_serial_if(.wb_clk_i(regclk),
                    .wb_rst_i(1'b0),
                    `CONNECT_WBM_IFM( wb_ , bm_ ),
                    .burst_size_i(2'b00),
                    .address_i(my_address),
                    .TX(bm_tx),
                    .RX(bm_rx));
    // dumb testing
    assign bm_ack_i = bm_cyc_o && bm_stb_o;
    assign bm_dat_i = (bm_adr_o[2]) ? DATEVERSION : IDENT;        
    
    wire [15:0] emio_gpio_i = {16{1'b0}};
    wire [15:0] emio_gpio_o;
    wire [15:0] emio_gpio_t;
    assign emio_sel = emio_gpio_o[1] && !emio_gpio_t[1];    
    (* KEEP = "TRUE" *)
    wire ps_clk;
    zynq_bd_wrapper u_pswrap( .UART_1_0_rxd( emio_rx ),
                              .UART_1_0_txd( emio_tx ),
                              .GPIO_0_0_tri_i( emio_gpio_i ),
                              .GPIO_0_0_tri_o( emio_gpio_o ),
                              .GPIO_0_0_tri_t( emio_gpio_t ),
                              .pl_clk0_0(ps_clk));

    uart_vio u_vio(.clk(ps_clk),.probe_in0(emio_sel));
    uart_ila u_ila(.clk(regclk),.probe0(bm_tx),.probe1(bm_rx));
                              
    // unused outputs
    obufds_autoinv #(.INV(INV_COUT)) u_cout(.I(1'b0),.O_P(COUT_P),.O_N(COUT_N));
    obufds_autoinv #(.INV(INV_TXCLK)) u_txclk(.I(1'b0),.O_P(TXCLK_P),.O_N(TXCLK_N));
    obufds_autoinv #(.INV(INV_DOUT)) u_dout(.I(1'b0),.O_P(DOUT_P),.O_N(DOUT_N));
endmodule
