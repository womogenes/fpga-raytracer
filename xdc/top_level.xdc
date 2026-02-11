# Genesys 2: 200 MHz SYSCLK_P/N, divided-by-2 to 100 MHz (gclk)

set_property -dict {PACKAGE_PIN AD12 IOSTANDARD LVDS} [get_ports {sysclk_p}]
set_property -dict {PACKAGE_PIN AD11 IOSTANDARD LVDS} [get_ports {sysclk_n}]
create_clock -add -name sysclk -period 5.000 -waveform {0 2.5} [get_ports {sysclk_p}]
create_generated_clock -add -name gclk -source [get_ports {sysclk_p}] -divide_by 2 [get_pins {sysclk_div2/O}]

# Set Bank 0 voltage
#set_property CFGBVS VCCO [current_design]
#set_property CONFIG_VOLTAGE 3.3 [current_design]

# new for week 6: avoid having Vivado freak out about clock domain crossing!

set_max_delay -datapath_only 6 -from [get_clocks clk_controller_clk_wiz_0] -to [get_clocks clk_pixel_cw_hdmi]
set_max_delay -datapath_only 6 -from [get_clocks clk_pixel_cw_hdmi] -to [get_clocks clk_controller_clk_wiz_0]
set_max_delay -datapath_only 6 -from [get_clocks clk_controller_clk_wiz_0] -to [get_clocks clk_passthrough_clk_wiz_0]
set_max_delay -datapath_only 6 -from [get_clocks clk_passthrough_clk_wiz_0] -to [get_clocks clk_controller_clk_wiz_0]

# Allow combinational loop for ring oscillator RNG
# TODO: clean this up

set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/prng_sphere/ro_sampler/ro_array[3].n1]

set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/tracer/ray_reflect/rng8/ro_sampler/ro_array[3].n1]

set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_u/ro_sampler/ro_array[3].n1]

set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[0].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[1].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[2].n1]
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets my_rtx/caster/maker/rng8_v/ro_sampler/ro_array[3].n1]

# USER GREEN LEDS
set_property -dict { PACKAGE_PIN T28   IOSTANDARD LVCMOS25 } [get_ports { led[0] }]; #IO_L15P_T2_DQS_13 Sch=led[0]
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS25 } [get_ports { led[1] }]; #IO_L15N_T2_DQS_13 Sch=led[1]
set_property -dict { PACKAGE_PIN U30   IOSTANDARD LVCMOS25 } [get_ports { led[2] }]; #IO_L17P_T2_13 Sch=led[2]
set_property -dict { PACKAGE_PIN U29   IOSTANDARD LVCMOS25 } [get_ports { led[3] }]; #IO_L17N_T2_13 Sch=led[3]
set_property -dict { PACKAGE_PIN V20   IOSTANDARD LVCMOS25 } [get_ports { led[4] }]; #IO_L14N_T2_SRCC_13 Sch=led[4]
set_property -dict { PACKAGE_PIN V26   IOSTANDARD LVCMOS25 } [get_ports { led[5] }]; #IO_L16N_T2_13 Sch=led[5]
set_property -dict { PACKAGE_PIN W24   IOSTANDARD LVCMOS25 } [get_ports { led[6] }]; #IO_L16P_T2_13 Sch=led[6]
set_property -dict { PACKAGE_PIN W23   IOSTANDARD LVCMOS25 } [get_ports { led[7] }]; #IO_L5P_T0_13 Sch=led[7]

## USER PUSH BUTTON
set_property -dict { PACKAGE_PIN E18 IOSTANDARD LVCMOS12 } [get_ports { "btn[0]" }]; #IO_L20N_T3_16 Sch=btnc
set_property -dict { PACKAGE_PIN M19 IOSTANDARD LVCMOS12 } [get_ports { "btn[1]" }]; #IO_L22N_T3_16 Sch=btnd
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS12 } [get_ports { "btn[2]" }]; #IO_L20P_T3_16 Sch=btnl
set_property -dict { PACKAGE_PIN C19 IOSTANDARD LVCMOS12 } [get_ports { "btn[3]" }]; #IO_L6P_T0_16 Sch=btnr
set_property -dict { PACKAGE_PIN B19 IOSTANDARD LVCMOS12 } [get_ports { "btn[4]" }]; #IO_0_16 Sch=btnu

## USER SLIDE SWITCH
set_property -dict { PACKAGE_PIN G19  IOSTANDARD LVCMOS12 } [get_ports { sw[0] }]; #IO_L22P_T3_16 Sch=sw[0]
set_property -dict { PACKAGE_PIN G25  IOSTANDARD LVCMOS12 } [get_ports { sw[1] }]; #IO_25_16 Sch=sw[1]
set_property -dict { PACKAGE_PIN H24  IOSTANDARD LVCMOS12 } [get_ports { sw[2] }]; #IO_L24P_T3_16 Sch=sw[2]
set_property -dict { PACKAGE_PIN K19  IOSTANDARD LVCMOS12 } [get_ports { sw[3] }]; #IO_L24N_T3_16 Sch=sw[3]
set_property -dict { PACKAGE_PIN N19  IOSTANDARD LVCMOS12 } [get_ports { sw[4] }]; #IO_L6P_T0_15 Sch=sw[4]
set_property -dict { PACKAGE_PIN P19  IOSTANDARD LVCMOS12 } [get_ports { sw[5] }]; #IO_0_15 Sch=sw[5]
set_property -dict { PACKAGE_PIN P26  IOSTANDARD LVCMOS12 } [get_ports { sw[6] }]; #IO_L19P_T3_A22_15 Sch=sw[6]
set_property -dict { PACKAGE_PIN P27  IOSTANDARD LVCMOS12 } [get_ports { sw[7] }]; #IO_25_15 Sch=sw[7]


# PMOD A Signals

set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[0]" ]
set_property -dict {PACKAGE_PIN F15 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[1]" ]
set_property -dict {PACKAGE_PIN H13 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[2]" ]
set_property -dict {PACKAGE_PIN H14 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[3]" ]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[4]" ]
set_property -dict {PACKAGE_PIN J14 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[5]" ]
set_property -dict {PACKAGE_PIN E14 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[6]" ]
set_property -dict {PACKAGE_PIN E15 IOSTANDARD LVCMOS33}  [ get_ports "pmoda[7]" ]

# PMOD B Signals
##fixed K14 and J15 which were a copy-paste and wrong.
#set_property -dict {PACKAGE_PIN H18 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[0]" ]
#set_property -dict {PACKAGE_PIN G18 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[1]" ]
#set_property -dict {PACKAGE_PIN K14 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[2]" ]
#set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[3]" ]
#set_property -dict {PACKAGE_PIN H16 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[4]" ]
#set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[5]" ]
#set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[6]" ]
#set_property -dict {PACKAGE_PIN J16 IOSTANDARD LVCMOS33}  [ get_ports "pmodb[7]" ]

# PMOD AB Signals
#set_property -dict {PACKAGE_PIN D11 IOSTANDARD LVCMOS33} [get_ports {jab[0]}]
#set_property -dict {PACKAGE_PIN C12 IOSTANDARD LVCMOS33} [get_ports {jab[1]}]
#set_property -dict {PACKAGE_PIN E16 IOSTANDARD LVCMOS33} [get_ports {jab[2]}]
#set_property -dict {PACKAGE_PIN G16 IOSTANDARD LVCMOS33} [get_ports {jab[3]}]
#set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {jab[4]}]
#set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports {jab[5]}]


#HDMI Signals
set_property -dict { PACKAGE_PIN AB20    IOSTANDARD TMDS_33  } [get_ports {hdmi_clk_n}]
set_property -dict { PACKAGE_PIN AA20    IOSTANDARD TMDS_33  } [get_ports {hdmi_clk_p}]
set_property -dict { PACKAGE_PIN AC21    IOSTANDARD TMDS_33  } [get_ports {hdmi_tx_n[0]}]
set_property -dict { PACKAGE_PIN AA23   IOSTANDARD TMDS_33  } [get_ports {hdmi_tx_n[1]}]
set_property -dict { PACKAGE_PIN AC25   IOSTANDARD TMDS_33  } [get_ports {hdmi_tx_n[2]}]
set_property -dict { PACKAGE_PIN AC20    IOSTANDARD TMDS_33  } [get_ports {hdmi_tx_p[0]}]
set_property -dict { PACKAGE_PIN AA22   IOSTANDARD TMDS_33  } [get_ports {hdmi_tx_p[1]}]
set_property -dict { PACKAGE_PIN AB24   IOSTANDARD TMDS_33  } [get_ports {hdmi_tx_p[2]}]

# PWM audio out signals
#change G15 to B13 and E13 to B14
#set_property PACKAGE_PIN B13 [ get_ports "spkl"]
#set_property PACKAGE_PIN B14 [ get_ports "spkr"]
#set_property IOSTANDARD LVCMOS33 [ get_ports "spk*"]

# PWM Microphone signals
#set_property -dict {PACKAGE_PIN E12 IOSTANDARD LVCMOS33} [get_ports {mic_clk}]
#set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports {mic_data}]



# UART over micro-USB signals
# labeled from the perspective of the FPGA!
# note the inversion from RealDigital official documentation.
set_property -dict {PACKAGE_PIN Y20  IOSTANDARD LVCMOS33} [get_ports {uart_rxd}]
set_property -dict {PACKAGE_PIN Y23 IOSTANDARD LVCMOS33} [get_ports {uart_txd}]

# MICRO SD SPI signals
# set_property -dict {PACKAGE_PIN M16 IOSTANDARD LVCMOS33} [get_ports {sd_cipo}]
# set_property -dict {PACKAGE_PIN N18 IOSTANDARD LVCMOS33} [get_ports {sd_cs}]
# set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports {sd_copi}]
# set_property -dict {PACKAGE_PIN P18 IOSTANDARD LVCMOS33} [get_ports {sd_dclk}]

############## NET - IOSTANDARD ##################
### Pins below are for the DDR3
### Remove the first column of comments in one block to activate all appropriate pins

## PadFunction: IO_L1N_T0_34 (SCHEMATIC DDR_DQ0)
current_instance -quiet
set_property SLEW FAST [get_ports {ddr3_dq[0]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[0]}]
set_property PACKAGE_PIN E3 [get_ports {ddr3_dq[0]}]

# PadFunction: IO_L2P_T0_34 (SCHEMATIC DDR_DQ1)
set_property SLEW FAST [get_ports {ddr3_dq[1]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[1]}]
set_property PACKAGE_PIN F7 [get_ports {ddr3_dq[1]}]

# PadFunction: IO_L2N_T0_34 (SCHEMATIC DDR_DQ2)
set_property SLEW FAST [get_ports {ddr3_dq[2]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[2]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[2]}]
set_property PACKAGE_PIN F2 [get_ports {ddr3_dq[2]}]

# PadFunction: IO_L4P_T0_34 (SCHEMATIC DDR_DQ3)
set_property SLEW FAST [get_ports {ddr3_dq[3]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[3]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[3]}]
set_property PACKAGE_PIN F8 [get_ports {ddr3_dq[3]}]

# PadFunction: IO_L4N_T0_34 (SCHEMATIC DDR_DQ4)
set_property SLEW FAST [get_ports {ddr3_dq[4]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[4]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[4]}]
set_property PACKAGE_PIN H3 [get_ports {ddr3_dq[4]}]

# PadFunction: IO_L5P_T0_34 (SCHEMATIC DDR_DQ5)
set_property SLEW FAST [get_ports {ddr3_dq[5]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[5]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[5]}]
set_property PACKAGE_PIN H8 [get_ports {ddr3_dq[5]}]

# PadFunction: IO_L5N_T0_34 (SCHEMATIC DDR_DQ6)
set_property SLEW FAST [get_ports {ddr3_dq[6]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[6]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[6]}]
set_property PACKAGE_PIN G2 [get_ports {ddr3_dq[6]}]

# PadFunction: IO_L6P_T0_34 (SCHEMATIC DDR_DQ7)
set_property SLEW FAST [get_ports {ddr3_dq[7]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[7]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[7]}]
set_property PACKAGE_PIN H7 [get_ports {ddr3_dq[7]}]

# PadFunction: IO_L7N_T1_34 (SCHEMATIC DDR_DQ8)
set_property SLEW FAST [get_ports {ddr3_dq[8]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[8]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[8]}]
set_property PACKAGE_PIN D7 [get_ports {ddr3_dq[8]}]

# PadFunction: IO_L8P_T1_34 (SCHEMATIC DDR_DQ9)
set_property SLEW FAST [get_ports {ddr3_dq[9]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[9]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[9]}]
set_property PACKAGE_PIN C3 [get_ports {ddr3_dq[9]}]

# PadFunction: IO_L8N_T1_34 (SCHEMATIC DDR_DQ10)
set_property SLEW FAST [get_ports {ddr3_dq[10]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[10]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[10]}]
set_property PACKAGE_PIN C8 [get_ports {ddr3_dq[10]}]

# PadFunction: IO_L10P_T1_34 (SCHEMATIC DDR_DQ11)
set_property SLEW FAST [get_ports {ddr3_dq[11]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[11]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[11]}]
set_property PACKAGE_PIN C2 [get_ports {ddr3_dq[11]}]

# PadFunction: IO_L10N_T1_34 (SCHEMATIC DDR_DQ12)
set_property SLEW FAST [get_ports {ddr3_dq[12]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[12]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[12]}]
set_property PACKAGE_PIN A7 [get_ports {ddr3_dq[12]}]

# PadFunction: IO_L11P_T1_SRCC_34 (SCHEMATIC DDR_DQ13)
set_property SLEW FAST [get_ports {ddr3_dq[13]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[13]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[13]}]
set_property PACKAGE_PIN A2 [get_ports {ddr3_dq[13]}]

# PadFunction: IO_L11N_T1_SRCC_34 (SCHEMATIC DDR_DQ14)
set_property SLEW FAST [get_ports {ddr3_dq[14]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[14]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[14]}]
set_property PACKAGE_PIN B8 [get_ports {ddr3_dq[14]}]

# PadFunction: IO_L12P_T1_MRCC_34 (SCHEMATIC DDR_DQ15)
set_property SLEW FAST [get_ports {ddr3_dq[15]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dq[15]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dq[15]}]
set_property PACKAGE_PIN A3 [get_ports {ddr3_dq[15]}]

# PadFunction: IO_L13P_T2_MRCC_34 (SCHEMATIC DDR_A14)
#set_property SLEW FAST [get_ports {ddr3_addr[14]}]
#set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[14]}]
#set_property PACKAGE_PIN R6 [get_ports {ddr3_addr[14]}]

# PadFunction: IO_L13N_T2_MRCC_34 (SCHEMATIC DDR_A13)
set_property SLEW FAST [get_ports {ddr3_addr[13]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[13]}]
set_property PACKAGE_PIN T7 [get_ports {ddr3_addr[13]}]

# PadFunction: IO_L14P_T2_SRCC_34 (SCHEMATIC DDR_A12)
set_property SLEW FAST [get_ports {ddr3_addr[12]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[12]}]
set_property PACKAGE_PIN T3 [get_ports {ddr3_addr[12]}]

# PadFunction: IO_L14N_T2_SRCC_34 (SCHEMATIC DDR_A11)
set_property SLEW FAST [get_ports {ddr3_addr[11]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[11]}]
set_property PACKAGE_PIN N7 [get_ports {ddr3_addr[11]}]

# PadFunction: IO_L15P_T2_DQS_34 (SCHEMATIC DDR_A10)
set_property SLEW FAST [get_ports {ddr3_addr[10]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[10]}]
set_property PACKAGE_PIN R7 [get_ports {ddr3_addr[10]}]

# PadFunction: IO_L15N_T2_DQS_34 (SCHEMATIC DDR_A9)
set_property SLEW FAST [get_ports {ddr3_addr[9]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[9]}]
set_property PACKAGE_PIN L7 [get_ports {ddr3_addr[9]}]

# PadFunction: IO_L16P_T2_34 (SCHEMATIC DDR_A8)
set_property SLEW FAST [get_ports {ddr3_addr[8]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[8]}]
set_property PACKAGE_PIN R3 [get_ports {ddr3_addr[8]}]

# PadFunction: IO_L16N_T2_34 (SCHEMATIC DDR_A7)
set_property SLEW FAST [get_ports {ddr3_addr[7]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[7]}]
set_property PACKAGE_PIN T8 [get_ports {ddr3_addr[7]}]

# PadFunction: IO_L17P_T2_34 (SCHEMATIC DDR_A6)
set_property SLEW FAST [get_ports {ddr3_addr[6]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[6]}]
set_property PACKAGE_PIN R2 [get_ports {ddr3_addr[6]}]

# PadFunction: IO_L17N_T2_34 (SCHEMATIC DDR_A5)
set_property SLEW FAST [get_ports {ddr3_addr[5]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[5]}]
set_property PACKAGE_PIN R8 [get_ports {ddr3_addr[5]}]

# PadFunction: IO_L18P_T2_34 (SCHEMATIC DDR_A4)
set_property SLEW FAST [get_ports {ddr3_addr[4]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[4]}]
set_property PACKAGE_PIN P2 [get_ports {ddr3_addr[4]}]

# PadFunction: IO_L18N_T2_34 (SCHEMATIC DDR_A3)
set_property SLEW FAST [get_ports {ddr3_addr[3]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[3]}]
set_property PACKAGE_PIN P8 [get_ports {ddr3_addr[3]}]

# PadFunction: IO_L19P_T3_34 (SCHEMATIC DDR_A2)
set_property SLEW FAST [get_ports {ddr3_addr[2]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[2]}]
set_property PACKAGE_PIN N2 [get_ports {ddr3_addr[2]}]

# PadFunction: IO_L19N_T3_VREF_34 (SCHEMATIC DDR_A1)
set_property SLEW FAST [get_ports {ddr3_addr[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[1]}]
set_property PACKAGE_PIN P3 [get_ports {ddr3_addr[1]}]

# PadFunction: IO_L20P_T3_34 (SCHEMATIC DDR_A0)
set_property SLEW FAST [get_ports {ddr3_addr[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_addr[0]}]
set_property PACKAGE_PIN P7 [get_ports {ddr3_addr[0]}]

# PadFunction: IO_L20N_T3_34 (SCHEMATIC DDR_BA2)
set_property SLEW FAST [get_ports {ddr3_ba[2]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_ba[2]}]
set_property PACKAGE_PIN M3 [get_ports {ddr3_ba[2]}]

# PadFunction: IO_L22P_T3_34 (SCHEMATIC DDR_BA1)
set_property SLEW FAST [get_ports {ddr3_ba[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_ba[1]}]
set_property PACKAGE_PIN N8 [get_ports {ddr3_ba[1]}]

# PadFunction: IO_L22N_T3_34 (SCHEMATIC DDR_BA0)
set_property SLEW FAST [get_ports {ddr3_ba[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_ba[0]}]
set_property PACKAGE_PIN M2 [get_ports {ddr3_ba[0]}]

# PadFunction: IO_L23P_T3_34 (SCHEMATIC DDR_RAS_B
set_property SLEW FAST [get_ports ddr3_ras_n]
set_property IOSTANDARD SSTL135 [get_ports ddr3_ras_n]
set_property PACKAGE_PIN J3 [get_ports ddr3_ras_n]

# PadFunction: IO_L23N_T3_34 (SCHEMATIC DDR_CAS_B)
set_property SLEW FAST [get_ports ddr3_cas_n]
set_property IOSTANDARD SSTL135 [get_ports ddr3_cas_n]
set_property PACKAGE_PIN K3 [get_ports ddr3_cas_n]

# PadFunction: IO_L24P_T3_34 (SCHEMATIC DDR_WE_B)
set_property SLEW FAST [get_ports ddr3_we_n]
set_property IOSTANDARD SSTL135 [get_ports ddr3_we_n]
set_property PACKAGE_PIN L3 [get_ports ddr3_we_n]

# PadFunction: IO_L6N_T0_VREF_34 (SCHEMATIC DDR_RESET_B)
set_property SLEW FAST [get_ports ddr3_reset_n]
set_property IOSTANDARD SSTL135 [get_ports ddr3_reset_n]
set_property PACKAGE_PIN T2 [get_ports ddr3_reset_n]

# PadFunction: IO_L24N_T3_34 (SCHEMATIC DDR_CKE)
set_property SLEW FAST [get_ports {ddr3_clke}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_clke}]
set_property PACKAGE_PIN K9 [get_ports {ddr3_clke}]

# PadFunction: IO_25_34 (SCHEMATIC DDR_ODT)
set_property SLEW FAST [get_ports {ddr3_odt}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_odt}]
set_property PACKAGE_PIN K1 [get_ports {ddr3_odt}]

# PadFunction: IO_L1P_T0_34 (SCHEMATIC DDR_LDM)
set_property SLEW FAST [get_ports {ddr3_dm[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dm[0]}]
set_property PACKAGE_PIN E7 [get_ports {ddr3_dm[0]}]

# PadFunction: IO_L7P_T1_34 (SCHEMATIC DDR_UDM)
set_property SLEW FAST [get_ports {ddr3_dm[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddr3_dm[1]}]
set_property PACKAGE_PIN D3 [get_ports {ddr3_dm[1]}]

# PadFunction: IO_L3P_T0_DQS_34 (SCHEMATIC DDR_LDQS_P)
set_property SLEW FAST [get_ports {ddr3_dqs_p[0]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dqs_p[0]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddr3_dqs_p[0]}]

# PadFunction: IO_L3N_T0_DQS_34 (SCHEMATIC DDR_LDQS_N)
set_property SLEW FAST [get_ports {ddr3_dqs_n[0]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dqs_n[0]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddr3_dqs_n[0]}]
set_property PACKAGE_PIN F3 [get_ports {ddr3_dqs_p[0]}]
set_property PACKAGE_PIN G3 [get_ports {ddr3_dqs_n[0]}]

# PadFunction: IO_L9P_T1_DQS_34 (SCHEMATIC DDR_UDQS_P)
set_property SLEW FAST [get_ports {ddr3_dqs_p[1]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dqs_p[1]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddr3_dqs_p[1]}]

# PadFunction: IO_L9N_T1_DQS_34 (SCHEMATIC DDR_UDQS_N)
set_property SLEW FAST [get_ports {ddr3_dqs_n[1]}]
set_property IN_TERM UNTUNED_SPLIT_50 [get_ports {ddr3_dqs_n[1]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddr3_dqs_n[1]}]
set_property PACKAGE_PIN C7 [get_ports {ddr3_dqs_p[1]}]
set_property PACKAGE_PIN B7 [get_ports {ddr3_dqs_n[1]}]

# PadFunction: IO_L21P_T3_DQS_34 (SCHEMATIC DDR_CLK_P)
set_property SLEW FAST [get_ports {ddr3_clk_p}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddr3_clk_p}]

# PadFunction: IO_L21N_T3_DQS_34 (SCHEMATIC DDR_CLK_N)
set_property SLEW FAST [get_ports {ddr3_clk_n}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddr3_clk_n}]
set_property PACKAGE_PIN J7 [get_ports {ddr3_clk_p}]
set_property PACKAGE_PIN K7 [get_ports {ddr3_clk_n}]


# GLOBAL CONFIGURATIONS

set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

set_property INTERNAL_VREF 0.675 [get_iobanks 34]
set_property INTERNAL_VREF 0.675 [get_iobanks 35]
#set_property CFGBVS VCCO [current_design]
#set_property CONFIG_VOLTAGE 3.3 [current_design]
