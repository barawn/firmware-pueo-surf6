proc get_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set basedirlist [ lreplace $projdirlist end end ]
    return [ file join {*}$basedirlist ]
}

source [file join [get_repo_dir] postprocess_fwupdate_bram.tcl]

update_fwupdate_luts


