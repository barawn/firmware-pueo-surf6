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

set curdir [pwd]
set verstring [pretty_version [get_built_project_version]]
set topname [get_property TOP [current_design]]
set origbit [format "%s.bit" $topname]
set origltx [format "%s.ltx" $topname]
set origll [format "%s.ll" $topname]
set fullbitname [format "%s_%s.bit" $topname $verstring]
set fullltxname [format "%s_%s.ltx" $topname $verstring]
set fullfwuname [format "%s_%s.fwu" $topname $verstring]

set build_dir [file join $projdir build]

set bitfn [file join $build_dir $fullbitname]
set ltxfn [file join $build_dir $fullltxname]
set fwufn [file join $build_dir $fullfwuname]

file copy -force $origbit $bitfn
# check if it exists
if { [file exists $origltx] } {
    file copy -force $origltx $ltxfn
} else {
    puts "Skipping LTX copy since it doesn't exist."
}

set firstBramLoc [get_first_fwupdate_bramloc]
set searchString [format "%s RAM=B:BIT0" $firstBramLoc]
set llfp [open $origll r]
set outfp [open $fwufn w]
while {[gets $llfp line] != -1} {
    if {[string first $searchString $line] != -1} {
	puts $outfp $line
    }
}
close $llfp
close $outfp

cd $curdir

