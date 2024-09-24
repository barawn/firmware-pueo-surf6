# this file contains common convenience functions
# they were moved out of project_init.tcl so they could be sourced
# in batch mode scripts as well
# The only one that isn't is get_repo_dir, since it needs to exist
# to FIND this file.
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

proc get_built_project_version {} {
    set dna [get_cells -hier -filter { CUSTOM_DNA_VER != "" }]
    set binver [lindex [split [get_property CUSTOM_DNA_VER $dna] "b"] 1]
    return [bin2dec $binver]
}

proc pretty_version { ver } {
    set vrev [ expr $ver & 0xFF ]
    set vmin [ expr ($ver & 0xF00) >> 8]
    set vmaj [ expr ($ver & 0xF000) >> 12]
    return [format "v%sr%sp%s" $vmaj $vmin $vrev]
}

