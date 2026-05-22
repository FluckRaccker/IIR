set_global_assignment -entity "PLL12M288" -library "lib_PLL12M288" -name IP_TOOL_NAME "altera_pll"
set_global_assignment -entity "PLL12M288" -library "lib_PLL12M288" -name IP_TOOL_VERSION "20.1"
set_global_assignment -entity "PLL12M288" -library "lib_PLL12M288" -name IP_TOOL_ENV "mwpim"
set_global_assignment -library "lib_PLL12M288" -name SPD_FILE [file join $::quartus(sip_path) "PLL12M288.spd"]

set_global_assignment -library "lib_PLL12M288" -name MISC_FILE [file join $::quartus(sip_path) "PLL12M288_sim/PLL12M288.vo"]
