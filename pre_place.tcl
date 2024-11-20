set brams [get_cells -hier -filter { CUSTOM_BRAM_IDX != "" }]
foreach b $brams {
    set idx [get_property CUSTOM_BRAM_IDX $b]
    if { [expr $idx == 0] } {
	puts "first bram is $b"
	set firstBram $b
    }
}
set pblock [create_pblock pb_firstBram]
set_property IS_SOFT 0 $pblock
add_cells_to_pblock $pblock $firstBram

set max 0
set x0brams [get_sites -filter { NAME =~ "RAMB36_X0Y*" }]
foreach b $x0brams {
    set y [lindex [split $b "XY"] 2]
    if [expr $y > $max] {
	set max $y
    }
}
puts "max BRAM Y-index is $y"
for {set thisY 0} { $thisY < $max } { incr thisY 12 } {
    set filterString "NAME =~ RAMB36_X*Y$thisY"
    resize_pblock -add [get_sites -filter $filterString ] $pblock
}
