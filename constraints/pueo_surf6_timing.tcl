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
    if {[llength $srcRegs] == 0} {
        puts "set_cc_paths: No registers flagged with CUSTOM_CC_SRC $srcType: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_cc_paths: No registers flagged with CUSTOM_CC_DST $dstType: returning."
        return
    }
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
    if {[llength $srcRegs] == 0} {
        puts "set_gray_paths: No registers flagged with CUSTOM_GRAY_SRC $srcType: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_gray_paths: No registers flagged with CUSTOM_GRAY_DST $dstType: returning."
        return
    }
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
    if {[llength $srcRegs] == 0} {
        puts "set_ignore_paths: No registers flagged with CUSTOM_IGN_SRC $srcType: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_ignore_paths: No registers flagged with CUSTOM_IGN_DST $dstType: returning."
        return
    }
    set_false_path -from $srcRegs -to $dstRegs
}

######## END CONVENIENCE FUNCTIONS

# PIN CLOCKS
set sysrefclk [create_clock -period 2.667 -name sysref_clk [get_ports -filter { NAME =~ "SYSREFCLK_P" && DIRECTION == "IN" }]]
set clktypes($sysrefclk) SYSREFCLK

# we can set BOTH of these to the same clktype because only one gets used:
# the only reason we have a name/type hash is to allow getting the period of the clock automatically
# this follows SYSCLK_N because the clock is inverted
set sysclk [create_clock -period 2.667 -name sys_clk [get_ports -filter { NAME =~ "SYSCLK_N" && DIRECTION == IN }]]
set clktypes($sysclk) SYSREFCLK

# If we want RXCLK/ACLK timed together, we need to compensate for the
# difference in their clock network routing. Otherwise it tries to use
# it to help.
set rxclk [create_clock -period 8.00 -waveform { 0.9 4.9 } -name rxclk_clk [get_ports -filter { NAME =~ "RXCLK_P" && DIRECTION == "IN" }]]
set clktypes($rxclk) RXCLK

set gtpclk0 [create_clock -period 8.00 -name gtpclk0_clk [get_ports -filter { NAME =~ "B128_CLK_P[0]" && DIRECTION == "IN" }]]
set clktypes($gtpclk0) GTPCLK0

set gtpclk1 [create_clock -period 8.00 -name gtpclk1_clk [get_ports -filter { NAME =~ "B128_CLK_P[1]" && DIRECTION == "IN" }]]
set clktypes($gtpclk1) GTPCLK1

# GENERATED CLOCKS

set ifclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "ifclk"}]]
set clktypes($ifclk) IFCLK

set clk300 [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "clk300"}]]
set clktypes($clk300) CLK300

set psclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "ps_clk" }]]
set clktypes($psclk) PSCLK

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

# weirdo clock transfer regs
set xfr_src_aclk [get_cells -hier -filter {CUSTOM_RXCLK_ACLK_SOURCE=="ACLK"}]
set xfr_src_rxclk [get_cells -hier -filter {CUSTOM_RXCLK_ACLK_SOURCE=="RXCLK"}]
set xfr_tgt_aclk [get_cells -hier -filter {CUSTOM_RXCLK_ACLK_TARGET=="ACLK"}]
set xfr_tgt_rxclk [get_cells -hier -filter {CUSTOM_RXCLK_ACLK_TARGET=="RXCLK"}]
if { [llength $xfr_src_aclk] != 0 } {
        # FROM sysclk TO rxclk is multicycle b/c rxclk is forward-delayed
        # i.e. we want from clock at 0 to clock at 3.567 b/c *internally* that
        # ends up roughly the same due to the -2.8 ns shift
#        set_multicycle_path 2 -from $xfr_src_aclk -to $xfr_tgt_rxclk
#        set_multicycle_path 1 -from $xfr_src_aclk -to $xfr_tgt_rxclk -hold
        set_max_delay -datapath_only -from $xfr_src_aclk -to $xfr_tgt_rxclk 1.33
        set_max_delay -datapath_only -from $xfr_src_rxclk -to $xfr_tgt_aclk 1.33
        set_bus_skew -from $xfr_src_rxclk -to $xfr_tgt_aclk 0.1
        # FROM rxclk TO sysclk is NOT multicycle: there we want
        # from clock 0.9 to 2.667.
}


# and now we use the magics to handle the CC paths in the TURFIO module
set_cc_paths $sysclk $psclk $clktypelist
set_cc_paths $psclk $sysclk $clktypelist

set_cc_paths $psclk $clk300 $clktypelist
set_cc_paths $clk300 $psclk $clktypelist

set_cc_paths $psclk $rxclk $clktypelist
set_cc_paths $rxclk $psclk $clktypelist

set_cc_paths $psclk $ifclk $clktypelist


# CLOCK ADJUSTMENTS
# Xilinx doesn't have any way to properly adjust launch/capture clocks
# arbitrarily (set_multicycle_path does not allow _separate_ launch/capture
# clock adjustments on setup/hold, you can only do one or the other)
# So, eff you, Xilinx, just specify everyone myself.
set sync_src [get_cells -hier -filter { NAME =~ "u_syncgen/next_do_sync_reg" }]
set sync_tgt [get_cells -hier -filter { NAME =~ "u_syncgen/ifclk_sync_reg"}]
lappend sync_tgt [get_cells -hier -filter { NAME =~ "u_syncgen/memclk_sync_reg"}]

# Both IFCLK and MEMCLK fundamentally have the same setup/hold
# because they are both sourced and captured by the same edges
# so setup is 2.667 (launch to capture) and hold is -5.333 (launch to prior capture)
set_max_delay -from $sync_src -to $sync_tgt 2.667
set_min_delay -from $sync_src -to $sync_tgt -5.333 

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