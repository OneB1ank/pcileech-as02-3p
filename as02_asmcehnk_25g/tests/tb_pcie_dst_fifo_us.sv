`timescale 1ns / 1ps
`default_nettype none

// Behavioral FIFO model for the focused destination-staging contract test.
// The generated XCI remains the implementation source used by Vivado builds.
module fifo_134_134_clk2 (
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

module tb_pcie_dst_fifo_us;
    logic clk_pcie = 1'b0;
    logic clk_sys = 1'b0;
    logic rst_pcie = 1'b1;
    logic rst_sys = 1'b1;

    always #2 clk_pcie = !clk_pcie;
    always #5 clk_sys = !clk_sys;

    IfAXIS128 tlps_in();
    IfPCIeFifoTlp dfifo();

    logic [127:0] input_data = 128'd0;
    logic [3:0] input_keep = 4'd0;
    logic input_valid = 1'b0;
    logic input_last = 1'b0;
    logic input_first = 1'b0;
    logic output_read_enable = 1'b0;

    assign tlps_in.tdata = input_data;
    assign tlps_in.tkeepdw = input_keep;
    assign tlps_in.tvalid = input_valid;
    assign tlps_in.tlast = input_last;
    assign tlps_in.tuser = {8'd0, input_first};

    assign dfifo.tx_data = 32'd0;
    assign dfifo.tx_last = 1'b0;
    assign dfifo.tx_valid = 1'b0;
    assign dfifo.rx_rd_en = output_read_enable;

    asmcehnk_tlps128_dst_fifo_us dut (
        .rst_pcie(rst_pcie),
        .rst_sys(rst_sys),
        .clk_pcie(clk_pcie),
        .clk_sys(clk_sys),
        .tlps_in(tlps_in.sink_lite),
        .dfifo(dfifo.mp_pcie)
    );

    logic [133:0] expected_words [0:31];
    logic [127:0] observed_data;
    logic [3:0] observed_valid;
    logic [3:0] observed_last;
    logic [3:0] expected_last;
    logic simultaneous_consume_complete_seen = 1'b0;
    logic empty_request_active = 1'b0;
    integer expected_count = 0;
    integer received_count = 0;
    integer errors = 0;
    integer send_index;
    integer request_cycle;

    always @(*) begin
        observed_data = {
            dfifo.rx_data[3],
            dfifo.rx_data[2],
            dfifo.rx_data[1],
            dfifo.rx_data[0]
        };
        observed_valid = {
            dfifo.rx_valid[3],
            dfifo.rx_valid[2],
            dfifo.rx_valid[1],
            dfifo.rx_valid[0]
        };
        observed_last = {
            dfifo.rx_last[3],
            dfifo.rx_last[2],
            dfifo.rx_last[1],
            dfifo.rx_last[0]
        };
    end

    always @(posedge clk_sys) begin
        if (!rst_sys) begin
            if (dut.stage_count_reg > 2 || dut.read_pending_count_reg > 2 ||
                dut.stage_reserved_count > 2) begin
                $display("PCIE_DST_FIFO_CAPACITY_FAIL stage=%0d pending=%0d reserved=%0d",
                         dut.stage_count_reg, dut.read_pending_count_reg,
                         dut.stage_reserved_count);
                errors = errors + 1;
            end

            if (dut.fifo_valid && dut.stage_consume) begin
                simultaneous_consume_complete_seen = 1'b1;
            end

            if (|observed_valid) begin
                if (empty_request_active) begin
                    $display("PCIE_DST_FIFO_EMPTY_REQUEST_FAIL valid=%b", observed_valid);
                    errors = errors + 1;
                end else if (received_count >= expected_count) begin
                    $display("PCIE_DST_FIFO_UNEXPECTED_OUTPUT_FAIL index=%0d", received_count);
                    errors = errors + 1;
                end else begin
                    expected_last = 4'b0000;
                    if (expected_words[received_count][132]) begin
                        case (expected_words[received_count][131:128])
                            4'b0001: expected_last = 4'b0001;
                            4'b0011: expected_last = 4'b0010;
                            4'b0111: expected_last = 4'b0100;
                            4'b1111: expected_last = 4'b1000;
                            default: expected_last = 4'b0000;
                        endcase
                    end

                    if (observed_data !== expected_words[received_count][127:0] ||
                        observed_valid !== expected_words[received_count][131:128] ||
                        observed_last !== expected_last ||
                        dfifo.rx_first[0] !== expected_words[received_count][133] ||
                        dfifo.rx_first[1] !== 1'b0 ||
                        dfifo.rx_first[2] !== 1'b0 ||
                        dfifo.rx_first[3] !== 1'b0) begin
                        $display("PCIE_DST_FIFO_ORDER_FAIL index=%0d data=%h valid=%b last=%b first=%b expected=%h",
                                 received_count, observed_data, observed_valid,
                                 observed_last, dfifo.rx_first[0],
                                 expected_words[received_count]);
                        errors = errors + 1;
                    end
                    received_count = received_count + 1;
                end
            end
        end
    end

    initial begin
        repeat (5) @(posedge clk_sys);
        rst_pcie = 1'b0;
        rst_sys = 1'b0;
        repeat (4) @(posedge clk_sys);

        // A request against an empty FIFO must not synthesize a valid word.
        empty_request_active = 1'b1;
        @(negedge clk_sys);
        output_read_enable = 1'b1;
        @(negedge clk_sys);
        output_read_enable = 1'b0;
        repeat (3) @(posedge clk_sys);
        empty_request_active = 1'b0;

        // First batch: continuous requests verify one-cycle request/return,
        // ordering, tkeep/last decoding, and consume+complete throughput.
        for (send_index = 0; send_index < 12; send_index = send_index + 1) begin
            @(negedge clk_pcie);
            input_data = {
                32'hd0000000 | send_index,
                32'hc0000000 | send_index,
                32'hb0000000 | send_index,
                32'ha0000000 | send_index
            };
            case (send_index[1:0])
                2'd0: input_keep = 4'b0001;
                2'd1: input_keep = 4'b0011;
                2'd2: input_keep = 4'b0111;
                default: input_keep = 4'b1111;
            endcase
            input_first = (send_index[1:0] == 2'd0);
            input_last = (send_index[1:0] == 2'd3);
            input_valid = 1'b1;
            expected_words[expected_count] = {
                input_first, input_last, input_keep, input_data
            };
            expected_count = expected_count + 1;
        end
        @(negedge clk_pcie);
        input_valid = 1'b0;
        input_first = 1'b0;
        input_last = 1'b0;
        input_keep = 4'd0;

        repeat (10) @(posedge clk_sys);
        @(negedge clk_sys);
        output_read_enable = 1'b1;
        repeat (12) @(negedge clk_sys);
        output_read_enable = 1'b0;
        repeat (8) @(posedge clk_sys);

        if (received_count != expected_count) begin
            $display("PCIE_DST_FIFO_CONTINUOUS_COUNT_FAIL received=%0d expected=%0d",
                     received_count, expected_count);
            errors = errors + 1;
        end
        if (!simultaneous_consume_complete_seen) begin
            $display("PCIE_DST_FIFO_SIMULTANEOUS_PATH_FAIL");
            errors = errors + 1;
        end

        // Seed stale queued data, then emulate the real network-reset path:
        // system staging resets first and the synchronized PCIe soft-path
        // reset follows.  No pre-reset word may leak into the next batch.
        for (send_index = 0; send_index < 3; send_index = send_index + 1) begin
            @(negedge clk_pcie);
            input_data = {96'h0, 24'hdead00, send_index[7:0]};
            input_keep = 4'b0001;
            input_first = (send_index == 0);
            input_last = (send_index == 2);
            input_valid = 1'b1;
        end
        @(negedge clk_pcie);
        input_valid = 1'b0;
        wait (dut.stage_count_reg != 0);
        @(negedge clk_sys);
        output_read_enable = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!(|observed_valid)) begin
            $display("PCIE_DST_FIFO_RESET_PRECONDITION_FAIL");
            errors = errors + 1;
        end
        @(negedge clk_sys);
        rst_sys = 1'b1;
        #1;
        if (|observed_valid) begin
            $display("PCIE_DST_FIFO_RESET_GATE_FAIL valid=%b", observed_valid);
            errors = errors + 1;
        end
        repeat (3) @(posedge clk_pcie);
        rst_pcie = 1'b1;
        repeat (3) @(posedge clk_sys);
        output_read_enable = 1'b0;
        rst_sys = 1'b0;
        repeat (3) @(posedge clk_pcie);
        rst_pcie = 1'b0;
        repeat (5) @(posedge clk_sys);

        if (dut.stage_count_reg !== 0 || dut.read_pending_count_reg !== 0 ||
            |observed_valid) begin
            $display("PCIE_DST_FIFO_RESET_FAIL stage=%0d pending=%0d valid=%b",
                     dut.stage_count_reg, dut.read_pending_count_reg,
                     observed_valid);
            errors = errors + 1;
        end

        // Second batch: deterministic request gaps cover isolated reads and
        // ordering after reset without relying on tasks or helper functions.
        for (send_index = 0; send_index < 8; send_index = send_index + 1) begin
            @(negedge clk_pcie);
            input_data = {
                32'hf0000000 | send_index,
                32'he0000000 | send_index,
                32'h90000000 | send_index,
                32'h80000000 | send_index
            };
            input_keep = 4'b1111;
            input_first = (send_index == 0);
            input_last = (send_index == 7);
            input_valid = 1'b1;
            expected_words[expected_count] = {
                input_first, input_last, input_keep, input_data
            };
            expected_count = expected_count + 1;
        end
        @(negedge clk_pcie);
        input_valid = 1'b0;
        input_first = 1'b0;
        input_last = 1'b0;
        input_keep = 4'd0;

        repeat (10) @(posedge clk_sys);
        for (request_cycle = 0; request_cycle < 12; request_cycle = request_cycle + 1) begin
            @(negedge clk_sys);
            output_read_enable = ((request_cycle % 3) != 1);
        end
        @(negedge clk_sys);
        output_read_enable = 1'b0;
        repeat (8) @(posedge clk_sys);

        if (received_count != expected_count) begin
            $display("PCIE_DST_FIFO_GAPPED_COUNT_FAIL received=%0d expected=%0d",
                     received_count, expected_count);
            errors = errors + 1;
        end

        // Exercise the opposite paired-reset order with staged data present.
        // PCIe reset clears the CDC FIFO first; system reset then clears the
        // elastic queue before either side is released for the next epoch.
        for (send_index = 0; send_index < 2; send_index = send_index + 1) begin
            @(negedge clk_pcie);
            input_data = {96'd0, 24'hbeef00, send_index[7:0]};
            input_keep = 4'b0001;
            input_first = (send_index == 0);
            input_last = (send_index == 1);
            input_valid = 1'b1;
        end
        @(negedge clk_pcie);
        input_valid = 1'b0;
        wait (dut.stage_count_reg != 0);
        @(negedge clk_pcie);
        rst_pcie = 1'b1;
        repeat (2) @(posedge clk_sys);
        rst_sys = 1'b1;
        repeat (3) @(posedge clk_pcie);
        rst_pcie = 1'b0;
        repeat (2) @(posedge clk_sys);
        rst_sys = 1'b0;
        repeat (5) @(posedge clk_sys);

        if (dut.stage_count_reg !== 0 || dut.read_pending_count_reg !== 0 ||
            |observed_valid) begin
            $display("PCIE_DST_FIFO_REVERSE_RESET_FAIL stage=%0d pending=%0d valid=%b",
                     dut.stage_count_reg, dut.read_pending_count_reg,
                     observed_valid);
            errors = errors + 1;
        end

        @(negedge clk_pcie);
        input_data = 128'hfeed_0003_feed_0002_feed_0001_feed_0000;
        input_keep = 4'b1111;
        input_first = 1'b1;
        input_last = 1'b1;
        input_valid = 1'b1;
        expected_words[expected_count] = {
            input_first, input_last, input_keep, input_data
        };
        expected_count = expected_count + 1;
        @(negedge clk_pcie);
        input_valid = 1'b0;
        input_first = 1'b0;
        input_last = 1'b0;
        input_keep = 4'd0;
        repeat (6) @(posedge clk_sys);
        @(negedge clk_sys);
        output_read_enable = 1'b1;
        @(negedge clk_sys);
        output_read_enable = 1'b0;
        repeat (5) @(posedge clk_sys);

        if (received_count != expected_count) begin
            $display("PCIE_DST_FIFO_REVERSE_RESET_RECOVERY_FAIL received=%0d expected=%0d",
                     received_count, expected_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PCIE_DST_FIFO_US_TEST_PASS");
        end else begin
            $display("PCIE_DST_FIFO_US_TEST_FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule

`resetall
