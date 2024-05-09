//Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2022.2 (win64) Build 3671981 Fri Oct 14 05:00:03 MDT 2022
//Date        : Thu Mar 28 12:31:40 2024
//Host        : ASCPHY-NC196428 running 64-bit major release  (build 9200)
//Command     : generate_target zynq_bd_wrapper.bd
//Design      : zynq_bd_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module zynq_bd_wrapper
   (UART_1_0_rxd,
    UART_1_0_txd,
    GPIO_0_0_tri_i,
    GPIO_0_0_tri_o,
    GPIO_0_0_tri_t,
    pl_clk0_0    
    );
    
  parameter REVISION = "A";    
  input UART_1_0_rxd;
  output UART_1_0_txd;
  input [15:0] GPIO_0_0_tri_i;
  output [15:0] GPIO_0_0_tri_o;
  output [15:0] GPIO_0_0_tri_t;
  output pl_clk0_0;
  generate
    if (REVISION == "B") begin : REVB
      zynq_bd_revB zynq_bd_i
           (.UART_1_0_rxd(UART_1_0_rxd),
            .UART_1_0_txd(UART_1_0_txd),
            .GPIO_0_0_tri_i(GPIO_0_0_tri_i),
            .GPIO_0_0_tri_o(GPIO_0_0_tri_o),
            .GPIO_0_0_tri_t(GPIO_0_0_tri_t),
            .pl_clk0_0(pl_clk0_0));
    end else begin : REVA
      zynq_bd zynq_bd_i
           (.UART_1_0_rxd(UART_1_0_rxd),
            .UART_1_0_txd(UART_1_0_txd),
            .GPIO_0_0_tri_i(GPIO_0_0_tri_i),
            .GPIO_0_0_tri_o(GPIO_0_0_tri_o),
            .GPIO_0_0_tri_t(GPIO_0_0_tri_t),
            .pl_clk0_0(pl_clk0_0));
     end  
  endgenerate
endmodule
