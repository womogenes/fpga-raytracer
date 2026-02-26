set_param general.maxThreads 16

set partNum xc7k325t-ffg900-2
set dutVariant [lindex $argv 0]
if {$dutVariant eq ""} {
    set dutVariant "fp_add"
}

if {$dutVariant eq "fp_add"} {
    set dutDefine ""
} elseif {$dutVariant eq "fp_add_one_cycle_baseline"} {
    set dutDefine "FP_ADD_ONE_CYCLE_BASELINE"
} elseif {$dutVariant eq "fp_add_one_cycle_opt"} {
    set dutDefine "FP_ADD_ONE_CYCLE_OPT"
} else {
    error "Unsupported DUT variant: $dutVariant"
}

set outputDir [file join obj_test $dutVariant]
file mkdir $outputDir

set sources_sv [concat \
    [glob ./hdl/constants.sv] \
    [glob ./hdl/types/*.sv] \
    [glob ./hdl/pipeline.sv] \
    [glob ./hdl/clock/*.sv] \
    [glob ./hdl/math/clz.sv] \
    [glob ./hdl/math/fp_add.sv] \
    [glob ./hdl/tb/fp_add/*.sv] \
    [glob ./hdl/top_level_test.sv] \
]

if {$dutDefine eq ""} {
    read_verilog -sv $sources_sv
} else {
    read_verilog -sv -define $dutDefine $sources_sv
}

set sources_v [concat \
    [glob -nocomplain ./hdl/hdmi/*.v] \
]
if {[llength $sources_v] > 0} {
    read_verilog $sources_v
}

read_xdc ./xdc/top_level_test.xdc
set_part $partNum

synth_design -top top_level -part $partNum -verbose
report_timing_summary -file $outputDir/post_synth_timing_summary.rpt
report_utilization -file $outputDir/post_synth_util.rpt -hierarchical -hierarchical_depth 8
report_timing -file $outputDir/post_synth_timing.rpt

opt_design
place_design
report_clock_utilization -file $outputDir/clock_util.rpt
if {[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] < 0} {
    puts "Found setup timing violations => running physical optimization"
    phys_opt_design
}

report_utilization -file $outputDir/post_place_util.rpt
report_timing_summary -file $outputDir/post_place_timing_summary.rpt
report_timing -file $outputDir/post_place_timing.rpt

route_design -directive Explore
report_route_status -file $outputDir/post_route_status.rpt
report_utilization -file $outputDir/post_route_util.rpt
report_timing_summary -file $outputDir/post_route_timing_summary.rpt
report_timing -file $outputDir/post_route_timing.rpt
report_power -file $outputDir/post_route_power.rpt
report_drc -file $outputDir/post_imp_drc.rpt
