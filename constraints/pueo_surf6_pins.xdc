# AG17

set_property -dict { PACKAGE_PIN AG17 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports SYSREFCLK_P]
set_property -dict { PACKAGE_PIN AH17 IOSTANDARD LVDS DIFF_TERM TRUE } [get_ports SYSREFCLK_N]

set_property -dict { PACKAGE_PIN F14 IOSTANDARD LVCMOS33 } [get_ports PL_SYSREF_P]
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports PL_SYSREF_N]

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

set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports CMD_RX]
set_property -dict { PACKAGE_PIN C13 IOSTANDARD LVCMOS33 } [get_ports CMD_TX]

