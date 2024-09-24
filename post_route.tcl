# get_repo_dir doesn't work because we're not in the Vivado project
# so instead we use search_repo_dir.
proc search_repo_dir {} {    
    set projdir [get_property DIRECTORY [current_project]]
    set fullprojdir [file normalize $projdir]
    set projdirlist [ file split $fullprojdir ]
    set projindex [lsearch $projdirlist "vivado_project"]
    set basedirlist [lrange $projdirlist 0 [expr $projindex - 1]]
    return [ file join {*}$basedirlist ]
}

set rdir [search_repo_dir]
source [file join $rdir postprocess_fwupdate_bram.tcl]

update_fwupdate_luts


