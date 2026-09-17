`timescale 1ns / 1ps
`include "asmcehnk_header.svh"

module tb_pcie_mux_backpressure;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [2:0] source1_index = 3'd0;
    logic [2:0] source2_index = 3'd0;
    logic [2:0] output_index = 3'd0;
    logic [3:0] stall_count = 4'd0;
    integer errors = 0;

    IfAXIS128 source1();
    IfAXIS128 source2();
    IfAXIS128 output_stream();

    always #2 clk = ~clk;

    assign source1.tdata = (source1_index == 0) ? 128'h0001 : 128'h0002;
    assign source1.tkeepdw = 4'hf;
    assign source1.tvalid = source1_index < 2;
    assign source1.tlast = source1_index == 1;
    assign source1.tuser = (source1_index == 0) ? 9'h001 : 9'h002;
    assign source1.has_data = source1.tvalid;

    assign source2.tdata = (source2_index == 0) ? 128'h1001 : 128'h1002;
    assign source2.tkeepdw = 4'hf;
    assign source2.tvalid = source2_index < 2;
    assign source2.tlast = source2_index == 1;
    assign source2.tuser = (source2_index == 0) ? 9'h101 : 9'h102;
    assign source2.has_data = source2.tvalid;

    assign output_stream.tready = (stall_count != 4'd3) &&
                                  (stall_count != 4'd7);

    asmcehnk_tlps128_mux2 dut (
        .clk       (clk),
        .rst       (rst),
        .tlps_in1  (source1.sink),
        .tlps_in2  (source2.sink),
        .tlps_out  (output_stream.source)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            source1_index <= 3'd0;
            source2_index <= 3'd0;
            output_index <= 3'd0;
            stall_count <= 4'd0;
        end else begin
            stall_count <= stall_count + 1'b1;
            if (source1.tvalid && source1.tready) begin
                source1_index <= source1_index + 1'b1;
            end
            if (source2.tvalid && source2.tready) begin
                source2_index <= source2_index + 1'b1;
            end
            if (output_stream.tvalid && output_stream.tready) begin
                case (output_index)
                    3'd0: if (output_stream.tdata != 128'h0001 || output_stream.tlast) errors <= errors + 1;
                    3'd1: if (output_stream.tdata != 128'h0002 || !output_stream.tlast) errors <= errors + 1;
                    3'd2: if (output_stream.tdata != 128'h1001 || output_stream.tlast) errors <= errors + 1;
                    3'd3: if (output_stream.tdata != 128'h1002 || !output_stream.tlast) errors <= errors + 1;
                    default: errors <= errors + 1;
                endcase
                output_index <= output_index + 1'b1;
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (30) @(posedge clk);
        if (errors == 0 && output_index == 4 &&
            source1_index == 2 && source2_index == 2) begin
            $display("PCIE_MUX_BACKPRESSURE_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_MUX_BACKPRESSURE_TEST_FAIL errors=%0d outputs=%0d source1=%0d source2=%0d",
               errors, output_index, source1_index, source2_index);
    end

endmodule

module tb_pcie_cc_native_arbiter;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [255:0] normal_data = 256'd0;
    logic [7:0] normal_keep = 8'd0;
    logic normal_valid = 1'b0;
    logic normal_last = 1'b0;
    logic [255:0] error_data = 256'd0;
    logic error_valid = 1'b0;
    logic output_ready = 1'b0;
    integer output_count = 0;
    integer errors = 0;

    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(33)) normal_axis();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(33)) error_axis();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(33)) output_axis();

    always #2 clk = ~clk;

    assign normal_axis.tdata = normal_data;
    assign normal_axis.tkeep = normal_keep;
    assign normal_axis.tstrb = normal_keep;
    assign normal_axis.tvalid = normal_valid;
    assign normal_axis.tlast = normal_last;
    assign normal_axis.tuser = 33'h000000011;
    assign normal_axis.tid = '0;
    assign normal_axis.tdest = '0;

    assign error_axis.tdata = error_data;
    assign error_axis.tkeep = 8'hff;
    assign error_axis.tstrb = 8'hff;
    assign error_axis.tvalid = error_valid;
    assign error_axis.tlast = 1'b1;
    assign error_axis.tuser = 33'h000000022;
    assign error_axis.tid = '0;
    assign error_axis.tdest = '0;

    assign output_axis.tready = output_ready;

    asmcehnk_pcie_us_axis_cc_mux2 dut (
        .clk              (clk),
        .rst              (rst),
        .s_axis_cc_error  (error_axis),
        .s_axis_cc_normal (normal_axis),
        .m_axis_cc        (output_axis)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            output_count <= 0;
        end else if (output_axis.tvalid && output_axis.tready) begin
            case (output_count)
                0: begin
                    if (output_axis.tdata != {8{32'h11111111}} ||
                        output_axis.tkeep != 8'hff || output_axis.tlast ||
                        output_axis.tuser != 33'h000000011) begin
                        errors <= errors + 1;
                    end
                end
                1: begin
                    if (output_axis.tdata != {8{32'h22222222}} ||
                        output_axis.tkeep != 8'h0f || !output_axis.tlast ||
                        output_axis.tuser != 33'h000000011) begin
                        errors <= errors + 1;
                    end
                end
                2: begin
                    if (output_axis.tdata != {8{32'heeeeeeee}} ||
                        output_axis.tkeep != 8'hff || !output_axis.tlast ||
                        output_axis.tuser != 33'h000000022) begin
                        errors <= errors + 1;
                    end
                end
                default: errors <= errors + 1;
            endcase
            output_count <= output_count + 1;
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Lock the normal packet while the output is stalled.
        normal_data = {8{32'h11111111}};
        normal_keep = 8'hff;
        normal_last = 1'b0;
        normal_valid = 1'b1;
        repeat (2) @(posedge clk);

        // A later error packet must not preempt the selected normal packet.
        @(negedge clk);
        error_data = {8{32'heeeeeeee}};
        error_valid = 1'b1;
        repeat (3) begin
            @(posedge clk);
            #1;
            if (!output_axis.tvalid ||
                output_axis.tdata != {8{32'h11111111}} ||
                output_axis.tlast || error_axis.tready) begin
                errors = errors + 1;
            end
        end

        @(negedge clk);
        output_ready = 1'b1;
        wait (normal_axis.tready);
        @(posedge clk);
        @(negedge clk);
        normal_data = {8{32'h22222222}};
        normal_keep = 8'h0f;
        normal_last = 1'b1;

        wait (normal_axis.tready);
        @(posedge clk);
        @(negedge clk);
        normal_valid = 1'b0;

        wait (error_axis.tready);
        @(posedge clk);
        @(negedge clk);
        error_valid = 1'b0;
        output_ready = 1'b0;

        wait (output_count == 3);
        repeat (3) @(posedge clk);
        if (errors == 0 && output_count == 3) begin
            $display("PCIE_CC_NATIVE_ARBITER_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_CC_NATIVE_ARBITER_TEST_FAIL errors=%0d outputs=%0d",
               errors, output_count);
    end

    initial begin
        #1500;
        $fatal(1, "PCIE_CC_NATIVE_ARBITER_TEST_TIMEOUT errors=%0d outputs=%0d",
               errors, output_count);
    end

endmodule

module tb_pcie_cq_rc_merge;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic cq_sent = 1'b0;
    logic rc_sent = 1'b0;
    logic [2:0] output_count = 3'd0;
    logic [3:0] cycle_count = 4'd0;
    logic [255:0] cq_data = 256'd0;
    logic [255:0] rc_data = 256'd0;
    integer errors = 0;

    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(88)) cq_axis();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(75)) rc_axis();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(33)) cq_error_axis();
    IfAXIS128 cq_raw();
    IfAXIS128 rc_raw();
    IfAXIS128 merged();

    always #2 clk = ~clk;

    assign cq_axis.tdata = cq_data;
    assign cq_axis.tkeep = 8'h0f;
    assign cq_axis.tstrb = cq_axis.tkeep;
    assign cq_axis.tvalid = !cq_sent;
    assign cq_axis.tlast = 1'b1;
    assign cq_axis.tuser = {{80{1'b0}}, 4'h0, 4'hf};
    assign cq_axis.tid = '0;
    assign cq_axis.tdest = '0;

    assign rc_axis.tdata = rc_data;
    assign rc_axis.tkeep = 8'h07;
    assign rc_axis.tstrb = rc_axis.tkeep;
    assign rc_axis.tvalid = !rc_sent;
    assign rc_axis.tlast = 1'b1;
    assign rc_axis.tuser = '0;
    assign rc_axis.tid = '0;
    assign rc_axis.tdest = '0;

    assign merged.tready = (cycle_count != 4'd6) &&
                           (cycle_count != 4'd7);
    assign cq_error_axis.tready = 1'b1;

    asmcehnk_pcie_us_cq_to_tlps128 cq_inst (
        .clk        (clk),
        .rst        (rst),
        .pcie_id    (16'h5678),
        .s_axis_cq  (cq_axis),
        .tlps_out   (cq_raw.source),
        .m_axis_cc_error (cq_error_axis)
    );

    asmcehnk_pcie_us_rc_to_tlps128 rc_inst (
        .clk        (clk),
        .rst        (rst),
        .s_axis_rc  (rc_axis),
        .tlps_out   (rc_raw.source),
        .tag_release       (),
        .tag_release_valid ()
    );

    asmcehnk_tlps128_mux2 mux_inst (
        .clk        (clk),
        .rst        (rst),
        .tlps_in1   (cq_raw.sink),
        .tlps_in2   (rc_raw.sink),
        .tlps_out   (merged.source)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            cq_sent <= 1'b0;
            rc_sent <= 1'b0;
            output_count <= 3'd0;
            cycle_count <= 4'd0;
        end else begin
            cycle_count <= cycle_count + 1'b1;
            if (cq_axis.tvalid && cq_axis.tready) cq_sent <= 1'b1;
            if (rc_axis.tvalid && rc_axis.tready) rc_sent <= 1'b1;
            if (merged.tvalid && merged.tready) begin
                if (output_count == 0) begin
                    if (merged.tdata[31:24] != 8'h00 ||
                        merged.tdata[63:48] != 16'h1234 ||
                        merged.tdata[47:40] != 8'h5a ||
                        !merged.tlast || !merged.tuser[0]) errors <= errors + 1;
                end else if (output_count == 1) begin
                    if (merged.tdata[31:25] != 7'b0000101 ||
                        merged.tdata[63:48] != 16'h1111 ||
                        !merged.tlast || !merged.tuser[0]) errors <= errors + 1;
                end else begin
                    errors <= errors + 1;
                end
                output_count <= output_count + 1'b1;
            end
        end
    end

    initial begin
        cq_data[63:2] = 62'h0000_0000_0000_0100;
        cq_data[74:64] = 11'd1;
        cq_data[78:75] = 4'b0000;
        cq_data[95:80] = 16'h1234;
        cq_data[103:96] = 8'h5a;
        cq_data[114:112] = 3'd0;
        rc_data[42:32] = 11'd0;
        rc_data[45:43] = 3'd0;
        rc_data[63:48] = 16'h5678;
        rc_data[71:64] = 8'h33;
        rc_data[87:72] = 16'h1111;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (40) @(posedge clk);
        if (errors == 0 && cq_sent && rc_sent && output_count == 2) begin
            $display("PCIE_CQ_RC_MERGE_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_CQ_RC_MERGE_TEST_FAIL errors=%0d cq=%b rc=%b outputs=%0d",
               errors, cq_sent, rc_sent, output_count);
    end

endmodule

module tb_pcie_rq_credit;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic ack_valid = 1'b0;
    logic [6:0] accepted_count = 7'd0;
    logic [6:0] output_count = 7'd0;
    wire [6:0] status_outstanding;
    wire status_blocked;
    wire status_error;
    integer errors = 0;

    IfAXIS128 raw_tlp();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(62)) rq_axis();

    always #2 clk = ~clk;

    assign raw_tlp.tdata = {32'd0, 32'h0000_1000,
                            {16'd0, accepted_count[6:0], 1'b0, 4'h0, 4'hf},
                            32'h0000_0001};
    assign raw_tlp.tkeepdw = 4'b0111;
    assign raw_tlp.tvalid = accepted_count < 7'd33;
    assign raw_tlp.tlast = 1'b1;
    assign raw_tlp.tuser = 9'b000000001;
    assign raw_tlp.has_data = raw_tlp.tvalid;

    assign rq_axis.tready = 1'b1;

    asmcehnk_tlps128_to_axis_rq_us #(.RQ_SEQ_NUM_W(6)) dut (
        .clk                      (clk),
        .rst                      (rst),
        .tlps_in                  (raw_tlp.sink),
        .m_axis_rq                (rq_axis),
        .pcie_rq_seq_num0         (6'd0),
        .pcie_rq_seq_num_vld0     (ack_valid),
        .pcie_rq_seq_num1         (6'd0),
        .pcie_rq_seq_num_vld1     (1'b0),
        .rc_tag_release           (8'd0),
        .rc_tag_release_valid     (1'b0),
        .status_outstanding       (status_outstanding),
        .status_blocked           (status_blocked),
        .status_error             (status_error),
        .status_tag_blocked       (),
        .status_tag_error         ()
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            accepted_count <= 7'd0;
            output_count <= 7'd0;
        end else begin
            if (raw_tlp.tvalid && raw_tlp.tready) begin
                accepted_count <= accepted_count + 1'b1;
            end
            if (rq_axis.tvalid && rq_axis.tready) begin
                if (rq_axis.tuser[27:24] != output_count[3:0] ||
                    rq_axis.tuser[61:60] != output_count[5:4]) begin
                    errors <= errors + 1;
                end
                output_count <= output_count + 1'b1;
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        wait (accepted_count == 7'd32);
        repeat (10) @(posedge clk);
        if (accepted_count != 7'd32 || raw_tlp.tready != 1'b0 ||
            status_outstanding != 7'd32 || !status_blocked || status_error) begin
            errors = errors + 1;
        end
        @(negedge clk);
        ack_valid = 1'b1;
        @(negedge clk);
        ack_valid = 1'b0;
        wait (accepted_count == 7'd33);
        repeat (5) @(posedge clk);
        if (errors == 0 && output_count == 7'd33) begin
            $display("PCIE_RQ_CREDIT_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_RQ_CREDIT_TEST_FAIL errors=%0d accepted=%0d outputs=%0d ready=%b",
               errors, accepted_count, output_count, raw_tlp.tready);
    end

    initial begin
        #2000;
        $fatal(1, "PCIE_RQ_CREDIT_TEST_TIMEOUT accepted=%0d outputs=%0d",
               accepted_count, output_count);
    end

endmodule

module tb_pcie_cc_multibeat;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [127:0] raw_data = 128'd0;
    logic [3:0] raw_keep = 4'd0;
    logic raw_valid = 1'b0;
    logic raw_last = 1'b0;
    logic [8:0] raw_user = 9'd0;
    logic cc_ready = 1'b1;
    logic [1:0] output_count = 2'd0;
    logic [255:0] stalled_data = 256'd0;
    integer errors = 0;

    IfAXIS128 raw_tlp();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(33)) cc_axis();

    always #2 clk = ~clk;

    assign raw_tlp.tdata = raw_data;
    assign raw_tlp.tkeepdw = raw_keep;
    assign raw_tlp.tvalid = raw_valid;
    assign raw_tlp.tlast = raw_last;
    assign raw_tlp.tuser = raw_user;
    assign raw_tlp.has_data = raw_valid;
    assign cc_axis.tready = cc_ready;

    asmcehnk_tlps128_to_axis_cc_us dut (
        .clk        (clk),
        .rst        (rst),
        .tlps_in    (raw_tlp.sink),
        .m_axis_cc  (cc_axis)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            output_count <= 2'd0;
        end else if (cc_axis.tvalid && cc_axis.tready) begin
            if (output_count == 2'd0) begin
                if (cc_axis.tkeep != 8'hff || cc_axis.tlast ||
                    cc_axis.tdata[6:0] != 7'h20 ||
                    cc_axis.tdata[28:16] != 13'h018 ||
                    cc_axis.tdata[42:32] != 11'd6 ||
                    cc_axis.tdata[63:48] != 16'h1234 ||
                    cc_axis.tdata[71:64] != 8'h5a ||
                    cc_axis.tdata[87:72] != 16'h5678 ||
                    !cc_axis.tdata[88] ||
                    cc_axis.tdata[127:96] != 32'h4433_2211 ||
                    cc_axis.tdata[159:128] != 32'h8877_6655 ||
                    cc_axis.tdata[191:160] != 32'hccbb_aa99 ||
                    cc_axis.tdata[223:192] != 32'h00ff_eedd ||
                    cc_axis.tdata[255:224] != 32'h6745_2301) begin
                    errors <= errors + 1;
                end
            end else if (output_count == 2'd1) begin
                if (cc_axis.tkeep != 8'h01 || !cc_axis.tlast ||
                    cc_axis.tdata[31:0] != 32'hefcd_ab89) begin
                    errors <= errors + 1;
                end
            end else begin
                errors <= errors + 1;
            end
            output_count <= output_count + 1'b1;
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Raw CplD header plus the first payload DWORD.
        raw_data = {32'h1122_3344, 32'h1234_5a20,
                    32'h5678_0018, 32'h4a00_0006};
        raw_keep = 4'b1111;
        raw_user = 9'b000000001;
        raw_last = 1'b0;
        raw_valid = 1'b1;
        wait (raw_tlp.tready);
        @(posedge clk);
        @(negedge clk);

        // Leave a five-DWORD partial CC beat; the old packer deadlocked here.
        raw_data = {96'd0, 32'h5566_7788};
        raw_keep = 4'b0001;
        raw_user = 9'd0;
        raw_last = 1'b0;
        wait (raw_tlp.tready);
        @(posedge clk);
        @(negedge clk);

        // Cross the 256-bit boundary and leave one final DWORD.
        raw_data = {32'h89ab_cdef, 32'h0123_4567,
                    32'hddee_ff00, 32'h99aa_bbcc};
        raw_keep = 4'b1111;
        raw_last = 1'b1;
        wait (raw_tlp.tready);
        @(posedge clk);
        @(negedge clk);
        raw_valid = 1'b0;
        raw_keep = 4'd0;
        raw_last = 1'b0;

        // Hold the first CC beat and verify ready/valid stability.
        cc_ready = 1'b0;
        stalled_data = cc_axis.tdata;
        repeat (3) begin
            @(posedge clk);
            if (!cc_axis.tvalid || cc_axis.tdata != stalled_data ||
                cc_axis.tkeep != 8'hff || cc_axis.tlast) begin
                errors = errors + 1;
            end
        end
        @(negedge clk);
        cc_ready = 1'b1;
        wait (output_count == 2'd2);
        repeat (3) @(posedge clk);

        if (errors == 0) begin
            $display("PCIE_CC_MULTIBEAT_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_CC_MULTIBEAT_TEST_FAIL errors=%0d outputs=%0d",
               errors, output_count);
    end

    initial begin
        #2000;
        $fatal(1, "PCIE_CC_MULTIBEAT_TEST_TIMEOUT errors=%0d outputs=%0d",
               errors, output_count);
    end

endmodule

module tb_pcie_tag_lifecycle;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic raw_valid = 1'b0;
    logic rc_valid = 1'b0;
    logic rc_last = 1'b1;
    logic [255:0] rc_data = 256'd0;
    logic [7:0] rc_keep = 8'd0;
    logic [7:0] rc_tag_release;
    logic rc_tag_release_valid;
    wire [6:0] status_outstanding;
    wire status_seq_blocked;
    wire status_seq_error;
    wire status_tag_blocked;
    wire status_tag_error;
    integer rq_output_count = 0;
    integer errors = 0;

    IfAXIS128 raw_tlp();
    IfAXIS128 rc_raw();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(62)) rq_axis();
    taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
                   .USER_EN(1), .USER_W(75)) rc_axis();

    always #2 clk = ~clk;

    assign raw_tlp.tdata = {32'd0, 32'h0000_1000,
                            32'h0000_5a0f, 32'h0000_0001};
    assign raw_tlp.tkeepdw = 4'b0111;
    assign raw_tlp.tvalid = raw_valid;
    assign raw_tlp.tlast = 1'b1;
    assign raw_tlp.tuser = 9'b000000001;
    assign raw_tlp.has_data = raw_valid;
    assign rq_axis.tready = 1'b1;

    assign rc_axis.tdata = rc_data;
    assign rc_axis.tkeep = rc_keep;
    assign rc_axis.tstrb = rc_keep;
    assign rc_axis.tvalid = rc_valid;
    assign rc_axis.tlast = rc_last;
    assign rc_axis.tuser = 75'd0;
    assign rc_axis.tid = '0;
    assign rc_axis.tdest = '0;
    assign rc_raw.tready = 1'b1;

    asmcehnk_tlps128_to_axis_rq_us #(.RQ_SEQ_NUM_W(6)) rq_inst (
        .clk                      (clk),
        .rst                      (rst),
        .tlps_in                  (raw_tlp.sink),
        .m_axis_rq                (rq_axis),
        .pcie_rq_seq_num0         (6'd0),
        .pcie_rq_seq_num_vld0     (1'b0),
        .pcie_rq_seq_num1         (6'd0),
        .pcie_rq_seq_num_vld1     (1'b0),
        .rc_tag_release           (rc_tag_release),
        .rc_tag_release_valid     (rc_tag_release_valid),
        .status_outstanding       (status_outstanding),
        .status_blocked           (status_seq_blocked),
        .status_error             (status_seq_error),
        .status_tag_blocked       (status_tag_blocked),
        .status_tag_error         (status_tag_error)
    );

    asmcehnk_pcie_us_rc_to_tlps128 rc_inst (
        .clk               (clk),
        .rst               (rst),
        .s_axis_rc         (rc_axis),
        .tlps_out          (rc_raw.source),
        .tag_release       (rc_tag_release),
        .tag_release_valid (rc_tag_release_valid)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            rq_output_count <= 0;
        end else if (rq_axis.tvalid && rq_axis.tready) begin
            if (rq_axis.tdata[103:96] != 8'h5a) begin
                errors <= errors + 1;
            end
            rq_output_count <= rq_output_count + 1;
        end
    end

    initial begin
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Launch one MRd with client tag 5a.
        raw_valid = 1'b1;
        wait (raw_tlp.tready);
        @(posedge clk);
        @(negedge clk);
        raw_valid = 1'b0;
        repeat (2) @(posedge clk);

        // A second MRd with the same tag must remain backpressured.
        @(negedge clk);
        raw_valid = 1'b1;
        repeat (3) @(posedge clk);
        if (raw_tlp.tready || !status_tag_blocked || status_tag_error) begin
            errors = errors + 1;
        end

        // First half of a split completion: byte_count 16 > payload 8.
        @(negedge clk);
        rc_data = 256'd0;
        rc_data[28:16] = 13'd16;
        rc_data[42:32] = 11'd2;
        rc_data[71:64] = 8'h5a;
        rc_data[159:96] = 64'h1122_3344_5566_7788;
        rc_keep = 8'b0001_1111;
        rc_valid = 1'b1;
        wait (rc_axis.tready);
        @(posedge clk);
        @(negedge clk);
        rc_valid = 1'b0;
        repeat (3) @(posedge clk);
        if (raw_tlp.tready || !status_tag_blocked || status_tag_error) begin
            errors = errors + 1;
        end

        // A terminal completion must not release its tag before a multi-beat
        // RC packet reaches the accepted tlast beat.
        @(negedge clk);
        rc_data = 256'd0;
        rc_data[28:16] = 13'd24;
        rc_data[42:32] = 11'd6;
        rc_data[71:64] = 8'h5a;
        rc_data[255:96] = 160'h0011_2233_4455_6677_8899_aabb_ccdd_eeff_1020_3040;
        rc_keep = 8'hff;
        rc_last = 1'b0;
        rc_valid = 1'b1;
        wait (rc_axis.tready);
        @(posedge clk);
        @(negedge clk);
        rc_valid = 1'b0;
        repeat (3) @(posedge clk);
        if (raw_tlp.tready || !status_tag_blocked || status_tag_error) begin
            errors = errors + 1;
        end

        @(negedge clk);
        rc_data = 256'd0;
        rc_data[31:0] = 32'h5060_7080;
        rc_keep = 8'b0000_0001;
        rc_last = 1'b1;
        rc_valid = 1'b1;
        wait (rc_axis.tready);
        @(posedge clk);
        @(negedge clk);
        rc_valid = 1'b0;
        wait (raw_tlp.tready);
        @(posedge clk);
        @(negedge clk);
        raw_valid = 1'b0;

        // A final completion for an unknown tag must set a sticky error.
        rc_data = 256'd0;
        rc_data[28:16] = 13'd4;
        rc_data[42:32] = 11'd1;
        rc_data[71:64] = 8'h33;
        rc_keep = 8'b0000_1111;
        rc_last = 1'b1;
        rc_valid = 1'b1;
        wait (rc_axis.tready);
        @(posedge clk);
        @(negedge clk);
        rc_valid = 1'b0;
        repeat (4) @(posedge clk);

        if (errors == 0 && rq_output_count == 2 && status_tag_error &&
            !status_seq_error && status_outstanding == 7'd2) begin
            $display("PCIE_TAG_LIFECYCLE_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_TAG_LIFECYCLE_TEST_FAIL errors=%0d rq=%0d tag_block=%b tag_error=%b seq=%0d",
               errors, rq_output_count, status_tag_blocked,
               status_tag_error, status_outstanding);
    end

    initial begin
        #3000;
        $fatal(1, "PCIE_TAG_LIFECYCLE_TEST_TIMEOUT errors=%0d rq=%0d",
               errors, rq_output_count);
    end

endmodule
