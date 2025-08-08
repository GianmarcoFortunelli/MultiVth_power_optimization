proc multiVth {slackThreshold maxPaths} {

    # 4'50" in milliseconds
    set MAXTIME 290000

    set s_time [clock milliseconds]

    set percFirst 10

    puts "\n\n\n-----------------------------------------------------------------------------------------" 
    puts "\nSTARTING OPTIMIZATION WITH CRITERIA: higher deltaP/deltaSlack first \n\nTrying to swap LVT cells in HVT\n"
    forcingDeltaOpt $slackThreshold $maxPaths $percFirst "H" $s_time

    if { [clock milliseconds] - $s_time < $MAXTIME} {
        set percSec 10
        puts "\n\n-----------------------------------------------------------------------------------------\n" 
        puts "\nSTARTING OPTIMIZATION WITH CRITERIA: higher slack first \nTrying to swap LVT cells in HVT\n"
        forcingSlackOpt $slackThreshold $maxPaths $percSec "H" $s_time
    }

    if { [clock milliseconds] - $s_time < $MAXTIME } {
         set percThird 10
        puts "\n\n\n-----------------------------------------------------------------------------------------\n" 
        puts "\nSTARTING OPTIMIZATION WITH CRITERIA: higher deltaP/deltaSlack first \n\nTrying to swap LVT cells in SVT\n"
        forcingDeltaOpt $slackThreshold $maxPaths $percFirst "S" $s_time
    }

    if { [clock milliseconds] - $s_time < $MAXTIME} {
        set percFourth 10
        puts "\n\n\n\n\n\n\-----------------------------------------------------------------------------------------\n" 
        puts "\nSTARTING OPTIMIZATION WITH CRITERIA: higher slack first \n\nTrying to swap LVT cells in SVT\n"
        forcingSlackOpt $slackThreshold $maxPaths $percSec "S" $s_time
    }

    return 1
}

proc computeSlack {} {
    # return a order list of cell according to their slack

    puts "\n-----------------------------------------------------------------------------------------\n" 
    puts "Computing priority of the LVT cells based on criteria:               higher Slack\n" 
    update_timing -full
    set cell_slacks {}
    set lvt_cells [ get_cells -quiet -filter "lib_cell.threshold_voltage_group == LVT"]

    # for each LVT cell append on a list (slack, cell)
    foreach_in_collection cell $lvt_cells {
        set path_collection [get_timing_paths -through $cell -nworst 1]
        if {[sizeof_collection $path_collection] > 0} {
            set path [index_collection $path_collection 0]
            set slack [get_attribute $path slack]
            lappend cell_slacks [list $slack $cell]
        }    
    }
    set sorted_cell [lsort -decreasing -index 0 $cell_slacks]
    return $sorted_cell
}

proc computePriority {optCell} {
    # return an ordered list of cell according to their deltaPower/deltaSlack

    puts "\n-----------------------------------------------------------------------------------------\n" 
    puts "Computing priority of the LVT cells if changed in $optCell VT based on criteria: \n\ndeltaP/deltaSlack\n"     

    # Collection of the LVT cells
    set lvt_cells_coll [get_cells -quiet -filter "lib_cell.threshold_voltage_group == LVT"] 
    # List of the cell object names (U10 U11 ...)
    set lvt_cells_obj_name [get_object_name $lvt_cells_coll]
    
    set differences {}
    set nCell [llength $lvt_cells_obj_name]
        
    # Note the power and slack of cells
    # before changing the cell
    set oldPower [savePower 0 $nCell $lvt_cells_coll] 
    set oldTiming [saveTiming 0 $nCell $lvt_cells_coll]

    # swap al cells 
    foreach_in_collection cell $lvt_cells_coll {
        swap_vt $cell $optCell 
    }

    # Note the power and slack of cells
    # after changing the cell
    update_timing -full
    set newPower [savePower 0 $nCell $lvt_cells_coll] 
    set newTiming [saveTiming 0 $nCell $lvt_cells_coll]
    set differences [makeDiv $oldPower $newPower $oldTiming $newTiming $lvt_cells_obj_name 0 $nCell]

    # revert changes
    foreach_in_collection cell $lvt_cells_coll {
        swap_vt $cell L
    }

    set sorted_cell [lsort -real -index 1 -decreasing $differences]
    puts "\n-----------------------------------------------------------------------------------------\n" 

    return $sorted_cell
}

proc savePower { sP eP cell_list} {
    # return a list that containts leakage power of all cell
    set powerList ""
    set startPoint $sP
    set endPoint $eP
    while {$startPoint < $endPoint} {
        set cell [index_collection $cell_list $startPoint]
        set leakage [get_attribute $cell leakage_power]
        lappend powerList $leakage 
        incr startPoint
    }
    return $powerList

}

proc saveTiming { sP eP cell_list } {
    # return a list that containts slack of all cell
    set slackList ""
    set startPoint $sP
    set endPoint $eP
    while {$startPoint < $endPoint} {
        set cell [index_collection $cell_list $startPoint]
        set path_collection [get_timing_paths -through $cell -nworst 1]
        if {[sizeof_collection $path_collection] > 0} {
            set path [index_collection $path_collection 0]
            set slack [get_attribute $path slack]
            lappend slackList $slack
        }
        incr startPoint
    }
    return $slackList
}

proc makeDiv { oldP newP oldT newT c_list startP endP } {
    # return priority coefficient
    set c 0
    set lista ""
    while { $c < ($endP - $startP) } {
        set oldPo [lindex $oldP $c]
        set oldTi [lindex $oldT $c]
        set newPo [lindex $newP $c]
        set newTi [lindex $newT $c]
        set diffP [expr {($oldPo - $newPo) * pow(10,12)}]
        set diffT [ expr { $oldTi - $newTi}]
        set prio [ expr { $diffP / $diffT}]
        set index [ expr { $startP + $c }]
        set nome [ get_cells [ lindex $c_list $index]]
        lappend lista [list $nome $prio]
        incr c
    }
    return $lista
}

proc swap_vt {cell vt} {
    # given a cell and its required vth
    # it replace the cell with the required version
    set library_name "CORE65LP${vt}VT"
    set ref_name [get_attribute $cell ref_name]
    set ref_name_split [split $ref_name "_"]
    set current_vt [lindex $ref_name_split 1]
    set update_vt [string replace $current_vt 1 1 $vt]
    lset ref_name_split 1 $update_vt
    set new_ref_name [join $ref_name_split "_"]
    size_cell $cell "${library_name}/${new_ref_name}"
}

proc checkRule {slackThreshold maxPaths} {  
    # return 1 if rule violation

    update_timing -full
    # Check for slack violation
    set critical_path [get_timing_paths]
    foreach cp $critical_path {
        set slack [get_attribute $cp slack]
         if {$slack <= 0 } {
            return 1
        }
    }

    # Check for maxpath violation
    
    set endpoints [add_to_collection [all_outputs] [all_registers -data_pins]]
    foreach_in_collection endpoint $endpoints {
        set paths [get_timing_paths -to $endpoint -nworst $maxPaths -slack_lesser_than $slackThreshold]

        set num_paths [sizeof_collection $paths]
        set endpoint_name [get_object_name $endpoint]
        
        if {$num_paths >= $maxPaths} {
            return 1
        }
    }
    return 0
}

proc forcingSlackOpt {slackThreshold maxPaths perc OPT s_time} { 

    # Optimization (slack)
    # compute priority
    # start changing n_cell/10
    # if no rule violation change other 10% of the cell (otherwise swap back)
    # otherwise halve n. of cell to change
    # if not possible to change even a single cell
    # skip that cell
    # try to change cells until it skips 15 cells consecutivly
    # it try to change 2% or 0.67% simultanously but if error decrease

    # 4'59' in milliseconds
    set MAXTIME 299000

    set sorted_cell [ computeSlack ] 
    set nCell [llength $sorted_cell]
    set nCell_to_change [expr { $nCell/$perc }]
    set offset 0

    while {($nCell_to_change >= 1) && (($offset - 1 + $nCell_to_change) < $nCell)} {

        if { [clock milliseconds] - $s_time > $MAXTIME } {
            break
        }
        puts "SLACK $OPT: Trying to change $nCell_to_change cells simultaneously"
        puts "Starting from position $offset\n"
        set count 0

        while {$count < $nCell_to_change} {
            set ind [ expr { $offset + $count }]
            set cell_s [lindex [lindex $sorted_cell $ind] 1]
            swap_vt $cell_s $OPT
            incr count
        }


        if {[checkRule $slackThreshold $maxPaths] == 1} {
            # Swap back cells if there is a rule violation
            puts "Error: swapping back to LVT $nCell_to_change cells\n"
            set count 0
            
            while {$count < $nCell_to_change} {
                set ind [ expr { $offset + $count }]
                set cell_s [lindex [lindex $sorted_cell $ind] 1]
                swap_vt $cell_s "L"
                incr count
            }
            puts "Halve n_cell_to_change"
            set nCell_to_change [expr { $nCell_to_change/2 }]

        } elseif {$offset / $nCell_to_change >= ($nCell/$nCell_to_change)* 0.5 && [clock milliseconds] - $s_time < $MAXTIME} {
            
            puts "Recompute priority"
            set sorted_cell [computeSlack]
            set nCell [llength $sorted_cell] 
            set offset 0

        } else {
            puts "Done"
            set offset [ expr {$offset + $nCell_to_change}]
        }
    }
    puts "-----------------------------------------------------------------------------\n"
    puts "START FORCING"
    set trial 0
    set nCell_to_change [expr {max(1, int($nCell / 50))}]
    incr offset
    set exit 0

    while { $trial < 15 } {
        if { [clock milliseconds] - $s_time > $MAXTIME } {
            break
        }
        while { $offset - 1 < $nCell - $nCell_to_change } {
            if { [clock milliseconds] - $s_time > $MAXTIME } {
                set exit 1
                break
            }
            puts "\nFORCING SLACK $OPT: Swapping $nCell_to_change from pos $offset"
            set count 0

            while { $count < $nCell_to_change } {
                set ind [expr {$offset + $count}]
                set cell [lindex [lindex $sorted_cell $ind] 1]
                swap_vt $cell $OPT
                incr count
            }
            if { [checkRule $slackThreshold $maxPaths] == 0} {
                set offset [ expr { $offset + $nCell_to_change}]
                set trial 0
                puts "Correct"
            } else {
                puts "Error"
                break
            }
        }
        if { ($offset - 1 < $nCell - $nCell_to_change) && $exit==0} {
            puts "Swapping back"
            set count 0
            while { $count < $nCell_to_change } {
                set ind [expr { $offset + $count }]
                set cell [lindex [lindex $sorted_cell $ind] 1]
                swap_vt $cell "L"
                incr count
            }
            if { $nCell_to_change != 1 } {
                if {$trial > 1 && $nCell_to_change > 3} {
                    set nCell_to_change 2
                } else {
                    set nCell_to_change [expr {max(1, int($nCell_to_change/2))}]
                }
                puts "halving n of cell: $nCell_to_change"
            } else {
                incr trial
                incr offset
                puts "incr trial: $trial"
                if {$trial > 4 || $offset > $nCell/4} {
                    set nCell_to_change 1
                } else {
                    set nCell_to_change [expr {max(1, int($nCell / 150))}]
                }
            }
        } else {
            break
        }
    }
    puts "DONE SLACK"
    return 0
}

proc forcingDeltaOpt {slackThreshold maxPaths perc OPT s_time} {
    
    # Optimization (slack)
    # compute priority
    # start changing n_cell/10
    # if no rule violation change other 10% of the cell (otherwise swap back)
    # otherwise halve n. of cell to change
    # if not possible to change even a single cell
    # skip that cell
    # try to change cells until it skips 10 cells consecutivly
    # it try to change 2% or 0.67% simultanously but if error decrease

    # 4'50" in milliseconds
    set MAXTIME 299000

    set sorted_cell [ computePriority $OPT] 
    set nCell [llength $sorted_cell]
    set nCell_to_change [expr { $nCell/$perc }]
    set offset 0

    while {($nCell_to_change >= 1) && (($offset - 1 + $nCell_to_change) < $nCell)} {

        if { [clock milliseconds] - $s_time > $MAXTIME } {
            break
        }

        # Change a set of $nCell_to_change cells
        puts "\n DELTA $OPT: Trying to change $nCell_to_change cells simultaneously"
        puts "Starting from position $offset\n"
        set count 0
        while {$count < $nCell_to_change} {
            # Take a cell from the ordered list
            set ind [ expr { $offset + $count }]
            set cell_s [lindex [lindex $sorted_cell $ind] 0]
            set cell_s [get_cells $cell_s]
            swap_vt $cell_s $OPT
            incr count
        }


        if {[checkRule $slackThreshold $maxPaths] == 1} {
            # Swap back cells if there is a rule violation
            puts "Error: swapping back to LVT $nCell_to_change cells\n"
            set count 0
 
            while {$count < $nCell_to_change} {

                set ind [ expr { $offset + $count }]
                # puts $ind
                set cell_s [lindex [lindex $sorted_cell $ind] 0 ]
                swap_vt $cell_s "L"
                incr count
            }
            # Halve the number of cells to swap simultaneusly
            puts "Halving the number of cells to change simultaneously\n"
            set nCell_to_change [expr { $nCell_to_change/2 }]

        } elseif {$offset / $nCell_to_change >= ($nCell/$nCell_to_change)* 0.5 && [clock milliseconds] - $s_time < $MAXTIME} {
            # Update priority list if more the 4 group of cells have already been changed ???
            # and it has elapsed less than 280ms ??? since the starting of the algorithm
            puts "Recompute priority"
            set sorted_cell [computePriority $OPT] 
            set nCell [llength $sorted_cell]
            set offset 0
        } else {
            puts "Done"
            set offset [ expr {$offset + $nCell_to_change}]
        }
    }
    puts "-----------------------------------------------------------------------------\n"
    puts "START FORCING"
    set trial 0
    set nCell_to_change [expr {max(1, int($nCell / 50))}]
    incr offset
    set exit 0

    while { $trial < 10 } {
        if { [clock milliseconds] - $s_time > $MAXTIME } {
            break
        }
        while { $offset - 1 < $nCell - $nCell_to_change } {
            if { [clock milliseconds] - $s_time > $MAXTIME } {
                set exit 1
                break
            }
            puts "\n FORCING DELTA $OPT: Swapping $nCell_to_change from pos $offset"

            set count 0
            while { $count < $nCell_to_change } {
                set ind [expr {$offset + $count}]
                set cell [lindex [lindex $sorted_cell $ind] 0]
                set cell [get_cells $cell]
                swap_vt $cell $OPT
                incr count
            }
            if { [checkRule $slackThreshold $maxPaths] == 0} {
                set offset [ expr { $offset + $nCell_to_change}]
                set trial 0
                puts "Correct"
            } else {
                puts "Error"
                break
            }
        }
        if { ($offset - 1 < $nCell - $nCell_to_change) && $exit==0} {
            puts "Swapping back"
            set count 0
            while { $count < $nCell_to_change } {
                set ind [expr { $offset + $count }]
                set cell [lindex [lindex $sorted_cell $ind] 0]
                set cell [get_cells $cell]
                swap_vt $cell "L"
                incr count
            }
            if { $nCell_to_change != 1 } {
                if {$trial > 1 && $nCell_to_change > 3} {
                    set nCell_to_change 2
                } else {
                    set nCell_to_change [expr {max(1, int($nCell_to_change/2))}]
                }
                puts "halving n of cell: $nCell_to_change"
            } else {
                incr trial
                incr offset
                puts "incr trial: $trial"
                if {$trial > 4 || $offset > $nCell/4} {
                    set nCell_to_change 1
                } else {
                    set nCell_to_change [expr {max(1, int($nCell / 150))}]
                }
            }
        } else {
            break
        }
    }

    return 0
}
