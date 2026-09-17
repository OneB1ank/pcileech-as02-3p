`timescale 1ns / 1ps
`default_nettype none

// Behavioral token FIFO for the focused legacy source-to-RQ contract test.
`ifndef AS02_USE_XCI_FIFO_MODEL
module fifo_1_1_clk2 (
    input  wire rst,
    input  wire wr_clk,
    input  wire rd_clk,
    input  wire din,
    input  wire wr_en,
    input  wire rd_en,
    output wire dout,
    output wire full,
    output wire empty,
    output wire valid
);
    logic memory [0:31];
    logic [5:0] write_pointer = 6'd0;
    logic [5:0] read_pointer = 6'd0;
    logic data_reg = 1'b0;
    logic valid_reg = 1'b0;

    assign dout = data_reg;
    assign full = ((write_pointer + 1'b1) == read_pointer);
    assign empty = (write_pointer == read_pointer);
    assign valid = valid_reg;

    always @(posedge wr_clk) begin
        if (rst) begin
            write_pointer <= 6'd0;
        end else if (wr_en && !full) begin
            memory[write_pointer[4:0]] <= din;
            write_pointer <= write_pointer + 1'b1;
        end
    end

    always @(posedge rd_clk) begin
        if (rst) begin
            read_pointer <= 6'd0;
            data_reg <= 1'b0;
            valid_reg <= 1'b0;
        end else begin
            valid_reg <= 1'b0;
            if (rd_en && !empty) begin
                data_reg <= memory[read_pointer[4:0]];
                read_pointer <= read_pointer + 1'b1;
                valid_reg <= 1'b1;
            end
        end
    end
endmodule

// Behavioral Standard-mode data FIFO.  valid is a one-cycle return pulse and
// deliberately does not hold data for a later ready cycle.
module fifo_134_134_clk2_rxfifo (
    input  wire         rst,
    input  wire         wr_clk,
    input  wire         rd_clk,
    input  wire [133:0] din,
    input  wire         wr_en,
    input  wire         rd_en,
    output wire [133:0] dout,
    output wire         full,
    output wire         empty,
    output wire         valid
);
    logic [133:0] memory [0:63];
    logic [6:0] write_pointer = 7'd0;
    logic [6:0] read_pointer = 7'd0;
    logic [133:0] data_reg = 134'd0;
    logic valid_reg = 1'b0;

    assign dout = data_reg;
    assign full = ((write_pointer + 1'b1) == read_pointer);
    assign empty = (write_pointer == read_pointer);
    assign valid = valid_reg;

    always @(posedge wr_clk) begin
        if (rst) begin
            write_pointer <= 7'd0;
        end else if (wr_en && !full) begin
            memory[write_pointer[5:0]] <= din;
            write_pointer <= write_pointer + 1'b1;
        end
    end

    always @(posedge rd_clk) begin
        if (rst) begin
            read_pointer <= 7'd0;
            data_reg <= 134'd0;
            valid_reg <= 1'b0;
        end else begin
            valid_reg <= 1'b0;
            if (rd_en && !empty) begin
                data_reg <= memory[read_pointer[5:0]];
                read_pointer <= read_pointer + 1'b1;
                valid_reg <= 1'b1;
            end
        end
    end
endmodule
`endif

module tb_pcie_src_fifo_rq_us;
    logic clk_pcie = 1'b0;
    logic clk_sys = 1'b0;
    logic rst_pcie = 1'b1;
    logic rst_sys = 1'b1;
    logic [31:0] dfifo_tx_data = 32'd0;
    logic dfifo_tx_last = 1'b0;
    logic dfifo_tx_valid = 1'b0;
    logic rq_ready = 1'b1;
    logic [4:0] seq_ack_number = 5'd0;
    logic seq_ack_valid = 1'b0;

    // Model the 250 MHz PCIe user clock and the independent 25G network clock.
    always #2.00 clk_pcie = !clk_pcie;
    always #1.24 clk_sys = !clk_sys;

    IfAXIS128 legacy_tlp();
    IfAXIS128 rq_raw_tlp();
    taxi_axis_if #(
        .DATA_W(256),
        .KEEP_EN(1),
        .KEEP_W(8),
        .USER_EN(1),
        .USER_W(62)
    ) rq_axis();

    wire [5:0] status_outstanding;
    wire status_blocked;
    wire status_error;
    wire status_tag_blocked;
    wire status_tag_error;

    assign rq_axis.tready = rq_ready;

    asmcehnk_tlps128_src_fifo legacy_source_inst (
        .rst_pcie       (rst_pcie),
        .rst_sys        (rst_sys),
        .clk_pcie       (clk_pcie),
        .clk_sys        (clk_sys),
        .dfifo_tx_data  (dfifo_tx_data),
        .dfifo_tx_last  (dfifo_tx_last),
        .dfifo_tx_valid (dfifo_tx_valid),
        .tlps_out       (legacy_tlp.source)
    );

    asmcehnk_tlps128_src_elastic_us elastic_inst (
        .rst            (rst_pcie),
        .clk            (clk_pcie),
        .tlps_legacy_in (legacy_tlp.sink),
        .tlps_out       (rq_raw_tlp.source)
    );

    asmcehnk_tlps128_to_axis_rq_us #(
        .RQ_SEQ_NUM_W(5)
    ) rq_adapter_inst (
        .clk                      (clk_pcie),
        .rst                      (rst_pcie),
        .tlps_in                  (rq_raw_tlp.sink),
        .m_axis_rq                (rq_axis),
        .pcie_rq_seq_num0         (seq_ack_number),
        .pcie_rq_seq_num_vld0     (seq_ack_valid),
        .pcie_rq_seq_num1         (5'd0),
        .pcie_rq_seq_num_vld1     (1'b0),
        .rc_tag_release           (8'd0),
        .rc_tag_release_valid     (1'b0),
        .status_outstanding       (status_outstanding),
        .status_blocked           (status_blocked),
        .status_error             (status_error),
        .status_tag_blocked       (status_tag_blocked),
        .status_tag_error         (status_tag_error)
    );

    logic [133:0] stalled_word = 134'd0;
    logic stall_active = 1'b0;
    logic credit_hold_seen = 1'b0;
    integer credit_hold_cycles = 0;
    integer legacy_return_count = 0;
    integer rq_output_count = 0;
    integer errors = 0;
    integer packet_index;
    integer word_index;

    always @(posedge clk_pcie) begin
        if (rst_pcie) begin
            stall_active = 1'b0;
        end else begin
            if (elastic_inst.stage_count_reg > 2 ||
                elastic_inst.read_pending_count_reg > 2 ||
                elastic_inst.stage_reserved_count > 2) begin
                $display("PCIE_SRC_FIFO_CAPACITY_FAIL stage=%0d pending=%0d reserved=%0d",
                         elastic_inst.stage_count_reg,
                         elastic_inst.read_pending_count_reg,
                         elastic_inst.stage_reserved_count);
                errors = errors + 1;
            end

            if (legacy_tlp.tvalid) begin
                legacy_return_count = legacy_return_count + 1;
            end

            if (rq_raw_tlp.tvalid && !rq_raw_tlp.tready) begin
                credit_hold_seen = 1'b1;
                credit_hold_cycles = credit_hold_cycles + 1;
                if (!stall_active) begin
                    stalled_word = {
                        rq_raw_tlp.tuser[0],
                        rq_raw_tlp.tlast,
                        rq_raw_tlp.tkeepdw,
                        rq_raw_tlp.tdata
                    };
                    stall_active = 1'b1;
                end else if ({
                    rq_raw_tlp.tuser[0],
                    rq_raw_tlp.tlast,
                    rq_raw_tlp.tkeepdw,
                    rq_raw_tlp.tdata
                } !== stalled_word) begin
                    $display("PCIE_SRC_FIFO_STABILITY_FAIL");
                    errors = errors + 1;
                end
            end else if (rq_raw_tlp.tvalid && rq_raw_tlp.tready) begin
                stall_active = 1'b0;
            end

            if (rq_axis.tvalid && rq_axis.tready) begin
                if (rq_output_count < 17) begin
                    if ({rq_axis.tdata[63:2], 2'b00} !==
                        (64'h0000_1000 * (rq_output_count + 1)) ||
                        rq_axis.tdata[103:96] !== (8'h10 + rq_output_count) ||
                        rq_axis.tkeep !== 8'h0f || !rq_axis.tlast) begin
                        $display("PCIE_SRC_FIFO_ORDER_FAIL index=%0d addr=%h tag=%h keep=%h last=%b",
                                 rq_output_count,
                                 {rq_axis.tdata[63:2], 2'b00},
                                 rq_axis.tdata[103:96],
                                 rq_axis.tkeep,
                                 rq_axis.tlast);
                        errors = errors + 1;
                    end
                end else if (rq_output_count == 17) begin
                    if ({rq_axis.tdata[63:2], 2'b00} !== 64'h0005_5000 ||
                        rq_axis.tdata[103:96] !== 8'h55) begin
                        $display("PCIE_SRC_FIFO_POST_RESET_FAIL addr=%h tag=%h",
                                 {rq_axis.tdata[63:2], 2'b00},
                                 rq_axis.tdata[103:96]);
                        errors = errors + 1;
                    end
                end else if (rq_output_count == 18) begin
                    if ({rq_axis.tdata[63:2], 2'b00} !== 64'h0006_6000 ||
                        rq_axis.tdata[103:96] !== 8'h66) begin
                        $display("PCIE_SRC_FIFO_REVERSE_RESET_FAIL addr=%h tag=%h",
                                 {rq_axis.tdata[63:2], 2'b00},
                                 rq_axis.tdata[103:96]);
                        errors = errors + 1;
                    end
                end else begin
                    $display("PCIE_SRC_FIFO_DUPLICATE_FAIL index=%0d", rq_output_count);
                    errors = errors + 1;
                end
                rq_output_count = rq_output_count + 1;
            end
        end
    end

    initial begin
        // The generated FIFO netlist includes the Xilinx global-set/reset
        // interval and independent-domain reset synchronizers.
        #200;
        repeat (8) @(posedge clk_pcie);
        @(negedge clk_sys);
        rst_sys = 1'b0;
        @(negedge clk_pcie);
        rst_pcie = 1'b0;
        repeat (24) @(posedge clk_sys);
        repeat (24) @(posedge clk_pcie);

        // Seventeen one-DWORD MRd packets fill the sixteen-entry sequence-credit
        // window.  The seventeenth raw TLP must remain stable until sequence 0 is
        // acknowledged instead of being lost as a Standard-FIFO valid pulse.
        for (packet_index = 0; packet_index < 17; packet_index = packet_index + 1) begin
            for (word_index = 0; word_index < 3; word_index = word_index + 1) begin
                @(negedge clk_sys);
                dfifo_tx_valid = 1'b1;
                dfifo_tx_last = (word_index == 2);
                case (word_index)
                    0: dfifo_tx_data = 32'h0000_0001;
                    1: dfifo_tx_data = 32'h0000_000f |
                                           ((8'h10 + packet_index) << 8);
                    default: dfifo_tx_data = 32'h0000_1000 *
                                             (packet_index + 1);
                endcase
            end
        end
        @(negedge clk_sys);
        dfifo_tx_valid = 1'b0;
        dfifo_tx_last = 1'b0;
        dfifo_tx_data = 32'd0;

        wait (rq_output_count == 16);
        wait (status_blocked && rq_raw_tlp.tvalid && !rq_raw_tlp.tready);
        repeat (5) @(posedge clk_pcie);
        if (!credit_hold_seen || credit_hold_cycles < 3 ||
            status_outstanding != 6'd16) begin
            $display("PCIE_SRC_FIFO_CREDIT_HOLD_FAIL seen=%b cycles=%0d outstanding=%0d",
                     credit_hold_seen, credit_hold_cycles, status_outstanding);
            errors = errors + 1;
        end

        @(negedge clk_pcie);
        seq_ack_number = 5'd0;
        seq_ack_valid = 1'b1;
        @(negedge clk_pcie);
        seq_ack_valid = 1'b0;

        wait (rq_output_count == 17);
        repeat (4) @(posedge clk_pcie);
        if (legacy_return_count != 17 || status_error || status_tag_blocked ||
            status_tag_error) begin
            $display("PCIE_SRC_FIFO_ACCOUNTING_FAIL returns=%0d seq_error=%b tag_block=%b tag_error=%b",
                     legacy_return_count, status_error,
                     status_tag_blocked, status_tag_error);
            errors = errors + 1;
        end

        // Reset a partial legacy packet with the system side first and the
        // PCIe side shortly afterwards.  No pre-reset fragment may reappear.
        @(negedge clk_sys);
        dfifo_tx_valid = 1'b1;
        dfifo_tx_last = 1'b0;
        dfifo_tx_data = 32'h0000_0001;
        @(negedge clk_sys);
        dfifo_tx_data = 32'h0000_aa0f;
        @(negedge clk_sys);
        dfifo_tx_valid = 1'b0;
        dfifo_tx_data = 32'd0;
        rst_sys = 1'b1;
        repeat (2) @(posedge clk_pcie);
        rst_pcie = 1'b1;
        repeat (4) @(posedge clk_pcie);
        @(negedge clk_sys);
        rst_sys = 1'b0;
        repeat (2) @(posedge clk_pcie);
        @(negedge clk_pcie);
        rst_pcie = 1'b0;
        repeat (24) @(posedge clk_sys);
        repeat (24) @(posedge clk_pcie);

        @(negedge clk_sys);
        dfifo_tx_valid = 1'b1;
        dfifo_tx_last = 1'b0;
        dfifo_tx_data = 32'h0000_0001;
        @(negedge clk_sys);
        dfifo_tx_data = 32'h0000_550f;
        @(negedge clk_sys);
        dfifo_tx_last = 1'b1;
        dfifo_tx_data = 32'h0005_5000;
        @(negedge clk_sys);
        dfifo_tx_valid = 1'b0;
        dfifo_tx_last = 1'b0;
        dfifo_tx_data = 32'd0;

        wait (rq_output_count == 18);
        repeat (6) @(posedge clk_pcie);

        // Hold native RQ, queue additional raw TLPs, then assert the PCIe side
        // reset before the system side.  The paired reset must discard every
        // pre-reset stage and the following epoch must start cleanly.
        @(negedge clk_pcie);
        rq_ready = 1'b0;
        for (packet_index = 0; packet_index < 3; packet_index = packet_index + 1) begin
            for (word_index = 0; word_index < 3; word_index = word_index + 1) begin
                @(negedge clk_sys);
                dfifo_tx_valid = 1'b1;
                dfifo_tx_last = (word_index == 2);
                case (word_index)
                    0: dfifo_tx_data = 32'h0000_0001;
                    1: dfifo_tx_data = 32'h0000_000f |
                                           ((8'h60 + packet_index) << 8);
                    default: dfifo_tx_data = 32'h0006_0000 +
                                             (packet_index * 32'h0000_1000);
                endcase
            end
        end
        @(negedge clk_sys);
        dfifo_tx_valid = 1'b0;
        dfifo_tx_last = 1'b0;
        dfifo_tx_data = 32'd0;

        wait (rq_axis.tvalid && !rq_axis.tready);
        wait ((elastic_inst.stage_count_reg != 0) || legacy_tlp.has_data);
        @(negedge clk_pcie);
        rst_pcie = 1'b1;
        repeat (2) @(posedge clk_sys);
        @(negedge clk_sys);
        rst_sys = 1'b1;
        repeat (4) @(posedge clk_pcie);
        @(negedge clk_pcie);
        rst_pcie = 1'b0;
        repeat (2) @(posedge clk_sys);
        @(negedge clk_sys);
        rst_sys = 1'b0;
        rq_ready = 1'b1;
        repeat (24) @(posedge clk_sys);
        repeat (24) @(posedge clk_pcie);

        if (rq_output_count != 18 || elastic_inst.stage_count_reg != 0 ||
            elastic_inst.read_pending_count_reg != 0 || rq_axis.tvalid) begin
            $display("PCIE_SRC_FIFO_REVERSE_RESET_STATE_FAIL outputs=%0d stage=%0d pending=%0d rq_valid=%b",
                     rq_output_count, elastic_inst.stage_count_reg,
                     elastic_inst.read_pending_count_reg, rq_axis.tvalid);
            errors = errors + 1;
        end

        @(negedge clk_sys);
        dfifo_tx_valid = 1'b1;
        dfifo_tx_last = 1'b0;
        dfifo_tx_data = 32'h0000_0001;
        @(negedge clk_sys);
        dfifo_tx_data = 32'h0000_660f;
        @(negedge clk_sys);
        dfifo_tx_last = 1'b1;
        dfifo_tx_data = 32'h0006_6000;
        @(negedge clk_sys);
        dfifo_tx_valid = 1'b0;
        dfifo_tx_last = 1'b0;
        dfifo_tx_data = 32'd0;

        wait (rq_output_count == 19);
        repeat (6) @(posedge clk_pcie);

        if (errors == 0) begin
            $display("PCIE_SRC_FIFO_RQ_ELASTIC_TEST_PASS");
            $finish;
        end
        $fatal(1, "PCIE_SRC_FIFO_RQ_ELASTIC_TEST_FAIL errors=%0d outputs=%0d returns=%0d",
               errors, rq_output_count, legacy_return_count);
    end

    initial begin
        #50000;
        $fatal(1, "PCIE_SRC_FIFO_RQ_ELASTIC_TEST_TIMEOUT errors=%0d outputs=%0d returns=%0d",
               errors, rq_output_count, legacy_return_count);
    end
endmodule

`resetall
