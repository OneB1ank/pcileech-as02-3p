# AS02MC04 hardware-debug image builder.
#
# This creates an isolated project, enables AS02_HW_DEBUG, inserts one ILA in
# the SFP1/network domain and one ILA in the PCIe user-clock domain, then emits
# fpga_debug.bit and fpga_debug.ltx in the project root.  It never modifies the
# normal fpga.xpr or the source-controlled XDC.

set script_dir [file normalize [file dirname [info script]]]
set debug_project_dir [file join $script_dir .tmp_vivado_debug]
set debug_constraint_dir [file join $debug_project_dir debug_constraints]

proc as02_debug_scalar {name} {
    global as02_debug_scope
    set pattern [format {^%s/%s$} $as02_debug_scope $name]
    set nets [get_nets -hier -regexp $pattern]
    if {[llength $nets] != 1} {
        error "Expected one debug net named '$name', found [llength $nets]: $nets"
    }
    return $nets
}

proc as02_debug_vector_at {scope name width} {
    set pattern [format {^%s/%s\[[0-9]+\]$} $scope $name]
    set nets [lsort -dictionary [get_nets -hier -regexp $pattern]]
    if {[llength $nets] != $width} {
        error "Expected $width debug nets for '$name', found [llength $nets]"
    }
    return $nets
}

proc as02_debug_probe_at {core index scope name width} {
    if {$index > 0} {
        create_debug_port $core probe
    }
    set port [get_debug_ports ${core}/probe${index}]
    set nets [as02_debug_vector_at $scope $name $width]
    set_property PROBE_TYPE DATA_AND_TRIGGER $port
    set_property PORT_WIDTH $width $port
    connect_debug_port $port $nets
}

set ::env(AS02_PROJECT_DIR) $debug_project_dir
source [file join $script_dir vivado_generate_project_as02.tcl]
set_property verilog_define [list AS02_DISABLE_STARTUPE2 AS02_HW_DEBUG] \
    [get_filesets sources_1]

create_ip -name vio -vendor xilinx.com -library ip -module_name as02_net_vio
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {4} \
    CONFIG.C_NUM_PROBE_OUT {0} \
    CONFIG.C_PROBE_IN0_WIDTH {64} \
    CONFIG.C_PROBE_IN1_WIDTH {256} \
    CONFIG.C_PROBE_IN2_WIDTH {128} \
    CONFIG.C_PROBE_IN3_WIDTH {64} \
] [get_ips as02_net_vio]

create_ip -name vio -vendor xilinx.com -library ip -module_name as02_pcie_vio
set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {3} \
    CONFIG.C_NUM_PROBE_OUT {0} \
    CONFIG.C_PROBE_IN0_WIDTH {64} \
    CONFIG.C_PROBE_IN1_WIDTH {256} \
    CONFIG.C_PROBE_IN2_WIDTH {128} \
] [get_ips as02_pcie_vio]

reset_run synth_1
launch_runs -jobs 4 synth_1
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Debug synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
open_run synth_1
set as02_debug_scope [get_cells -hier -filter {REF_NAME == asmcehnk_as02_core}]
if {[llength $as02_debug_scope] != 1} {
    error "Expected one asmcehnk_as02_core instance, found: $as02_debug_scope"
}
set as02_udp_debug_scope [get_cells -hier -filter {REF_NAME == asmcehnk_eth_axis_udp_25g}]
if {[llength $as02_udp_debug_scope] != 1} {
    error "Expected one asmcehnk_eth_axis_udp_25g instance, found: $as02_udp_debug_scope"
}

create_debug_core as02_net_ila ila
set_property C_DATA_DEPTH 2048 [get_debug_cores as02_net_ila]
set_property C_INPUT_PIPE_STAGES 2 [get_debug_cores as02_net_ila]
connect_debug_port [get_debug_ports as02_net_ila/clk] \
    [as02_debug_scalar dbg_net_clk]
as02_debug_probe_at as02_net_ila 0 $as02_debug_scope dbg_net_control 64
as02_debug_probe_at as02_net_ila 1 $as02_debug_scope dbg_net_rx_data 64
as02_debug_probe_at as02_net_ila 2 $as02_debug_scope dbg_net_rx_keep 8
as02_debug_probe_at as02_net_ila 3 $as02_debug_scope dbg_net_tx_data 64
as02_debug_probe_at as02_net_ila 4 $as02_debug_scope dbg_net_tx_keep 8
as02_debug_probe_at as02_net_ila 5 $as02_debug_scope dbg_net_com_rx_data 64
as02_debug_probe_at as02_net_ila 6 $as02_debug_scope dbg_net_com_tx_data 256
as02_debug_probe_at as02_net_ila 7 $as02_udp_debug_scope dbg_udp_control 64
as02_debug_probe_at as02_net_ila 8 $as02_udp_debug_scope dbg_udp_metadata 128
as02_debug_probe_at as02_net_ila 9 $as02_udp_debug_scope dbg_udp_peer 64
as02_debug_probe_at as02_net_ila 10 $as02_udp_debug_scope dbg_udp_counters 256

create_debug_core as02_pcie_ila ila
set_property C_DATA_DEPTH 2048 [get_debug_cores as02_pcie_ila]
set_property C_INPUT_PIPE_STAGES 2 [get_debug_cores as02_pcie_ila]
connect_debug_port [get_debug_ports as02_pcie_ila/clk] \
    [as02_debug_scalar dbg_pcie_clk]
as02_debug_probe_at as02_pcie_ila 0 $as02_debug_scope dbg_pcie_control 64
as02_debug_probe_at as02_pcie_ila 1 $as02_debug_scope dbg_pcie_keep 32
as02_debug_probe_at as02_pcie_ila 2 $as02_debug_scope dbg_pcie_cq_data 256
as02_debug_probe_at as02_pcie_ila 3 $as02_debug_scope dbg_pcie_cq_user 88
as02_debug_probe_at as02_pcie_ila 4 $as02_debug_scope dbg_pcie_cc_data 256
as02_debug_probe_at as02_pcie_ila 5 $as02_debug_scope dbg_pcie_cc_user 33
as02_debug_probe_at as02_pcie_ila 6 $as02_debug_scope dbg_pcie_rq_data 256
as02_debug_probe_at as02_pcie_ila 7 $as02_debug_scope dbg_pcie_rq_user 62
as02_debug_probe_at as02_pcie_ila 8 $as02_debug_scope dbg_pcie_rc_data 256
as02_debug_probe_at as02_pcie_ila 9 $as02_debug_scope dbg_pcie_rc_user 75
as02_debug_probe_at as02_pcie_ila 10 $as02_debug_scope dbg_pcie_counters 256
as02_debug_probe_at as02_pcie_ila 11 $as02_debug_scope dbg_pcie_status 128

report_debug_core
# Save the instrumented design into a copied constraint set.  Calling plain
# save_constraints here would rewrite the linked source XDC files.
file mkdir $debug_constraint_dir
save_constraints_as -dir $debug_constraint_dir \
    -target_constrs_file as02_hw_debug.xdc as02_debug_constrs
set_property CONSTRSET as02_debug_constrs [get_runs impl_1]
if {[info exists ::env(AS02_DEBUG_SYNTH_ONLY)] &&
    $::env(AS02_DEBUG_SYNTH_ONLY) eq "1"} {
    write_checkpoint -force [file join $debug_project_dir fpga_debug_synth.dcp]
    puts "AS02 debug synthesis and ILA insertion complete; implementation skipped."
    return
}
close_design
reset_run impl_1
launch_runs -jobs 4 impl_1 -to_step write_bitstream
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Debug implementation failed: [get_property STATUS [get_runs impl_1]]"
}
open_run impl_1
report_timing_summary -file [file join $script_dir fpga_debug_timing.rpt]
report_utilization -file [file join $script_dir fpga_debug_utilization.rpt]
set setup_path [get_timing_paths -delay_type max -max_paths 1]
set hold_path [get_timing_paths -delay_type min -max_paths 1]
set setup_slack [get_property SLACK $setup_path]
set hold_slack [get_property SLACK $hold_path]
if {$setup_slack < 0.0 || $hold_slack < 0.0} {
    error "Debug image timing failed: setup=$setup_slack ns, hold=$hold_slack ns"
}
write_bitstream -force -bin_file [file join $script_dir fpga_debug.bit]
write_debug_probes -force [file join $script_dir fpga_debug.ltx]
puts "AS02 debug image complete: $script_dir/fpga_debug.bit"
puts "AS02 debug probes complete: $script_dir/fpga_debug.ltx"
