# AS02MC04 PCIe profile/XCI regression

set test_dir [file normalize [file dirname [info script]]]
set project_root [file normalize [file join $test_dir ..]]
set work_root [file normalize [file join $project_root .tmp_pcie_profile]]
if {[info exists ::env(AS02_PCIE_PROFILE_WORK_DIR)] &&
    $::env(AS02_PCIE_PROFILE_WORK_DIR) ne ""} {
    set work_root [file normalize $::env(AS02_PCIE_PROFILE_WORK_DIR)]
}

file delete -force $work_root
file mkdir $work_root

create_project -force pcie_profile_check $work_root -part xcku3p-ffvb676-2-e
import_ip [file join $project_root ip pcie4_uscale_plus_0.xci]

source [file join $project_root ip pcie4_uscale_plus_0_profile.tcl]
set pcie_ip [get_ips -quiet pcie4_uscale_plus_0]

# First verify the source-controlled XCI, then exercise the profile apply path
# used by ip/pcie4_uscale_plus_0.tcl and verify the result again.
::as02_pcie_profile::verify $pcie_ip
::as02_pcie_profile::apply $pcie_ip
::as02_pcie_profile::verify $pcie_ip

generate_target all $pcie_ip
report_ip_status -name as02_pcie_profile_ip_status

set generated_wrapper [file join $work_root pcie_profile_check.gen sources_1 ip \
    pcie4_uscale_plus_0 synth pcie4_uscale_plus_0.v]
if {![file exists $generated_wrapper]} {
    error "Generated PCIe synthesis wrapper is missing: $generated_wrapper"
}

set wrapper_fh [open $generated_wrapper r]
set wrapper_data [read $wrapper_fh]
close $wrapper_fh

foreach expected_text {
    {.PL_LINK_CAP_MAX_LINK_SPEED(4)}
    {.PL_LINK_CAP_MAX_LINK_WIDTH(8)}
    {.AXI4_DATA_WIDTH(256)}
    {.PCIE_ID_IF("FALSE")}
    {.PF0_CLASS_CODE(24'H0C0340)}
    {.PF0_VENDOR_ID(16'H10EE)}
    {.PF0_DEVICE_ID(16'H0666)}
    {.PF0_BAR0_APERTURE_SIZE(9'H005)}
    {.PF0_BAR0_CONTROL(3'H4)}
    {.DSN_CAP_ENABLE("TRUE")}
    {.MSI_EN("TRUE")}
    {.MSIX_EN("FALSE")}
    {.ARI_CAP_ENABLE("FALSE")}
    {.RBAR_ENABLE("FALSE")}
    {.PF0_VC_CAP_ENABLE("FALSE")}
    {.CFG_EXT_IF("FALSE")}
    {.EXTENDED_CFG_EXTEND_INTERFACE_ENABLE("FALSE")}
    {.LEGACY_CFG_EXTEND_INTERFACE_ENABLE("FALSE")}
} {
    if {[string first $expected_text $wrapper_data] < 0} {
        error "Generated PCIe wrapper is missing expected profile mapping: $expected_text"
    }
}

# Exercise the true from-zero path used by ip/pcie4_uscale_plus_0.tcl.  Importing
# the checked-in XCI alone would not catch class-property dependency ordering.
create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip \
    -module_name pcie4_uscale_plus_fresh
set fresh_ip [get_ips -quiet pcie4_uscale_plus_fresh]
::as02_pcie_profile::apply $fresh_ip
::as02_pcie_profile::verify $fresh_ip
generate_target synthesis $fresh_ip

set fresh_wrapper [file join $work_root pcie_profile_check.gen sources_1 ip \
    pcie4_uscale_plus_fresh synth pcie4_uscale_plus_fresh.v]
if {![file exists $fresh_wrapper]} {
    error "Fresh generated PCIe synthesis wrapper is missing: $fresh_wrapper"
}
set fresh_fh [open $fresh_wrapper r]
set fresh_data [read $fresh_fh]
close $fresh_fh
if {[string first {.PF0_CLASS_CODE(24'H0C0340)} $fresh_data] < 0} {
    error "Fresh generated PCIe wrapper did not preserve class 0C0340"
}

puts "AS02_PCIE_PROFILE_TEST_PASS"
close_project
