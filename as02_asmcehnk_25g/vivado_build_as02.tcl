# AS02MC04 asmcehnk 25G Vivado synth/impl/bitstream build
set script_dir [file normalize [file dirname [info script]]]
cd $script_dir
source [file join $script_dir vivado_generate_project_as02.tcl]
set artifact_dir $project_dir
file mkdir $artifact_dir

reset_run synth_1
launch_runs -jobs 4 synth_1
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "AS02 synthesis failed: $synth_status"
}

reset_run impl_1
launch_runs -jobs 4 -to_step route_design impl_1
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "*Complete*" $impl_status]} {
    error "AS02 implementation failed: $impl_status"
}

open_run impl_1
report_utilization -file [file join $artifact_dir fpga_utilization.rpt]
report_utilization -hierarchical -file [file join $artifact_dir fpga_utilization_hierarchical.rpt]
report_timing_summary -delay_type min_max -max_paths 20 \
    -file [file join $artifact_dir fpga_timing_summary.rpt]
report_cdc -details -file [file join $artifact_dir fpga_cdc.rpt]
report_methodology -file [file join $artifact_dir fpga_methodology.rpt]

set setup_failures [get_timing_paths -quiet -delay_type max -max_paths 1 -slack_lesser_than 0]
set hold_failures [get_timing_paths -quiet -delay_type min -max_paths 1 -slack_lesser_than 0]
if {[llength $setup_failures] || [llength $hold_failures]} {
    error "AS02 routed timing failed; bitstream generation blocked"
}

set bitstream_dir [file join $artifact_dir fpga.runs impl_1]
file mkdir $bitstream_dir
write_bitstream -force -bin_file [file join $bitstream_dir fpga.bit]
if {[llength [get_debug_cores -quiet]]} {
    write_debug_probes -force [file join $bitstream_dir fpga.ltx]
}
puts "AS02 asmcehnk routed timing passed and bitstream build completed: $bitstream_dir/fpga.bit"
