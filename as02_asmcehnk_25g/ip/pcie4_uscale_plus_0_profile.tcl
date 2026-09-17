# AS02MC04 UltraScale+ PCIe configuration profile
#
# This source-controlled dictionary is the AS02 equivalent of the project-owned
# parameter section that AMDUSB4 added to its generated 7-series core_top RTL.
# UltraScale+ applies these values while creating the XCI, then verifies that a
# checked-in XCI still carries the same effective hard-IP personality.

namespace eval ::as02_pcie_profile {
    variable profile_name {as02_amdusb4_style_profile_v1}

    # -------------------------------------------------------------------------
    # 7-series-style key parameter section
    # -------------------------------------------------------------------------
    # These project-owned names mirror the role of AMDUSB4's customized
    # pcie_7x_0_core_top parameter block.  The dictionary below maps every value
    # onto the supported UltraScale+ PCIe4 IP property.
    variable PCIE_ID_IF {false}
    variable CFG_VEND_ID {10EE}
    variable CFG_DEV_ID {0666}
    variable CFG_REV_ID {02}
    variable CFG_SUBSYS_VEND_ID {10EE}
    variable CFG_SUBSYS_ID {0007}
    # Keep the proven PCILeech VID/DID and BAR envelope, but use the active
    # AMDUSB4 serial-bus/USB class instead of the stale network-class default.
    variable CLASS_CODE {0C0340}

    variable LINK_CAP_MAX_LINK_SPEED {8.0_GT/s}
    variable LINK_CAP_MAX_LINK_WIDTH {X8}
    variable C_DATA_WIDTH {256_bit}
    variable USER_CLK_FREQ {250}
    variable DEV_CAP_MAX_PAYLOAD_SUPPORTED {512_bytes}
    variable DEV_CAP_EXT_TAG_SUPPORTED {true}

    variable BAR0_ENABLED {true}
    variable BAR0_TYPE {Memory}
    variable BAR0_64BIT {false}
    variable BAR0_PREFETCHABLE {false}
    variable BAR0_SCALE {Kilobytes}
    variable BAR0_SIZE {4}

    variable MSI_CAP_ON {true}
    variable MSI_CAP_MULTIMSGCAP {1_vector}
    variable MSI_CAP_PER_VECTOR_MASKING_CAPABLE {false}
    variable MSIX_CAP_ON {false}
    variable DSN_CAP_ON {true}
    variable AER_CAP_ON {false}
    variable AER_CAP_ECRC_GEN_AND_CHECK_CAPABLE {false}
    variable PM_CAP_PMESUPPORT_D0 {false}
    variable PM_CAP_PMESUPPORT_D1 {false}
    variable PM_CAP_PMESUPPORT_D3HOT {false}
    variable PM_CAP_D1SUPPORT {false}
    variable VC_CAP_ON {false}
    variable RBAR_CAP_ON {false}
    variable ARI_CAP_ON {false}
    variable SRIOV_CAP_ON {false}
    variable VSEC_CAP_ON {false}
    variable EXT_CFG_CAP_ON {false}
    variable LEGACY_EXT_CFG_CAP_ON {false}
    # The active AS02 RTL consumes cfg_mgmt and raw-TLP shadow paths.  Keep the
    # generated extended-CFG ports disabled until a dedicated adapter is wired;
    # this prevents an unconnected optional interface from entering the build.
    variable CFG_EXT_IF {false}

    # Vivado's lookup assistant does not expose programming interface 40h.
    # Seed its descriptive menu fields with the closest USB category, then
    # disable the assistant and make the raw 0C/03/40 fields authoritative.
    variable class_menu_metadata [dict create \
        CONFIG.pf0_base_class_menu {Serial_bus_controllers} \
        CONFIG.pf0_sub_class_interface_menu {Universal_Serial_Bus_with_no_specific_programming_interface} \
    ]

    # Apply these only after the lookup assistant is disabled.  Vivado ignores
    # raw class fields when they share one set_property transaction with the
    # assistant transition.
    variable class_code_properties [dict create \
        CONFIG.PF0_Use_Class_Code_Lookup_Assistant {false} \
        CONFIG.pf0_class_code_base {0C} \
        CONFIG.pf0_class_code_sub {03} \
        CONFIG.pf0_class_code_interface {40} \
        CONFIG.PF0_CLASS_CODE $CLASS_CODE \
    ]

    # -------------------------------------------------------------------------
    # UltraScale+ XCI property mapping
    # -------------------------------------------------------------------------
    variable properties [dict create \
        CONFIG.pcie_id_if $PCIE_ID_IF \
        CONFIG.PL_LINK_CAP_MAX_LINK_SPEED $LINK_CAP_MAX_LINK_SPEED \
        CONFIG.PL_LINK_CAP_MAX_LINK_WIDTH $LINK_CAP_MAX_LINK_WIDTH \
        CONFIG.AXISTEN_IF_RC_STRADDLE {false} \
        CONFIG.axisten_if_enable_client_tag {true} \
        CONFIG.axisten_if_width $C_DATA_WIDTH \
        CONFIG.axisten_freq $USER_CLK_FREQ \
        CONFIG.extended_tag_field $DEV_CAP_EXT_TAG_SUPPORTED \
        CONFIG.pf0_dev_cap_max_payload $DEV_CAP_MAX_PAYLOAD_SUPPORTED \
        CONFIG.vendor_id $CFG_VEND_ID \
        CONFIG.PF0_DEVICE_ID $CFG_DEV_ID \
        CONFIG.PF0_REVISION_ID $CFG_REV_ID \
        CONFIG.PF0_SUBSYSTEM_VENDOR_ID $CFG_SUBSYS_VEND_ID \
        CONFIG.PF0_SUBSYSTEM_ID $CFG_SUBSYS_ID \
        CONFIG.pf0_bar0_enabled $BAR0_ENABLED \
        CONFIG.pf0_bar0_type $BAR0_TYPE \
        CONFIG.pf0_bar0_64bit $BAR0_64BIT \
        CONFIG.pf0_bar0_prefetchable $BAR0_PREFETCHABLE \
        CONFIG.pf0_bar0_scale $BAR0_SCALE \
        CONFIG.pf0_bar0_size $BAR0_SIZE \
        CONFIG.pf0_msi_enabled $MSI_CAP_ON \
        CONFIG.PF0_MSI_CAP_MULTIMSGCAP $MSI_CAP_MULTIMSGCAP \
        CONFIG.en_msi_per_vec_masking $MSI_CAP_PER_VECTOR_MASKING_CAPABLE \
        CONFIG.pf0_msix_enabled $MSIX_CAP_ON \
        CONFIG.pf0_dsn_enabled $DSN_CAP_ON \
        CONFIG.pf0_aer_enabled $AER_CAP_ON \
        CONFIG.PF0_AER_CAP_ECRC_GEN_AND_CHECK_CAPABLE $AER_CAP_ECRC_GEN_AND_CHECK_CAPABLE \
        CONFIG.PF0_PM_CAP_PMESUPPORT_D0 $PM_CAP_PMESUPPORT_D0 \
        CONFIG.PF0_PM_CAP_PMESUPPORT_D1 $PM_CAP_PMESUPPORT_D1 \
        CONFIG.PF0_PM_CAP_PMESUPPORT_D3HOT $PM_CAP_PMESUPPORT_D3HOT \
        CONFIG.PF0_PM_CAP_SUPP_D1_STATE $PM_CAP_D1SUPPORT \
        CONFIG.pf0_vc_cap_enabled $VC_CAP_ON \
        CONFIG.rbar_enable $RBAR_CAP_ON \
        CONFIG.pf0_ari_enabled $ARI_CAP_ON \
        CONFIG.SRIOV_CAP_ENABLE $SRIOV_CAP_ON \
        CONFIG.ext_xvc_vsec_enable $VSEC_CAP_ON \
        CONFIG.ext_pcie_cfg_space_enabled $EXT_CFG_CAP_ON \
        CONFIG.legacy_ext_pcie_cfg_space_enabled $LEGACY_EXT_CFG_CAP_ON \
        CONFIG.cfg_ext_if $CFG_EXT_IF \
        CONFIG.mode_selection {Advanced} \
        CONFIG.en_gt_selection {true} \
        CONFIG.select_quad {GTY_Quad_225} \
    ]
}

proc ::as02_pcie_profile::apply {ip_obj} {
    variable profile_name
    variable class_menu_metadata
    variable class_code_properties
    variable properties

    if {[llength $ip_obj] != 1} {
        error "AS02 PCIe profile '$profile_name' requires exactly one IP object"
    }

    set class_properties [dict merge $class_menu_metadata $class_code_properties]
    set class_update_required false
    dict for {property expected} $class_properties {
        if {[string tolower [string trim [get_property $property $ip_obj]]] ne
            [string tolower [string trim $expected]]} {
            set class_update_required true
            break
        }
    }

    if {$class_update_required} {
        set_property CONFIG.PF0_Use_Class_Code_Lookup_Assistant true $ip_obj
        set_property -dict $class_menu_metadata $ip_obj
        set_property CONFIG.PF0_Use_Class_Code_Lookup_Assistant false $ip_obj
        set_property -dict $class_code_properties $ip_obj
    }
    set_property -dict $properties $ip_obj
}

proc ::as02_pcie_profile::verify {ip_obj} {
    variable profile_name
    variable class_menu_metadata
    variable class_code_properties
    variable properties

    if {[llength $ip_obj] != 1} {
        error "AS02 PCIe profile '$profile_name' requires exactly one IP object"
    }

    set expected_properties [dict merge $class_menu_metadata $class_code_properties $properties]
    set mismatches [list]
    dict for {property expected} $expected_properties {
        set actual [get_property $property $ip_obj]
        set expected_norm [string tolower [string trim $expected]]
        set actual_norm [string tolower [string trim $actual]]
        if {$actual_norm ne $expected_norm} {
            lappend mismatches "$property expected=$expected actual=$actual"
        }
    }

    if {[llength $mismatches]} {
        error "AS02 PCIe profile '$profile_name' mismatch:\n  [join $mismatches \"\n  \"]"
    }

    puts "AS02 PCIe profile verified: $profile_name ([dict size $expected_properties] properties)"
}
