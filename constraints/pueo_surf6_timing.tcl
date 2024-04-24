######## CONVENIENCE FUNCTIONS
# These all have escape clauses because clocks sometimes don't exist in the elaboration/synthesis
# steps.

proc set_cc_paths { srcClk dstClk ctlist } {
    if {$srcClk eq ""} {
        puts "set_cc_paths: No source clock: returning."
        return
    }
    if {$dstClk eq ""} {
        puts "set_cc_paths: No destination clock: returning."
        return
    }
    array set ctypes $ctlist
    set srcType $ctypes($srcClk)
    set dstType $ctypes($dstClk)
    set maxTime [get_property PERIOD $srcClk]
    set srcRegs [get_cells -hier -filter "CUSTOM_CC_SRC == $srcType"]
    set dstRegs [get_cells -hier -filter "CUSTOM_CC_DST == $dstType"]
    set_max_delay -datapath_only -from $srcRegs -to $dstRegs $maxTime
}

proc set_gray_paths { srcClk dstClk ctlist } {
    if {$srcClk eq ""} {
        puts "set_gray_paths: No source clock: returning."
        return
    }
    if {$dstClk eq ""} {
        puts "set_gray_paths: No destination clock: returning."
        return
    }
    array set ctypes $ctlist
    set maxTime [get_property PERIOD $srcClk]
    set maxSkew [expr min([get_property PERIOD $srcClk], [get_property PERIOD $dstClk])]
    set srcRegs [get_cells -hier -filter "CUSTOM_GRAY_SRC == $ctypes($srcClk)"]
    set dstRegs [get_cells -hier -filter "CUSTOM_GRAY_DST == $ctypes($dstClk)"]
    set_max_delay -datapath_only -from $srcRegs -to $dstRegs $maxTime
    set_bus_skew -from $srcRegs -to $dstRegs $maxSkew
}

proc set_ignore_paths { srcClk dstClk ctlist } {
    if {$srcClk eq ""} {
        puts "set_ignore_paths: No source clock: returning."
        return
    }
    if {$dstClk eq ""} {
        puts "set_ignore_paths: No destination clock: returning."
        return
    }
    array set ctypes $ctlist
    set srcRegs [get_cells -hier -filter "CUSTOM_IGN_SRC == $ctypes($srcClk)"]
    set dstRegs [get_cells -hier -filter "CUSTOM_IGN_DST == $ctypes($dstClk)"]
    set_false_path -from $srcRegs -to $dstRegs
}

######## END CONVENIENCE FUNCTIONS

# PIN CLOCKS
set sysrefclk [create_clock -period 2.667 -name sysref_clk [get_ports -filter { NAME =~ "SYSREFCLK_P" && DIRECTION == "IN" }]]
set clktypes($sysrefclk) SYSREFCLK

set rxclk [create_clock -period 8.00 -name rxclk_clk [get_ports -filter { NAME =~ "RXCLK_P" && DIRECTION == "IN" }]]
set clktypes($rxclk) RXCLK

set gtpclk0 [create_clock -period 8.00 -name gtpclk0_clk [get_ports -filter { NAME =~ "B128_CLK_P[0]" && DIRECTION == "IN" }]]
set clktypes($gtpclk0) GTPCLK0

set gtpclk1 [create_clock -period 8.00 -name gtpclk1_clk [get_ports -filter { NAME =~ "B128_CLK_P[1]" && DIRECTION == "IN" }]]
set clktypes($gtpclk1) GTPCLK1

# GENERATED CLOCKS

set ifclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "if_clk"}]]
set clktypes($slowclk) IFCLK

set clk300 [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "clk300"}]]
set clktypes($clk300) CLK300

# create clktypelist variable to save
set clktypelist [array get clktypes]

###### END CLOCK DEFINITIONS

# autoignore the flag_sync module guys
set sync_flag_regs [get_cells -hier -filter {NAME =~ *FlagToggle_clkA_reg*}]
set sync_sync_regs [get_cells -hier -filter {NAME =~ *SyncA_clkB_reg*}]
set sync_syncB_regs [get_cells -hier -filter {NAME =~ *SyncB_clkA_reg*}]
set_max_delay -datapath_only -from $sync_flag_regs -to $sync_sync_regs 10.000
set_max_delay -datapath_only -from $sync_sync_regs -to $sync_syncB_regs 10.000

# autoignore the clockmon regs
set clockmon_level_regs [ get_cells -hier -filter {NAME =~ *u_clkmon/*clk_32x_level_reg*} ]
set clockmon_cc_regs [ get_cells -hier -filter {NAME =~ *u_clkmon/*level_cdc_ff1_reg*}]
set clockmon_run_reset_regs [ get_cells -hier -filter {NAME =~ *u_clkmon/clk_running_reset_reg*}]
set clockmon_run_regs [get_cells -hier -filter {NAME=~ *u_clkmon/*u_clkmon*}]
set clockmon_run_cc_regs [get_cells -hier -filter {NAME=~ *u_clkmon/clk_running_status_cdc1_reg*}]
set_max_delay -datapath_only -from $clockmon_level_regs -to $clockmon_cc_regs 10.000
set_max_delay -datapath_only -from $clockmon_run_reset_regs -to $clockmon_run_regs 10.000
set_max_delay -datapath_only -from $clockmon_run_regs -to $clockmon_run_cc_regs 10.000

# NOTE NOTE
# THIS MEANS DEBUGGING ONLY WORKS IF PS IS RUNNING
# guard against dumbassery
set my_dbg_hub [get_debug_cores dbg_hub -quiet]
if {[llength $my_dbg_hub] > 0} {
   set_property C_CLK_INPUT_FREQ_HZ 300000000 $my_dbg_hub
   set_property C_ENABLE_CLK_DIVIDER false $my_dbg_hub
   set_property C_USER_SCAN_CHAIN 1 $my_dbg_hub
   connect_debug_port dbg_hub/clk ps_clk
} else {
   puts "skipping debug hub commands, not inserted yet"
}