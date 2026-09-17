`resetall
`timescale 1ns / 1ps
`default_nettype none
`include "asmcehnk_header.svh"

module asmcehnk_pcie_tlp_us #(
    parameter RQ_SEQ_NUM_W = 6
)(
    input  wire logic clk,
    input  wire logic rst,
    input  wire logic clk_sys,
    input  wire logic rst_sys,

    IfPCIeFifoTlp.mp_pcie dtlp,

    taxi_axis_if.snk s_axis_pcie_cq,
    taxi_axis_if.src m_axis_pcie_cc,
    taxi_axis_if.src m_axis_pcie_rq,
    taxi_axis_if.snk s_axis_pcie_rc,

    IfShadow2Fifo.shadow dshadow2fifo,
    input wire logic [15:0] pcie_id,
    input wire logic [31:0] base_address_register,

    input wire logic [RQ_SEQ_NUM_W-1:0] pcie_rq_seq_num0,
    input wire logic                    pcie_rq_seq_num_vld0,
    input wire logic [RQ_SEQ_NUM_W-1:0] pcie_rq_seq_num1,
    input wire logic                    pcie_rq_seq_num_vld1,

    output wire logic [11:0]            status_rq_flow
);

    // UltraScale+ PCIe shim for the AMDUSB4/asmcehnk raw 128-bit TLP framework.
    // AMDUSB4 already implements BAR0/shadow/config/TLP FIFO logic against a
    // 7-series raw TLP stream; this file only adapts AS02 pcie4_uscale_plus
    // CQ/CC/RQ/RC formatting to that raw stream.  Keep the framework modules
    // reused instead of rewriting their chip-independent behavior.

    // Stages implemented here:
    //   * CQ memory BAR MRd/MWr descriptor -> AMDUSB4 IfAXIS128 raw TLP.
    //   * AMDUSB4 raw completion TLPs from cfgspace_shadow/BAR -> CC packets.
    //   * AMDUSB4 raw outbound MRd/MWr TLPs -> UltraScale+ RQ packets.
    //   * UltraScale+ RC completions -> AMDUSB4 IfAXIS128 raw Cpl/CplD TLPs.
    // The chip-independent asmcehnk FIFO, BAR and shadow-config modules stay
    // reused; only the pcie4_uscale_plus stream descriptors are translated here.

    IfAXIS128 tlps_rx_from_cq();
    IfAXIS128 tlps_rx_from_rc();
    IfAXIS128 tlps_cq_event();
    IfAXIS128 tlps_rx_to_filter();
    IfAXIS128 tlps_filtered();
    IfAXIS128 tlps_tx_from_fifo();
    IfAXIS128 tlps_tx_to_rq();
    IfAXIS128 tlps_cfg_rsp();
    IfAXIS128 tlps_bar_rsp();
    IfAXIS128 tlps_cc_mux();
    IfAXIS128 tlps_null1();
    IfAXIS128 tlps_null2();
    IfShadow2Fifo dshadow_pcie();

    taxi_axis_if #(
        .DATA_W  (256),
        .KEEP_EN (1),
        .KEEP_W  (8),
        .USER_EN (1),
        .USER_W  (33)
    ) axis_cc_normal();
    taxi_axis_if #(
        .DATA_W  (256),
        .KEEP_EN (1),
        .KEEP_W  (8),
        .USER_EN (1),
        .USER_W  (33)
    ) axis_cc_error();

    wire [5:0] shadow_control_async;
    wire [5:0] shadow_control_pcie;
    wire [RQ_SEQ_NUM_W:0] rq_seq_outstanding;
    wire                  rq_seq_blocked;
    wire                  rq_seq_error;
    wire                  rq_tag_blocked;
    wire                  rq_tag_error;
    wire [7:0]            rc_tag_release;
    wire                  rc_tag_release_valid;

    assign status_rq_flow[6:0] = {
        {(6-RQ_SEQ_NUM_W){1'b0}}, rq_seq_outstanding
    };
    assign status_rq_flow[7] = rq_seq_blocked;
    assign status_rq_flow[8] = rq_seq_error;
    assign status_rq_flow[9] = rq_tag_blocked;
    assign status_rq_flow[10] = rq_tag_error;
    assign status_rq_flow[11] = 1'b0;

    assign shadow_control_async = {
        dshadow2fifo.alltlp_filter,
        dshadow2fifo.cfgtlp_filter,
        dshadow2fifo.cfgtlp_wren,
        dshadow2fifo.cfgtlp_zero,
        dshadow2fifo.cfgtlp_en,
        dshadow2fifo.bar_en
    };

    taxi_sync_signal #(
        .WIDTH(6),
        .N(2)
    ) shadow_control_sync_inst (
        .clk (clk),
        .in  (shadow_control_async),
        .out (shadow_control_pcie)
    );

    // The shadow command/response FIFOs already cross clk_sys/clk.  Only the
    // slowly changing mode controls need a synchronizer before PCIe-side use.
    assign dshadow_pcie.rx_rden = dshadow2fifo.rx_rden;
    assign dshadow_pcie.rx_wren = dshadow2fifo.rx_wren;
    assign dshadow_pcie.rx_be = dshadow2fifo.rx_be;
    assign dshadow_pcie.rx_data = dshadow2fifo.rx_data;
    assign dshadow_pcie.rx_addr = dshadow2fifo.rx_addr;
    assign dshadow_pcie.rx_addr_lo = dshadow2fifo.rx_addr_lo;
    assign dshadow_pcie.alltlp_filter = shadow_control_pcie[5];
    assign dshadow_pcie.cfgtlp_filter = shadow_control_pcie[4];
    assign dshadow_pcie.cfgtlp_wren = shadow_control_pcie[3];
    assign dshadow_pcie.cfgtlp_zero = shadow_control_pcie[2];
    assign dshadow_pcie.cfgtlp_en = shadow_control_pcie[1];
    assign dshadow_pcie.bar_en = shadow_control_pcie[0];
    assign dshadow2fifo.tx_valid = dshadow_pcie.tx_valid;
    assign dshadow2fifo.tx_data = dshadow_pcie.tx_data;
    assign dshadow2fifo.tx_addr = dshadow_pcie.tx_addr;
    assign dshadow2fifo.tx_addr_lo = dshadow_pcie.tx_addr_lo;

    assign tlps_null1.tdata = 128'd0;
    assign tlps_null1.tkeepdw = 4'd0;
    assign tlps_null1.tvalid = 1'b0;
    assign tlps_null1.tlast = 1'b0;
    assign tlps_null1.tuser = 9'd0;
    assign tlps_null1.has_data = 1'b0;

    assign tlps_null2.tdata = 128'd0;
    assign tlps_null2.tkeepdw = 4'd0;
    assign tlps_null2.tvalid = 1'b0;
    assign tlps_null2.tlast = 1'b0;
    assign tlps_null2.tuser = 9'd0;
    assign tlps_null2.has_data = 1'b0;

    asmcehnk_pcie_us_cq_to_tlps128 cq_to_tlps128_inst (
        .clk             (clk),
        .rst             (rst),
        .pcie_id         (pcie_id),
        .s_axis_cq       (s_axis_pcie_cq),
        .tlps_out        (tlps_rx_from_cq.source),
        .m_axis_cc_error (axis_cc_error)
    );

    // CQ and RC are independent PCIe channels.  Merge them with packet-locked
    // ready/valid arbitration so simultaneous traffic cannot overwrite a
    // one-word holding register.
    asmcehnk_tlps128_mux2 rx_tlps_mux_inst (
        .clk        (clk),
        .rst        (rst),
        .tlps_in1   (tlps_rx_from_cq.sink),
        .tlps_in2   (tlps_rx_from_rc.sink),
        .tlps_out   (tlps_rx_to_filter.source)
    );

    assign tlps_rx_to_filter.tready = 1'b1;

    // BAR and shadow helpers have the original AMDUSB4 pulse-only input.
    // Present a CQ beat exactly once, when the lossless merger accepts it.
    assign tlps_cq_event.tdata = tlps_rx_from_cq.tdata;
    assign tlps_cq_event.tkeepdw = tlps_rx_from_cq.tkeepdw;
    assign tlps_cq_event.tvalid = tlps_rx_from_cq.tvalid && tlps_rx_from_cq.tready;
    assign tlps_cq_event.tlast = tlps_rx_from_cq.tlast;
    assign tlps_cq_event.tuser = tlps_rx_from_cq.tuser;
    assign tlps_cq_event.has_data = tlps_rx_from_cq.has_data;

    asmcehnk_tlps128_filter tlp_filter_inst (
        .rst            (rst),
        .clk_pcie       (clk),
        .alltlp_filter  (shadow_control_pcie[5]),
        .cfgtlp_filter  (shadow_control_pcie[4]),
        .tlps_in        (tlps_rx_to_filter.sink_lite),
        .tlps_out       (tlps_filtered.source_lite)
    );

    asmcehnk_tlps128_dst_fifo_us tlp_dst_fifo_inst (
        .rst_pcie (rst),
        .rst_sys  (rst_sys),
        .clk_pcie (clk),
        .clk_sys  (clk_sys),
        .tlps_in  (tlps_filtered.sink_lite),
        .dfifo    (dtlp)
    );

    // asmcehnk -> PCIe TLP TX source FIFO: preserve the AMDUSB4 implementation.
    // Its read-valid pulse is normalized by an AS02-only elastic stage before
    // the UltraScale+ RQ packetizer applies native descriptor/tuser formatting.
    asmcehnk_tlps128_src_fifo tlp_src_fifo_inst (
        .rst_pcie       (rst),
        .rst_sys        (rst_sys),
        .clk_pcie       (clk),
        .clk_sys        (clk_sys),
        .dfifo_tx_data  (dtlp.tx_data),
        .dfifo_tx_last  (dtlp.tx_last),
        .dfifo_tx_valid (dtlp.tx_valid),
        .tlps_out       (tlps_tx_from_fifo.source)
    );

    asmcehnk_tlps128_src_elastic_us tlp_src_elastic_inst (
        .rst            (rst),
        .clk            (clk),
        .tlps_legacy_in (tlps_tx_from_fifo.sink),
        .tlps_out       (tlps_tx_to_rq.source)
    );

    asmcehnk_tlps128_to_axis_rq_us #(
        .RQ_SEQ_NUM_W(RQ_SEQ_NUM_W)
    ) tlps128_to_rq_inst (
        .clk                  (clk),
        .rst                  (rst),
        .tlps_in              (tlps_tx_to_rq.sink),
        .m_axis_rq            (m_axis_pcie_rq),
        .pcie_rq_seq_num0     (pcie_rq_seq_num0),
        .pcie_rq_seq_num_vld0 (pcie_rq_seq_num_vld0),
        .pcie_rq_seq_num1     (pcie_rq_seq_num1),
        .pcie_rq_seq_num_vld1 (pcie_rq_seq_num_vld1),
        .rc_tag_release       (rc_tag_release),
        .rc_tag_release_valid (rc_tag_release_valid),
        .status_outstanding   (rq_seq_outstanding),
        .status_blocked       (rq_seq_blocked),
        .status_error         (rq_seq_error),
        .status_tag_blocked   (rq_tag_blocked),
        .status_tag_error     (rq_tag_error)
    );

    asmcehnk_tlps128_cfgspace_shadow cfgspace_shadow_inst (
        .rst          (rst),
        .clk_pcie     (clk),
        .clk_sys      (clk_sys),
        .tlps_in      (tlps_cq_event.sink_lite),
        .pcie_id      (pcie_id),
        .tlps_cfg_rsp (tlps_cfg_rsp.source),
        .dshadow2fifo (dshadow_pcie)
    );

    wire        bar_int_enable_unused;
    wire [31:0] bar_o_addr_unused;
    wire [31:0] bar_o_data_unused;
    wire        bar_dbg_rd_valid_unused;
    wire [63:0] bar_dbg_rd_info_unused;
    wire        bar_dbg_wr_valid_unused;
    wire [63:0] bar_dbg_wr_info_unused;

    asmcehnk_tlps128_bar_controller bar_controller_inst (
        .rst                   (rst),
        .clk                   (clk),
        .bar_en                (shadow_control_pcie[0]),
        .int_enable            (bar_int_enable_unused),
        .o_addr                (bar_o_addr_unused),
        .o_data                (bar_o_data_unused),
        .base_address_register (base_address_register),
        .pcie_id               (pcie_id),
        .dbg_rd_valid          (bar_dbg_rd_valid_unused),
        .dbg_rd_info           (bar_dbg_rd_info_unused),
        .dbg_wr_valid          (bar_dbg_wr_valid_unused),
        .dbg_wr_info           (bar_dbg_wr_info_unused),
        .tlps_in               (tlps_cq_event.sink_lite),
        .tlps_out              (tlps_bar_rsp.source)
    );

    // CC only carries completions generated by AMDUSB4 cfgspace/BAR helpers.
    // Raw outbound TLPs from the host command FIFO use the independent RQ path.
    asmcehnk_tlps128_sink_mux1 cc_mux_inst (
        .rst            (rst),
        .clk_pcie       (clk),
        .tlps_out       (tlps_cc_mux.source),
        .tlps_in1       (tlps_cfg_rsp.sink),
        .tlps_in2       (tlps_bar_rsp.sink),
        .tlps_in3       (tlps_null1.sink),
        .tlps_in4       (tlps_null2.sink)
    );

    asmcehnk_tlps128_to_axis_cc_us tlps128_to_cc_inst (
        .clk        (clk),
        .rst        (rst),
        .tlps_in    (tlps_cc_mux.sink),
        .m_axis_cc  (axis_cc_normal)
    );

    asmcehnk_pcie_us_axis_cc_mux2 cc_axis_mux_inst (
        .clk             (clk),
        .rst             (rst),
        .s_axis_cc_error (axis_cc_error),
        .s_axis_cc_normal(axis_cc_normal),
        .m_axis_cc       (m_axis_pcie_cc)
    );

    asmcehnk_pcie_us_rc_to_tlps128 rc_to_tlps128_inst (
        .clk        (clk),
        .rst        (rst),
        .s_axis_rc  (s_axis_pcie_rc),
        .tlps_out   (tlps_rx_from_rc.source),
        .tag_release       (rc_tag_release),
        .tag_release_valid (rc_tag_release_valid)
    );

endmodule

module asmcehnk_tlps128_mux2 (
    input  wire logic clk,
    input  wire logic rst,

    IfAXIS128.sink   tlps_in1,
    IfAXIS128.sink   tlps_in2,
    IfAXIS128.source tlps_out
);

    logic [1:0] select_reg = 2'd0;

    wire [1:0] select_next;
    wire       output_fire;

    assign select_next = (select_reg != 2'd0) ? select_reg :
                         tlps_in1.tvalid       ? 2'd1 :
                         tlps_in2.tvalid       ? 2'd2 : 2'd0;
    assign output_fire = tlps_out.tvalid && tlps_out.tready;

    assign tlps_out.tdata = (select_next == 2'd1) ? tlps_in1.tdata :
                            (select_next == 2'd2) ? tlps_in2.tdata : 128'd0;
    assign tlps_out.tkeepdw = (select_next == 2'd1) ? tlps_in1.tkeepdw :
                              (select_next == 2'd2) ? tlps_in2.tkeepdw : 4'd0;
    assign tlps_out.tlast = (select_next == 2'd1) ? tlps_in1.tlast :
                            (select_next == 2'd2) ? tlps_in2.tlast : 1'b0;
    assign tlps_out.tuser = (select_next == 2'd1) ? tlps_in1.tuser :
                            (select_next == 2'd2) ? tlps_in2.tuser : 9'd0;
    assign tlps_out.tvalid = (select_next == 2'd1) ? tlps_in1.tvalid :
                             (select_next == 2'd2) ? tlps_in2.tvalid : 1'b0;
    assign tlps_out.has_data = tlps_in1.has_data || tlps_in2.has_data;

    assign tlps_in1.tready = tlps_out.tready && (select_next == 2'd1);
    assign tlps_in2.tready = tlps_out.tready && (select_next == 2'd2);

    always_ff @(posedge clk) begin
        if (rst) begin
            select_reg <= 2'd0;
        end else if (output_fire && tlps_out.tlast) begin
            select_reg <= 2'd0;
        end else if (select_reg == 2'd0 && select_next != 2'd0) begin
            select_reg <= select_next;
        end
    end

endmodule

module asmcehnk_pcie_us_axis_cc_mux2 (
    input  wire logic clk,
    input  wire logic rst,

    taxi_axis_if.snk s_axis_cc_error,
    taxi_axis_if.snk s_axis_cc_normal,
    taxi_axis_if.src m_axis_cc
);

    logic [1:0] cc_axis_select_reg = 2'd0;

    wire [1:0] cc_axis_select_next;
    wire       cc_axis_output_fire;

    assign cc_axis_select_next = (cc_axis_select_reg != 2'd0) ?
                                 cc_axis_select_reg :
                                 s_axis_cc_error.tvalid ? 2'd1 :
                                 s_axis_cc_normal.tvalid ? 2'd2 : 2'd0;
    assign cc_axis_output_fire = m_axis_cc.tvalid && m_axis_cc.tready;

    assign m_axis_cc.tdata = (cc_axis_select_next == 2'd1) ?
                             s_axis_cc_error.tdata :
                             (cc_axis_select_next == 2'd2) ?
                             s_axis_cc_normal.tdata : 256'd0;
    assign m_axis_cc.tkeep = (cc_axis_select_next == 2'd1) ?
                             s_axis_cc_error.tkeep :
                             (cc_axis_select_next == 2'd2) ?
                             s_axis_cc_normal.tkeep : 8'd0;
    assign m_axis_cc.tstrb = (cc_axis_select_next == 2'd1) ?
                             s_axis_cc_error.tstrb :
                             (cc_axis_select_next == 2'd2) ?
                             s_axis_cc_normal.tstrb : 8'd0;
    assign m_axis_cc.tlast = (cc_axis_select_next == 2'd1) ?
                             s_axis_cc_error.tlast :
                             (cc_axis_select_next == 2'd2) ?
                             s_axis_cc_normal.tlast : 1'b0;
    assign m_axis_cc.tuser = (cc_axis_select_next == 2'd1) ?
                             s_axis_cc_error.tuser :
                             (cc_axis_select_next == 2'd2) ?
                             s_axis_cc_normal.tuser : 33'd0;
    assign m_axis_cc.tid = (cc_axis_select_next == 2'd1) ?
                           s_axis_cc_error.tid :
                           (cc_axis_select_next == 2'd2) ?
                           s_axis_cc_normal.tid : '0;
    assign m_axis_cc.tdest = (cc_axis_select_next == 2'd1) ?
                             s_axis_cc_error.tdest :
                             (cc_axis_select_next == 2'd2) ?
                             s_axis_cc_normal.tdest : '0;
    assign m_axis_cc.tvalid = (cc_axis_select_next == 2'd1) ?
                              s_axis_cc_error.tvalid :
                              (cc_axis_select_next == 2'd2) ?
                              s_axis_cc_normal.tvalid : 1'b0;

    assign s_axis_cc_error.tready = m_axis_cc.tready &&
                                    (cc_axis_select_next == 2'd1);
    assign s_axis_cc_normal.tready = m_axis_cc.tready &&
                                     (cc_axis_select_next == 2'd2);

    always_ff @(posedge clk) begin
        if (rst) begin
            cc_axis_select_reg <= 2'd0;
        end else if (cc_axis_select_reg == 2'd0) begin
            if ((cc_axis_select_next != 2'd0) &&
                !(cc_axis_output_fire && m_axis_cc.tlast)) begin
                cc_axis_select_reg <= cc_axis_select_next;
            end
        end else if (cc_axis_output_fire && m_axis_cc.tlast) begin
            cc_axis_select_reg <= 2'd0;
        end
    end

endmodule

module asmcehnk_pcie_us_cq_to_tlps128 (
    input  wire logic clk,
    input  wire logic rst,
    input  wire logic [15:0] pcie_id,

    taxi_axis_if.snk s_axis_cq,
    IfAXIS128.source tlps_out,
    taxi_axis_if.src m_axis_cc_error
);

    localparam [3:0] REQ_MEM_READ  = 4'b0000;
    localparam [3:0] REQ_MEM_WRITE = 4'b0001;
    localparam integer CQ_CAPTURE_BEATS = 32'd17;

    typedef enum logic [2:0] {
        CQ_WRAP_IDLE,
        CQ_WRAP_CAPTURE,
        CQ_WRAP_REPLAY,
        CQ_WRAP_DRAIN,
        CQ_WRAP_DRAIN_UR
    } cq_wrap_state_t;

    cq_wrap_state_t state_reg = CQ_WRAP_IDLE;

    taxi_axis_if #(
        .DATA_W  (256),
        .KEEP_EN (1),
        .KEEP_W  (8),
        .USER_EN (1),
        .USER_W  (88)
    ) cq_replay();
    IfAXIS128 tlps_stream();

    logic [255:0] capture_data_mem [0:CQ_CAPTURE_BEATS-1];
    logic [7:0]   capture_keep_mem [0:CQ_CAPTURE_BEATS-1];
    logic [87:0]  capture_first_user_reg = 88'd0;
    logic [4:0]   capture_write_index_reg = 5'd0;
    logic [4:0]   capture_last_index_reg = 5'd0;
    logic [4:0]   replay_index_reg = 5'd0;
    logic [10:0]  capture_remaining_reg = 11'd0;

    logic [255:0] error_cc_tdata_reg = 256'd0;
    logic         error_cc_tvalid_reg = 1'b0;

    wire [63:0] wrap_cq_addr;
    wire [10:0] wrap_cq_len_dw;
    wire [3:0]  wrap_cq_type;
    wire [15:0] wrap_cq_requester_id;
    wire [7:0]  wrap_cq_tag;
    wire [2:0]  wrap_cq_tc;
    wire [2:0]  wrap_cq_attr;
    wire [2:0]  cq_first_payload_count;
    wire [3:0]  capture_beat_dw_count;
    wire        cq_first_expected_last;
    wire        capture_expected_last;
    wire        cq_mrd_supported;
    wire        cq_mrd_shape_valid;
    wire        cq_mwr_supported;
    wire        cq_request_is_posted;
    wire        cq_descriptor_valid;
    wire        wrap_cq_fire;
    wire        replay_fire;
    wire        error_cc_fire;

    logic [7:0] cq_first_expected_keep;
    logic [7:0] capture_expected_keep;
    logic [95:0] error_cc_desc_next;
    logic [31:0] error_cc_info_next;
    logic [255:0] error_cc_tdata_next;

    assign wrap_cq_addr = {s_axis_cq.tdata[63:2], 2'b00};
    assign wrap_cq_len_dw = s_axis_cq.tdata[74:64];
    assign wrap_cq_type = s_axis_cq.tdata[78:75];
    assign wrap_cq_requester_id = s_axis_cq.tdata[95:80];
    assign wrap_cq_tag = s_axis_cq.tdata[103:96];
    assign wrap_cq_tc = s_axis_cq.tdata[123:121];
    assign wrap_cq_attr = s_axis_cq.tdata[126:124];
    assign cq_first_payload_count = (wrap_cq_len_dw >= 11'd4) ? 3'd4 :
                                     wrap_cq_len_dw[2:0];
    assign capture_beat_dw_count = (capture_remaining_reg >= 11'd8) ? 4'd8 :
                                   {1'b0, capture_remaining_reg[2:0]};
    assign cq_first_expected_last = wrap_cq_len_dw <= 11'd4;
    assign capture_expected_last = capture_remaining_reg <= 11'd8;
    assign cq_mrd_supported = (wrap_cq_type == REQ_MEM_READ) &&
                              (wrap_cq_addr[63:32] == 32'd0) &&
                              (wrap_cq_len_dw != 11'd0);
    assign cq_mrd_shape_valid = (s_axis_cq.tkeep == 8'h0f) &&
                                s_axis_cq.tlast;
    // The active PCIe4 profile advertises a 512-byte maximum payload, so all
    // legal CQ MWr packets fit in one 17-beat native capture buffer.
    assign cq_mwr_supported = (wrap_cq_type == REQ_MEM_WRITE) &&
                              (wrap_cq_addr[63:32] == 32'd0) &&
                              (wrap_cq_len_dw != 11'd0) &&
                              (wrap_cq_len_dw <= 11'd128);
    assign cq_request_is_posted = (wrap_cq_type == REQ_MEM_WRITE) ||
                                   ((wrap_cq_type & 4'b1100) == 4'b1100);
    assign cq_descriptor_valid = (s_axis_cq.tkeep[3:0] == 4'hf);
    assign wrap_cq_fire = s_axis_cq.tvalid && s_axis_cq.tready;
    assign replay_fire = cq_replay.tvalid && cq_replay.tready;
    assign error_cc_fire = error_cc_tvalid_reg && m_axis_cc_error.tready;

    always_comb begin
        case (cq_first_payload_count)
            3'd1: cq_first_expected_keep = 8'b0001_1111;
            3'd2: cq_first_expected_keep = 8'b0011_1111;
            3'd3: cq_first_expected_keep = 8'b0111_1111;
            3'd4: cq_first_expected_keep = 8'b1111_1111;
            default: cq_first_expected_keep = 8'b0000_1111;
        endcase
    end

    always_comb begin
        case (capture_beat_dw_count)
            4'd1: capture_expected_keep = 8'b0000_0001;
            4'd2: capture_expected_keep = 8'b0000_0011;
            4'd3: capture_expected_keep = 8'b0000_0111;
            4'd4: capture_expected_keep = 8'b0000_1111;
            4'd5: capture_expected_keep = 8'b0001_1111;
            4'd6: capture_expected_keep = 8'b0011_1111;
            4'd7: capture_expected_keep = 8'b0111_1111;
            4'd8: capture_expected_keep = 8'b1111_1111;
            default: capture_expected_keep = 8'b0000_0000;
        endcase
    end

    always_comb begin
        error_cc_desc_next = 96'd0;
        error_cc_desc_next[28:16] = 13'd20;
        error_cc_desc_next[42:32] = 11'd5;
        error_cc_desc_next[45:43] = 3'b001;
        error_cc_desc_next[63:48] = wrap_cq_requester_id;
        error_cc_desc_next[71:64] = wrap_cq_tag;
        error_cc_desc_next[87:72] = pcie_id;
        error_cc_desc_next[88] = 1'b1;
        error_cc_desc_next[91:89] = wrap_cq_tc;
        error_cc_desc_next[94:92] = wrap_cq_attr;

        error_cc_info_next = {8'b0, s_axis_cq.tuser[52:45], 5'b0,
                              s_axis_cq.tuser[44:43], s_axis_cq.tuser[42],
                              s_axis_cq.tuser[7:0]};
        error_cc_tdata_next = {s_axis_cq.tdata[127:0], error_cc_info_next,
                               error_cc_desc_next};
    end

    always_comb begin
        cq_replay.tdata = 256'd0;
        cq_replay.tkeep = 8'd0;
        cq_replay.tstrb = 8'd0;
        cq_replay.tvalid = 1'b0;
        cq_replay.tlast = 1'b0;
        cq_replay.tuser = 88'd0;
        cq_replay.tid = '0;
        cq_replay.tdest = '0;
        s_axis_cq.tready = 1'b0;

        case (state_reg)
            CQ_WRAP_IDLE: begin
                if (!tlps_stream.has_data && !error_cc_tvalid_reg) begin
                    if (cq_mrd_supported && cq_mrd_shape_valid) begin
                        cq_replay.tdata = s_axis_cq.tdata;
                        cq_replay.tkeep = s_axis_cq.tkeep;
                        cq_replay.tstrb = s_axis_cq.tstrb;
                        cq_replay.tvalid = s_axis_cq.tvalid;
                        cq_replay.tlast = s_axis_cq.tlast;
                        cq_replay.tuser = s_axis_cq.tuser;
                        cq_replay.tid = s_axis_cq.tid;
                        cq_replay.tdest = s_axis_cq.tdest;
                        s_axis_cq.tready = cq_replay.tready;
                    end else begin
                        s_axis_cq.tready = 1'b1;
                    end
                end
            end
            CQ_WRAP_CAPTURE,
            CQ_WRAP_DRAIN,
            CQ_WRAP_DRAIN_UR: s_axis_cq.tready = 1'b1;
            CQ_WRAP_REPLAY: begin
                cq_replay.tdata = capture_data_mem[replay_index_reg];
                cq_replay.tkeep = capture_keep_mem[replay_index_reg];
                cq_replay.tstrb = capture_keep_mem[replay_index_reg];
                cq_replay.tvalid = 1'b1;
                cq_replay.tlast = replay_index_reg == capture_last_index_reg;
                cq_replay.tuser = (replay_index_reg == 5'd0) ?
                                  capture_first_user_reg : 88'd0;
            end
            default: s_axis_cq.tready = 1'b0;
        endcase
    end

    assign tlps_out.tdata = tlps_stream.tdata;
    assign tlps_out.tkeepdw = tlps_stream.tkeepdw;
    assign tlps_out.tvalid = tlps_stream.tvalid;
    assign tlps_out.tlast = tlps_stream.tlast;
    assign tlps_out.tuser = tlps_stream.tuser;
    assign tlps_out.has_data = tlps_stream.has_data;
    assign tlps_stream.tready = tlps_out.tready;

    assign m_axis_cc_error.tdata = error_cc_tdata_reg;
    assign m_axis_cc_error.tkeep = 8'hff;
    assign m_axis_cc_error.tstrb = 8'hff;
    assign m_axis_cc_error.tvalid = error_cc_tvalid_reg;
    assign m_axis_cc_error.tlast = 1'b1;
    assign m_axis_cc_error.tuser = 33'd0;
    assign m_axis_cc_error.tid = '0;
    assign m_axis_cc_error.tdest = '0;

    asmcehnk_pcie_us_cq_to_tlps128_stream stream_inst (
        .clk       (clk),
        .rst       (rst),
        .s_axis_cq (cq_replay),
        .tlps_out  (tlps_stream.source)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg <= CQ_WRAP_IDLE;
            capture_first_user_reg <= 88'd0;
            capture_write_index_reg <= 5'd0;
            capture_last_index_reg <= 5'd0;
            replay_index_reg <= 5'd0;
            capture_remaining_reg <= 11'd0;
            error_cc_tdata_reg <= 256'd0;
            error_cc_tvalid_reg <= 1'b0;
        end else begin
            if (error_cc_fire) begin
                error_cc_tvalid_reg <= 1'b0;
            end

            case (state_reg)
                CQ_WRAP_IDLE: begin
                    if (wrap_cq_fire) begin
                        if (cq_mwr_supported) begin
                            capture_data_mem[0] <= s_axis_cq.tdata;
                            capture_keep_mem[0] <= s_axis_cq.tkeep;
                            capture_first_user_reg <= s_axis_cq.tuser;
                            if ((s_axis_cq.tkeep == cq_first_expected_keep) &&
                                (s_axis_cq.tlast == cq_first_expected_last)) begin
                                if (s_axis_cq.tlast) begin
                                    capture_last_index_reg <= 5'd0;
                                    replay_index_reg <= 5'd0;
                                    state_reg <= CQ_WRAP_REPLAY;
                                end else begin
                                    capture_write_index_reg <= 5'd1;
                                    capture_remaining_reg <= wrap_cq_len_dw -
                                                             cq_first_payload_count;
                                    state_reg <= CQ_WRAP_CAPTURE;
                                end
                            end else begin
                                state_reg <= s_axis_cq.tlast ? CQ_WRAP_IDLE :
                                                               CQ_WRAP_DRAIN;
                            end
                        end else if (cq_mrd_supported) begin
                            state_reg <= s_axis_cq.tlast ? CQ_WRAP_IDLE :
                                                           CQ_WRAP_DRAIN;
                        end else if (cq_request_is_posted) begin
                            state_reg <= s_axis_cq.tlast ? CQ_WRAP_IDLE :
                                                           CQ_WRAP_DRAIN;
                        end else if (cq_descriptor_valid && s_axis_cq.tlast) begin
                            error_cc_tdata_reg <= error_cc_tdata_next;
                            error_cc_tvalid_reg <= 1'b1;
                        end else if (cq_descriptor_valid) begin
                            error_cc_tdata_reg <= error_cc_tdata_next;
                            state_reg <= CQ_WRAP_DRAIN_UR;
                        end else begin
                            state_reg <= s_axis_cq.tlast ? CQ_WRAP_IDLE :
                                                           CQ_WRAP_DRAIN;
                        end
                    end
                end
                CQ_WRAP_CAPTURE: begin
                    if (wrap_cq_fire) begin
                        if ((s_axis_cq.tkeep == capture_expected_keep) &&
                            (s_axis_cq.tlast == capture_expected_last)) begin
                            capture_data_mem[capture_write_index_reg] <=
                                s_axis_cq.tdata;
                            capture_keep_mem[capture_write_index_reg] <=
                                s_axis_cq.tkeep;
                            if (s_axis_cq.tlast) begin
                                capture_last_index_reg <= capture_write_index_reg;
                                replay_index_reg <= 5'd0;
                                state_reg <= CQ_WRAP_REPLAY;
                            end else begin
                                capture_write_index_reg <=
                                    capture_write_index_reg + 1'b1;
                                capture_remaining_reg <= capture_remaining_reg -
                                                         capture_beat_dw_count;
                            end
                        end else begin
                            state_reg <= s_axis_cq.tlast ? CQ_WRAP_IDLE :
                                                           CQ_WRAP_DRAIN;
                        end
                    end
                end
                CQ_WRAP_REPLAY: begin
                    if (replay_fire) begin
                        if (replay_index_reg == capture_last_index_reg) begin
                            state_reg <= CQ_WRAP_IDLE;
                        end else begin
                            replay_index_reg <= replay_index_reg + 1'b1;
                        end
                    end
                end
                CQ_WRAP_DRAIN: begin
                    if (wrap_cq_fire && s_axis_cq.tlast) begin
                        state_reg <= CQ_WRAP_IDLE;
                    end
                end
                CQ_WRAP_DRAIN_UR: begin
                    if (wrap_cq_fire && s_axis_cq.tlast) begin
                        error_cc_tvalid_reg <= 1'b1;
                        state_reg <= CQ_WRAP_IDLE;
                    end
                end
                default: state_reg <= CQ_WRAP_IDLE;
            endcase
        end
    end

endmodule
module asmcehnk_pcie_us_cq_to_tlps128_stream (
    input  wire logic clk,
    input  wire logic rst,

    taxi_axis_if.snk s_axis_cq,
    IfAXIS128.source tlps_out
);

    localparam [3:0] REQ_MEM_READ  = 4'b0000;
    localparam [3:0] REQ_MEM_WRITE = 4'b0001;

    typedef enum logic [1:0] {
        CQ_STATE_IDLE,
        CQ_STATE_FLUSH,
        CQ_STATE_PAYLOAD,
        CQ_STATE_DRAIN
    } cq_state_t;

    cq_state_t state_reg = CQ_STATE_IDLE;

    logic [127:0] out_tdata_reg = '0;
    logic [3:0]   out_tkeepdw_reg = '0;
    logic         out_tvalid_reg = 1'b0;
    logic         out_tlast_reg = 1'b0;
    logic [8:0]   out_tuser_reg = '0;

    logic [127:0] pending_data_reg = '0;
    logic [2:0]   pending_count_reg = '0;
    logic         pending_last_reg = 1'b0;
    logic [10:0]  remaining_dw_reg = '0;

    assign tlps_out.tdata   = out_tdata_reg;
    assign tlps_out.tkeepdw = out_tkeepdw_reg;
    assign tlps_out.tvalid  = out_tvalid_reg;
    assign tlps_out.tlast   = out_tlast_reg;
    assign tlps_out.tuser   = out_tuser_reg;
    assign tlps_out.has_data = out_tvalid_reg || (state_reg != CQ_STATE_IDLE);

    wire cq_output_ready;

    assign cq_output_ready = !out_tvalid_reg || tlps_out.tready;
    assign s_axis_cq.tready = cq_output_ready &&
                              ((state_reg == CQ_STATE_IDLE) ||
                               (state_reg == CQ_STATE_PAYLOAD) ||
                               (state_reg == CQ_STATE_DRAIN));

    wire        cq_fire;
    wire [63:0] cq_addr;
    wire [10:0] cq_len_dw;
    wire [9:0]  cq_len10;
    wire [3:0]  cq_type;
    wire [15:0] cq_requester_id;
    wire [7:0]  cq_tag;
    wire [2:0]  cq_bar_id;
    wire [2:0]  cq_tc;
    wire [2:0]  cq_attr;
    wire [3:0]  cq_first_be;
    wire [3:0]  cq_last_be;
    wire [31:0] cq_payload_dw0_swap;
    wire [31:0] cq_payload_dw1_swap;
    wire [31:0] cq_payload_dw2_swap;
    wire [31:0] cq_payload_dw3_swap;
    wire [31:0] cq_payload_dw4_swap;
    wire [31:0] cq_payload_dw5_swap;
    wire [31:0] cq_payload_dw6_swap;
    wire [31:0] cq_payload_dw7_swap;

    logic [6:0]  cq_bar_onehot;
    logic [31:0] cq_raw_mem_read_dw0;
    logic [31:0] cq_raw_mem_write_dw0;

    assign cq_fire = s_axis_cq.tvalid && s_axis_cq.tready;
    assign cq_addr = {s_axis_cq.tdata[63:2], 2'b00};
    assign cq_len_dw = s_axis_cq.tdata[74:64];
    assign cq_len10 = cq_len_dw[10] ? 10'd0 : cq_len_dw[9:0];
    assign cq_type = s_axis_cq.tdata[78:75];
    assign cq_requester_id = s_axis_cq.tdata[95:80];
    assign cq_tag = s_axis_cq.tdata[103:96];
    assign cq_bar_id = s_axis_cq.tdata[114:112];
    assign cq_tc = s_axis_cq.tdata[123:121];
    assign cq_attr = s_axis_cq.tdata[126:124];
    assign cq_first_be = s_axis_cq.tuser[3:0];
    assign cq_last_be = s_axis_cq.tuser[7:4];
    assign cq_payload_dw0_swap = {s_axis_cq.tdata[135:128], s_axis_cq.tdata[143:136], s_axis_cq.tdata[151:144], s_axis_cq.tdata[159:152]};
    assign cq_payload_dw1_swap = {s_axis_cq.tdata[167:160], s_axis_cq.tdata[175:168], s_axis_cq.tdata[183:176], s_axis_cq.tdata[191:184]};
    assign cq_payload_dw2_swap = {s_axis_cq.tdata[199:192], s_axis_cq.tdata[207:200], s_axis_cq.tdata[215:208], s_axis_cq.tdata[223:216]};
    assign cq_payload_dw3_swap = {s_axis_cq.tdata[231:224], s_axis_cq.tdata[239:232], s_axis_cq.tdata[247:240], s_axis_cq.tdata[255:248]};
    assign cq_payload_dw4_swap = {s_axis_cq.tdata[7:0], s_axis_cq.tdata[15:8], s_axis_cq.tdata[23:16], s_axis_cq.tdata[31:24]};
    assign cq_payload_dw5_swap = {s_axis_cq.tdata[39:32], s_axis_cq.tdata[47:40], s_axis_cq.tdata[55:48], s_axis_cq.tdata[63:56]};
    assign cq_payload_dw6_swap = {s_axis_cq.tdata[71:64], s_axis_cq.tdata[79:72], s_axis_cq.tdata[87:80], s_axis_cq.tdata[95:88]};
    assign cq_payload_dw7_swap = {s_axis_cq.tdata[103:96], s_axis_cq.tdata[111:104], s_axis_cq.tdata[119:112], s_axis_cq.tdata[127:120]};

    always_comb begin
        case (cq_bar_id)
            3'd0: cq_bar_onehot = 7'b0000001;
            3'd1: cq_bar_onehot = 7'b0000010;
            3'd2: cq_bar_onehot = 7'b0000100;
            3'd3: cq_bar_onehot = 7'b0001000;
            3'd4: cq_bar_onehot = 7'b0010000;
            3'd5: cq_bar_onehot = 7'b0100000;
            default: cq_bar_onehot = 7'b1000000;
        endcase
    end

    always_comb begin
        cq_raw_mem_read_dw0 = {3'b000, 5'b00000, 1'b0, cq_tc, 1'b0, cq_attr[2],
                               1'b0, 1'b0, 1'b0, 1'b0, cq_attr[1:0], 2'b00, cq_len10};
        cq_raw_mem_write_dw0 = {3'b010, 5'b00000, 1'b0, cq_tc, 1'b0, cq_attr[2],
                                1'b0, 1'b0, 1'b0, 1'b0, cq_attr[1:0], 2'b00, cq_len10};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg <= CQ_STATE_IDLE;
            out_tdata_reg <= '0;
            out_tkeepdw_reg <= '0;
            out_tvalid_reg <= 1'b0;
            out_tlast_reg <= 1'b0;
            out_tuser_reg <= '0;
            pending_data_reg <= '0;
            pending_count_reg <= '0;
            pending_last_reg <= 1'b0;
            remaining_dw_reg <= '0;
        end else if (cq_output_ready) begin
            out_tvalid_reg <= 1'b0;
            out_tdata_reg <= '0;
            out_tkeepdw_reg <= '0;
            out_tlast_reg <= 1'b0;
            out_tuser_reg <= '0;

            case (state_reg)
                CQ_STATE_IDLE: begin
                    if (cq_fire) begin
                        if ((cq_type == REQ_MEM_READ) && (cq_addr[63:32] == 32'd0) && (cq_len_dw != 11'd0)) begin
                            out_tdata_reg[31:0]  <= cq_raw_mem_read_dw0;
                            out_tdata_reg[63:32] <= {cq_requester_id, cq_tag, cq_last_be, cq_first_be};
                            out_tdata_reg[95:64] <= {cq_addr[31:2], 2'b00};
                            out_tdata_reg[127:96] <= 32'd0;
                            out_tkeepdw_reg <= 4'b0111;
                            out_tlast_reg <= 1'b1;
                            out_tvalid_reg <= 1'b1;
                            out_tuser_reg <= {cq_bar_onehot, 1'b1, 1'b1};
                            state_reg <= s_axis_cq.tlast ? CQ_STATE_IDLE : CQ_STATE_DRAIN;
                        end else if ((cq_type == REQ_MEM_WRITE) && (cq_addr[63:32] == 32'd0) && (cq_len_dw != 11'd0)) begin
                            logic [2:0] first_count;
                            logic [10:0] rem_after_first;
                            if (cq_len_dw > 11'd4) begin
                                first_count = 3'd4;
                            end else begin
                                first_count = cq_len_dw[2:0];
                            end
                            rem_after_first = cq_len_dw - first_count;

                            out_tdata_reg[31:0]  <= cq_raw_mem_write_dw0;
                            out_tdata_reg[63:32] <= {cq_requester_id, cq_tag, cq_last_be, cq_first_be};
                            out_tdata_reg[95:64] <= {cq_addr[31:2], 2'b00};
                            out_tdata_reg[127:96] <= cq_payload_dw0_swap;
                            out_tkeepdw_reg <= 4'b1111;
                            out_tlast_reg <= (cq_len_dw == 11'd1) && s_axis_cq.tlast;
                            out_tvalid_reg <= 1'b1;
                            out_tuser_reg <= {cq_bar_onehot, ((cq_len_dw == 11'd1) && s_axis_cq.tlast), 1'b1};

                            pending_data_reg[31:0]   <= cq_payload_dw1_swap;
                            pending_data_reg[63:32]  <= cq_payload_dw2_swap;
                            pending_data_reg[95:64]  <= cq_payload_dw3_swap;
                            pending_data_reg[127:96] <= 32'd0;
                            pending_count_reg <= (first_count == 3'd0) ? 3'd0 : (first_count - 3'd1);
                            pending_last_reg <= (rem_after_first == 11'd0) && s_axis_cq.tlast;
                            remaining_dw_reg <= rem_after_first;

                            if (first_count > 3'd1) begin
                                state_reg <= CQ_STATE_FLUSH;
                            end else if (rem_after_first != 11'd0) begin
                                state_reg <= CQ_STATE_PAYLOAD;
                            end else begin
                                state_reg <= s_axis_cq.tlast ? CQ_STATE_IDLE : CQ_STATE_DRAIN;
                            end
                        end else begin
                            // Unsupported CQ request for this first BAR gate.
                            state_reg <= s_axis_cq.tlast ? CQ_STATE_IDLE : CQ_STATE_DRAIN;
                        end
                    end
                end
                CQ_STATE_FLUSH: begin
                    out_tdata_reg <= pending_data_reg;
                    case (pending_count_reg)
                        3'd0: out_tkeepdw_reg <= 4'b0000;
                        3'd1: out_tkeepdw_reg <= 4'b0001;
                        3'd2: out_tkeepdw_reg <= 4'b0011;
                        3'd3: out_tkeepdw_reg <= 4'b0111;
                        default: out_tkeepdw_reg <= 4'b1111;
                    endcase
                    out_tlast_reg <= pending_last_reg;
                    out_tvalid_reg <= (pending_count_reg != 3'd0);
                    out_tuser_reg <= {7'd0, pending_last_reg, 1'b0};
                    pending_count_reg <= 3'd0;
                    pending_last_reg <= 1'b0;

                    if (remaining_dw_reg != 11'd0) begin
                        state_reg <= CQ_STATE_PAYLOAD;
                    end else begin
                        state_reg <= pending_last_reg ? CQ_STATE_IDLE : CQ_STATE_DRAIN;
                    end
                end
                CQ_STATE_PAYLOAD: begin
                    if (cq_fire) begin
                        logic [2:0] lower_count;
                        logic [2:0] upper_count;
                        logic [10:0] rem_after_lower;
                        logic [10:0] rem_after_beat;
                        if (remaining_dw_reg > 11'd4) begin
                            lower_count = 3'd4;
                        end else begin
                            lower_count = remaining_dw_reg[2:0];
                        end
                        rem_after_lower = remaining_dw_reg - lower_count;
                        if (rem_after_lower > 11'd4) begin
                            upper_count = 3'd4;
                        end else begin
                            upper_count = rem_after_lower[2:0];
                        end
                        rem_after_beat = rem_after_lower - upper_count;

                        out_tdata_reg[31:0]   <= cq_payload_dw4_swap;
                        out_tdata_reg[63:32]  <= cq_payload_dw5_swap;
                        out_tdata_reg[95:64]  <= cq_payload_dw6_swap;
                        out_tdata_reg[127:96] <= cq_payload_dw7_swap;
                        case (lower_count)
                            3'd0: out_tkeepdw_reg <= 4'b0000;
                            3'd1: out_tkeepdw_reg <= 4'b0001;
                            3'd2: out_tkeepdw_reg <= 4'b0011;
                            3'd3: out_tkeepdw_reg <= 4'b0111;
                            default: out_tkeepdw_reg <= 4'b1111;
                        endcase
                        out_tlast_reg <= (upper_count == 3'd0) && (rem_after_beat == 11'd0) && s_axis_cq.tlast;
                        out_tvalid_reg <= (lower_count != 3'd0);
                        out_tuser_reg <= {7'd0, ((upper_count == 3'd0) && (rem_after_beat == 11'd0) && s_axis_cq.tlast), 1'b0};

                        pending_data_reg[31:0]   <= cq_payload_dw0_swap;
                        pending_data_reg[63:32]  <= cq_payload_dw1_swap;
                        pending_data_reg[95:64]  <= cq_payload_dw2_swap;
                        pending_data_reg[127:96] <= cq_payload_dw3_swap;
                        pending_count_reg <= upper_count;
                        pending_last_reg <= (upper_count != 3'd0) && (rem_after_beat == 11'd0) && s_axis_cq.tlast;
                        remaining_dw_reg <= rem_after_beat;

                        if (upper_count != 3'd0) begin
                            state_reg <= CQ_STATE_FLUSH;
                        end else if (rem_after_beat != 11'd0) begin
                            state_reg <= CQ_STATE_PAYLOAD;
                        end else begin
                            state_reg <= s_axis_cq.tlast ? CQ_STATE_IDLE : CQ_STATE_DRAIN;
                        end
                    end
                end
                CQ_STATE_DRAIN: begin
                    if (cq_fire && s_axis_cq.tlast) begin
                        state_reg <= CQ_STATE_IDLE;
                    end
                end
                default: state_reg <= CQ_STATE_IDLE;
            endcase
        end
    end

endmodule


module asmcehnk_tlps128_to_axis_rq_us #(
    parameter RQ_SEQ_NUM_W = 6
)(
    input  wire logic clk,
    input  wire logic rst,

    IfAXIS128.sink   tlps_in,
    taxi_axis_if.src m_axis_rq,

    input wire logic [RQ_SEQ_NUM_W-1:0] pcie_rq_seq_num0,
    input wire logic                    pcie_rq_seq_num_vld0,
    input wire logic [RQ_SEQ_NUM_W-1:0] pcie_rq_seq_num1,
    input wire logic                    pcie_rq_seq_num_vld1,

    input wire logic [7:0]              rc_tag_release,
    input wire logic                    rc_tag_release_valid,

    output wire logic [RQ_SEQ_NUM_W:0]  status_outstanding,
    output wire logic                   status_blocked,
    output wire logic                   status_error,
    output wire logic                   status_tag_blocked,
    output wire logic                   status_tag_error
);

    localparam int RQ_USER_W = m_axis_rq.USER_W;
    localparam int RQ_SEQ_COUNT = 1 << RQ_SEQ_NUM_W;
    localparam int RQ_OUTSTANDING_LIMIT = 1 << (RQ_SEQ_NUM_W-1);

    localparam [3:0] REQ_MEM_READ  = 4'b0000;
    localparam [3:0] REQ_MEM_WRITE = 4'b0001;

    typedef enum logic [1:0] {
        RQ_STATE_IDLE,
        RQ_STATE_PAYLOAD,
        RQ_STATE_DRAIN
    } rq_state_t;

    rq_state_t state_reg = RQ_STATE_IDLE;

    logic [255:0] out_tdata_reg = '0;
    logic [7:0]   out_tkeep_reg = '0;
    logic [RQ_USER_W-1:0] out_tuser_reg = '0;
    logic         out_tlast_reg = 1'b0;
    logic         out_tvalid_reg = 1'b0;

    logic [RQ_SEQ_NUM_W-1:0] seq_alloc_reg = '0;
    logic [RQ_SEQ_COUNT-1:0] seq_pending_reg = '0;
    logic [RQ_SEQ_COUNT-1:0] seq_pending_next;
    logic [RQ_SEQ_NUM_W:0]   seq_outstanding_reg = '0;
    logic [RQ_SEQ_NUM_W:0]   seq_outstanding_next;
    logic                    seq_error_reg = 1'b0;
    logic [255:0]            tag_pending_reg = '0;
    logic [255:0]            tag_pending_next;
    logic                    tag_error_reg = 1'b0;

    assign m_axis_rq.tdata = out_tdata_reg;
    assign m_axis_rq.tkeep = out_tkeep_reg;
    assign m_axis_rq.tstrb = out_tkeep_reg;
    assign m_axis_rq.tuser = out_tuser_reg;
    assign m_axis_rq.tlast = out_tlast_reg;
    assign m_axis_rq.tvalid = out_tvalid_reg;
    assign m_axis_rq.tid = '0;
    assign m_axis_rq.tdest = '0;

    wire output_ready;
    wire rq_input_fire;
    wire rq_start_needs_credit;
    wire rq_credit_available;
    wire rq_seq_launch;
    wire rq_seq_ack0;
    wire rq_seq_ack1;
    wire rq_tag_launch;
    wire rq_tag_blocked;
    wire rc_tag_release_known;
    wire [31:0] raw_dw0;
    wire [31:0] raw_dw1;
    wire [31:0] raw_dw2;
    wire [31:0] raw_dw3;
    wire [2:0]  raw_fmt;
    wire [4:0]  raw_type;
    wire [9:0]  raw_len10;
    wire [10:0] raw_len10_ext;
    wire [10:0] raw_len11;
    wire        raw_is_4dw;
    wire        raw_is_mrd;
    wire        raw_is_mwr;
    wire        raw_hdr_present;
    wire [31:0] raw_dw0_swap;
    wire [31:0] raw_dw1_swap;
    wire [31:0] raw_dw2_swap;
    wire [31:0] raw_dw3_swap;
    wire [63:0] raw_addr64;
    wire [7:0]  raw_tag;

    logic [127:0] rq_desc_read;
    logic [127:0] rq_desc_write;
    logic [RQ_USER_W-1:0] rq_tuser_next;

    assign output_ready = !out_tvalid_reg || m_axis_rq.tready;
    assign rq_start_needs_credit = (state_reg == RQ_STATE_IDLE) &&
                                   tlps_in.tvalid && raw_hdr_present &&
                                   (raw_is_mrd || raw_is_mwr);
    assign rq_credit_available = (seq_outstanding_reg < RQ_OUTSTANDING_LIMIT) &&
                                 !seq_pending_reg[seq_alloc_reg];
    assign rq_tag_blocked = (state_reg == RQ_STATE_IDLE) &&
                            tlps_in.tvalid && raw_hdr_present && raw_is_mrd &&
                            tag_pending_reg[raw_tag];
    assign tlps_in.tready = output_ready &&
                            (!rq_start_needs_credit || rq_credit_available) &&
                            !rq_tag_blocked;

    assign rq_input_fire = tlps_in.tvalid && tlps_in.tready;
    assign raw_dw0 = tlps_in.tdata[31:0];
    assign raw_dw1 = tlps_in.tdata[63:32];
    assign raw_dw2 = tlps_in.tdata[95:64];
    assign raw_dw3 = tlps_in.tdata[127:96];
    assign raw_fmt = raw_dw0[31:29];
    assign raw_type = raw_dw0[28:24];
    assign raw_len10 = raw_dw0[9:0];
    assign raw_len10_ext = {1'b0, raw_len10};
    assign raw_len11 = (raw_len10_ext == 11'd0) ? 11'd1024 : raw_len10_ext;
    assign raw_is_4dw = raw_fmt[0];
    assign raw_is_mrd = (raw_type == 5'b00000) && ((raw_fmt == 3'b000) || (raw_fmt == 3'b001));
    assign raw_is_mwr = (raw_type == 5'b00000) && ((raw_fmt == 3'b010) || (raw_fmt == 3'b011));
    assign raw_hdr_present = tlps_in.tuser[0] && tlps_in.tkeepdw[0] && tlps_in.tkeepdw[1] &&
                             tlps_in.tkeepdw[2] && (!raw_is_4dw || tlps_in.tkeepdw[3]);
    assign raw_dw0_swap = {tlps_in.tdata[7:0], tlps_in.tdata[15:8], tlps_in.tdata[23:16], tlps_in.tdata[31:24]};
    assign raw_dw1_swap = {tlps_in.tdata[39:32], tlps_in.tdata[47:40], tlps_in.tdata[55:48], tlps_in.tdata[63:56]};
    assign raw_dw2_swap = {tlps_in.tdata[71:64], tlps_in.tdata[79:72], tlps_in.tdata[87:80], tlps_in.tdata[95:88]};
    assign raw_dw3_swap = {tlps_in.tdata[103:96], tlps_in.tdata[111:104], tlps_in.tdata[119:112], tlps_in.tdata[127:120]};
    assign raw_addr64 = raw_is_4dw ? {raw_dw2, raw_dw3[31:2], 2'b00} :
                                    {32'd0, raw_dw2[31:2], 2'b00};
    assign raw_tag = raw_dw1[15:8];

    assign rq_seq_launch = rq_input_fire && (state_reg == RQ_STATE_IDLE) &&
                           raw_hdr_present && (raw_is_mrd || raw_is_mwr);
    assign rq_tag_launch = rq_seq_launch && raw_is_mrd;
    assign rq_seq_ack0 = pcie_rq_seq_num_vld0 &&
                         seq_pending_reg[pcie_rq_seq_num0];
    assign rq_seq_ack1 = pcie_rq_seq_num_vld1 &&
                         seq_pending_reg[pcie_rq_seq_num1] &&
                         !(pcie_rq_seq_num_vld0 &&
                           (pcie_rq_seq_num0 == pcie_rq_seq_num1));
    assign status_outstanding = seq_outstanding_reg;
    assign status_blocked = rq_start_needs_credit && !rq_credit_available;
    assign status_error = seq_error_reg;
    assign status_tag_blocked = rq_tag_blocked;
    assign status_tag_error = tag_error_reg;
    assign rc_tag_release_known = rc_tag_release_valid &&
                                  tag_pending_reg[rc_tag_release];

    always_comb begin
        seq_pending_next = seq_pending_reg;
        seq_outstanding_next = seq_outstanding_reg;

        if (rq_seq_ack0) begin
            seq_pending_next[pcie_rq_seq_num0] = 1'b0;
            seq_outstanding_next = seq_outstanding_next - 1'b1;
        end
        if (rq_seq_ack1) begin
            seq_pending_next[pcie_rq_seq_num1] = 1'b0;
            seq_outstanding_next = seq_outstanding_next - 1'b1;
        end
        if (rq_seq_launch) begin
            seq_pending_next[seq_alloc_reg] = 1'b1;
            seq_outstanding_next = seq_outstanding_next + 1'b1;
        end
    end

    always_comb begin
        tag_pending_next = tag_pending_reg;

        if (rc_tag_release_known) begin
            tag_pending_next[rc_tag_release] = 1'b0;
        end
        if (rq_tag_launch) begin
            tag_pending_next[raw_tag] = 1'b1;
        end
    end

    always_comb begin
        rq_desc_read = '0;
        rq_desc_read[1:0] = raw_dw0[11:10];
        rq_desc_read[63:2] = raw_addr64[63:2];
        rq_desc_read[74:64] = raw_len11;
        rq_desc_read[78:75] = REQ_MEM_READ;
        rq_desc_read[79] = raw_dw0[14];
        rq_desc_read[95:80] = raw_dw1[31:16];
        rq_desc_read[103:96] = raw_dw1[15:8];
        rq_desc_read[119:104] = 16'd0;
        rq_desc_read[120] = 1'b0;
        rq_desc_read[123:121] = raw_dw0[22:20];
        rq_desc_read[126:124] = {raw_dw0[18], raw_dw0[13:12]};
        rq_desc_read[127] = 1'b0;

        rq_desc_write = rq_desc_read;
        rq_desc_write[78:75] = REQ_MEM_WRITE;
    end

    always_comb begin
        rq_tuser_next = '0;
        rq_tuser_next[3:0] = raw_dw1[3:0];
        rq_tuser_next[7:4] = raw_dw1[7:4];
        rq_tuser_next[10:8] = 3'd0;
        rq_tuser_next[11] = 1'b0;
        rq_tuser_next[12] = 1'b0;
        rq_tuser_next[14:13] = 2'b00;
        rq_tuser_next[15] = 1'b0;
        rq_tuser_next[23:16] = 8'd0;
        rq_tuser_next[27:24] = seq_alloc_reg[3:0];
        rq_tuser_next[59:28] = 32'd0;
        rq_tuser_next[61:60] = seq_alloc_reg[RQ_SEQ_NUM_W-1:4];
    end

    always_ff @(posedge clk) begin
        seq_pending_reg <= seq_pending_next;
        seq_outstanding_reg <= seq_outstanding_next;
        tag_pending_reg <= tag_pending_next;

        if ((pcie_rq_seq_num_vld0 && !rq_seq_ack0) ||
            (pcie_rq_seq_num_vld1 && !rq_seq_ack1)) begin
            seq_error_reg <= 1'b1;
        end
        if (rc_tag_release_valid && !rc_tag_release_known) begin
            tag_error_reg <= 1'b1;
        end

        if (output_ready) begin
            out_tdata_reg <= '0;
            out_tkeep_reg <= '0;
            out_tuser_reg <= '0;
            out_tlast_reg <= 1'b0;
            out_tvalid_reg <= 1'b0;

            if (rq_input_fire) begin
                case (state_reg)
                    RQ_STATE_IDLE: begin
                        if (raw_hdr_present && raw_is_mrd) begin
                            out_tdata_reg[127:0] <= rq_desc_read;
                            out_tkeep_reg <= 8'b0000_1111;
                            out_tuser_reg <= rq_tuser_next;
                            out_tlast_reg <= 1'b1;
                            out_tvalid_reg <= 1'b1;
                            seq_alloc_reg <= seq_alloc_reg + {{(RQ_SEQ_NUM_W-1){1'b0}}, 1'b1};
                            state_reg <= tlps_in.tlast ? RQ_STATE_IDLE : RQ_STATE_DRAIN;
                        end else if (raw_hdr_present && raw_is_mwr) begin
                            logic payload0_present;
                            payload0_present = !raw_is_4dw && tlps_in.tkeepdw[3];

                            out_tdata_reg[127:0] <= rq_desc_write;
                            out_tdata_reg[159:128] <= payload0_present ? raw_dw3_swap : 32'd0;
                            out_tkeep_reg <= payload0_present ? 8'b0001_1111 : 8'b0000_1111;
                            out_tuser_reg <= rq_tuser_next;
                            out_tlast_reg <= tlps_in.tlast;
                            out_tvalid_reg <= 1'b1;
                            seq_alloc_reg <= seq_alloc_reg + {{(RQ_SEQ_NUM_W-1){1'b0}}, 1'b1};
                            state_reg <= tlps_in.tlast ? RQ_STATE_IDLE : RQ_STATE_PAYLOAD;
                        end else begin
                            state_reg <= tlps_in.tlast ? RQ_STATE_IDLE : RQ_STATE_DRAIN;
                        end
                    end
                    RQ_STATE_PAYLOAD: begin
                        logic [2:0] payload_count;
                        payload_count = {2'd0, tlps_in.tkeepdw[0]} + {2'd0, tlps_in.tkeepdw[1]} +
                                        {2'd0, tlps_in.tkeepdw[2]} + {2'd0, tlps_in.tkeepdw[3]};

                        out_tdata_reg[31:0] <= raw_dw0_swap;
                        out_tdata_reg[63:32] <= raw_dw1_swap;
                        out_tdata_reg[95:64] <= raw_dw2_swap;
                        out_tdata_reg[127:96] <= raw_dw3_swap;
                        case (payload_count)
                            3'd0: out_tkeep_reg <= 8'b0000_0000;
                            3'd1: out_tkeep_reg <= 8'b0000_0001;
                            3'd2: out_tkeep_reg <= 8'b0000_0011;
                            3'd3: out_tkeep_reg <= 8'b0000_0111;
                            default: out_tkeep_reg <= 8'b0000_1111;
                        endcase
                        out_tuser_reg <= '0;
                        out_tlast_reg <= tlps_in.tlast;
                        out_tvalid_reg <= (payload_count != 3'd0);
                        state_reg <= tlps_in.tlast ? RQ_STATE_IDLE : RQ_STATE_PAYLOAD;
                    end
                    RQ_STATE_DRAIN: begin
                        state_reg <= tlps_in.tlast ? RQ_STATE_IDLE : RQ_STATE_DRAIN;
                    end
                    default: state_reg <= RQ_STATE_IDLE;
                endcase
            end
        end

        if (rst) begin
            state_reg <= RQ_STATE_IDLE;
            out_tdata_reg <= '0;
            out_tkeep_reg <= '0;
            out_tuser_reg <= '0;
            out_tlast_reg <= 1'b0;
            out_tvalid_reg <= 1'b0;
            seq_alloc_reg <= '0;
            seq_pending_reg <= '0;
            seq_outstanding_reg <= '0;
            seq_error_reg <= 1'b0;
            tag_pending_reg <= '0;
            tag_error_reg <= 1'b0;
        end
    end

endmodule

module asmcehnk_pcie_us_rc_to_tlps128 (
    input  wire logic clk,
    input  wire logic rst,

    taxi_axis_if.snk s_axis_rc,
    IfAXIS128.source tlps_out,

    output wire logic [7:0] tag_release,
    output wire logic       tag_release_valid
);

    typedef enum logic [0:0] {
        RC_STATE_IDLE,
        RC_STATE_FLUSH
    } rc_state_t;

    rc_state_t state_reg = RC_STATE_IDLE;

    logic [127:0] out_tdata_reg = '0;
    logic [3:0]   out_tkeepdw_reg = '0;
    logic         out_tvalid_reg = 1'b0;
    logic         out_tlast_reg = 1'b0;
    logic [8:0]   out_tuser_reg = '0;

    logic [127:0] pending_data_reg = '0;
    logic [2:0]   pending_count_reg = '0;
    logic         pending_last_reg = 1'b0;
    logic         frame_reg = 1'b0;
    logic [7:0]   release_tag_reg = 8'd0;
    logic         release_pending_reg = 1'b0;

    assign tlps_out.tdata = out_tdata_reg;
    assign tlps_out.tkeepdw = out_tkeepdw_reg;
    assign tlps_out.tvalid = out_tvalid_reg;
    assign tlps_out.tlast = out_tlast_reg;
    assign tlps_out.tuser = out_tuser_reg;
    assign tlps_out.has_data = out_tvalid_reg ||
                               (state_reg != RC_STATE_IDLE) || frame_reg;

    wire rc_output_ready;

    assign rc_output_ready = !out_tvalid_reg || tlps_out.tready;
    assign s_axis_rc.tready = rc_output_ready && (state_reg == RC_STATE_IDLE);
    wire rc_input_fire;
    wire [95:0] rc_desc;
    wire [10:0] rc_len_dw;
    wire [9:0]  rc_len10;
    wire        rc_has_data;
    wire [12:0] rc_byte_count;
    wire [12:0] rc_payload_bytes;
    wire [2:0]  rc_completion_status;
    wire        rc_completion_final;
    wire [31:0] rc_data_dw0_swap;
    wire [31:0] rc_data_dw1_swap;
    wire [31:0] rc_data_dw2_swap;
    wire [31:0] rc_data_dw3_swap;
    wire [31:0] rc_data_dw4_swap;
    wire [31:0] rc_data_dw5_swap;
    wire [31:0] rc_data_dw6_swap;
    wire [31:0] rc_data_dw7_swap;

    logic [3:0]  rc_valid_dw_count;
    logic [31:0] rc_raw_dw0_next;
    logic [31:0] rc_raw_dw1_next;
    logic [31:0] rc_raw_dw2_next;

    assign rc_input_fire = s_axis_rc.tvalid && s_axis_rc.tready;
    assign rc_desc = s_axis_rc.tdata[95:0];
    assign rc_len_dw = rc_desc[42:32];
    assign rc_len10 = rc_len_dw[10] ? 10'd0 : rc_len_dw[9:0];
    assign rc_has_data = (rc_len_dw != 11'd0);
    assign rc_byte_count = rc_desc[28:16];
    assign rc_payload_bytes = {rc_len_dw, 2'b00} -
                              {11'd0, rc_desc[1:0]};
    assign rc_completion_status = rc_desc[45:43];
    assign rc_completion_final = rc_desc[30] ||
                                 (rc_completion_status != 3'd0) ||
                                 !rc_has_data ||
                                 (rc_byte_count <= rc_payload_bytes);
    assign tag_release = frame_reg ? release_tag_reg : rc_desc[71:64];
    assign tag_release_valid = rc_input_fire && s_axis_rc.tlast &&
                               ((!frame_reg && rc_completion_final) ||
                                (frame_reg && release_pending_reg));
    assign rc_data_dw0_swap = {s_axis_rc.tdata[103:96], s_axis_rc.tdata[111:104], s_axis_rc.tdata[119:112], s_axis_rc.tdata[127:120]};
    assign rc_data_dw1_swap = {s_axis_rc.tdata[135:128], s_axis_rc.tdata[143:136], s_axis_rc.tdata[151:144], s_axis_rc.tdata[159:152]};
    assign rc_data_dw2_swap = {s_axis_rc.tdata[167:160], s_axis_rc.tdata[175:168], s_axis_rc.tdata[183:176], s_axis_rc.tdata[191:184]};
    assign rc_data_dw3_swap = {s_axis_rc.tdata[199:192], s_axis_rc.tdata[207:200], s_axis_rc.tdata[215:208], s_axis_rc.tdata[223:216]};
    assign rc_data_dw4_swap = {s_axis_rc.tdata[231:224], s_axis_rc.tdata[239:232], s_axis_rc.tdata[247:240], s_axis_rc.tdata[255:248]};
    assign rc_data_dw5_swap = {s_axis_rc.tdata[7:0], s_axis_rc.tdata[15:8], s_axis_rc.tdata[23:16], s_axis_rc.tdata[31:24]};
    assign rc_data_dw6_swap = {s_axis_rc.tdata[39:32], s_axis_rc.tdata[47:40], s_axis_rc.tdata[55:48], s_axis_rc.tdata[63:56]};
    assign rc_data_dw7_swap = {s_axis_rc.tdata[71:64], s_axis_rc.tdata[79:72], s_axis_rc.tdata[87:80], s_axis_rc.tdata[95:88]};

    always_comb begin
        rc_valid_dw_count = {3'd0, s_axis_rc.tkeep[0]} + {3'd0, s_axis_rc.tkeep[1]} +
                            {3'd0, s_axis_rc.tkeep[2]} + {3'd0, s_axis_rc.tkeep[3]} +
                            {3'd0, s_axis_rc.tkeep[4]} + {3'd0, s_axis_rc.tkeep[5]} +
                            {3'd0, s_axis_rc.tkeep[6]} + {3'd0, s_axis_rc.tkeep[7]};
    end

    always_comb begin
        rc_raw_dw0_next = {rc_has_data ? 3'b010 : 3'b000, 5'b01010,
                           1'b0, rc_desc[91:89], 1'b0, rc_desc[94],
                           1'b0, 1'b0, 1'b0, rc_desc[46], rc_desc[93:92],
                           rc_desc[9:8], rc_len10};
        rc_raw_dw1_next = {rc_desc[87:72], rc_desc[45:43], 1'b0, rc_desc[27:16]};
        rc_raw_dw2_next = {rc_desc[63:48], rc_desc[71:64], 1'b0, rc_desc[6:0]};
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg <= RC_STATE_IDLE;
            out_tdata_reg <= '0;
            out_tkeepdw_reg <= '0;
            out_tvalid_reg <= 1'b0;
            out_tlast_reg <= 1'b0;
            out_tuser_reg <= '0;
            pending_data_reg <= '0;
            pending_count_reg <= '0;
            pending_last_reg <= 1'b0;
            frame_reg <= 1'b0;
            release_tag_reg <= 8'd0;
            release_pending_reg <= 1'b0;
        end else if (rc_output_ready) begin
            out_tvalid_reg <= 1'b0;
            out_tdata_reg <= '0;
            out_tkeepdw_reg <= '0;
            out_tlast_reg <= 1'b0;
            out_tuser_reg <= '0;

            case (state_reg)
                RC_STATE_IDLE: begin
                    if (rc_input_fire) begin
                        if (!frame_reg) begin
                            if (rc_valid_dw_count >= 4'd3) begin
                                logic [2:0] payload_count;
                                logic payload0_present;
                                payload_count = rc_valid_dw_count - 4'd3;
                                payload0_present = (payload_count != 3'd0);

                                out_tdata_reg[31:0] <= rc_raw_dw0_next;
                                out_tdata_reg[63:32] <= rc_raw_dw1_next;
                                out_tdata_reg[95:64] <= rc_raw_dw2_next;
                                out_tdata_reg[127:96] <= payload0_present ? rc_data_dw0_swap : 32'd0;
                                out_tkeepdw_reg <= payload0_present ? 4'b1111 : 4'b0111;
                                out_tlast_reg <= s_axis_rc.tlast && (payload_count <= 3'd1);
                                out_tvalid_reg <= 1'b1;
                                out_tuser_reg <= {7'd0, (s_axis_rc.tlast && (payload_count <= 3'd1)), 1'b1};

                                pending_data_reg[31:0] <= rc_data_dw1_swap;
                                pending_data_reg[63:32] <= rc_data_dw2_swap;
                                pending_data_reg[95:64] <= rc_data_dw3_swap;
                                pending_data_reg[127:96] <= rc_data_dw4_swap;
                                pending_count_reg <= (payload_count > 3'd1) ? (payload_count - 3'd1) : 3'd0;
                                pending_last_reg <= s_axis_rc.tlast && (payload_count > 3'd1);
                                state_reg <= (payload_count > 3'd1) ? RC_STATE_FLUSH : RC_STATE_IDLE;
                            end
                            release_tag_reg <= rc_desc[71:64];
                            release_pending_reg <= rc_completion_final &&
                                                   !s_axis_rc.tlast;
                            frame_reg <= !s_axis_rc.tlast;
                        end else begin
                            logic [2:0] lower_count;
                            logic [2:0] upper_count;
                            lower_count = (rc_valid_dw_count > 4'd4) ? 3'd4 : rc_valid_dw_count[2:0];
                            upper_count = (rc_valid_dw_count > 4'd4) ? (rc_valid_dw_count[2:0] - 3'd4) : 3'd0;

                            out_tdata_reg[31:0] <= rc_data_dw5_swap;
                            out_tdata_reg[63:32] <= rc_data_dw6_swap;
                            out_tdata_reg[95:64] <= rc_data_dw7_swap;
                            out_tdata_reg[127:96] <= rc_data_dw0_swap;
                            case (lower_count)
                                3'd0: out_tkeepdw_reg <= 4'b0000;
                                3'd1: out_tkeepdw_reg <= 4'b0001;
                                3'd2: out_tkeepdw_reg <= 4'b0011;
                                3'd3: out_tkeepdw_reg <= 4'b0111;
                                default: out_tkeepdw_reg <= 4'b1111;
                            endcase
                            out_tlast_reg <= s_axis_rc.tlast && (upper_count == 3'd0);
                            out_tvalid_reg <= (lower_count != 3'd0);
                            out_tuser_reg <= {7'd0, (s_axis_rc.tlast && (upper_count == 3'd0)), 1'b0};

                            pending_data_reg[31:0] <= rc_data_dw1_swap;
                            pending_data_reg[63:32] <= rc_data_dw2_swap;
                            pending_data_reg[95:64] <= rc_data_dw3_swap;
                            pending_data_reg[127:96] <= rc_data_dw4_swap;
                            pending_count_reg <= upper_count;
                            pending_last_reg <= s_axis_rc.tlast && (upper_count != 3'd0);
                            state_reg <= (upper_count != 3'd0) ? RC_STATE_FLUSH : RC_STATE_IDLE;
                            if (s_axis_rc.tlast) begin
                                release_pending_reg <= 1'b0;
                            end
                            frame_reg <= !s_axis_rc.tlast;
                        end
                    end
                end
                RC_STATE_FLUSH: begin
                    out_tdata_reg <= pending_data_reg;
                    case (pending_count_reg)
                        3'd0: out_tkeepdw_reg <= 4'b0000;
                        3'd1: out_tkeepdw_reg <= 4'b0001;
                        3'd2: out_tkeepdw_reg <= 4'b0011;
                        3'd3: out_tkeepdw_reg <= 4'b0111;
                        default: out_tkeepdw_reg <= 4'b1111;
                    endcase
                    out_tlast_reg <= pending_last_reg;
                    out_tvalid_reg <= (pending_count_reg != 3'd0);
                    out_tuser_reg <= {7'd0, pending_last_reg, 1'b0};
                    pending_count_reg <= 3'd0;
                    pending_last_reg <= 1'b0;
                    state_reg <= RC_STATE_IDLE;
                end
                default: state_reg <= RC_STATE_IDLE;
            endcase
        end
    end

endmodule

module asmcehnk_tlps128_to_axis_cc_us (
    input  wire logic clk,
    input  wire logic rst,

    IfAXIS128.sink    tlps_in,
    taxi_axis_if.src  m_axis_cc
);

    logic [255:0] out_tdata_reg = '0;
    logic [7:0]   out_tkeep_reg = '0;
    logic         out_tvalid_reg = 1'b0;
    logic         out_tlast_reg = 1'b0;

    logic [383:0] pack_data_reg = '0;
    logic [3:0]   pack_count_reg = '0;
    logic         pack_last_reg = 1'b0;

    assign m_axis_cc.tdata = out_tdata_reg;
    assign m_axis_cc.tkeep = out_tkeep_reg;
    assign m_axis_cc.tstrb = out_tkeep_reg;
    assign m_axis_cc.tvalid = out_tvalid_reg;
    assign m_axis_cc.tlast = out_tlast_reg;
    assign m_axis_cc.tuser = 33'd0;
    assign m_axis_cc.tid = '0;
    assign m_axis_cc.tdest = '0;

    wire cc_output_ready;

    assign cc_output_ready = !out_tvalid_reg || m_axis_cc.tready;
    assign tlps_in.tready = cc_output_ready && !pack_last_reg &&
                            (pack_count_reg <= 4'd8);

    wire cc_input_fire;
    wire [31:0] cc_raw_dw0;
    wire [31:0] cc_raw_dw1;
    wire [31:0] cc_raw_dw2;
    wire [31:0] cc_raw_dw3_swap;
    wire [31:0] cc_raw_payload0_swap;
    wire [31:0] cc_raw_payload1_swap;
    wire [31:0] cc_raw_payload2_swap;
    wire [31:0] cc_raw_payload3_swap;

    logic [95:0] cc_desc_next;

    assign cc_input_fire = tlps_in.tvalid && tlps_in.tready;
    assign cc_raw_dw0 = tlps_in.tdata[31:0];
    assign cc_raw_dw1 = tlps_in.tdata[63:32];
    assign cc_raw_dw2 = tlps_in.tdata[95:64];
    assign cc_raw_dw3_swap = {tlps_in.tdata[103:96], tlps_in.tdata[111:104], tlps_in.tdata[119:112], tlps_in.tdata[127:120]};
    assign cc_raw_payload0_swap = {tlps_in.tdata[7:0], tlps_in.tdata[15:8], tlps_in.tdata[23:16], tlps_in.tdata[31:24]};
    assign cc_raw_payload1_swap = {tlps_in.tdata[39:32], tlps_in.tdata[47:40], tlps_in.tdata[55:48], tlps_in.tdata[63:56]};
    assign cc_raw_payload2_swap = {tlps_in.tdata[71:64], tlps_in.tdata[79:72], tlps_in.tdata[87:80], tlps_in.tdata[95:88]};
    assign cc_raw_payload3_swap = {tlps_in.tdata[103:96], tlps_in.tdata[111:104], tlps_in.tdata[119:112], tlps_in.tdata[127:120]};

    always_comb begin
        cc_desc_next = '0;
        cc_desc_next[6:0]   = cc_raw_dw2[6:0];
        cc_desc_next[9:8]   = cc_raw_dw0[11:10];
        cc_desc_next[28:16] = {1'b0, cc_raw_dw1[11:0]};
        cc_desc_next[42:32] = {1'b0, cc_raw_dw0[9:0]};
        cc_desc_next[45:43] = cc_raw_dw1[15:13];
        cc_desc_next[63:48] = cc_raw_dw2[31:16];
        cc_desc_next[71:64] = cc_raw_dw2[15:8];
        cc_desc_next[87:72] = cc_raw_dw1[31:16];
        cc_desc_next[88]    = 1'b1;
        cc_desc_next[91:89] = cc_raw_dw0[22:20];
        cc_desc_next[94:92] = {cc_raw_dw0[18], cc_raw_dw0[13:12]};
        cc_desc_next[95]    = 1'b0;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            out_tdata_reg <= '0;
            out_tkeep_reg <= '0;
            out_tvalid_reg <= 1'b0;
            out_tlast_reg <= 1'b0;
            pack_data_reg <= '0;
            pack_count_reg <= '0;
            pack_last_reg <= 1'b0;
        end else if (cc_output_ready) begin
            out_tdata_reg <= '0;
            out_tkeep_reg <= '0;
            out_tvalid_reg <= 1'b0;
            out_tlast_reg <= 1'b0;

            // A final raw beat can leave up to four DWORDs after a full
            // 256-bit CC beat.  Emit that tail before accepting a new packet.
            if (pack_last_reg && (pack_count_reg != 4'd0)) begin
                out_tdata_reg <= pack_data_reg[255:0];
                case (pack_count_reg)
                    4'd1: out_tkeep_reg <= 8'b0000_0001;
                    4'd2: out_tkeep_reg <= 8'b0000_0011;
                    4'd3: out_tkeep_reg <= 8'b0000_0111;
                    4'd4: out_tkeep_reg <= 8'b0000_1111;
                    4'd5: out_tkeep_reg <= 8'b0001_1111;
                    4'd6: out_tkeep_reg <= 8'b0011_1111;
                    4'd7: out_tkeep_reg <= 8'b0111_1111;
                    default: out_tkeep_reg <= 8'b1111_1111;
                endcase
                out_tvalid_reg <= 1'b1;
                out_tlast_reg <= 1'b1;
                pack_data_reg <= '0;
                pack_count_reg <= '0;
                pack_last_reg <= 1'b0;
            end else if (cc_input_fire) begin
                logic [383:0] pack_tmp;
                logic [3:0] count_tmp;

                pack_tmp = pack_data_reg;
                count_tmp = pack_count_reg;

                if (tlps_in.tuser[0]) begin
                    pack_tmp[95:0] = cc_desc_next;
                    count_tmp = 4'd3;
                    if (tlps_in.tkeepdw[3]) begin
                        pack_tmp[127:96] = cc_raw_dw3_swap;
                        count_tmp = 4'd4;
                    end
                end else begin
                    if (tlps_in.tkeepdw[0]) begin
                        pack_tmp[count_tmp*32 +: 32] = cc_raw_payload0_swap;
                        count_tmp = count_tmp + 4'd1;
                    end
                    if (tlps_in.tkeepdw[1]) begin
                        pack_tmp[count_tmp*32 +: 32] = cc_raw_payload1_swap;
                        count_tmp = count_tmp + 4'd1;
                    end
                    if (tlps_in.tkeepdw[2]) begin
                        pack_tmp[count_tmp*32 +: 32] = cc_raw_payload2_swap;
                        count_tmp = count_tmp + 4'd1;
                    end
                    if (tlps_in.tkeepdw[3]) begin
                        pack_tmp[count_tmp*32 +: 32] = cc_raw_payload3_swap;
                        count_tmp = count_tmp + 4'd1;
                    end
                end

                if (count_tmp >= 4'd8) begin
                    out_tdata_reg <= pack_tmp[255:0];
                    out_tkeep_reg <= 8'b1111_1111;
                    out_tvalid_reg <= 1'b1;
                    out_tlast_reg <= tlps_in.tlast && (count_tmp == 4'd8);

                    if (count_tmp > 4'd8) begin
                        pack_data_reg <= {256'd0, pack_tmp[383:256]};
                        pack_count_reg <= count_tmp - 4'd8;
                        pack_last_reg <= tlps_in.tlast;
                    end else begin
                        pack_data_reg <= '0;
                        pack_count_reg <= '0;
                        pack_last_reg <= 1'b0;
                    end
                end else if (tlps_in.tlast) begin
                    out_tdata_reg <= pack_tmp[255:0];
                    case (count_tmp)
                        4'd1: out_tkeep_reg <= 8'b0000_0001;
                        4'd2: out_tkeep_reg <= 8'b0000_0011;
                        4'd3: out_tkeep_reg <= 8'b0000_0111;
                        4'd4: out_tkeep_reg <= 8'b0000_1111;
                        4'd5: out_tkeep_reg <= 8'b0001_1111;
                        4'd6: out_tkeep_reg <= 8'b0011_1111;
                        4'd7: out_tkeep_reg <= 8'b0111_1111;
                        default: out_tkeep_reg <= 8'b0000_0000;
                    endcase
                    out_tvalid_reg <= (count_tmp != 4'd0);
                    out_tlast_reg <= (count_tmp != 4'd0);
                    pack_data_reg <= '0;
                    pack_count_reg <= '0;
                    pack_last_reg <= 1'b0;
                end else begin
                    pack_data_reg <= pack_tmp;
                    pack_count_reg <= count_tmp;
                    pack_last_reg <= 1'b0;
                end
            end
        end
    end

endmodule

`resetall
