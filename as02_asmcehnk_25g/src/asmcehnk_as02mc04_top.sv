// SPDX-License-Identifier: MIT
//
// asmcehnk FPGA.
//
// Top module for the Alibaba AS02MC04 XCKU3P-FFVB676-2E board.
// This file is the asmcehnk-named board top corresponding to AMDUSB4's
// asmcehnk_enigma_x1_top.sv.  Keep this top asmcehnk-facing: expose the
// command/register/transport parameters here, and keep Taxi shell metadata
// inside fpga.sv.
//
// Physical SFP1 is the asmcehnk UDP transport port.  Physical SFP2 is kept
// intentionally idle/safe in the first AS02 image.
//

`resetall
`timescale 1ns / 1ps
`default_nettype none

module asmcehnk_as02mc04_top #(
    // asmcehnk-visible command/config-space identity, matching AMDUSB4 style.
    parameter       PARAM_DEVICE_ID = 8'd5,
    parameter       PARAM_VERSION_NUMBER_MAJOR = 8'd4,
    parameter       PARAM_VERSION_NUMBER_MINOR = 8'd13,
    parameter       PARAM_CUSTOM_VALUE = 32'hffffffff,

    // AS02 UDP transport defaults: 192.168.0.222:28474, local management MAC.
    parameter logic [47:0] PARAM_LOCAL_MAC = 48'h02_00_00_00_00_de,
    parameter logic [31:0] PARAM_LOCAL_IP  = 32'hc0a800de,
    parameter logic [15:0] PARAM_UDP_PORT  = 16'h6f3a
)(
    /*
     * Clock: 100MHz LVDS
     * Reset: push button, active high
     */
    input  wire logic        clk_100mhz_p,
    input  wire logic        clk_100mhz_n,
    input  wire logic        reset,

    /* GPIO */
    output wire logic        sfp_led[2],
    output wire logic [3:0]  led,
    output wire logic        led_r,
    output wire logic        led_g,
    output wire logic        led_hb,

    /* I2C / SMBus */
    inout  wire logic        i2c_scl,
    inout  wire logic        i2c_sda,
    inout  wire logic        smbclk,
    inout  wire logic        smbdat,

    /* Ethernet: 2x SFP/SFP28 */
    input  wire logic        sfp_rx_p[2],
    input  wire logic        sfp_rx_n[2],
    output wire logic        sfp_tx_p[2],
    output wire logic        sfp_tx_n[2],
    input  wire logic        sfp_mgt_refclk_p,
    input  wire logic        sfp_mgt_refclk_n,
    input  wire logic [1:0]  sfp_npres,
    input  wire logic [1:0]  sfp_tx_fault,
    input  wire logic [1:0]  sfp_los,
    inout  wire logic [1:0]  sfp_i2c_scl,
    inout  wire logic [1:0]  sfp_i2c_sda,

    /* PCIe Gen3 x8 */
    input  wire logic [7:0]  pcie_rx_p,
    input  wire logic [7:0]  pcie_rx_n,
    output wire logic [7:0]  pcie_tx_p,
    output wire logic [7:0]  pcie_tx_n,
    input  wire logic        pcie_refclk_p,
    input  wire logic        pcie_refclk_n,
    input  wire logic        pcie_reset_n
);

fpga #(
    .PARAM_DEVICE_ID(PARAM_DEVICE_ID),
    .PARAM_VERSION_NUMBER_MAJOR(PARAM_VERSION_NUMBER_MAJOR),
    .PARAM_VERSION_NUMBER_MINOR(PARAM_VERSION_NUMBER_MINOR),
    .PARAM_CUSTOM_VALUE(PARAM_CUSTOM_VALUE),
    .PARAM_LOCAL_MAC(PARAM_LOCAL_MAC),
    .PARAM_LOCAL_IP(PARAM_LOCAL_IP),
    .PARAM_UDP_PORT(PARAM_UDP_PORT)
)
fpga_shell_inst (
    .clk_100mhz_p(clk_100mhz_p),
    .clk_100mhz_n(clk_100mhz_n),
    .reset(reset),
    .sfp_led(sfp_led),
    .led(led),
    .led_r(led_r),
    .led_g(led_g),
    .led_hb(led_hb),
    .i2c_scl(i2c_scl),
    .i2c_sda(i2c_sda),
    .smbclk(smbclk),
    .smbdat(smbdat),
    .sfp_rx_p(sfp_rx_p),
    .sfp_rx_n(sfp_rx_n),
    .sfp_tx_p(sfp_tx_p),
    .sfp_tx_n(sfp_tx_n),
    .sfp_mgt_refclk_p(sfp_mgt_refclk_p),
    .sfp_mgt_refclk_n(sfp_mgt_refclk_n),
    .sfp_npres(sfp_npres),
    .sfp_tx_fault(sfp_tx_fault),
    .sfp_los(sfp_los),
    .sfp_i2c_scl(sfp_i2c_scl),
    .sfp_i2c_sda(sfp_i2c_sda),
    .pcie_rx_p(pcie_rx_p),
    .pcie_rx_n(pcie_rx_n),
    .pcie_tx_p(pcie_tx_p),
    .pcie_tx_n(pcie_tx_n),
    .pcie_refclk_p(pcie_refclk_p),
    .pcie_refclk_n(pcie_refclk_n),
    .pcie_reset_n(pcie_reset_n)
);

endmodule

`resetall
