# search_repo_dir finds the repo dir so long as we were called ANYWHERE
# in the project AND the project dir is called vivado_project
proc search_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set fullprojdir [file normalize $projdir]
    set projdirlist [ file split $fullprojdir ]
    set projindex [lsearch $projdirlist "vivado_project"]
    set basedirlist [lrange $projdirlist 0 [expr $projindex - 1]]
    return [ file join {*}$basedirlist ]
}

set projdir [search_repo_dir]
source [file join $projdir project_utility.tcl]
source [file join $projdir postprocess_fwupdate_bram.tcl]

set topname [get_property TOP [current_design]]
set origll [format "%s.ll" $topname]
set origbit [format "%s.bit" $topname]

write_bitstream -no_binary_bitfile -logic_location_file -force $origbit
set firstBramLoc [get_first_fwupdate_bramloc]
set searchString [format "%s RAM=B:BIT0" $firstBramLoc]
set llfp [open $origll r]
while {[gets $llfp line] != -1} {
    if {[string first $searchString $line] != -1} {
	set usercodeHex [lindex $line 2]
	set usercode [string range $usercodeHex 2 [string length $usercodeHex]]
    }
}
puts "Updating USERID to $usercode"
set_property BITSTREAM.CONFIG.USERID $usercode [current_design]

