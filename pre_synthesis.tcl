# Current date, time, and seconds since epoch
# 0 = 4-digit year
# 1 = 2-digit year
# 2 = 2-digit month
# 3 = 2-digit day
# 4 = 2-digit hour
# 5 = 2-digit minute
# 6 = 2-digit second
# 7 = Epoch (seconds since 1970-01-01_00:00:00)
# Array index                                            0  1  2  3  4  5  6  7
set datetime_arr [clock format [clock seconds] -format {%Y %y %m %d %H %M %S %s}]

set year [string trimleft [lindex $datetime_arr 1] 0 ]
set month [string trimleft [lindex $datetime_arr 2] 0 ]
set day [string trimleft [lindex $datetime_arr 3] 0 ]

set firmware_date [expr [expr $year << 9]+[expr $month << 5]+$day]

set_property generic "FIRMWARE_DATE=32'd$firmware_date" [current_fileset]
