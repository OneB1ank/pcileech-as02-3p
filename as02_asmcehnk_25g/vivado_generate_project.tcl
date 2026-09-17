# AS02MC04 asmcehnk 25G Vivado project generator
#
# AMDUSB4-style entry point.  The board-specific implementation is kept in
# vivado_generate_project_as02.tcl, but scripts/users can now use the same
# canonical command shape as AMDUSB4:
#
#   vivado -nojournal -nolog -mode batch -source vivado_generate_project.tcl
#   # or from Vivado Tcl console:
#   source vivado_generate_project.tcl

set script_dir [file normalize [file dirname [info script]]]
source [file join $script_dir vivado_generate_project_as02.tcl]

