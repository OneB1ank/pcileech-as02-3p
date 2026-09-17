// AS02MC04 line-rate UDP transport.
// Taxi owns the board MAC/GTY; Corundum owns Ethernet/ARP/IPv4/UDP parsing.
// This file contains only the asmcehnk payload and last-peer adaptation.

`resetall
`timescale 1ns / 1ps
`default_nettype none

module asmcehnk_eth_axis_udp_25g #(
    parameter logic [47:0] PARAM_LOCAL_MAC = 48'h02_00_00_00_00_de,
    parameter logic [31:0] PARAM_LOCAL_IP  = 32'hc0a800de,
    parameter logic [15:0] PARAM_UDP_PORT  = 16'h6f3a
)(
    input  wire logic   clk,
    input  wire logic   rst,

    taxi_axis_if.snk    s_axis_rx,
    taxi_axis_if.src    m_axis_tx,

    output wire [63:0]  com_rx_data,
    output wire         com_rx_valid,
    input  wire [255:0] com_tx_data,
    input  wire         com_tx_valid,
    output wire         com_tx_ready
);

    // Ethernet frame splitter output.
    wire        rx_eth_hdr_valid;
    wire        rx_eth_hdr_ready;
    wire [47:0] rx_eth_dest_mac;
    wire [47:0] rx_eth_src_mac;
    wire [15:0] rx_eth_type;
    wire [63:0] rx_eth_payload_tdata;
    wire [7:0]  rx_eth_payload_tkeep;
    wire        rx_eth_payload_tvalid;
    wire        rx_eth_payload_tready;
    wire        rx_eth_payload_tlast;
    wire        rx_eth_payload_tuser;

    // Ethernet frame merger input.
    wire        tx_eth_hdr_valid;
    wire        tx_eth_hdr_ready;
    wire [47:0] tx_eth_dest_mac;
    wire [47:0] tx_eth_src_mac;
    wire [15:0] tx_eth_type;
    wire [63:0] tx_eth_payload_tdata;
    wire [7:0]  tx_eth_payload_tkeep;
    wire        tx_eth_payload_tvalid;
    wire        tx_eth_payload_tready;
    wire        tx_eth_payload_tlast;
    wire        tx_eth_payload_tuser;

    // Corundum UDP receive interface.
    wire        rx_udp_hdr_valid;
    wire        rx_udp_hdr_ready;
    wire [31:0] rx_udp_ip_source_ip;
    wire [31:0] rx_udp_ip_dest_ip;
    wire [2:0]  rx_udp_ip_flags;
    wire [12:0] rx_udp_ip_fragment_offset;
    wire [15:0] rx_udp_source_port;
    wire [15:0] rx_udp_dest_port;
    wire [15:0] rx_udp_length;
    wire [63:0] rx_udp_payload_tdata;
    wire [7:0]  rx_udp_payload_tkeep;
    wire        rx_udp_payload_tvalid;
    wire        rx_udp_payload_tready;
    wire        rx_udp_payload_tlast;
    wire        rx_udp_payload_tuser;

    // Corundum UDP transmit interface.
    wire        tx_udp_hdr_valid;
    wire        tx_udp_hdr_ready;
    wire [15:0] tx_udp_length;
    wire [63:0] tx_udp_payload_tdata;
    wire [7:0]  tx_udp_payload_tkeep;
    wire        tx_udp_payload_tvalid;
    wire        tx_udp_payload_tready;
    wire        tx_udp_payload_tlast;

    // Last legal peer and current RX frame classification.
    logic [31:0] peer_ip_reg = 32'd0;
    logic [15:0] peer_port_reg = 16'd0;
    logic        peer_valid_reg = 1'b0;
    logic        rx_payload_active_reg = 1'b0;
    logic        rx_payload_accept_reg = 1'b0;

    wire rx_hdr_match;
    wire rx_hdr_fire;
    wire rx_payload_fire;

    assign rx_hdr_match = (rx_udp_ip_dest_ip == PARAM_LOCAL_IP) &&
                          (rx_udp_dest_port == PARAM_UDP_PORT) &&
                          (rx_udp_length >= 16'd16) &&
                          (rx_udp_length[2:0] == 3'd0) &&
                          (rx_udp_ip_fragment_offset == 13'd0) &&
                          !rx_udp_ip_flags[0];
    assign rx_udp_hdr_ready = !rx_payload_active_reg;
    assign rx_udp_payload_tready = 1'b1;
    assign rx_hdr_fire = rx_udp_hdr_valid && rx_udp_hdr_ready;
    assign rx_payload_fire = rx_udp_payload_tvalid && rx_udp_payload_tready;

    // LeechCore RawUDP sends each 64-bit command in NeTV2 byte order. Ethernet
    // AXIS lane 0 is the first wire byte, while asmcehnk expects that byte at
    // bit 63 and the trailing 0x77 magic at bit 7:0.
    assign com_rx_data = {
        rx_udp_payload_tdata[7:0],
        rx_udp_payload_tdata[15:8],
        rx_udp_payload_tdata[23:16],
        rx_udp_payload_tdata[31:24],
        rx_udp_payload_tdata[39:32],
        rx_udp_payload_tdata[47:40],
        rx_udp_payload_tdata[55:48],
        rx_udp_payload_tdata[63:56]
    };
    assign com_rx_valid = rx_payload_active_reg && rx_payload_accept_reg &&
                          rx_udp_payload_tvalid && (rx_udp_payload_tkeep == 8'hff) &&
                          !rx_udp_payload_tuser;

    always_ff @(posedge clk) begin
        if (rst) begin
            peer_ip_reg <= 32'd0;
            peer_port_reg <= 16'd0;
            peer_valid_reg <= 1'b0;
            rx_payload_active_reg <= 1'b0;
            rx_payload_accept_reg <= 1'b0;
        end else begin
            if (rx_hdr_fire) begin
                rx_payload_active_reg <= 1'b1;
                rx_payload_accept_reg <= rx_hdr_match;

                if (rx_hdr_match) begin
                    peer_ip_reg <= rx_udp_ip_source_ip;
                    peer_port_reg <= rx_udp_source_port;
                    peer_valid_reg <= 1'b1;
                end
            end

            if (rx_payload_fire && rx_udp_payload_tlast) begin
                rx_payload_active_reg <= 1'b0;
                rx_payload_accept_reg <= 1'b0;
            end
        end
    end

    // Packetize the native 256-bit mux output before the generic width/frame
    // FIFO.  A descriptor FIFO keeps the variable UDP length aligned with each
    // committed payload frame.
    wire [255:0] leechcore_tx_data;
    wire [255:0] packet_axis_tdata;
    wire [31:0]  packet_axis_tkeep;
    wire         packet_axis_tvalid;
    wire         packet_axis_tready;
    wire         packet_axis_tlast;
    wire [15:0]  packet_desc_length;
    wire         packet_desc_valid;
    wire         packet_desc_ready;
    wire         packetizer_data_ready;

    assign com_tx_ready = peer_valid_reg && packetizer_data_ready;

    // AMDUSB4 emits status in bits 255:224 followed by data0..data6. The old
    // 256->32 FIFO read the most-significant DWORD first and NeTV2 serialized
    // every DWORD most-significant byte first. Full byte reversal recreates
    // that RawUDP wire stream before the generic AXIS width adapter.
    assign leechcore_tx_data = {
        com_tx_data[7:0],
        com_tx_data[15:8],
        com_tx_data[23:16],
        com_tx_data[31:24],
        com_tx_data[39:32],
        com_tx_data[47:40],
        com_tx_data[55:48],
        com_tx_data[63:56],
        com_tx_data[71:64],
        com_tx_data[79:72],
        com_tx_data[87:80],
        com_tx_data[95:88],
        com_tx_data[103:96],
        com_tx_data[111:104],
        com_tx_data[119:112],
        com_tx_data[127:120],
        com_tx_data[135:128],
        com_tx_data[143:136],
        com_tx_data[151:144],
        com_tx_data[159:152],
        com_tx_data[167:160],
        com_tx_data[175:168],
        com_tx_data[183:176],
        com_tx_data[191:184],
        com_tx_data[199:192],
        com_tx_data[207:200],
        com_tx_data[215:208],
        com_tx_data[223:216],
        com_tx_data[231:224],
        com_tx_data[239:232],
        com_tx_data[247:240],
        com_tx_data[255:248]
    };

    asmcehnk_udp_tx_packetizer_256 #(
        .C_MAX_WORDS  (32),
        .C_IDLE_CYCLES(16)
    ) tx_packetizer_inst (
        .i_clk         (clk),
        .i_rstn        (!rst),
        .i_data        (leechcore_tx_data),
        .i_data_valid  (com_tx_valid && peer_valid_reg),
        .o_data_ready  (packetizer_data_ready),
        .o_axis_tdata  (packet_axis_tdata),
        .o_axis_tkeep  (packet_axis_tkeep),
        .o_axis_tvalid (packet_axis_tvalid),
        .i_axis_tready (packet_axis_tready),
        .o_axis_tlast  (packet_axis_tlast),
        .o_desc_length (packet_desc_length),
        .o_desc_valid  (packet_desc_valid),
        .i_desc_ready  (packet_desc_ready)
    );

    wire [63:0] payload_fifo_tdata;
    wire [7:0]  payload_fifo_tkeep;
    wire        payload_fifo_tvalid;
    wire        payload_fifo_tready;
    wire        payload_fifo_tlast;

    axis_fifo_adapter #(
        .DEPTH              (16384),
        .S_DATA_WIDTH       (256),
        .S_KEEP_ENABLE      (1),
        .S_KEEP_WIDTH       (32),
        .M_DATA_WIDTH       (64),
        .M_KEEP_ENABLE      (1),
        .M_KEEP_WIDTH       (8),
        .ID_ENABLE          (0),
        .DEST_ENABLE        (0),
        .USER_ENABLE        (0),
        .RAM_PIPELINE       (2),
        .OUTPUT_FIFO_ENABLE (1),
        .FRAME_FIFO         (1),
        .DROP_OVERSIZE_FRAME(0),
        .DROP_BAD_FRAME     (0),
        .DROP_WHEN_FULL     (0)
    ) tx_payload_fifo_inst (
        .clk                 (clk),
        .rst                 (rst),
        .s_axis_tdata        (packet_axis_tdata),
        .s_axis_tkeep        (packet_axis_tkeep),
        .s_axis_tvalid       (packet_axis_tvalid),
        .s_axis_tready       (packet_axis_tready),
        .s_axis_tlast        (packet_axis_tlast),
        .s_axis_tid          (8'd0),
        .s_axis_tdest        (8'd0),
        .s_axis_tuser        (1'b0),
        .m_axis_tdata        (payload_fifo_tdata),
        .m_axis_tkeep        (payload_fifo_tkeep),
        .m_axis_tvalid       (payload_fifo_tvalid),
        .m_axis_tready       (payload_fifo_tready),
        .m_axis_tlast        (payload_fifo_tlast),
        .m_axis_tid          (),
        .m_axis_tdest        (),
        .m_axis_tuser        (),
        .pause_req           (1'b0),
        .pause_ack           (),
        .status_depth        (),
        .status_depth_commit (),
        .status_overflow     (),
        .status_bad_frame    (),
        .status_good_frame   ()
    );

    wire [15:0] desc_fifo_tdata;
    wire        desc_fifo_tvalid;
    wire        desc_fifo_tready;

    axis_fifo #(
        .DEPTH              (256),
        .DATA_WIDTH         (16),
        .KEEP_ENABLE        (0),
        .KEEP_WIDTH         (1),
        .LAST_ENABLE        (0),
        .ID_ENABLE          (0),
        .DEST_ENABLE        (0),
        .USER_ENABLE        (0),
        .RAM_PIPELINE       (1),
        .OUTPUT_FIFO_ENABLE (1),
        .FRAME_FIFO         (0)
    ) tx_desc_fifo_inst (
        .clk                 (clk),
        .rst                 (rst),
        .s_axis_tdata        (packet_desc_length),
        .s_axis_tkeep        (1'b1),
        .s_axis_tvalid       (packet_desc_valid),
        .s_axis_tready       (packet_desc_ready),
        .s_axis_tlast        (1'b0),
        .s_axis_tid          (8'd0),
        .s_axis_tdest        (8'd0),
        .s_axis_tuser        (1'b0),
        .m_axis_tdata        (desc_fifo_tdata),
        .m_axis_tkeep        (),
        .m_axis_tvalid       (desc_fifo_tvalid),
        .m_axis_tready       (desc_fifo_tready),
        .m_axis_tlast        (),
        .m_axis_tid          (),
        .m_axis_tdest        (),
        .m_axis_tuser        (),
        .pause_req           (1'b0),
        .pause_ack           (),
        .status_depth        (),
        .status_depth_commit (),
        .status_overflow     (),
        .status_bad_frame    (),
        .status_good_frame   ()
    );

    logic tx_payload_active_reg = 1'b0;
    wire  tx_hdr_fire;
    wire  tx_payload_fire;

    wire ip_rx_busy;
    wire ip_tx_busy;
    wire udp_rx_busy;
    wire udp_tx_busy;
    wire ip_rx_error_header_early_termination;
    wire ip_rx_error_payload_early_termination;
    wire ip_rx_error_invalid_header;
    wire ip_rx_error_invalid_checksum;
    wire ip_tx_error_payload_early_termination;
    wire ip_tx_error_arp_failed;
    wire udp_rx_error_header_early_termination;
    wire udp_rx_error_payload_early_termination;
    wire udp_tx_error_payload_early_termination;

    assign tx_udp_hdr_valid = peer_valid_reg && desc_fifo_tvalid &&
                              payload_fifo_tvalid && !tx_payload_active_reg;
    assign desc_fifo_tready = tx_udp_hdr_ready && tx_udp_hdr_valid;
    assign tx_hdr_fire = tx_udp_hdr_valid && tx_udp_hdr_ready;

    assign tx_udp_length = desc_fifo_tdata;
    assign tx_udp_payload_tdata = payload_fifo_tdata;
    assign tx_udp_payload_tkeep = payload_fifo_tkeep;
    assign tx_udp_payload_tvalid = tx_payload_active_reg && payload_fifo_tvalid;
    assign tx_udp_payload_tlast = payload_fifo_tlast;
    assign payload_fifo_tready = tx_payload_active_reg && tx_udp_payload_tready;
    assign tx_payload_fire = tx_udp_payload_tvalid && tx_udp_payload_tready;

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_payload_active_reg <= 1'b0;
        end else begin
            if (tx_hdr_fire) begin
                tx_payload_active_reg <= 1'b1;
            end
            if (tx_payload_fire && tx_udp_payload_tlast) begin
                tx_payload_active_reg <= 1'b0;
            end
        end
    end

    // Full Ethernet frame ingress/egress around the Corundum protocol stack.
    eth_axis_rx #(
        .DATA_WIDTH (64),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH (8)
    ) eth_axis_rx_inst (
        .clk                           (clk),
        .rst                           (rst),
        .s_axis_tdata                  (s_axis_rx.tdata),
        .s_axis_tkeep                  (s_axis_rx.tkeep),
        .s_axis_tvalid                 (s_axis_rx.tvalid),
        .s_axis_tready                 (s_axis_rx.tready),
        .s_axis_tlast                  (s_axis_rx.tlast),
        .s_axis_tuser                  (s_axis_rx.tuser[0]),
        .m_eth_hdr_valid               (rx_eth_hdr_valid),
        .m_eth_hdr_ready               (rx_eth_hdr_ready),
        .m_eth_dest_mac                (rx_eth_dest_mac),
        .m_eth_src_mac                 (rx_eth_src_mac),
        .m_eth_type                    (rx_eth_type),
        .m_eth_payload_axis_tdata      (rx_eth_payload_tdata),
        .m_eth_payload_axis_tkeep      (rx_eth_payload_tkeep),
        .m_eth_payload_axis_tvalid     (rx_eth_payload_tvalid),
        .m_eth_payload_axis_tready     (rx_eth_payload_tready),
        .m_eth_payload_axis_tlast      (rx_eth_payload_tlast),
        .m_eth_payload_axis_tuser      (rx_eth_payload_tuser),
        .busy                          (),
        .error_header_early_termination()
    );

    eth_axis_tx #(
        .DATA_WIDTH (64),
        .KEEP_ENABLE(1),
        .KEEP_WIDTH (8)
    ) eth_axis_tx_inst (
        .clk                      (clk),
        .rst                      (rst),
        .s_eth_hdr_valid          (tx_eth_hdr_valid),
        .s_eth_hdr_ready          (tx_eth_hdr_ready),
        .s_eth_dest_mac           (tx_eth_dest_mac),
        .s_eth_src_mac            (tx_eth_src_mac),
        .s_eth_type               (tx_eth_type),
        .s_eth_payload_axis_tdata (tx_eth_payload_tdata),
        .s_eth_payload_axis_tkeep (tx_eth_payload_tkeep),
        .s_eth_payload_axis_tvalid(tx_eth_payload_tvalid),
        .s_eth_payload_axis_tready(tx_eth_payload_tready),
        .s_eth_payload_axis_tlast (tx_eth_payload_tlast),
        .s_eth_payload_axis_tuser (tx_eth_payload_tuser),
        .m_axis_tdata             (m_axis_tx.tdata),
        .m_axis_tkeep             (m_axis_tx.tkeep),
        .m_axis_tvalid            (m_axis_tx.tvalid),
        .m_axis_tready            (m_axis_tx.tready),
        .m_axis_tlast             (m_axis_tx.tlast),
        .m_axis_tuser             (m_axis_tx.tuser),
        .busy                     ()
    );

    assign m_axis_tx.tstrb = m_axis_tx.tkeep;
    assign m_axis_tx.tid = '0;
    assign m_axis_tx.tdest = '0;

    udp_complete_64 #(
        .ARP_CACHE_ADDR_WIDTH             (9),
        .ARP_REQUEST_RETRY_COUNT          (4),
        .ARP_REQUEST_RETRY_INTERVAL       (781250000),
        .ARP_REQUEST_TIMEOUT              (1953125000),
        .UDP_CHECKSUM_GEN_ENABLE          (1),
        .UDP_CHECKSUM_PAYLOAD_FIFO_DEPTH  (2048),
        .UDP_CHECKSUM_HEADER_FIFO_DEPTH   (8)
    ) udp_complete_inst (
        .clk                                      (clk),
        .rst                                      (rst),
        .s_eth_hdr_valid                          (rx_eth_hdr_valid),
        .s_eth_hdr_ready                          (rx_eth_hdr_ready),
        .s_eth_dest_mac                           (rx_eth_dest_mac),
        .s_eth_src_mac                            (rx_eth_src_mac),
        .s_eth_type                               (rx_eth_type),
        .s_eth_payload_axis_tdata                 (rx_eth_payload_tdata),
        .s_eth_payload_axis_tkeep                 (rx_eth_payload_tkeep),
        .s_eth_payload_axis_tvalid                (rx_eth_payload_tvalid),
        .s_eth_payload_axis_tready                (rx_eth_payload_tready),
        .s_eth_payload_axis_tlast                 (rx_eth_payload_tlast),
        .s_eth_payload_axis_tuser                 (rx_eth_payload_tuser),
        .m_eth_hdr_valid                          (tx_eth_hdr_valid),
        .m_eth_hdr_ready                          (tx_eth_hdr_ready),
        .m_eth_dest_mac                           (tx_eth_dest_mac),
        .m_eth_src_mac                            (tx_eth_src_mac),
        .m_eth_type                               (tx_eth_type),
        .m_eth_payload_axis_tdata                 (tx_eth_payload_tdata),
        .m_eth_payload_axis_tkeep                 (tx_eth_payload_tkeep),
        .m_eth_payload_axis_tvalid                (tx_eth_payload_tvalid),
        .m_eth_payload_axis_tready                (tx_eth_payload_tready),
        .m_eth_payload_axis_tlast                 (tx_eth_payload_tlast),
        .m_eth_payload_axis_tuser                 (tx_eth_payload_tuser),
        .s_ip_hdr_valid                           (1'b0),
        .s_ip_hdr_ready                           (),
        .s_ip_dscp                                (6'd0),
        .s_ip_ecn                                 (2'd0),
        .s_ip_length                              (16'd0),
        .s_ip_ttl                                 (8'd0),
        .s_ip_protocol                            (8'd0),
        .s_ip_source_ip                           (32'd0),
        .s_ip_dest_ip                             (32'd0),
        .s_ip_payload_axis_tdata                  (64'd0),
        .s_ip_payload_axis_tkeep                  (8'd0),
        .s_ip_payload_axis_tvalid                 (1'b0),
        .s_ip_payload_axis_tready                 (),
        .s_ip_payload_axis_tlast                  (1'b0),
        .s_ip_payload_axis_tuser                  (1'b0),
        .m_ip_hdr_valid                           (),
        .m_ip_hdr_ready                           (1'b1),
        .m_ip_eth_dest_mac                        (),
        .m_ip_eth_src_mac                         (),
        .m_ip_eth_type                            (),
        .m_ip_version                             (),
        .m_ip_ihl                                 (),
        .m_ip_dscp                                (),
        .m_ip_ecn                                 (),
        .m_ip_length                              (),
        .m_ip_identification                      (),
        .m_ip_flags                               (),
        .m_ip_fragment_offset                     (),
        .m_ip_ttl                                 (),
        .m_ip_protocol                            (),
        .m_ip_header_checksum                     (),
        .m_ip_source_ip                           (),
        .m_ip_dest_ip                             (),
        .m_ip_payload_axis_tdata                  (),
        .m_ip_payload_axis_tkeep                  (),
        .m_ip_payload_axis_tvalid                 (),
        .m_ip_payload_axis_tready                 (1'b1),
        .m_ip_payload_axis_tlast                  (),
        .m_ip_payload_axis_tuser                  (),
        .s_udp_hdr_valid                          (tx_udp_hdr_valid),
        .s_udp_hdr_ready                          (tx_udp_hdr_ready),
        .s_udp_ip_dscp                            (6'd0),
        .s_udp_ip_ecn                             (2'd0),
        .s_udp_ip_ttl                             (8'd64),
        .s_udp_ip_source_ip                       (PARAM_LOCAL_IP),
        .s_udp_ip_dest_ip                         (peer_ip_reg),
        .s_udp_source_port                        (PARAM_UDP_PORT),
        .s_udp_dest_port                          (peer_port_reg),
        .s_udp_length                             (tx_udp_length),
        .s_udp_checksum                           (16'd0),
        .s_udp_payload_axis_tdata                 (tx_udp_payload_tdata),
        .s_udp_payload_axis_tkeep                 (tx_udp_payload_tkeep),
        .s_udp_payload_axis_tvalid                (tx_udp_payload_tvalid),
        .s_udp_payload_axis_tready                (tx_udp_payload_tready),
        .s_udp_payload_axis_tlast                 (tx_udp_payload_tlast),
        .s_udp_payload_axis_tuser                 (1'b0),
        .m_udp_hdr_valid                          (rx_udp_hdr_valid),
        .m_udp_hdr_ready                          (rx_udp_hdr_ready),
        .m_udp_eth_dest_mac                       (),
        .m_udp_eth_src_mac                        (),
        .m_udp_eth_type                           (),
        .m_udp_ip_version                         (),
        .m_udp_ip_ihl                             (),
        .m_udp_ip_dscp                            (),
        .m_udp_ip_ecn                             (),
        .m_udp_ip_length                          (),
        .m_udp_ip_identification                  (),
        .m_udp_ip_flags                           (rx_udp_ip_flags),
        .m_udp_ip_fragment_offset                 (rx_udp_ip_fragment_offset),
        .m_udp_ip_ttl                             (),
        .m_udp_ip_protocol                        (),
        .m_udp_ip_header_checksum                 (),
        .m_udp_ip_source_ip                       (rx_udp_ip_source_ip),
        .m_udp_ip_dest_ip                         (rx_udp_ip_dest_ip),
        .m_udp_source_port                        (rx_udp_source_port),
        .m_udp_dest_port                          (rx_udp_dest_port),
        .m_udp_length                             (rx_udp_length),
        .m_udp_checksum                           (),
        .m_udp_payload_axis_tdata                 (rx_udp_payload_tdata),
        .m_udp_payload_axis_tkeep                 (rx_udp_payload_tkeep),
        .m_udp_payload_axis_tvalid                (rx_udp_payload_tvalid),
        .m_udp_payload_axis_tready                (rx_udp_payload_tready),
        .m_udp_payload_axis_tlast                 (rx_udp_payload_tlast),
        .m_udp_payload_axis_tuser                 (rx_udp_payload_tuser),
        .ip_rx_busy                               (ip_rx_busy),
        .ip_tx_busy                               (ip_tx_busy),
        .udp_rx_busy                              (udp_rx_busy),
        .udp_tx_busy                              (udp_tx_busy),
        .ip_rx_error_header_early_termination     (ip_rx_error_header_early_termination),
        .ip_rx_error_payload_early_termination    (ip_rx_error_payload_early_termination),
        .ip_rx_error_invalid_header               (ip_rx_error_invalid_header),
        .ip_rx_error_invalid_checksum             (ip_rx_error_invalid_checksum),
        .ip_tx_error_payload_early_termination    (ip_tx_error_payload_early_termination),
        .ip_tx_error_arp_failed                   (ip_tx_error_arp_failed),
        .udp_rx_error_header_early_termination    (udp_rx_error_header_early_termination),
        .udp_rx_error_payload_early_termination   (udp_rx_error_payload_early_termination),
        .udp_tx_error_payload_early_termination   (udp_tx_error_payload_early_termination),
        .local_mac                                (PARAM_LOCAL_MAC),
        .local_ip                                 (PARAM_LOCAL_IP),
        .gateway_ip                               ({PARAM_LOCAL_IP[31:8], 8'd1}),
        .subnet_mask                              (32'hffffff00),
        .clear_arp_cache                          (1'b0)
    );

`ifdef AS02_HW_DEBUG
    logic [31:0] dbg_cnt_mac_rx_frames = 32'd0;
    logic [31:0] dbg_cnt_udp_headers = 32'd0;
    logic [31:0] dbg_cnt_udp_accept = 32'd0;
    logic [31:0] dbg_cnt_udp_reject = 32'd0;
    logic [31:0] dbg_cnt_udp_rx_words = 32'd0;
    logic [31:0] dbg_cnt_com_tx_words = 32'd0;
    logic [31:0] dbg_cnt_udp_tx_frames = 32'd0;
    logic [31:0] dbg_cnt_errors = 32'd0;

    wire dbg_udp_error_event;
    wire dbg_udp_partial_event;
    (* mark_debug = "true", keep = "true" *) wire [63:0] dbg_udp_control;
    (* mark_debug = "true", keep = "true" *) wire [127:0] dbg_udp_metadata;
    (* mark_debug = "true", keep = "true" *) wire [63:0] dbg_udp_peer;
    (* mark_debug = "true", keep = "true" *) wire [255:0] dbg_udp_counters;

    assign dbg_udp_error_event = ip_rx_error_header_early_termination |
                                 ip_rx_error_payload_early_termination |
                                 ip_rx_error_invalid_header |
                                 ip_rx_error_invalid_checksum |
                                 ip_tx_error_payload_early_termination |
                                 ip_tx_error_arp_failed |
                                 udp_rx_error_header_early_termination |
                                 udp_rx_error_payload_early_termination |
                                 udp_tx_error_payload_early_termination;
    assign dbg_udp_partial_event = rx_payload_fire &&
                                   ((rx_udp_payload_tkeep != 8'hff) |
                                    rx_udp_payload_tuser);

    always_ff @(posedge clk) begin
        if (rst) begin
            dbg_cnt_mac_rx_frames <= 32'd0;
            dbg_cnt_udp_headers <= 32'd0;
            dbg_cnt_udp_accept <= 32'd0;
            dbg_cnt_udp_reject <= 32'd0;
            dbg_cnt_udp_rx_words <= 32'd0;
            dbg_cnt_com_tx_words <= 32'd0;
            dbg_cnt_udp_tx_frames <= 32'd0;
            dbg_cnt_errors <= 32'd0;
        end else begin
            if (s_axis_rx.tvalid && s_axis_rx.tready && s_axis_rx.tlast) begin
                dbg_cnt_mac_rx_frames <= dbg_cnt_mac_rx_frames + 32'd1;
            end
            if (rx_hdr_fire) begin
                dbg_cnt_udp_headers <= dbg_cnt_udp_headers + 32'd1;
            end
            if (rx_hdr_fire && rx_hdr_match) begin
                dbg_cnt_udp_accept <= dbg_cnt_udp_accept + 32'd1;
            end
            if (rx_hdr_fire && !rx_hdr_match) begin
                dbg_cnt_udp_reject <= dbg_cnt_udp_reject + 32'd1;
            end
            if (com_rx_valid) begin
                dbg_cnt_udp_rx_words <= dbg_cnt_udp_rx_words + 32'd1;
            end
            if (com_tx_valid && com_tx_ready) begin
                dbg_cnt_com_tx_words <= dbg_cnt_com_tx_words + 32'd1;
            end
            if (tx_payload_fire && tx_udp_payload_tlast) begin
                dbg_cnt_udp_tx_frames <= dbg_cnt_udp_tx_frames + 32'd1;
            end
            if (dbg_udp_error_event || dbg_udp_partial_event) begin
                dbg_cnt_errors <= dbg_cnt_errors + 32'd1;
            end
        end
    end

    assign dbg_udp_control[0] = rst;
    assign dbg_udp_control[1] = rx_eth_hdr_valid;
    assign dbg_udp_control[2] = rx_eth_hdr_ready;
    assign dbg_udp_control[3] = rx_udp_hdr_valid;
    assign dbg_udp_control[4] = rx_udp_hdr_ready;
    assign dbg_udp_control[5] = rx_hdr_match;
    assign dbg_udp_control[6] = rx_hdr_fire;
    assign dbg_udp_control[7] = rx_payload_active_reg;
    assign dbg_udp_control[8] = rx_payload_accept_reg;
    assign dbg_udp_control[9] = rx_udp_payload_tvalid;
    assign dbg_udp_control[10] = rx_udp_payload_tready;
    assign dbg_udp_control[11] = rx_udp_payload_tlast;
    assign dbg_udp_control[12] = rx_udp_payload_tuser;
    assign dbg_udp_control[13] = com_rx_valid;
    assign dbg_udp_control[14] = peer_valid_reg;
    assign dbg_udp_control[15] = com_tx_valid;
    assign dbg_udp_control[16] = com_tx_ready;
    assign dbg_udp_control[17] = packet_axis_tvalid;
    assign dbg_udp_control[18] = packet_axis_tready;
    assign dbg_udp_control[19] = packet_axis_tlast;
    assign dbg_udp_control[20] = packet_desc_valid;
    assign dbg_udp_control[21] = packet_desc_ready;
    assign dbg_udp_control[22] = payload_fifo_tvalid;
    assign dbg_udp_control[23] = payload_fifo_tready;
    assign dbg_udp_control[24] = desc_fifo_tvalid;
    assign dbg_udp_control[25] = desc_fifo_tready;
    assign dbg_udp_control[26] = tx_udp_hdr_valid;
    assign dbg_udp_control[27] = tx_udp_hdr_ready;
    assign dbg_udp_control[28] = tx_udp_payload_tvalid;
    assign dbg_udp_control[29] = tx_udp_payload_tready;
    assign dbg_udp_control[30] = tx_udp_payload_tlast;
    assign dbg_udp_control[31] = dbg_udp_error_event;
    assign dbg_udp_control[32] = ip_rx_busy;
    assign dbg_udp_control[33] = ip_tx_busy;
    assign dbg_udp_control[34] = udp_rx_busy;
    assign dbg_udp_control[35] = udp_tx_busy;
    assign dbg_udp_control[36] = ip_rx_error_header_early_termination;
    assign dbg_udp_control[37] = ip_rx_error_payload_early_termination;
    assign dbg_udp_control[38] = ip_rx_error_invalid_header;
    assign dbg_udp_control[39] = ip_rx_error_invalid_checksum;
    assign dbg_udp_control[40] = ip_tx_error_payload_early_termination;
    assign dbg_udp_control[41] = ip_tx_error_arp_failed;
    assign dbg_udp_control[42] = udp_rx_error_header_early_termination;
    assign dbg_udp_control[43] = udp_rx_error_payload_early_termination;
    assign dbg_udp_control[44] = udp_tx_error_payload_early_termination;
    assign dbg_udp_control[45] = tx_payload_active_reg;
    assign dbg_udp_control[46] = rx_hdr_fire && !rx_hdr_match;
    assign dbg_udp_control[47] = dbg_udp_partial_event;
    assign dbg_udp_control[48] = com_tx_valid && !peer_valid_reg;
    assign dbg_udp_control[63:49] = 15'd0;

    assign dbg_udp_metadata = {
        rx_udp_ip_fragment_offset,
        rx_udp_ip_flags,
        rx_udp_length,
        rx_udp_dest_port,
        rx_udp_source_port,
        rx_udp_ip_dest_ip,
        rx_udp_ip_source_ip
    };
    assign dbg_udp_peer = {
        15'd0, peer_valid_reg, peer_port_reg, peer_ip_reg
    };
    assign dbg_udp_counters = {
        dbg_cnt_errors,
        dbg_cnt_udp_tx_frames,
        dbg_cnt_com_tx_words,
        dbg_cnt_udp_rx_words,
        dbg_cnt_udp_reject,
        dbg_cnt_udp_accept,
        dbg_cnt_udp_headers,
        dbg_cnt_mac_rx_frames
    };

    as02_net_vio as02_net_vio_inst (
        .clk      (clk),
        .probe_in0(dbg_udp_control),
        .probe_in1(dbg_udp_counters),
        .probe_in2(dbg_udp_metadata),
        .probe_in3(dbg_udp_peer)
    );
`endif

endmodule

`resetall
