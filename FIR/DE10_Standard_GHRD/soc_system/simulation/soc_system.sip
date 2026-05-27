set_global_assignment -entity "soc_system" -library "lib_soc_system" -name IP_TOOL_NAME "Qsys"
set_global_assignment -entity "soc_system" -library "lib_soc_system" -name IP_TOOL_VERSION "20.1"
set_global_assignment -entity "soc_system" -library "lib_soc_system" -name IP_TOOL_ENV "Qsys"
set_global_assignment -library "lib_soc_system" -name SPD_FILE [file join $::quartus(sip_path) "../soc_system.spd"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "../../soc_system.qsys"]

set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "soc_system.vhd"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/altera_avalon_mm_bridge.v"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/soc_system_led_pio.vhd"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/soc_system_jtag_uart.vhd"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/soc_system_hps_0.v"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/soc_system_f2sdram_only_master.vhd"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/soc_system_dipsw_pio.vhd"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/soc_system_button_pio.vhd"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/interrupt_latency_counter.v"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/irq_detector.v"]
set_global_assignment -library "lib_soc_system" -name MISC_FILE [file join $::quartus(sip_path) "submodules/state_machine_counter.v"]
