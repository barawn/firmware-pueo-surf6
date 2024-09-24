proc get_repo_dir {} {
    set projdir [get_property DIRECTORY [current_project]]
    set projdirlist [ file split $projdir ]
    set basedirlist [ lreplace $projdirlist end end ]
    return [ file join {*}$basedirlist ]
}

source [file join [get_repo_dir] project_utility.tcl]
source [file join [get_repo_dir] postprocess_fwupdate_bram.tcl]

set curdir [pwd]
set projdir [get_repo_dir]
set verstring [pretty_version [get_built_project_version]]
set topname [get_property TOP [current_design]]
set origbit [format "%s.bit" $topname]
set origltx [format "%s.ltx" $topname]
set origll [format "%s.ll" $topname]
set fullbitname [format "%s_%s.bit" $topname $verstring]
set fullltxname [format "%s_%s.ltx" $topname $verstring]
set fullfwuname [format "%s_%s.fwu" $topname $verstring]

set build_dir [file join [get_repo_dir] build]

set bitfn [file join $build_dir $fullbitname]
set ltxfn [file join $build_dir $fullltxname]
set fwufn [file join $build_dir $fullfwuname]

file copy -force $origbit $bitfn
file copy -force $origltx $ltxfn

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

