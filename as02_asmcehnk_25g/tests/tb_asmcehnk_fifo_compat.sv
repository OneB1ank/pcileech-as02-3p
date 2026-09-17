`timescale 1ns / 1ps
`include "asmcehnk_header.svh"

module sim_sync_fifo #(
    parameter WIDTH = 34,
    parameter DEPTH = 16
) (
    input  wire                 clk,
    input  wire                 srst,
    input  wire                 rd_en,
    output reg  [WIDTH-1:0]     dout,
    input  wire [WIDTH-1:0]     din,
    input  wire                 wr_en,
    output wire                 full,
    output wire                 almost_full,
    output wire                 empty,
    output reg                  valid
);

    reg [WIDTH-1:0] mem [0:DEPTH-1];
    integer wr_ptr = 0;
    integer rd_ptr = 0;
    integer count = 0;
    wire write_fire;
    wire read_fire;

    assign full = count == DEPTH;
    assign almost_full = count >= DEPTH - 2;
    assign empty = count == 0;
    assign write_fire = wr_en && !full;
    assign read_fire = rd_en && !empty;

    always @(posedge clk) begin
        if (srst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
            dout <= {WIDTH{1'b0}};
            valid <= 1'b0;
        end else begin
            valid <= 1'b0;

            if (write_fire) begin
                mem[wr_ptr] <= din;
                wr_ptr <= wr_ptr == DEPTH - 1 ? 0 : wr_ptr + 1;
            end

            if (read_fire) begin
                dout <= mem[rd_ptr];
                rd_ptr <= rd_ptr == DEPTH - 1 ? 0 : rd_ptr + 1;
                valid <= 1'b1;
            end

            case ({write_fire, read_fire})
                2'b10: count <= count + 1;
                2'b01: count <= count - 1;
                default: count <= count;
            endcase
        end
    end

endmodule

module fifo_34_34 (
    input  wire         clk,
    input  wire         srst,
    input  wire         rd_en,
    output wire [33:0]  dout,
    input  wire [33:0]  din,
    input  wire         wr_en,
    output wire         full,
    output wire         almost_full,
    output wire         empty,
    output wire         valid
);

    sim_sync_fifo #(
        .WIDTH(34),
        .DEPTH(512)
    ) fifo_inst (
        .clk        (clk),
        .srst       (srst),
        .rd_en      (rd_en),
        .dout       (dout),
        .din        (din),
        .wr_en      (wr_en),
        .full       (full),
        .almost_full(almost_full),
        .empty      (empty),
        .valid      (valid)
    );

endmodule

module fifo_64_64_clk1_fifocmd (
    input  wire         clk,
    input  wire         srst,
    input  wire         rd_en,
    output wire [63:0]  dout,
    input  wire [63:0]  din,
    input  wire         wr_en,
    output wire         full,
    output wire         empty,
    output wire         valid
);

    wire almost_full_unused;

    sim_sync_fifo #(
        .WIDTH(64),
        .DEPTH(32)
    ) fifo_inst (
        .clk        (clk),
        .srst       (srst),
        .rd_en      (rd_en),
        .dout       (dout),
        .din        (din),
        .wr_en      (wr_en),
        .full       (full),
        .almost_full(almost_full_unused),
        .empty      (empty),
        .valid      (valid)
    );

endmodule

module tb_asmcehnk_fifo_compat;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rst_cfg_reload = 1'b0;
    reg tick_100mhz_ce = 1'b1;
    time tick_before;
    integer errors = 0;
    integer timeout_count;
    integer block_count = 0;
    integer block_start;

    reg [63:0] com_dout = 64'd0;
    reg com_dout_valid = 1'b0;
    reg com_din_ready = 1'b1;

    reg [31:0] cfg_rx_data = 32'd0;
    reg cfg_rx_valid = 1'b0;
    reg [31:0] tlp_rx_data [0:3];
    reg tlp_rx_first [0:3];
    reg tlp_rx_last [0:3];
    reg tlp_rx_valid [0:3];

    reg drp_rdy = 1'b0;
    reg [15:0] drp_do = 16'd0;
    reg drp_request_seen = 1'b0;
    reg drp_completion_seen = 1'b0;
    reg shadow_tx_valid = 1'b0;
    reg [31:0] shadow_tx_data = 32'd0;
    reg [9:0] shadow_tx_addr = 10'd0;
    reg shadow_tx_addr_lo = 1'b0;

    reg [255:0] output_blocks [0:15];

    IfComToFifo dcom();
    IfPCIeFifoCfg dcfg();
    IfPCIeFifoTlp dtlp();
    IfPCIeFifoCore dpcie();
    IfShadow2Fifo dshadow2fifo();

    always #5 clk = ~clk;

    assign dcom.com_dout = com_dout;
    assign dcom.com_dout_valid = com_dout_valid;
    assign dcom.com_din_ready = com_din_ready;

    assign dcfg.rx_data = cfg_rx_data;
    assign dcfg.rx_valid = cfg_rx_valid;

    assign dtlp.rx_data[0] = tlp_rx_data[0];
    assign dtlp.rx_data[1] = tlp_rx_data[1];
    assign dtlp.rx_data[2] = tlp_rx_data[2];
    assign dtlp.rx_data[3] = tlp_rx_data[3];
    assign dtlp.rx_first[0] = tlp_rx_first[0];
    assign dtlp.rx_first[1] = tlp_rx_first[1];
    assign dtlp.rx_first[2] = tlp_rx_first[2];
    assign dtlp.rx_first[3] = tlp_rx_first[3];
    assign dtlp.rx_last[0] = tlp_rx_last[0];
    assign dtlp.rx_last[1] = tlp_rx_last[1];
    assign dtlp.rx_last[2] = tlp_rx_last[2];
    assign dtlp.rx_last[3] = tlp_rx_last[3];
    assign dtlp.rx_valid[0] = tlp_rx_valid[0];
    assign dtlp.rx_valid[1] = tlp_rx_valid[1];
    assign dtlp.rx_valid[2] = tlp_rx_valid[2];
    assign dtlp.rx_valid[3] = tlp_rx_valid[3];

    assign dpcie.drp_rdy = drp_rdy;
    assign dpcie.drp_do = drp_do;

    assign dshadow2fifo.tx_valid = shadow_tx_valid;
    assign dshadow2fifo.tx_data = shadow_tx_data;
    assign dshadow2fifo.tx_addr = shadow_tx_addr;
    assign dshadow2fifo.tx_addr_lo = shadow_tx_addr_lo;

    always @(posedge clk) begin
        drp_rdy <= dpcie.drp_en;
        if (dpcie.drp_en) begin
            drp_do <= 16'h55aa;
            drp_request_seen <= 1'b1;
        end
        if (drp_rdy) begin
            drp_completion_seen <= 1'b1;
        end
    end

    asmcehnk_fifo #(
        .PARAM_DEVICE_ID          (8'h05),
        .PARAM_VERSION_NUMBER_MAJOR(8'h01),
        .PARAM_VERSION_NUMBER_MINOR(8'h05),
        .PARAM_CUSTOM_VALUE       (32'h12345678)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .tick_100mhz_ce(tick_100mhz_ce),
        .rst_cfg_reload(rst_cfg_reload),
        .pcie_present (1'b1),
        .pcie_perst_n (1'b1),
        .dcom         (dcom.mp_fifo),
        .dcfg         (dcfg.mp_fifo),
        .dtlp         (dtlp.mp_fifo),
        .dpcie        (dpcie.mp_fifo),
        .dshadow2fifo (dshadow2fifo.fifo)
    );

    always @(posedge clk) begin
        if (dcom.com_din_wr_en && dcom.com_din_ready) begin
            output_blocks[block_count] = dcom.com_din;
            block_count = block_count + 1;
        end

    end

    initial begin
        tlp_rx_data[0] = 32'd0;
        tlp_rx_data[1] = 32'd0;
        tlp_rx_data[2] = 32'd0;
        tlp_rx_data[3] = 32'd0;
        tlp_rx_first[0] = 1'b0;
        tlp_rx_first[1] = 1'b0;
        tlp_rx_first[2] = 1'b0;
        tlp_rx_first[3] = 1'b0;
        tlp_rx_last[0] = 1'b0;
        tlp_rx_last[1] = 1'b0;
        tlp_rx_last[2] = 1'b0;
        tlp_rx_last[3] = 1'b0;
        tlp_rx_valid[0] = 1'b0;
        tlp_rx_valid[1] = 1'b0;
        tlp_rx_valid[2] = 1'b0;
        tlp_rx_valid[3] = 1'b0;

        repeat (10) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (12) @(posedge clk);

        if (!drp_request_seen || !drp_completion_seen) begin
            $display("FIFO_DRP_COMPLETION_MODEL_FAIL request=%b completion=%b",
                     drp_request_seen, drp_completion_seen);
            errors = errors + 1;
        end

        if (dpcie.pcie_rst_core !== 1'b1 ||
            dpcie.pcie_rst_subsys !== 1'b0 ||
            dshadow2fifo.cfgtlp_en !== 1'b1 ||
            dshadow2fifo.cfgtlp_filter !== 1'b1 ||
            dshadow2fifo.bar_en !== 1'b1 ||
            dshadow2fifo.alltlp_filter !== 1'b1) begin
            $display("FIFO_DEFAULT_CONTROL_FAIL");
            errors = errors + 1;
        end

        @(negedge clk);
        com_dout = 64'h11223344_00000476;
        com_dout_valid = 1'b1;
        #1;
        if (dtlp.tx_valid || dcfg.tx_valid) begin
            $display("FIFO_BAD_MAGIC_ACCEPTED");
            errors = errors + 1;
        end
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;

        @(negedge clk);
        com_dout = 64'h11223344_00000477;
        com_dout_valid = 1'b1;
        #1;
        if (!dtlp.tx_valid || dtlp.tx_data !== 32'h11223344 ||
            !dtlp.tx_last || dcfg.tx_valid) begin
            $display("FIFO_TLP_CLASSIFICATION_FAIL data=%h last=%b",
                     dtlp.tx_data, dtlp.tx_last);
            errors = errors + 1;
        end
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;

        @(negedge clk);
        com_dout = 64'haabbccdd_00000177;
        com_dout_valid = 1'b1;
        #1;
        if (!dcfg.tx_valid || dcfg.tx_data !== 64'haabbccdd_00000177 ||
            dtlp.tx_valid) begin
            $display("FIFO_CFG_CLASSIFICATION_FAIL data=%h", dcfg.tx_data);
            errors = errors + 1;
        end
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;

        @(negedge clk);
        com_dout = 64'h01000100_80022377;
        com_dout_valid = 1'b1;
        #1;
        if (!dut._cmd_rx_wren || dtlp.tx_valid || dcfg.tx_valid) begin
            $display("FIFO_LEECHCORE_COMMAND_CLASSIFICATION_FAIL");
            errors = errors + 1;
        end
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;
        repeat (20) @(posedge clk);

        block_start = block_count;
        @(negedge clk);
        com_dout = 64'h89abcdef_00000e77;
        com_dout_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;
        timeout_count = 0;
        while (block_count == block_start && timeout_count < 120) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (block_count == block_start) begin
            $display("FIFO_LOOPBACK_TIMEOUT");
            errors = errors + 1;
        end else if (output_blocks[block_start][223:192] !== 32'h89abcdef ||
                     output_blocks[block_start][251:248] !== 4'he) begin
            $display("FIFO_LOOPBACK_MUX_FAIL data=%h context=%h",
                     output_blocks[block_start][223:192],
                     output_blocks[block_start][251:248]);
            errors = errors + 1;
        end

        @(negedge clk);
        rst = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (12) @(posedge clk);

        block_start = block_count;
        @(negedge clk);
        com_dout = 64'h00000000_00001377;
        com_dout_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;
        timeout_count = 0;
        while (block_count == block_start && timeout_count < 160) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (block_count == block_start) begin
            $display("FIFO_RO_COMMAND_TIMEOUT");
            errors = errors + 1;
        end else if (output_blocks[block_start][223:192] !== 32'h000089ab ||
                     output_blocks[block_start][249:248] !== 2'b11) begin
            $display("FIFO_RO_COMMAND_FAIL data=%h tag=%b",
                     output_blocks[block_start][223:192],
                     output_blocks[block_start][249:248]);
            errors = errors + 1;
        end

        @(negedge clk);
        com_dout = 64'h1122ffff_80002377;
        com_dout_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;
        repeat (20) @(posedge clk);

        block_start = block_count;
        @(negedge clk);
        com_dout = 64'h00000000_80001377;
        com_dout_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;
        timeout_count = 0;
        while (block_count == block_start && timeout_count < 160) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (block_count == block_start) begin
            $display("FIFO_RW_COMMAND_TIMEOUT");
            errors = errors + 1;
        end else if (output_blocks[block_start][223:192] !== 32'h80001122) begin
            $display("FIFO_RW_COMMAND_FAIL data=%h",
                     output_blocks[block_start][223:192]);
            errors = errors + 1;
        end

        @(negedge clk);
        com_dout = 64'h00000000_40001377;
        com_dout_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;
        timeout_count = 0;
        while (!dshadow2fifo.rx_rden && timeout_count < 80) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (!dshadow2fifo.rx_rden || dshadow2fifo.rx_addr !== 10'd0 ||
            dshadow2fifo.rx_addr_lo !== 1'b0) begin
            $display("FIFO_SHADOW_READ_REQUEST_FAIL valid=%b addr=%h lo=%b",
                     dshadow2fifo.rx_rden, dshadow2fifo.rx_addr,
                     dshadow2fifo.rx_addr_lo);
            errors = errors + 1;
        end

        block_start = block_count;
        @(negedge clk);
        shadow_tx_data = 32'hdeadbeef;
        shadow_tx_addr = 10'h155;
        shadow_tx_addr_lo = 1'b1;
        shadow_tx_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        shadow_tx_valid = 1'b0;
        timeout_count = 0;
        while (block_count == block_start && timeout_count < 120) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (block_count == block_start) begin
            $display("FIFO_SHADOW_RESPONSE_TIMEOUT");
            errors = errors + 1;
        end else if (output_blocks[block_start][223:192] !== 32'hc556beef ||
                     output_blocks[block_start][249:248] !== 2'b11) begin
            $display("FIFO_SHADOW_RESPONSE_FAIL data=%h tag=%b",
                     output_blocks[block_start][223:192],
                     output_blocks[block_start][249:248]);
            errors = errors + 1;
        end

        @(negedge clk);
        com_dout = 64'ha1b2ffff_c0062377;
        com_dout_valid = 1'b1;
        @(posedge clk);
        @(negedge clk);
        com_dout_valid = 1'b0;
        timeout_count = 0;
        while (!dshadow2fifo.rx_wren && timeout_count < 80) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (!dshadow2fifo.rx_wren || dshadow2fifo.rx_addr !== 10'd1 ||
            dshadow2fifo.rx_addr_lo !== 1'b1 ||
            dshadow2fifo.rx_be !== 4'b0011 ||
            dshadow2fifo.rx_data !== 32'ha1b2a1b2) begin
            $display("FIFO_SHADOW_WRITE_REQUEST_FAIL valid=%b addr=%h lo=%b be=%b data=%h",
                     dshadow2fifo.rx_wren, dshadow2fifo.rx_addr,
                     dshadow2fifo.rx_addr_lo, dshadow2fifo.rx_be,
                     dshadow2fifo.rx_data);
            errors = errors + 1;
        end

        @(negedge clk);
        rst = 1'b1;
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (12) @(posedge clk);

        block_start = block_count;
        @(negedge clk);
        cfg_rx_data = 32'h12345678;
        cfg_rx_valid = 1'b1;
        tlp_rx_data[0] = 32'hcafebabe;
        tlp_rx_first[0] = 1'b1;
        tlp_rx_last[0] = 1'b1;
        tlp_rx_valid[0] = 1'b1;
        @(posedge clk);
        @(negedge clk);
        cfg_rx_valid = 1'b0;
        tlp_rx_valid[0] = 1'b0;
        timeout_count = 0;
        while (block_count == block_start && timeout_count < 120) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;
        end
        if (block_count == block_start) begin
            $display("FIFO_MULTI_SOURCE_TIMEOUT");
            errors = errors + 1;
        end else if (output_blocks[block_start][223:192] !== 32'h12345678 ||
                     output_blocks[block_start][191:160] !== 32'hcafebabe ||
                     output_blocks[block_start][251:248] !== 4'h1 ||
                     output_blocks[block_start][255:252] !== 4'hc) begin
            $display("FIFO_MULTI_SOURCE_ORDER_FAIL status=%h data0=%h data1=%h",
                     output_blocks[block_start][255:224],
                     output_blocks[block_start][223:192],
                     output_blocks[block_start][191:160]);
            errors = errors + 1;
        end

        // AS02 runs this module in the 25G clock domain.  The external
        // 100 MHz enable must be the only source of logical timer ticks.
        @(negedge clk);
        tick_100mhz_ce = 1'b0;
        tick_before = dut.tickcount64;
        repeat (8) @(posedge clk);
        @(negedge clk);
        if (dut.tickcount64 !== tick_before || dut.cmd_rx_rd_en !== 1'b0) begin
            $display("FIFO_100MHZ_TICK_HOLD_FAIL before=%0d after=%0d rd_en=%b",
                     tick_before, dut.tickcount64, dut.cmd_rx_rd_en);
            errors = errors + 1;
        end

        tick_100mhz_ce = 1'b1;
        @(posedge clk);
        @(negedge clk);
        tick_100mhz_ce = 1'b0;
        if (dut.tickcount64 !== tick_before + 1) begin
            $display("FIFO_100MHZ_TICK_PULSE_FAIL before=%0d after=%0d",
                     tick_before, dut.tickcount64);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("ASMCEHNK_FIFO_COMPAT_TEST_PASS");
        end else begin
            $display("ASMCEHNK_FIFO_COMPAT_TEST_FAIL errors=%0d", errors);
        end
        $finish;
    end

endmodule
