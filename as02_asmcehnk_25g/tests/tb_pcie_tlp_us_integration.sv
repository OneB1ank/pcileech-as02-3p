`timescale 1ns / 1ps
`default_nettype none
`include "asmcehnk_header.svh"

module tb_pcie_tlp_us_integration;
    logic clk_pcie = 1'b0;
    logic clk_sys = 1'b0;
    logic rst_pcie = 1'b1;
    logic rst_sys = 1'b1;

    logic [255:0] cq_data = 256'd0;
    logic [7:0] cq_keep = 8'd0;
    logic [87:0] cq_user = 88'd0;
    logic cq_valid = 1'b0;
    logic cq_last = 1'b0;
    logic [255:0] rc_data = 256'd0;
    logic [7:0] rc_keep = 8'd0;
    logic [74:0] rc_user = 75'd0;
    logic rc_valid = 1'b0;
    logic rc_last = 1'b0;
    logic cc_ready = 1'b1;
    logic rq_ready = 1'b1;

    logic [31:0] tlp_tx_data = 32'd0;
    logic tlp_tx_last = 1'b0;
    logic tlp_tx_valid = 1'b0;
    logic tlp_rx_rd_en = 1'b0;

    logic shadow_rx_rden = 1'b0;
    logic shadow_rx_wren = 1'b0;
    logic [3:0] shadow_rx_be = 4'd0;
    logic [31:0] shadow_rx_data = 32'd0;
    logic [9:0] shadow_rx_addr = 10'd0;
    logic shadow_rx_addr_lo = 1'b0;
    logic shadow_cfgtlp_wren = 1'b1;
    logic shadow_cfgtlp_zero = 1'b0;
    logic shadow_cfgtlp_en = 1'b1;
    logic shadow_cfgtlp_filter = 1'b0;
    logic shadow_alltlp_filter = 1'b0;
    logic shadow_bar_en = 1'b1;

    logic [5:0] rq_seq_num0 = 6'd0;
    logic rq_seq_vld0 = 1'b0;
    logic [5:0] rq_seq_num1 = 6'd0;
    logic rq_seq_vld1 = 1'b0;

    taxi_axis_if #(
        .DATA_W(256), .KEEP_EN(1), .KEEP_W(8), .USER_EN(1), .USER_W(88)
    ) cq_axis();
    taxi_axis_if #(
        .DATA_W(256), .KEEP_EN(1), .KEEP_W(8), .USER_EN(1), .USER_W(33)
    ) cc_axis();
    taxi_axis_if #(
        .DATA_W(256), .KEEP_EN(1), .KEEP_W(8), .USER_EN(1), .USER_W(62)
    ) rq_axis();
    taxi_axis_if #(
        .DATA_W(256), .KEEP_EN(1), .KEEP_W(8), .USER_EN(1), .USER_W(75)
    ) rc_axis();
    IfPCIeFifoTlp tlp_fifo();
    IfShadow2Fifo shadow_fifo();

    wire [11:0] status_rq_flow;

    integer cc_count = 0;
    integer rq_count = 0;
    integer rc_word_count = 0;
    integer errors = 0;
    logic [255:0] cc_stalled_data = 256'd0;
    logic [7:0] cc_stalled_keep = 8'd0;
    logic cc_stalled_last = 1'b0;
    logic cc_stall_seen = 1'b0;
    logic [127:0] rc_observed_data0 = 128'd0;
    logic [127:0] rc_observed_data1 = 128'd0;
    logic [3:0] rc_observed_valid0 = 4'd0;
    logic [3:0] rc_observed_valid1 = 4'd0;
    logic [3:0] rc_observed_last0 = 4'd0;
    logic [3:0] rc_observed_last1 = 4'd0;
    logic [3:0] rc_observed_first0 = 4'd0;
    logic [3:0] rc_observed_first1 = 4'd0;
    logic rq_stall_seen = 1'b0;
    logic [255:0] rq_stalled_data = 256'd0;
    logic [7:0] rq_stalled_keep = 8'd0;
    logic [61:0] rq_stalled_user = 62'd0;
    logic rq_stalled_last = 1'b0;
    logic rq_mwr_capture_enable = 1'b0;
    integer rq_mwr_capture_count = 0;
    integer rq_mwr_stall_cycles = 0;
    logic [255:0] rq_mwr_data0 = 256'd0;
    logic [255:0] rq_mwr_data1 = 256'd0;
    logic [7:0] rq_mwr_keep0 = 8'd0;
    logic [7:0] rq_mwr_keep1 = 8'd0;
    logic [61:0] rq_mwr_user0 = 62'd0;
    logic [61:0] rq_mwr_user1 = 62'd0;
    logic rq_mwr_last0 = 1'b0;
    logic rq_mwr_last1 = 1'b0;
    logic tag_block_seen = 1'b0;
    logic rq_flow_error_seen = 1'b0;
    logic reset_guard_active = 1'b0;
    logic stale_rq_seen = 1'b0;
    logic stale_rc_seen = 1'b0;
    integer rq_count_before_tag_release = 0;

    always #2.00 clk_pcie = !clk_pcie;
    always #1.24 clk_sys = !clk_sys;

    assign cq_axis.tdata = cq_data;
    assign cq_axis.tkeep = cq_keep;
    assign cq_axis.tstrb = cq_keep;
    assign cq_axis.tuser = cq_user;
    assign cq_axis.tvalid = cq_valid;
    assign cq_axis.tlast = cq_last;
    assign cq_axis.tid = '0;
    assign cq_axis.tdest = '0;

    assign rc_axis.tdata = rc_data;
    assign rc_axis.tkeep = rc_keep;
    assign rc_axis.tstrb = rc_keep;
    assign rc_axis.tuser = rc_user;
    assign rc_axis.tvalid = rc_valid;
    assign rc_axis.tlast = rc_last;
    assign rc_axis.tid = '0;
    assign rc_axis.tdest = '0;
    assign cc_axis.tready = cc_ready;
    assign rq_axis.tready = rq_ready;

    assign tlp_fifo.tx_data = tlp_tx_data;
    assign tlp_fifo.tx_last = tlp_tx_last;
    assign tlp_fifo.tx_valid = tlp_tx_valid;
    assign tlp_fifo.rx_rd_en = tlp_rx_rd_en;

    assign shadow_fifo.rx_rden = shadow_rx_rden;
    assign shadow_fifo.rx_wren = shadow_rx_wren;
    assign shadow_fifo.rx_be = shadow_rx_be;
    assign shadow_fifo.rx_data = shadow_rx_data;
    assign shadow_fifo.rx_addr = shadow_rx_addr;
    assign shadow_fifo.rx_addr_lo = shadow_rx_addr_lo;
    assign shadow_fifo.cfgtlp_wren = shadow_cfgtlp_wren;
    assign shadow_fifo.cfgtlp_zero = shadow_cfgtlp_zero;
    assign shadow_fifo.cfgtlp_en = shadow_cfgtlp_en;
    assign shadow_fifo.cfgtlp_filter = shadow_cfgtlp_filter;
    assign shadow_fifo.alltlp_filter = shadow_alltlp_filter;
    assign shadow_fifo.bar_en = shadow_bar_en;

    always @(posedge clk_pcie) begin
        if (reset_guard_active && rq_axis.tvalid) begin
            stale_rq_seen = 1'b1;
        end

        if (rst_pcie) begin
            rq_stall_seen = 1'b0;
        end else begin
            if (cc_axis.tvalid && cc_axis.tready) cc_count = cc_count + 1;
            if (rq_axis.tvalid && rq_axis.tready) rq_count = rq_count + 1;
            if (status_rq_flow[9]) tag_block_seen = 1'b1;
            if ((status_rq_flow[8] !== 1'b0) ||
                (status_rq_flow[10] !== 1'b0) ||
                (status_rq_flow[11] !== 1'b0)) begin
                rq_flow_error_seen = 1'b1;
            end

            if (rq_axis.tvalid && !rq_axis.tready) begin
                if (rq_mwr_capture_enable) begin
                    rq_mwr_stall_cycles = rq_mwr_stall_cycles + 1;
                end
                if (!rq_stall_seen) begin
                    rq_stalled_data = rq_axis.tdata;
                    rq_stalled_keep = rq_axis.tkeep;
                    rq_stalled_user = rq_axis.tuser;
                    rq_stalled_last = rq_axis.tlast;
                    rq_stall_seen = 1'b1;
                end else if (rq_axis.tdata !== rq_stalled_data ||
                             rq_axis.tkeep !== rq_stalled_keep ||
                             rq_axis.tuser !== rq_stalled_user ||
                             rq_axis.tlast !== rq_stalled_last) begin
                    $display("PCIE_INTEGRATION_RQ_STABILITY_FAIL");
                    errors = errors + 1;
                end
            end else if (rq_axis.tvalid && rq_axis.tready) begin
                rq_stall_seen = 1'b0;
            end

            if (rq_mwr_capture_enable && rq_axis.tvalid && rq_axis.tready) begin
                if (rq_mwr_capture_count == 0) begin
                    rq_mwr_data0 = rq_axis.tdata;
                    rq_mwr_keep0 = rq_axis.tkeep;
                    rq_mwr_user0 = rq_axis.tuser;
                    rq_mwr_last0 = rq_axis.tlast;
                end else if (rq_mwr_capture_count == 1) begin
                    rq_mwr_data1 = rq_axis.tdata;
                    rq_mwr_keep1 = rq_axis.tkeep;
                    rq_mwr_user1 = rq_axis.tuser;
                    rq_mwr_last1 = rq_axis.tlast;
                end else begin
                    $display("PCIE_INTEGRATION_RQ_MWR_EXTRA_BEAT_FAIL count=%0d",
                             rq_mwr_capture_count);
                    errors = errors + 1;
                end
                rq_mwr_capture_count = rq_mwr_capture_count + 1;
            end

            if (cc_axis.tvalid && !cc_axis.tready) begin
                if (!cc_stall_seen) begin
                    cc_stalled_data = cc_axis.tdata;
                    cc_stalled_keep = cc_axis.tkeep;
                    cc_stalled_last = cc_axis.tlast;
                    cc_stall_seen = 1'b1;
                end else if (cc_axis.tdata !== cc_stalled_data ||
                             cc_axis.tkeep !== cc_stalled_keep ||
                             cc_axis.tlast !== cc_stalled_last) begin
                    $display("PCIE_INTEGRATION_CC_STABILITY_FAIL");
                    errors = errors + 1;
                end
            end else if (cc_axis.tvalid && cc_axis.tready) begin
                cc_stall_seen = 1'b0;
            end
        end
    end

    always @(posedge clk_sys) begin
        if (reset_guard_active &&
            (tlp_fifo.rx_valid[0] || tlp_fifo.rx_valid[1] ||
             tlp_fifo.rx_valid[2] || tlp_fifo.rx_valid[3])) begin
            stale_rc_seen = 1'b1;
        end

        if (!rst_sys) begin
            if (tlp_fifo.rx_valid[0] || tlp_fifo.rx_valid[1] ||
                tlp_fifo.rx_valid[2] || tlp_fifo.rx_valid[3]) begin
                if (rc_word_count == 0) begin
                    rc_observed_data0 = {
                        tlp_fifo.rx_data[3], tlp_fifo.rx_data[2],
                        tlp_fifo.rx_data[1], tlp_fifo.rx_data[0]
                    };
                    rc_observed_valid0 = {
                        tlp_fifo.rx_valid[3], tlp_fifo.rx_valid[2],
                        tlp_fifo.rx_valid[1], tlp_fifo.rx_valid[0]
                    };
                    rc_observed_last0 = {
                        tlp_fifo.rx_last[3], tlp_fifo.rx_last[2],
                        tlp_fifo.rx_last[1], tlp_fifo.rx_last[0]
                    };
                    rc_observed_first0 = {
                        tlp_fifo.rx_first[3], tlp_fifo.rx_first[2],
                        tlp_fifo.rx_first[1], tlp_fifo.rx_first[0]
                    };
                end else if (rc_word_count == 1) begin
                    rc_observed_data1 = {
                        tlp_fifo.rx_data[3], tlp_fifo.rx_data[2],
                        tlp_fifo.rx_data[1], tlp_fifo.rx_data[0]
                    };
                    rc_observed_valid1 = {
                        tlp_fifo.rx_valid[3], tlp_fifo.rx_valid[2],
                        tlp_fifo.rx_valid[1], tlp_fifo.rx_valid[0]
                    };
                    rc_observed_last1 = {
                        tlp_fifo.rx_last[3], tlp_fifo.rx_last[2],
                        tlp_fifo.rx_last[1], tlp_fifo.rx_last[0]
                    };
                    rc_observed_first1 = {
                        tlp_fifo.rx_first[3], tlp_fifo.rx_first[2],
                        tlp_fifo.rx_first[1], tlp_fifo.rx_first[0]
                    };
                end
                rc_word_count = rc_word_count + 1;
            end
        end
    end

    asmcehnk_pcie_tlp_us #(
        .RQ_SEQ_NUM_W(6)
    ) dut (
        .clk(clk_pcie),
        .rst(rst_pcie),
        .clk_sys(clk_sys),
        .rst_sys(rst_sys),
        .dtlp(tlp_fifo.mp_pcie),
        .s_axis_pcie_cq(cq_axis),
        .m_axis_pcie_cc(cc_axis),
        .m_axis_pcie_rq(rq_axis),
        .s_axis_pcie_rc(rc_axis),
        .dshadow2fifo(shadow_fifo.shadow),
        .pcie_id(16'h5678),
        .base_address_register(32'h8000_0000),
        .pcie_rq_seq_num0(rq_seq_num0),
        .pcie_rq_seq_num_vld0(rq_seq_vld0),
        .pcie_rq_seq_num1(rq_seq_num1),
        .pcie_rq_seq_num_vld1(rq_seq_vld1),
        .status_rq_flow(status_rq_flow)
    );

    initial begin
        #200;
        repeat (12) @(posedge clk_pcie);
        @(negedge clk_sys);
        rst_sys = 1'b0;
        repeat (4) @(posedge clk_pcie);
        @(negedge clk_pcie);
        rst_pcie = 1'b0;
        repeat (40) @(posedge clk_pcie);

        // CQ BAR0 MRd: host reads the fixed asmcehnk identity register.
        cc_ready = 1'b0;
        @(negedge clk_pcie);
        cq_data = 256'd0;
        cq_data[63:2] = 62'h0000_0000_2000_0000;
        cq_data[74:64] = 11'd1;
        cq_data[78:75] = 4'b0000;
        cq_data[95:80] = 16'h1234;
        cq_data[103:96] = 8'h5a;
        cq_data[114:112] = 3'd0;
        cq_keep = 8'h0f;
        cq_user = 88'd0;
        cq_user[7:0] = 8'hff;
        cq_last = 1'b1;
        cq_valid = 1'b1;
        @(posedge clk_pcie);
        while (!cq_axis.tready) @(posedge clk_pcie);
        @(negedge clk_pcie);
        cq_valid = 1'b0;
        wait (cc_axis.tvalid);
        #1;
        repeat (4) @(posedge clk_pcie);
        #1;
        if (cc_axis.tdata[87:72] !== 16'h7856 ||
            cc_axis.tdata[63:48] !== 16'h1234 ||
            cc_axis.tdata[71:64] !== 8'h5a ||
            cc_axis.tdata[42:32] !== 11'd1 ||
            cc_axis.tdata[127:96] !== 32'h0100_0020 ||
            !cc_axis.tlast || cc_axis.tkeep !== 8'h0f) begin
            $display("PCIE_INTEGRATION_CQ_MRD_CC_FAIL data=%h keep=%h last=%b",
                     cc_axis.tdata, cc_axis.tkeep, cc_axis.tlast);
            errors = errors + 1;
        end
        @(negedge clk_pcie);
        cc_ready = 1'b1;
        @(posedge clk_pcie);
        @(negedge clk_pcie);

        // CQ MWr followed by MRd proves BAR0 write/read persistence.
        cq_data = 256'd0;
        cq_data[63:2] = 62'h0000_0000_2000_0800;
        cq_data[74:64] = 11'd1;
        cq_data[78:75] = 4'b0001;
        cq_data[95:80] = 16'h1234;
        cq_data[103:96] = 8'h5b;
        cq_data[114:112] = 3'd0;
        cq_data[159:128] = 32'h4433_2211;
        cq_keep = 8'h1f;
        cq_user[7:0] = 8'hff;
        cq_last = 1'b1;
        cq_valid = 1'b1;
        @(posedge clk_pcie);
        while (!cq_axis.tready) @(posedge clk_pcie);
        @(negedge clk_pcie);
        cq_valid = 1'b0;
        repeat (30) @(posedge clk_pcie);

        cq_data = 256'd0;
        cq_data[63:2] = 62'h0000_0000_2000_0800;
        cq_data[74:64] = 11'd1;
        cq_data[78:75] = 4'b0000;
        cq_data[95:80] = 16'h1234;
        cq_data[103:96] = 8'h5c;
        cq_data[114:112] = 3'd0;
        cq_keep = 8'h0f;
        cq_user[7:0] = 8'hff;
        cq_last = 1'b1;
        cq_valid = 1'b1;
        @(posedge clk_pcie);
        while (!cq_axis.tready) @(posedge clk_pcie);
        @(negedge clk_pcie);
        cq_valid = 1'b0;
        wait (cc_axis.tvalid);
        if (cc_axis.tdata[127:96] !== 32'h4433_2211 ||
            cc_axis.tdata[71:64] !== 8'h5c || !cc_axis.tlast) begin
            $display("PCIE_INTEGRATION_CQ_BAR_RW_FAIL data=%h", cc_axis.tdata);
            errors = errors + 1;
        end
        @(posedge clk_pcie);

        // Clear CQ traffic from the shared destination FIFO before beginning
        // the continuous outbound-MRd / inbound-RC tag-lifecycle sequence.
        // There is deliberately no reset between that MRd and its completion.
        @(negedge clk_pcie); rst_pcie = 1'b1;
        @(negedge clk_sys); rst_sys = 1'b1;
        repeat (8) @(posedge clk_pcie);
        repeat (8) @(posedge clk_sys);
        @(negedge clk_pcie); rst_pcie = 1'b0;
        @(negedge clk_sys); rst_sys = 1'b0;
        repeat (12) @(posedge clk_pcie);
        repeat (12) @(posedge clk_sys);
        rc_word_count = 0;
        rc_observed_data0 = 128'd0;
        rc_observed_data1 = 128'd0;
        rc_observed_valid0 = 4'd0;
        rc_observed_valid1 = 4'd0;
        rc_observed_last0 = 4'd0;
        rc_observed_last1 = 4'd0;
        rc_observed_first0 = 4'd0;
        rc_observed_first1 = 4'd0;

        // Raw AMDUSB4 MRd from the source FIFO becomes one native RQ beat.
        rq_ready = 1'b0;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_0001; tlp_tx_last = 1'b0; tlp_tx_valid = 1'b1;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_5a0f;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_1000; tlp_tx_last = 1'b1;
        @(negedge clk_sys); tlp_tx_valid = 1'b0; tlp_tx_last = 1'b0; tlp_tx_data = 32'd0;
        wait (rq_axis.tvalid);
        #1;
        repeat (3) @(posedge clk_pcie);
        #1;
        if (rq_axis.tdata[1:0] !== 2'b00 ||
            {rq_axis.tdata[63:2], 2'b00} !== 64'h0000_0000_0000_1000 ||
            rq_axis.tdata[74:64] !== 11'd1 ||
            rq_axis.tdata[78:75] !== 4'b0000 ||
            rq_axis.tdata[95:80] !== 16'd0 ||
            rq_axis.tdata[103:96] !== 8'h5a ||
            rq_axis.tdata[127:104] !== 24'd0 ||
            rq_axis.tdata[255:128] !== 128'd0 ||
            rq_axis.tkeep !== 8'h0f ||
            rq_axis.tuser !== 62'h0000_0000_0000_000f ||
            !rq_axis.tlast) begin
            $display("PCIE_INTEGRATION_RQ_MRD_FAIL data=%h keep=%h last=%b user=%h",
                     rq_axis.tdata, rq_axis.tkeep, rq_axis.tlast, rq_axis.tuser);
            errors = errors + 1;
        end
        @(negedge clk_pcie); rq_ready = 1'b1; @(posedge clk_pcie);

        // Raw AMDUSB4 MWr with one payload DWORD becomes two RQ beats.
        @(negedge clk_pcie); rq_ready = 1'b0;
        rq_mwr_capture_enable = 1'b1;
        rq_mwr_capture_count = 0;
        rq_mwr_stall_cycles = 0;
        @(negedge clk_sys); tlp_tx_data = 32'h4000_0002; tlp_tx_last = 1'b0; tlp_tx_valid = 1'b1;
        @(negedge clk_sys); tlp_tx_data = 32'h1234_5b0f;
        @(negedge clk_sys); tlp_tx_data = 32'h89ab_c000;
        @(negedge clk_sys); tlp_tx_data = 32'h4433_2211;
        @(negedge clk_sys); tlp_tx_data = 32'ha1b2_c3d4; tlp_tx_last = 1'b1;
        @(negedge clk_sys); tlp_tx_valid = 1'b0; tlp_tx_last = 1'b0; tlp_tx_data = 32'd0;
        wait (rq_axis.tvalid);
        repeat (4) @(posedge clk_pcie);
        @(negedge clk_pcie); rq_ready = 1'b1;
        wait (rq_mwr_capture_count == 2);
        repeat (4) @(posedge clk_pcie);
        rq_mwr_capture_enable = 1'b0;
        if (rq_mwr_capture_count !== 2 || rq_mwr_stall_cycles < 3 ||
            rq_mwr_data0[1:0] !== 2'b00 ||
            {rq_mwr_data0[63:2], 2'b00} !== 64'h0000_0000_89ab_c000 ||
            rq_mwr_data0[74:64] !== 11'd2 ||
            rq_mwr_data0[78:75] !== 4'b0001 ||
            rq_mwr_data0[79] !== 1'b0 ||
            rq_mwr_data0[95:80] !== 16'h1234 ||
            rq_mwr_data0[103:96] !== 8'h5b ||
            rq_mwr_data0[127:104] !== 24'd0 ||
            rq_mwr_data0[159:128] !== 32'h1122_3344 ||
            rq_mwr_data0[255:160] !== 96'd0 ||
            rq_mwr_keep0 !== 8'h1f || rq_mwr_last0 !== 1'b0 ||
            rq_mwr_user0[3:0] !== 4'hf ||
            rq_mwr_user0[7:4] !== 4'h0 ||
            rq_mwr_user0[23:8] !== 16'd0 ||
            rq_mwr_user0[27:24] !== 4'd1 ||
            rq_mwr_user0[61:28] !== 34'd0 ||
            rq_mwr_data1[31:0] !== 32'hd4c3_b2a1 ||
            rq_mwr_keep1 !== 8'h01 || rq_mwr_last1 !== 1'b1 ||
            rq_mwr_user1 !== 62'd0) begin
            $display("PCIE_INTEGRATION_RQ_MWR_FIELDS_FAIL count=%0d stall=%0d d0=%h keep0=%h last0=%b user0=%h d1=%h keep1=%h last1=%b user1=%h",
                     rq_mwr_capture_count, rq_mwr_stall_cycles,
                     rq_mwr_data0, rq_mwr_keep0, rq_mwr_last0, rq_mwr_user0,
                     rq_mwr_data1, rq_mwr_keep1, rq_mwr_last1, rq_mwr_user1);
            errors = errors + 1;
        end

        // Re-submit the same MRd tag.  It must remain blocked until the
        // matching terminal RC completion is accepted below.
        rq_count_before_tag_release = rq_count;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_0001; tlp_tx_last = 1'b0; tlp_tx_valid = 1'b1;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_5a0f;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_2000; tlp_tx_last = 1'b1;
        @(negedge clk_sys); tlp_tx_valid = 1'b0; tlp_tx_last = 1'b0; tlp_tx_data = 32'd0;
        wait (status_rq_flow[9]);
        repeat (4) @(posedge clk_pcie);
        if (rq_count !== rq_count_before_tag_release || !tag_block_seen ||
            status_rq_flow[9] !== 1'b1) begin
            $display("PCIE_INTEGRATION_RQ_TAG_BLOCK_FAIL before=%0d now=%0d status=%h",
                     rq_count_before_tag_release, rq_count, status_rq_flow);
            errors = errors + 1;
        end
        @(negedge clk_pcie); rq_ready = 1'b0;

        // Native RC CplD both releases tag 5a and is converted to a complete
        // two-word raw-128 packet in the destination FIFO.
        rc_data = 256'd0;
        rc_data[42:32] = 11'd2;
        rc_data[28:16] = 13'd8;
        rc_data[63:48] = 16'h1234;
        rc_data[71:64] = 8'h5a;
        rc_data[87:72] = 16'habcd;
        rc_data[6:0] = 7'h20;
        rc_data[127:96] = 32'h1122_3344;
        rc_data[159:128] = 32'ha1b2_c3d4;
        rc_keep = 8'h1f;
        rc_last = 1'b1;
        rc_valid = 1'b1;
        @(posedge clk_pcie);
        while (!rc_axis.tready) @(posedge clk_pcie);
        @(negedge clk_pcie); rc_valid = 1'b0;
        wait (rq_axis.tvalid);
        #1;
        if ({rq_axis.tdata[63:2], 2'b00} !== 64'h0000_0000_0000_2000 ||
            rq_axis.tdata[78:75] !== 4'b0000 ||
            rq_axis.tdata[103:96] !== 8'h5a ||
            rq_axis.tkeep !== 8'h0f || !rq_axis.tlast) begin
            $display("PCIE_INTEGRATION_RQ_TAG_RELEASE_DATA_FAIL data=%h keep=%h last=%b",
                     rq_axis.tdata, rq_axis.tkeep, rq_axis.tlast);
            errors = errors + 1;
        end
        @(negedge clk_pcie); rq_ready = 1'b1;
        wait (rq_count == (rq_count_before_tag_release + 1));
        repeat (40) @(posedge clk_pcie);
        @(negedge clk_sys); tlp_rx_rd_en = 1'b1;
        repeat (2) @(negedge clk_sys); tlp_rx_rd_en = 1'b0;
        repeat (20) @(posedge clk_sys);
        if (rc_word_count !== 2 ||
            rc_observed_data0 !== 128'h4433_2211_1234_5a20_abcd_0008_4a00_0002 ||
            rc_observed_data1 !== 128'h0000_0000_0000_0000_0000_0000_d4c3_b2a1 ||
            rc_observed_valid0 !== 4'hf || rc_observed_valid1 !== 4'h1 ||
            rc_observed_last0 !== 4'h0 || rc_observed_last1 !== 4'h1 ||
            rc_observed_first0 !== 4'h1 || rc_observed_first1 !== 4'h0) begin
            $display("PCIE_INTEGRATION_RC_DST_FAIL words=%0d d0=%h d1=%h valid0=%b valid1=%b last0=%b last1=%b first0=%b first1=%b",
                     rc_word_count, rc_observed_data0, rc_observed_data1,
                     rc_observed_valid0, rc_observed_valid1,
                     rc_observed_last0, rc_observed_last1,
                     rc_observed_first0, rc_observed_first1);
            errors = errors + 1;
        end

        // Shadow-config command/reply crosses clk_sys/clk_pcie through XCI FIFO.
        @(negedge clk_sys); shadow_rx_addr = 10'd0; shadow_rx_addr_lo = 1'b0; shadow_rx_rden = 1'b1;
        @(negedge clk_sys); shadow_rx_rden = 1'b0;
        wait (shadow_fifo.tx_valid);
        if (shadow_fifo.tx_addr !== 10'd0 ||
            shadow_fifo.tx_addr_lo !== 1'b0 ||
            shadow_fifo.tx_data !== 32'hc918_b418) begin
            $display("PCIE_INTEGRATION_SHADOW_REPLY_FAIL addr=%h lo=%b data=%h",
                     shadow_fifo.tx_addr, shadow_fifo.tx_addr_lo,
                     shadow_fifo.tx_data);
            errors = errors + 1;
        end

        // Overlap reset with a stalled RQ and a queued matching RC packet.
        // Sticky guards remain active through reset and the post-reset window.
        rq_ready = 1'b0;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_0001; tlp_tx_last = 1'b0; tlp_tx_valid = 1'b1;
        @(negedge clk_sys); tlp_tx_data = 32'h0000_660f;
        @(negedge clk_sys); tlp_tx_data = 32'h0006_6000; tlp_tx_last = 1'b1;
        @(negedge clk_sys); tlp_tx_valid = 1'b0; tlp_tx_last = 1'b0;
        wait (rq_axis.tvalid);

        @(negedge clk_pcie);
        rc_data = 256'd0;
        rc_data[42:32] = 11'd1;
        rc_data[28:16] = 13'd4;
        rc_data[63:48] = 16'h1234;
        rc_data[71:64] = 8'h66;
        rc_data[87:72] = 16'habcd;
        rc_data[6:0] = 7'h00;
        rc_data[127:96] = 32'h5566_7788;
        rc_keep = 8'h0f;
        rc_last = 1'b1;
        rc_valid = 1'b1;
        @(posedge clk_pcie);
        while (!rc_axis.tready) @(posedge clk_pcie);
        @(negedge clk_pcie); rc_valid = 1'b0;
        repeat (4) @(posedge clk_pcie);

        @(negedge clk_pcie); rst_pcie = 1'b1;
        @(negedge clk_sys); rst_sys = 1'b1;
        repeat (2) @(posedge clk_pcie);
        repeat (2) @(posedge clk_sys);
        reset_guard_active = 1'b1;
        repeat (6) @(posedge clk_pcie);
        @(negedge clk_pcie); rst_pcie = 1'b0;
        repeat (3) @(posedge clk_sys);
        @(negedge clk_sys); rst_sys = 1'b0; rq_ready = 1'b1;
        repeat (30) @(posedge clk_pcie);
        repeat (30) @(posedge clk_sys);
        reset_guard_active = 1'b0;
        if (stale_rq_seen || stale_rc_seen || rq_axis.tvalid ||
            tlp_fifo.rx_valid[0] || tlp_fifo.rx_valid[1] ||
            tlp_fifo.rx_valid[2] || tlp_fifo.rx_valid[3]) begin
            $display("PCIE_INTEGRATION_RESET_STALE_FAIL rq_seen=%b rc_seen=%b rq_valid=%b rx_valid=%b",
                     stale_rq_seen, stale_rc_seen, rq_axis.tvalid,
                     {tlp_fifo.rx_valid[3], tlp_fifo.rx_valid[2],
                      tlp_fifo.rx_valid[1], tlp_fifo.rx_valid[0]});
            errors = errors + 1;
        end

        if (rq_flow_error_seen || status_rq_flow[8] ||
            status_rq_flow[10] || status_rq_flow[11]) begin
            $display("PCIE_INTEGRATION_RQ_FLOW_STATUS_FAIL seen=%b status=%h",
                     rq_flow_error_seen, status_rq_flow);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PCIE_TLP_US_INTEGRATION_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_TLP_US_INTEGRATION_TEST_FAIL errors=%0d", errors);
    end

    initial begin
        #10000;
        $fatal(1, "PCIE_TLP_US_INTEGRATION_TEST_TIMEOUT");
    end
endmodule

`resetall
