# AS02MC04 asmcehnk 25G Vivado project generator
# AMDUSB4-style layout: ip/, src/
# Run from Vivado Tcl console or batch mode:
#   cd <repository>/as02_asmcehnk_25g
#   source vivado_generate_project_as02.tcl

set script_dir [file normalize [file dirname [info script]]]
set project_name fpga
set project_dir $script_dir
if {[info exists ::env(AS02_PROJECT_DIR)] && $::env(AS02_PROJECT_DIR) ne ""} {
    set project_dir [file normalize $::env(AS02_PROJECT_DIR)]
}
set fpga_part xcku3p-ffvb676-2-e
set fpga_top asmcehnk_as02mc04_top
set src_dir [file join $script_dir src]
set ip_dir [file join $script_dir ip]
set taxi_src_dir [file normalize [file join $script_dir .. third_party taxi src]]
set corundum_eth_dir [file normalize [file join $script_dir .. third_party corundum fpga lib eth rtl]]
set corundum_axis_dir [file normalize [file join $script_dir .. third_party corundum fpga lib eth lib axis rtl]]

if {[llength [get_parts -quiet $fpga_part]] == 0} {
    error "Required FPGA part '$fpga_part' is not installed in this Vivado. Install Kintex UltraScale+ device support before building AS02MC04."
}

proc as02_resolve_path {base rel taxi_src_dir} {
    set p [file normalize [file join $base $rel]]
    if {[file exists $p]} {
        return $p
    }
    set p_slash [string map {\\ /} $p]
    if {[regexp {^(.*/)?lib/taxi/src/(.*)$} $p_slash -> _ tail]} {
        set p2 [file normalize [file join $taxi_src_dir $tail]]
        if {[file exists $p2]} {
            return $p2
        }
    }
    error "Unable to resolve file-list entry '$rel' from '$base' -> '$p'"
}

proc as02_expand_f_file {file_path taxi_src_dir result_var seen_var} {
    upvar $result_var result
    upvar $seen_var seen
    set file_path [file normalize $file_path]
    if {[info exists seen($file_path)]} {
        return
    }
    set seen($file_path) 1
    set base [file dirname $file_path]
    set fh [open $file_path r]
    set data [read $fh]
    close $fh
    foreach raw [split $data "\n"] {
        set line [string trim $raw]
        if {$line eq ""} { continue }
        if {[string match "#*" $line]} { continue }
        set child [as02_resolve_path $base $line $taxi_src_dir]
        if {[string match -nocase "*.f" $child]} {
            as02_expand_f_file $child $taxi_src_dir result seen
        } else {
            lappend result $child
        }
    }
}

proc as02_add_source_or_f {path taxi_src_dir result_var seen_f_var} {
    upvar $result_var result
    upvar $seen_f_var seen_f
    set path [file normalize $path]
    if {[string match -nocase "*.f" $path]} {
        as02_expand_f_file $path $taxi_src_dir result seen_f
    } else {
        lappend result $path
    }
}

# asmcehnk_tlps128_filter is the chip-independent helper formerly bundled
# in the A7 TLP wrapper; keep the helper while excluding the A7 wrapper.
set source_roots [list \
    [file join $src_dir asmcehnk_as02mc04_top.sv] \
    [file join $src_dir fpga.sv] \
    [file join $src_dir fpga_core.sv] \
    [file join $taxi_src_dir cndm rtl cndm_brd_ctrl_i2c.f] \
    [file join $taxi_src_dir eth rtl us taxi_eth_mac_25g_us.f] \
    [file join $taxi_src_dir axis rtl taxi_axis_async_fifo.f] \
    [file join $taxi_src_dir sync rtl taxi_sync_reset.sv] \
    [file join $taxi_src_dir sync rtl taxi_sync_signal.sv] \
    [file join $src_dir asmcehnk_as02_core.sv] \
    [file join $src_dir asmcehnk_com_axis_udp_25g.sv] \
    [file join $src_dir asmcehnk_eth_axis_udp_25g.sv] \
    [file join $src_dir asmcehnk_udp_tx_packetizer_256.v] \
    [file join $corundum_eth_dir eth_axis_rx.v] \
    [file join $corundum_eth_dir eth_axis_tx.v] \
    [file join $corundum_eth_dir udp_complete_64.v] \
    [file join $corundum_eth_dir udp_checksum_gen_64.v] \
    [file join $corundum_eth_dir udp_64.v] \
    [file join $corundum_eth_dir udp_ip_rx_64.v] \
    [file join $corundum_eth_dir udp_ip_tx_64.v] \
    [file join $corundum_eth_dir ip_complete_64.v] \
    [file join $corundum_eth_dir ip_64.v] \
    [file join $corundum_eth_dir ip_eth_rx_64.v] \
    [file join $corundum_eth_dir ip_eth_tx_64.v] \
    [file join $corundum_eth_dir ip_arb_mux.v] \
    [file join $corundum_eth_dir arp.v] \
    [file join $corundum_eth_dir arp_cache.v] \
    [file join $corundum_eth_dir arp_eth_rx.v] \
    [file join $corundum_eth_dir arp_eth_tx.v] \
    [file join $corundum_eth_dir eth_arb_mux.v] \
    [file join $corundum_eth_dir lfsr.v] \
    [file join $corundum_axis_dir arbiter.v] \
    [file join $corundum_axis_dir priority_encoder.v] \
    [file join $corundum_axis_dir axis_adapter.v] \
    [file join $corundum_axis_dir axis_fifo.v] \
    [file join $corundum_axis_dir axis_fifo_adapter.v] \
    [file join $src_dir asmcehnk_fifo.sv] \
    [file join $src_dir asmcehnk_mux.sv] \
    [file join $src_dir asmcehnk_tlps128_filter.sv] \
    [file join $src_dir asmcehnk_tlps128_src_fifo.sv] \
    [file join $src_dir asmcehnk_tlps128_src_elastic_us.sv] \
    [file join $src_dir asmcehnk_tlps128_sink_mux1.sv] \
    [file join $src_dir asmcehnk_pcie_cfg_us.sv] \
    [file join $src_dir asmcehnk_tlps128_dst_fifo_us.sv] \
    [file join $src_dir asmcehnk_pcie_tlp_us.sv] \
    [file join $src_dir asmcehnk_tlps128_bar_controller.sv] \
    [file join $src_dir asmcehnk_tlps128_cfgspace_shadow.sv] \
]

set src_files [list]
array set seen_f {}
foreach s $source_roots {
    as02_add_source_or_f $s $taxi_src_dir src_files seen_f
}

# De-duplicate by basename like Taxi vivado.mk, where later entries win.
array set src_by_base {}
foreach f $src_files {
    set src_by_base([file tail $f]) $f
}
set src_files_uniq [list]
foreach name [lsort [array names src_by_base]] {
    lappend src_files_uniq $src_by_base($name)
}

set xdc_files [list \
    [file join $src_dir asmcehnk_as02mc04.xdc] \
    [file join $taxi_src_dir eth syn vivado taxi_eth_mac_fifo.tcl] \
    [file join $taxi_src_dir axis syn vivado taxi_axis_async_fifo.tcl] \
    [file join $taxi_src_dir ptp syn vivado taxi_ptp_td_leaf.tcl] \
    [file join $taxi_src_dir ptp syn vivado taxi_ptp_td_phc_regs.tcl] \
    [file join $taxi_src_dir ptp syn vivado taxi_ptp_td_rel2tod.tcl] \
    [file join $taxi_src_dir sync syn vivado taxi_sync_reset.tcl] \
    [file join $taxi_src_dir sync syn vivado taxi_sync_signal.tcl] \
]

set xci_files [list \
    [file join $ip_dir bram_bar_zero4k.xci] \
    [file join $ip_dir bram_pcie_cfgspace.xci] \
    [file join $ip_dir drom_pcie_cfgspace_writemask.xci] \
    [file join $ip_dir fifo_1_1_clk2.xci] \
    [file join $ip_dir fifo_129_129_clk1.xci] \
    [file join $ip_dir fifo_134_134_clk1_bar_rdrsp.xci] \
    [file join $ip_dir fifo_134_134_clk2_rxfifo.xci] \
    [file join $ip_dir fifo_134_134_clk2.xci] \
    [file join $ip_dir fifo_141_141_clk1_bar_wr.xci] \
    [file join $ip_dir fifo_34_34.xci] \
    [file join $ip_dir fifo_4_4_clk1_bar_rd1.xci] \
    [file join $ip_dir fifo_43_43_clk2.xci] \
    [file join $ip_dir fifo_49_49_clk2.xci] \
    [file join $ip_dir fifo_64_64_clk1_fifocmd.xci] \
    [file join $ip_dir fifo_64_64.xci] \
    [file join $ip_dir fifo_74_74_clk1_bar_rd1.xci] \
    [file join $ip_dir fifo_32_32_clk2.xci] \
    [file join $ip_dir pcie4_uscale_plus_0.xci] \
]

set ip_tcl_files [list \
    [file join $taxi_src_dir eth rtl us taxi_eth_phy_25g_us_gty_25g_156.tcl] \
]

puts "AS02 asmcehnk source count: [llength $src_files_uniq]"
puts "AS02 asmcehnk root: $script_dir"
puts "Taxi source root: $taxi_src_dir"

file mkdir $project_dir
create_project -force -part $fpga_part $project_name $project_dir
set_property -dict [list \
    default_lib {xil_defaultlib} \
    enable_vhdl_2008 {1} \
    ip_cache_permissions {read write} \
    mem.enable_memory_map_generation {1} \
    simulator_language {Mixed} \
    target_language {Verilog} \
    xpm_libraries {XPM_CDC XPM_MEMORY} \
] [current_project]
add_files -fileset sources_1 $src_files_uniq
add_files -fileset sources_1 [file join $src_dir asmcehnk_header.svh]
set_property file_type {SystemVerilog} [get_files -quiet *.sv]
set_property file_type {Verilog Header} [get_files -quiet *asmcehnk_header.svh]
set_property is_global_include true [get_files -quiet *asmcehnk_header.svh]
set_property include_dirs [list $src_dir] [get_filesets sources_1]
set_property verilog_define [list AS02_DISABLE_STARTUPE2] [get_filesets sources_1]
set_property top $fpga_top [current_fileset]
set_property top_auto_set 0 [get_filesets sources_1]
add_files -fileset constrs_1 $xdc_files
foreach xci $xci_files { import_ip $xci }

# Keep the checked-in UltraScale+ XCI synchronized with the project-owned
# profile that replaces AMDUSB4's hand-edited 7-series core_top parameters.
source [file join $ip_dir pcie4_uscale_plus_0_profile.tcl]
set as02_pcie_ip [get_ips -quiet pcie4_uscale_plus_0]
::as02_pcie_profile::verify $as02_pcie_ip

# Imported asmcehnk FIFO XCIs come from the reusable AMDUSB4/NeTV2 flow. Keep the
# RTL framework untouched, but upgrade/re-target these IP shells to the AS02
# XCKU3P project so Vivado 2024.2 does not lock them to the old A7/75T part.
# This includes the TLP/BAR/shadow BRAM and helper FIFOs from AMDUSB4.  The
# old 7-series PCIe XCI is intentionally not imported; its config fields are
# reference-only and are mapped onto the source-controlled pcie4_uscale_plus_0.xci.
set locked_reusable_ips [get_ips -quiet -filter {IS_LOCKED == 1}]
if {[llength $locked_reusable_ips]} {
    puts "Upgrading imported reusable AMDUSB4 IP for $fpga_part: $locked_reusable_ips"
    upgrade_ip $locked_reusable_ips
}
foreach tcl $ip_tcl_files { source $tcl }

# The AS02 shell instantiates only the low-latency GTY wrappers.  Taxi's shared
# generator also creates the standard-latency pair, so remove those unused IPs
# before saving the project to avoid stale XDC scopes and unnecessary OOC runs.
foreach ip_name {
    taxi_eth_phy_25g_us_gty_full
    taxi_eth_phy_25g_us_gty_ch
} {
    set ip_obj [get_ips -quiet $ip_name]
    if {[llength $ip_obj]} {
        remove_files [get_property IP_FILE $ip_obj]
    }
}

# Top-level generics mirror AMDUSB4's asmcehnk-facing parameters.  Do not add
# Taxi-style shell metadata generics here; AS02 enumeration
# identity lives in the generated UltraScale+ PCIe IP and the asmcehnk CFG
# bridge below.
set params [dict create]
dict set params PARAM_DEVICE_ID 8'd5
dict set params PARAM_VERSION_NUMBER_MAJOR 8'd4
dict set params PARAM_VERSION_NUMBER_MINOR 8'd13
dict set params PARAM_CUSTOM_VALUE 32'hffffffff
dict set params PARAM_LOCAL_MAC 48'h02_00_00_00_00_de
dict set params PARAM_LOCAL_IP 32'hc0a800de
dict set params PARAM_UDP_PORT 16'h6f3a

# PCIe personality now comes from the source-controlled XCI generated from the
# same AS02 settings.  Keep the 7-series pcie_7x_0.xci as reference only; the
# AS02 build imports ip/pcie4_uscale_plus_0.xci directly.

set param_list [list]
dict for {name value} $params {
    lappend param_list $name=$value
}
set_property generic $param_list [get_filesets sources_1]

# The 402.8 MHz SFP1 network domain needs the router's multi-pass timing
# exploration.  This closes the current checksum/staging paths without changing
# Corundum checksum behavior or the reused AMDUSB4 mux protocol.
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]

update_compile_order -fileset sources_1
puts "AS02 asmcehnk Vivado project generated: $project_dir/$project_name.xpr"

