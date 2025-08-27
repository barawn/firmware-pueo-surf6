######## CONVENIENCE FUNCTIONS
# These all have escape clauses because clocks sometimes don't exist in the elaboration/synthesis
# steps.

set we_are_synthesis [info exists are_we_synthesis]
puts "we are synthesis: $we_are_synthesis"

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
    set srcType $ctypes($srcClk)
    set dstType $ctypes($dstClk)
    set maxTime [get_property PERIOD $srcClk]
    set maxSkew [expr min([get_property PERIOD $srcClk], [get_property PERIOD $dstClk])]
    set srcRegs [get_cells -hier -filter "CUSTOM_GRAY_SRC == $srcType"]
    set dstRegs [get_cells -hier -filter "CUSTOM_GRAY_DST == $dstType"]
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
    set srcType $ctypes($srcClk)
    set dstType $ctypes($dstClk)
    set srcRegs [get_cells -hier -filter "CUSTOM_IGN_SRC == $srcType"]
    set dstRegs [get_cells -hier -filter "CUSTOM_IGN_DST == $dstType"]
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

# The standard multicycle path calls don't actually use "set_multicycle_path" because
# that whole procedure is dopestick annoying and often DOES NOT WORK if you're going
# between domains that don't have an integer relationship.
# Instead we just friggin' embed the min delay/max delays in UNITS OF THE SOURCE CLOCK.
#
# To have a destination be included in MULTIPLE tags you include them SEPARATED BY SPACES
# you CANNOT HAVE A MULTICYCLE PATH with one source to multiple destinations in this syntax:
# you have to break it up somewhere.
#
# TAGS HAVE TO JUST BE SIMPLE ALPHANUMERICS
#
# convenience function
proc build_multicycle_re_dst { tag } {
    # this works out to be "($tag)|($tag .*)|(.* $tag .*)|(.* $tag$)"
    # it'd be awesome if I could figure out how to make a word boundary work,
    # but I can't.
    set RE_DST {"(}    
    append RE_DST $tag
    append RE_DST {)|(}
    append RE_DST $tag
    append RE_DST { .*)|(.* }
    append RE_DST $tag
    append RE_DST { .*)|(.* }
    append RE_DST $tag
    append RE_DST {$)"}
    return $RE_DST
}

# note: the min/max delay attributes are set ONLY ON THE SOURCE REGISTER.
# EXAMPLE
# (* CUSTOM_MC_SRC_TAG = "ATOP_XFER", CUSTOM_MC_MIN = -2.5, CUSTOM_MC_MAX = 3.0 *)
# reg atop = 0;
# (* CUSTOM_MC_SRC_TAG = "BTOP_XFER", CUSTOM_MC_MIN = -3, CUSTOM_MC_MAX = 4.5 *)
# reg btop = 0;
# (* CUSTOM_MC_DST_TAG = "ATOP_XFER BTOP_XFER" *)
# reg dest = 0;
proc set_mc_paths { tag } {
    set RE_DST [build_multicycle_re_dst $tag]
    set srcRegs [get_cells -hier -filter "CUSTOM_MC_SRC_TAG == $tag"]
    set dstRegs [get_cells -hier -regexp -filter "CUSTOM_MC_DST_TAG =~ $RE_DST"]
    if {[llength $srcRegs] == 0} {
        puts "set_mc_paths: No registers flagged with CUSTOM_MC_SRC_TAG $tag: returning."
        return
    }
    if {[llength $dstRegs] == 0} {
        puts "set_mc_paths: No registers flagged with CUSTOM_MC_DST_TAG $tag: returning."
        return
    }
    set thisReg [lindex $srcRegs 0]
    set srcClk [get_clocks -of_objects [get_cells $thisReg]]
    set thisSourceClockPeriod [get_property PERIOD $srcClk]
    set thisMin [get_property CUSTOM_MC_MIN [get_cells $thisReg]]
    if {[llength $thisMin] == 0} {
        puts "set_mc_paths: No minimum delay specified in tag $tag: returning."
        return
    }        
    set thisMax [get_property CUSTOM_MC_MAX [get_cells $thisReg]]
    if {[llength $thisMax] == 0} {
        puts "set_mc_paths: No maximum delay specified in tag $tag: returning."
        return
    }        
    set minTime [expr $thisMin*$thisSourceClockPeriod]
    set maxTime [expr $thisMax*$thisSourceClockPeriod]
    puts "set_mc_paths: $tag min $minTime max $maxTime"
    set_min_delay -from $srcRegs -to $dstRegs $minTime
    set_max_delay -from $srcRegs -to $dstRegs $maxTime
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
set rackclk [create_clock -period 8.00 -waveform { 0.9 4.9 } -name rackclk [get_ports -filter { NAME =~ "RXCLK_P" && DIRECTION == "IN" }]]
set clktypes($rackclk) RACKCLK

# there are 4 possible GTP clock inputs. Just define them all here. Only one ever gets used so we just name them GTPCLK.
set gtpclk0 [create_clock -period 10.000 -name gtpclk0_clk [get_ports -filter { NAME =~ "B128_CLK_P[0]" && DIRECTION == "IN" }]]
set clktypes($gtpclk0) GTPCLK

set gtpclk1 [create_clock -period 10.000 -name gtpclk1_clk [get_ports -filter { NAME =~ "B128_CLK_P[1]" && DIRECTION == "IN" }]]
set clktypes($gtpclk1) GTPCLK

set gtpclk2 [create_clock -period 10.000 -name gtpclk2_clk [get_ports -filter { NAME =~ "B129_CLK_P[0]" && DIRECTION == "IN" }]]
set clktypes($gtpclk2) GTPCLK

set gtpclk3 [create_clock -period 10.000 -name gtpclk3_clk [get_ports -filter { NAME =~ "B129_CLK_P[1]" && DIRECTION == "IN" }]]
set clktypes($gtpclk3) GTPCLK 

# GENERATED CLOCKS

set ifclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "ifclk"}]]
set clktypes($ifclk) IFCLK

set memclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "memclk" }]]
set clktypes($memclk) MEMCLK

set clk300 [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "clk300"}]]
set clktypes($clk300) CLK300

set psclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "ps_clk" }]]
set clktypes($psclk) PSCLK

set rxclk [get_clocks -of_objects [get_nets -hier -filter { NAME =~ "rxclk" }]]
set clktypes($rxclk) RXCLK

# create clktypelist variable to save
set clktypelist [array get clktypes]

###### END CLOCK DEFINITIONS

# EVERYTHING AFTER THIS IS IMPLEMENTATION ONLY

if { $we_are_synthesis != 1 } {
    puts "Processing timing constraints."

    puts "Overconstraining memclk."
    set_clock_uncertainty -from $memclk -to $memclk 0.05
    set_clock_uncertainty -from $sysclk -to $memclk 0.05

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

    set_cc_paths $psclk $rackclk $clktypelist
    set_cc_paths $rackclk $psclk $clktypelist
    
    set_cc_paths $psclk $ifclk $clktypelist
    set_cc_paths $ifclk $psclk $clktypelist

    set_gray_paths $memclk $ifclk $clktypelist

    # just ignore the async removal crap
    set rackrst_src [get_cells -hier -filter { NAME =~ "u_id_ctrl/u_clkmon/clk_running_status_cdc2_reg[5]" }]
    set rackrst_dst [get_cells -hier -filter { NAME =~ "u_wb_rackctl/u_rackctl_rst" }]
    set_false_path -from $rackrst_src -to $rackrst_dst
    
    # We also have some ignore paths in the RACKctl handling the gigantic tristate times
    # These are rackclk to rackclk
    set_ignore_paths $rackclk $rackclk $clktypelist

    #############################################################
    ##   SYNCHRONOUS CLOCK TRANSFER CONSTRAINTS
    #############################################################

    # AUTOMATIC MULTICYCLE PATH FINDING
    set mc_sources [get_cells -hier -filter { CUSTOM_MC_SRC_TAG != "" }]
    set mc_all_tags {}
    foreach cell $mc_sources {
        lappend mc_all_tags [get_property CUSTOM_MC_SRC_TAG $cell]
    }
    set mc_tags [ lsort -unique $mc_all_tags ]
    foreach tag $mc_tags {
        puts "Handling multicycle tag $tag"
        set_mc_paths $tag
    }
    
#    set_mc_paths ATOP_XFER
#    set_mc_paths ABOT_XFER
#    set_mc_paths BTOP_XFER
#    set_mc_paths BBOT_XFER
#    set_mc_paths CTOP_XFER
#    set_mc_paths CBOT_XFER
#    set_mc_paths URAM_RESET
#    set_mc_paths FW_VALID
#    set_mc_paths FW_DATA
    
#    set_mc_paths RUNDO_SYNC
#    set_mc_paths RUNRST
#    set_mc_paths RUNSTOP
    
#    set_mc_paths TRIG_TO_IFCLK
    
#    set_mc_paths SYNC
    
#    set_mc_paths EVBUF_HEADER_SELECT
#    set_mc_paths EVBUF_HEADER_DATA
#    set_mc_paths EVBUF_DATA
}
    
#################################################################


# NOTE NOTE
# THIS MEANS DEBUGGING ONLY WORKS IF PS IS RUNNING
# guard against dumbassery
set my_dbg_hub [get_debug_cores dbg_hub -quiet]
if {[llength $my_dbg_hub] > 0} {
   set_property C_CLK_INPUT_FREQ_HZ 300000000 $my_dbg_hub
   set_property C_ENABLE_CLK_DIVIDER false $my_dbg_hub
   set_property C_USER_SCAN_CHAIN 1 $my_dbg_hub
   connect_debug_port dbg_hub/clk ps_clk
   # WTF IS THIS NEEDED FOR GOD DAMNIT
   # ONLY FOR IBERT AND I NEED A BETTER WAY OF TESTING THIS
   set_clock_groups -name async_ibert -asynchronous -group [get_clocks -include_generated_clocks gtpclk3_clk] -group $psclk
} else {
   puts "skipping debug hub commands, not inserted yet"
}
