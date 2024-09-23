# we need to locate 12 of the fwupdate BRAMs that are
# sequential in terms of their bit offset locations.
# this allows them to all be read out at once.
#
# We then alter their fwupdate enable LUTs
# (which take the 4 addr bits + fwrunning to
#  generate a BRAM enable) so they'll respond
# correctly to the addresses.
#
# There are 24 total, so 12 of them *must* be aligned
# properly.
#
# The LUTs and BRAMs are both tagged with associated custom properties:
# the BRAMs have CUSTOM_BRAM_IDX and the LUTs have CUSTOM_BRAM_LUT_IDX.
# We build a list of BRAMs and an array (hash) associating them with
# their LUTs. We then look for the first BRAM whose Y index is 0 mod 12.
# That's our key - we associate that BRAM's LUT with addr 0, and then
# continue upward.
proc get_chbuffer_brams { } {
    set brams [get_cells -hier -filter { CUSTOM_BRAM_IDX != "" }]
    return [lsort -command chbuffer_lsort_comp $brams]
}

# command is always equivalent of a-b
proc chbuffer_lsort_comp { a b } {
    set idxA [get_property CUSTOM_BRAM_IDX $a]
    set idxB [get_property CUSTOM_BRAM_IDX $b]
    set res [expr {$idxA - $idxB}]
    return $res
}

# find the first bram
proc get_fwupdate_first_bram_idx { brams } {
    set firstBram ""
    foreach bram $brams {
	# only work until we find the first one
	if { $firstBram == "" } {
	    set yloc [lindex [split [get_property LOC $bram] "Y"] 1]
	    if { [expr { $yloc % 12 }] == 0 } {
		set firstBram $bram
	    }
	}
    }
    set firstBramIdx [get_property CUSTOM_BRAM_IDX $firstBram]
    return $firstBramIdx
}

# we need both bin2dec and dec2bin
proc bin2dec bin {
    if {$bin == 0} {
        return 0 
    } elseif  {[string match -* $bin]} {
        set sign -
        set bin [string range $bin 1 end]
    } else {
        set sign {}
    }
    if {[string map [list 1 {} 0 {}] $bin] ne {}} {
        error "argument is not in base 2: $bin"
    }
    set r 0
    foreach d [split $bin {}] {
        incr r $r
        incr r $d
    }
    return $sign$r
}

proc dump_fwupdate_bramlocs { fnprefix } {
    set brams [get_chbuffer_brams]
    set firstBramIdx [get_fwupdate_first_bram_idx $brams]
    # now that we know the first BRAM idx, we can rewrite the LUTs
    set fwupdateBrams ""
    for { set i $firstBramIdx } { $i < [expr $firstBramIdx + 12] } { incr i } {
	lappend fwupdateBrams [lindex $brams $i]
    }

    set dna [get_cells -hier -filter { CUSTOM_DNA_VER != "" }]
    set binver [get_property CUSTOM_DNA_VER $dna]
    set decver [lindex [split $binver "b"] 1]
    set hexver [format %8.8llx $decver]
    set part [get_property part [current_design]]
    set psfx [lindex [split $part "-"] 0]
    append fnprefix $psfx "_" $hexver ".loc"
    set lastdir [pwd]
    cd [get_repo_dir]
    set fp [open $fnprefix w]
    foreach bram $fwupdateBrams {
	puts $fp [get_property LOC $bram]
    }
    close $fp
}

proc update_fwupdate_luts { } {
    set brams [get_chbuffer_brams]
    set firstBramIdx [get_fwupdate_first_bram_idx $brams]
    # once we know the first BRAM idx, we just start there,
    # and pluck the LUTs by search
    # The way the INITs work is that literally the bit corresponding
    # to the value gets set. So you just want the binary representation
    # of (1<<idx).
    for { set i 0 } { $i < 12 } { incr i } {
	set idxVal [expr $i + $firstBramIdx]
	set filterStr [format "CUSTOM_BRAM_LUT_IDX == $idxVal"]
	puts "searching for $filterStr"
	set lut [get_cells -hier -filter $filterStr]
	set hexInit [format %4.4llx [expr 1 << $i]]
	set initStr [format "16'h$hexInit"]
	puts "setting $lut INIT val to $initStr"
	set_property INIT $initStr $lut
    }
}
