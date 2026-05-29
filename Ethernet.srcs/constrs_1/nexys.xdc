## =============================================================
## nexys.xdc  —  Ethernet Packet Sender
## Board : Digilent Nexys A7-50T
## PHY   : SMSC LAN8720A (RMII)
## Pins verified against Nexys A7 Reference Manual Figure 4.1
## =============================================================

## ── System Clock (100 MHz, pin E3, bank 35 MRCC) ─────────────
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports {clk}]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports {clk}]

## ── Reset — btnR ─────────────────────────────────────────────
set_property -dict {PACKAGE_PIN M17 IOSTANDARD LVCMOS33} [get_ports {rst}]

## ── Send button — btnC ───────────────────────────────────────
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {btnC}]

## ── Switches ─────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN J15 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN L16 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]
set_property -dict {PACKAGE_PIN M13 IOSTANDARD LVCMOS33} [get_ports {sw[2]}]
set_property -dict {PACKAGE_PIN R15 IOSTANDARD LVCMOS33} [get_ports {sw[3]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {sw[4]}]
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS33} [get_ports {sw[5]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {sw[6]}]
set_property -dict {PACKAGE_PIN R13 IOSTANDARD LVCMOS33} [get_ports {sw[7]}]
set_property -dict {PACKAGE_PIN T8  IOSTANDARD LVCMOS18} [get_ports {sw[8]}]

## ── LEDs ─────────────────────────────────────────────────────
set_property -dict {PACKAGE_PIN H17 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN K15 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN J13 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN N14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN R18 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN V17 IOSTANDARD LVCMOS33} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN U17 IOSTANDARD LVCMOS33} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN U16 IOSTANDARD LVCMOS33} [get_ports {led[7]}]

## ── Seven-Segment Display (shared bus, active LOW) ───────────
## Code convention: seg(0)=a, seg(1)=b, ... seg(6)=g
set_property PACKAGE_PIN T10 [get_ports {seg[0]}]   ;# CA = a
set_property PACKAGE_PIN R10 [get_ports {seg[1]}]   ;# CB = b
set_property PACKAGE_PIN K16 [get_ports {seg[2]}]   ;# CC = c
set_property PACKAGE_PIN K13 [get_ports {seg[3]}]   ;# CD = d
set_property PACKAGE_PIN P15 [get_ports {seg[4]}]   ;# CE = e
set_property PACKAGE_PIN T11 [get_ports {seg[5]}]   ;# CF = f
set_property PACKAGE_PIN L18 [get_ports {seg[6]}]   ;# CG = g
set_property PACKAGE_PIN H15 [get_ports {dp}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dp}]

set_property PACKAGE_PIN J17 [get_ports {an[0]}]
set_property PACKAGE_PIN J18 [get_ports {an[1]}]
set_property PACKAGE_PIN T9  [get_ports {an[2]}]
set_property PACKAGE_PIN J14 [get_ports {an[3]}]
set_property PACKAGE_PIN P14 [get_ports {an[4]}]
set_property PACKAGE_PIN T14 [get_ports {an[5]}]
set_property PACKAGE_PIN K2  [get_ports {an[6]}]
set_property PACKAGE_PIN U13 [get_ports {an[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {an[*]}]

## ── Ethernet PHY — SMSC LAN8720A (RMII) ─────────────────────
## Reference: Nexys A7 Manual, Figure 4.1 (page 13)

## TX (FPGA → PHY)
set_property -dict {PACKAGE_PIN A10 IOSTANDARD LVCMOS33} [get_ports {eth_txd[0]}]
set_property -dict {PACKAGE_PIN A8  IOSTANDARD LVCMOS33} [get_ports {eth_txd[1]}]
set_property -dict {PACKAGE_PIN B9  IOSTANDARD LVCMOS33} [get_ports {eth_tx_en}]

## RX (PHY → FPGA)
set_property -dict {PACKAGE_PIN C11 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[0]}]
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports {eth_rxd[1]}]
set_property -dict {PACKAGE_PIN D9  IOSTANDARD LVCMOS33} [get_ports {eth_crs_dv}]
set_property -dict {PACKAGE_PIN C10 IOSTANDARD LVCMOS33} [get_ports {eth_rxerr}]

## 50 MHz reference clock: FPGA → PHY CLKIN
set_property -dict {PACKAGE_PIN D5  IOSTANDARD LVCMOS33} [get_ports {eth_ref_clk}]

## PHY hardware reset (active low)
set_property -dict {PACKAGE_PIN B3  IOSTANDARD LVCMOS33} [get_ports {eth_rst_n}]

## MDIO management bus
set_property -dict {PACKAGE_PIN A9  IOSTANDARD LVCMOS33} [get_ports {eth_mdio}]
set_property -dict {PACKAGE_PIN C9  IOSTANDARD LVCMOS33} [get_ports {eth_mdc}]

## ── Timing constraints ───────────────────────────────────────
set_false_path -from [get_ports {sw[*]}]
set_false_path -from [get_ports {btnC}]
set_false_path -from [get_ports {rst}]

## Generated 50 MHz clock from toggle FF (clk_50_pre_reg → BUFG_50 → clk_50)
## Source = C pin of the toggle FF; output = Q pin (BUFG is transparent in STA).
create_generated_clock -name clk_50_gen \
    -source [get_pins clk_50_pre_reg/C] \
    -divide_by 2 [get_pins clk_50_pre_reg/Q]

## RMII TX outputs are synchronous to eth_ref_clk (= clk_50_gen)
set_output_delay -clock [get_clocks clk_50_gen] -max  4.0 [get_ports {eth_txd[*] eth_tx_en}]
set_output_delay -clock [get_clocks clk_50_gen] -min -2.0 [get_ports {eth_txd[*] eth_tx_en}]

## RMII RX inputs are synchronous to eth_ref_clk (PHY clocks them out at 50 MHz)
set_input_delay  -clock [get_clocks clk_50_gen] -max  4.0 [get_ports {eth_rxd[*] eth_crs_dv eth_rxerr}]
set_input_delay  -clock [get_clocks clk_50_gen] -min  2.0 [get_ports {eth_rxd[*] eth_crs_dv eth_rxerr}]

## sys_clk_pin and clk_50_gen are derived from the same source FF and are
## phase-related — keep them in the same clock group so STA analyses paths
## between them rigorously.

## Fast slew + max drive on RMII outputs (required for clean 50 MHz edges at PHY)
set_property SLEW FAST [get_ports {eth_ref_clk eth_tx_en}]
set_property SLEW FAST [get_ports {eth_txd[*]}]
set_property DRIVE 12  [get_ports {eth_ref_clk eth_tx_en}]
set_property DRIVE 12  [get_ports {eth_txd[*]}]

## Pack RMII TX/RX flops into IOBs so their delay is fixed and matches
## the set_output_delay / set_input_delay budgets.
## IOB TRUE on ports is only honoured when the driving FF is in the same
## hierarchy level as the port. Flatten TX_INST so Vivado can see the FFs.
set_property KEEP_HIERARCHY FALSE [get_cells {TX_INST}]
set_property IOB TRUE [get_ports {eth_tx_en eth_txd[*]}]
set_property IOB TRUE [get_ports {eth_crs_dv eth_rxd[*] eth_rxerr}]