# AS02MC04 asmcehnk 25G Vivado build
#
# AMDUSB4-style build entry point.  This simply delegates to the AS02
# board-specific Vivado flow; Makefile is intentionally not part of this build.

set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir vivado_build_as02.tcl]

