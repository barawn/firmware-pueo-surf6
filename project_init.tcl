# Returns the base directory of the project. Assumes
# the project is stored in a subdirectory of the repository top level
# e.g. repo is "this_project", and project is in "this_project/vivado_project"
proc get_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set basedirlist [ lreplace $projdirlist end end ]
    return [ file join {*}$basedirlist ]
}

source [file join [get_repo_dir] verilog-library-barawn tclbits utility.tcl]
source [file join [get_repo_dir] verilog-library-barawn tclbits repo_files.tcl]

add_include_dir [file join [get_repo_dir] verilog-library-barawn include]
add_include_dir [file join [get_repo_dir] include]

# set pre-synthesis scripts
set_pre_synthesis_tcl [file join [get_repo_dir] pre_synthesis.tcl]
set_post_route_tcl [file join [get_repo_dir] post_route.tcl]
set_post_write_bitstream_tcl [file join [get_repo_dir] post_write_bitstream.tcl]

check_all
