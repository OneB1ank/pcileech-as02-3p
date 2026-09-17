// AS02MC04 25G AXI-Stream communication wrapper for asmcehnk.
// The original 64-bit RX and 256-bit TX IfComToFifo boundary is preserved;
// only the FT601/RMII physical transport is replaced by a line-rate UDP stack.

`resetall
`timescale 1ns / 1ps
`default_nettype none

`include "asmcehnk_header.svh"

module asmcehnk_com_axis_udp_25g #(
    parameter logic [47:0] PARAM_LOCAL_MAC = 48'h02_00_00_00_00_de,
    parameter logic [31:0] PARAM_LOCAL_IP  = 32'hc0a800de,
    parameter logic [15:0] PARAM_UDP_PORT  = 16'h6f3a
)(
    input  wire logic     clk,
    input  wire logic     rst,

    output wire logic     led_state_txdata,
    input  wire logic     led_state_invert,

    IfComToFifo.mp_com    dfifo,

    taxi_axis_if.snk      s_axis_rx,
    taxi_axis_if.src      m_axis_tx
);

    logic [4:0]  cnt_initial = '0;
    logic [63:0] initial_rx_data;

    wire         initial_rx_valid;
    wire [63:0]  udp_rx_data;
    wire         udp_rx_valid;
    wire         udp_tx_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            cnt_initial <= 5'd0;
        end else if (cnt_initial != 5'd21) begin
            cnt_initial <= cnt_initial + 5'd1;
        end else begin
            cnt_initial <= cnt_initial;
        end
    end

    assign initial_rx_valid = !rst && cnt_initial[4] && (cnt_initial != 5'd21);

    always_comb begin
        initial_rx_data = 64'h00000000_00000000;

        case (cnt_initial[2:0])
            3'd4: initial_rx_data = 64'h00000003_80182377;
            default: initial_rx_data = 64'h00000000_00000000;
        endcase
    end

    assign dfifo.com_dout = initial_rx_valid ? initial_rx_data : udp_rx_data;
    assign dfifo.com_dout_valid = initial_rx_valid || udp_rx_valid;
    assign dfifo.com_din_ready = udp_tx_ready;
    assign led_state_txdata = (!udp_tx_ready) ^ led_state_invert;

    asmcehnk_eth_axis_udp_25g #(
        .PARAM_LOCAL_MAC(PARAM_LOCAL_MAC),
        .PARAM_LOCAL_IP (PARAM_LOCAL_IP),
        .PARAM_UDP_PORT (PARAM_UDP_PORT)
    ) eth_axis_inst (
        .clk          (clk),
        .rst          (rst),
        .s_axis_rx    (s_axis_rx),
        .m_axis_tx    (m_axis_tx),
        .com_rx_data  (udp_rx_data),
        .com_rx_valid (udp_rx_valid),
        .com_tx_data  (dfifo.com_din),
        .com_tx_valid (dfifo.com_din_wr_en),
        .com_tx_ready (udp_tx_ready)
    );

endmodule

`resetall
