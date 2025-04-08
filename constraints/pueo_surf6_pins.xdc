# AG17

# these are the revA clock
set_property -dict { PACKAGE_PIN AG17 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports SYSREFCLK_P]
set_property -dict { PACKAGE_PIN AH17 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports SYSREFCLK_N]
# revB clock
set_property -dict { PACKAGE_PIN AH15 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports SYSCLK_P]
set_property -dict { PACKAGE_PIN AG15 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports SYSCLK_N]
# either PL/unused or OE_AUXCLK/OE_MGTCLK
set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports B88_L5_P]
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports B88_L5_N]
# revB pl_sysref
set_property -dict { PACKAGE_PIN AK18 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports PL_SYSREF_P]
set_property -dict { PACKAGE_PIN AL18 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports PL_SYSREF_N]

set_property -dict { PACKAGE_PIN AK16 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports RXCLK_P]
set_property -dict { PACKAGE_PIN AJ17 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports RXCLK_N]

set_property -dict { PACKAGE_PIN AN18 IOSTANDARD LVDS } [get_ports TXCLK_P]
set_property -dict { PACKAGE_PIN AP17 IOSTANDARD LVDS } [get_ports TXCLK_N]

set_property -dict { PACKAGE_PIN AM16 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports CIN_P]
set_property -dict { PACKAGE_PIN AL17 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports CIN_N]

set_property -dict { PACKAGE_PIN AP16 IOSTANDARD LVDS } [get_ports COUT_P]
set_property -dict { PACKAGE_PIN AP15 IOSTANDARD LVDS } [get_ports COUT_N]

set_property -dict { PACKAGE_PIN AN17 IOSTANDARD LVDS } [get_ports DOUT_P]
set_property -dict { PACKAGE_PIN AM17 IOSTANDARD LVDS } [get_ports DOUT_N]

# swapped between revA/B
set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports B88_L9_P]
set_property -dict { PACKAGE_PIN C13 IOSTANDARD LVCMOS33 DRIVE 8} [get_ports B88_L9_N]

# GPOs
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports READY_B]
set_property -dict { PACKAGE_PIN E12 IOSTANDARD LVCMOS33 } [get_ports { FP_LED[0] }]
set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 } [get_ports { FP_LED[1] }]
set_property -dict { PACKAGE_PIN B13 IOSTANDARD LVCMOS33 } [get_ports CALEN]
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports CAL_SEL_B]
set_property -dict { PACKAGE_PIN A13 IOSTANDARD LVCMOS33 } [get_ports B88_L11_N]
set_property -dict { PACKAGE_PIN B12 IOSTANDARD LVCMOS33 } [get_ports SEL_CAL_B]
set_property -dict { PACKAGE_PIN A12 IOSTANDARD LVCMOS33 } [get_ports SEL_CAL]

set_property -dict { PACKAGE_PIN M28 } [get_ports { B128_CLK_P[0] }]
set_property -dict { PACKAGE_PIN M29 } [get_ports { B128_CLK_N[0] }]
set_property -dict { PACKAGE_PIN K28 } [get_ports { B128_CLK_P[1] }]
set_property -dict { PACKAGE_PIN K29 } [get_ports { B128_CLK_N[1] }]

set_property -dict { PACKAGE_PIN H28 } [get_ports { B129_CLK_P[0] }]
set_property -dict { PACKAGE_PIN H29 } [get_ports { B129_CLK_N[0] }]
set_property -dict { PACKAGE_PIN F28 } [get_ports { B129_CLK_P[1] }]
set_property -dict { PACKAGE_PIN F29 } [get_ports { B129_CLK_N[1] }]

set_property -dict { PACKAGE_PIN AJ18 IOSTANDARD LVCMOS18} [get_ports { DBG_LED[0] }]
set_property -dict { PACKAGE_PIN AH18 IOSTANDARD LVCMOS18} [get_ports { DBG_LED[1] }]
set_property -dict { PACKAGE_PIN AF18 IOSTANDARD LVCMOS18} [get_ports { DBG_LED[2] }]
set_property -dict { PACKAGE_PIN AD18 IOSTANDARD LVCMOS18} [get_ports { DBG_LED[3] }]

set_property -dict { PACKAGE_PIN AM14 IOSTANDARD LVCMOS18} [get_ports { CLK_SDO_SYNC }]
