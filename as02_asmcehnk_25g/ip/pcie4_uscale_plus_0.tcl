set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir pcie4_uscale_plus_0_profile.tcl]

create_ip -name pcie4_uscale_plus -vendor xilinx.com -library ip -module_name pcie4_uscale_plus_0

set pcie_ip [get_ips pcie4_uscale_plus_0]
::as02_pcie_profile::apply $pcie_ip
::as02_pcie_profile::verify $pcie_ip
