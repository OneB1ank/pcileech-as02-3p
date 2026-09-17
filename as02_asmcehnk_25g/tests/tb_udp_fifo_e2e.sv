`timescale 1ns / 1ps
`include "asmcehnk_header.svh"

module e2e_sim_sync_fifo #(
    parameter WIDTH = 34,
    parameter DEPTH = 16
) (
    input  wire             clk,
    input  wire             srst,
    input  wire             rd_en,
    output reg  [WIDTH-1:0] dout,
    input  wire [WIDTH-1:0] din,
    input  wire             wr_en,
    output wire             full,
    output wire             almost_full,
    output wire             empty,
    output reg              valid
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
    input  wire        clk,
    input  wire        srst,
    input  wire        rd_en,
    output wire [33:0] dout,
    input  wire [33:0] din,
    input  wire        wr_en,
    output wire        full,
    output wire        almost_full,
    output wire        empty,
    output wire        valid
);

    e2e_sim_sync_fifo #(
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
    input  wire        clk,
    input  wire        srst,
    input  wire        rd_en,
    output wire [63:0] dout,
    input  wire [63:0] din,
    input  wire        wr_en,
    output wire        full,
    output wire        empty,
    output wire        valid
);

    wire almost_full_unused;

    e2e_sim_sync_fifo #(
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

module tb_udp_fifo_e2e;

    localparam integer FRAME_BYTES = 60;
    localparam integer MAX_OUT_FRAMES = 8;
    localparam integer MAX_OUT_BYTES = 128;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg rst_cfg_reload = 1'b0;
    reg [7:0] frame_mem [0:3][0:FRAME_BYTES-1];
    reg [7:0] out_mem [0:MAX_OUT_FRAMES-1][0:MAX_OUT_BYTES-1];
    integer out_len [0:MAX_OUT_FRAMES-1];
    integer out_frames = 0;
    integer out_pos = 0;
    integer fifo_blocks = 0;
    integer errors = 0;
    integer timeout_count;
    integer frame_count_before;
    integer block_count_before;
    integer output_lane;

    reg drp_rdy = 1'b0;
    reg [15:0] drp_do = 16'd0;

    taxi_axis_if #(
        .DATA_W (64),
        .KEEP_EN(1),
        .KEEP_W (8),
        .USER_EN(1),
        .USER_W (1)
    ) rx_if();

    taxi_axis_if #(
        .DATA_W (64),
        .KEEP_EN(1),
        .KEEP_W (8),
        .USER_EN(1),
        .USER_W (1)
    ) tx_if();

    IfComToFifo dcom();
    IfPCIeFifoCfg dcfg();
    IfPCIeFifoTlp dtlp();
    IfPCIeFifoCore dpcie();
    IfShadow2Fifo dshadow2fifo();

    always #1.241 clk = ~clk;

    assign dcfg.rx_data = 32'd0;
    assign dcfg.rx_valid = 1'b0;

    assign dtlp.rx_data[0] = 32'd0;
    assign dtlp.rx_data[1] = 32'd0;
    assign dtlp.rx_data[2] = 32'd0;
    assign dtlp.rx_data[3] = 32'd0;
    assign dtlp.rx_first[0] = 1'b0;
    assign dtlp.rx_first[1] = 1'b0;
    assign dtlp.rx_first[2] = 1'b0;
    assign dtlp.rx_first[3] = 1'b0;
    assign dtlp.rx_last[0] = 1'b0;
    assign dtlp.rx_last[1] = 1'b0;
    assign dtlp.rx_last[2] = 1'b0;
    assign dtlp.rx_last[3] = 1'b0;
    assign dtlp.rx_valid[0] = 1'b0;
    assign dtlp.rx_valid[1] = 1'b0;
    assign dtlp.rx_valid[2] = 1'b0;
    assign dtlp.rx_valid[3] = 1'b0;

    assign dpcie.drp_rdy = drp_rdy;
    assign dpcie.drp_do = drp_do;

    assign dshadow2fifo.tx_valid = 1'b0;
    assign dshadow2fifo.tx_data = 32'd0;
    assign dshadow2fifo.tx_addr = 10'd0;
    assign dshadow2fifo.tx_addr_lo = 1'b0;

    always @(posedge clk) begin
        drp_rdy <= dpcie.drp_en;
        if (dpcie.drp_en) begin
            drp_do <= 16'h55aa;
        end
    end

    always @(posedge clk) begin
        if (dcom.com_din_wr_en && dcom.com_din_ready) begin
            fifo_blocks = fifo_blocks + 1;
        end

        if (tx_if.tvalid && tx_if.tready) begin
            for (output_lane = 0; output_lane < 8; output_lane = output_lane + 1) begin
                if (tx_if.tkeep[output_lane]) begin
                    out_mem[out_frames][out_pos] =
                        tx_if.tdata[output_lane * 8 +: 8];
                    out_pos = out_pos + 1;
                end
            end

            if (tx_if.tlast) begin
                out_len[out_frames] = out_pos;
                out_frames = out_frames + 1;
                out_pos = 0;
            end
        end
    end

    asmcehnk_com_axis_udp_25g com_inst (
        .clk              (clk),
        .rst              (rst),
        .led_state_txdata (),
        .led_state_invert (1'b0),
        .dfifo            (dcom.mp_com),
        .s_axis_rx        (rx_if),
        .m_axis_tx        (tx_if)
    );

    asmcehnk_fifo #(
        .PARAM_DEVICE_ID           (8'h05),
        .PARAM_VERSION_NUMBER_MAJOR(8'h01),
        .PARAM_VERSION_NUMBER_MINOR(8'h05),
        .PARAM_CUSTOM_VALUE        (32'h12345678)
    ) fifo_inst (
        .clk            (clk),
        .tick_100mhz_ce (1'b1),
        .rst            (rst),
        .rst_cfg_reload (rst_cfg_reload),
        .pcie_present   (1'b1),
        .pcie_perst_n   (1'b1),
        .dcom           (dcom.mp_fifo),
        .dcfg           (dcfg.mp_fifo),
        .dtlp           (dtlp.mp_fifo),
        .dpcie          (dpcie.mp_fifo),
        .dshadow2fifo   (dshadow2fifo.fifo)
    );

    task automatic clear_frame;
        input integer slot;
        integer index;
        begin
            for (index = 0; index < FRAME_BYTES; index = index + 1) begin
                frame_mem[slot][index] = 8'd0;
            end
        end
    endtask

    task automatic build_udp_frame;
        input integer slot;
        input [15:0] destination_port;
        input [63:0] payload_word;
        begin
            clear_frame(slot);
            frame_mem[slot][0] = 8'h02;
            frame_mem[slot][1] = 8'h00;
            frame_mem[slot][2] = 8'h00;
            frame_mem[slot][3] = 8'h00;
            frame_mem[slot][4] = 8'h00;
            frame_mem[slot][5] = 8'hde;
            frame_mem[slot][6] = 8'h02;
            frame_mem[slot][7] = 8'h11;
            frame_mem[slot][8] = 8'h22;
            frame_mem[slot][9] = 8'h33;
            frame_mem[slot][10] = 8'h44;
            frame_mem[slot][11] = 8'h55;
            frame_mem[slot][12] = 8'h08;
            frame_mem[slot][13] = 8'h00;
            frame_mem[slot][14] = 8'h45;
            frame_mem[slot][16] = 8'h00;
            frame_mem[slot][17] = 8'h24;
            frame_mem[slot][18] = 8'h12;
            frame_mem[slot][19] = 8'h34;
            frame_mem[slot][22] = 8'h40;
            frame_mem[slot][23] = 8'h11;
            frame_mem[slot][24] = 8'he6;
            frame_mem[slot][25] = 8'h5c;
            frame_mem[slot][26] = 8'hc0;
            frame_mem[slot][27] = 8'ha8;
            frame_mem[slot][28] = 8'h00;
            frame_mem[slot][29] = 8'h0a;
            frame_mem[slot][30] = 8'hc0;
            frame_mem[slot][31] = 8'ha8;
            frame_mem[slot][32] = 8'h00;
            frame_mem[slot][33] = 8'hde;
            frame_mem[slot][34] = 8'h30;
            frame_mem[slot][35] = 8'h39;
            frame_mem[slot][36] = destination_port[15:8];
            frame_mem[slot][37] = destination_port[7:0];
            frame_mem[slot][38] = 8'h00;
            frame_mem[slot][39] = 8'h10;
            frame_mem[slot][42] = payload_word[63:56];
            frame_mem[slot][43] = payload_word[55:48];
            frame_mem[slot][44] = payload_word[47:40];
            frame_mem[slot][45] = payload_word[39:32];
            frame_mem[slot][46] = payload_word[31:24];
            frame_mem[slot][47] = payload_word[23:16];
            frame_mem[slot][48] = payload_word[15:8];
            frame_mem[slot][49] = payload_word[7:0];
        end
    endtask

    task automatic build_arp_frame;
        input integer slot;
        input [15:0] operation;
        begin
            clear_frame(slot);
            if (operation == 16'h0001) begin
                frame_mem[slot][0] = 8'hff;
                frame_mem[slot][1] = 8'hff;
                frame_mem[slot][2] = 8'hff;
                frame_mem[slot][3] = 8'hff;
                frame_mem[slot][4] = 8'hff;
                frame_mem[slot][5] = 8'hff;
            end else begin
                frame_mem[slot][0] = 8'h02;
                frame_mem[slot][1] = 8'h00;
                frame_mem[slot][2] = 8'h00;
                frame_mem[slot][3] = 8'h00;
                frame_mem[slot][4] = 8'h00;
                frame_mem[slot][5] = 8'hde;
            end
            frame_mem[slot][6] = 8'h02;
            frame_mem[slot][7] = 8'h11;
            frame_mem[slot][8] = 8'h22;
            frame_mem[slot][9] = 8'h33;
            frame_mem[slot][10] = 8'h44;
            frame_mem[slot][11] = 8'h55;
            frame_mem[slot][12] = 8'h08;
            frame_mem[slot][13] = 8'h06;
            frame_mem[slot][14] = 8'h00;
            frame_mem[slot][15] = 8'h01;
            frame_mem[slot][16] = 8'h08;
            frame_mem[slot][17] = 8'h00;
            frame_mem[slot][18] = 8'h06;
            frame_mem[slot][19] = 8'h04;
            frame_mem[slot][20] = operation[15:8];
            frame_mem[slot][21] = operation[7:0];
            frame_mem[slot][22] = 8'h02;
            frame_mem[slot][23] = 8'h11;
            frame_mem[slot][24] = 8'h22;
            frame_mem[slot][25] = 8'h33;
            frame_mem[slot][26] = 8'h44;
            frame_mem[slot][27] = 8'h55;
            frame_mem[slot][28] = 8'hc0;
            frame_mem[slot][29] = 8'ha8;
            frame_mem[slot][30] = 8'h00;
            frame_mem[slot][31] = 8'h0a;
            if (operation == 16'h0002) begin
                frame_mem[slot][32] = 8'h02;
                frame_mem[slot][33] = 8'h00;
                frame_mem[slot][34] = 8'h00;
                frame_mem[slot][35] = 8'h00;
                frame_mem[slot][36] = 8'h00;
                frame_mem[slot][37] = 8'hde;
            end
            frame_mem[slot][38] = 8'hc0;
            frame_mem[slot][39] = 8'ha8;
            frame_mem[slot][40] = 8'h00;
            frame_mem[slot][41] = 8'hde;
        end
    endtask

    task automatic send_frame;
        input integer slot;
        integer send_index;
        integer beat_bytes;
        integer send_lane;
        begin
            send_index = 0;
            while (send_index < FRAME_BYTES) begin
                @(negedge clk);
                rx_if.tdata = 64'd0;
                rx_if.tkeep = 8'd0;
                rx_if.tstrb = 8'd0;
                beat_bytes = FRAME_BYTES - send_index;
                if (beat_bytes > 8) begin
                    beat_bytes = 8;
                end
                for (send_lane = 0; send_lane < beat_bytes;
                     send_lane = send_lane + 1) begin
                    rx_if.tdata[send_lane * 8 +: 8] =
                        frame_mem[slot][send_index + send_lane];
                    rx_if.tkeep[send_lane] = 1'b1;
                    rx_if.tstrb[send_lane] = 1'b1;
                end
                rx_if.tlast = send_index + beat_bytes >= FRAME_BYTES;
                rx_if.tvalid = 1'b1;
                @(posedge clk);
                while (!rx_if.tready) begin
                    @(posedge clk);
                end
                send_index = send_index + beat_bytes;
            end
            @(negedge clk);
            rx_if.tdata = 64'd0;
            rx_if.tkeep = 8'd0;
            rx_if.tstrb = 8'd0;
            rx_if.tlast = 1'b0;
            rx_if.tvalid = 1'b0;
        end
    endtask

    task automatic wait_for_frame_count;
        input integer expected_count;
        input integer timeout_limit;
        begin
            timeout_count = 0;
            while (out_frames < expected_count &&
                   timeout_count < timeout_limit) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (out_frames < expected_count) begin
                $display("E2E_FRAME_TIMEOUT expected=%0d actual=%0d",
                         expected_count, out_frames);
                errors = errors + 1;
            end
        end
    endtask

    task automatic verify_stalled_tx;
        input integer stall_cycles;
        reg [63:0] held_data;
        reg [7:0] held_keep;
        reg held_last;
        integer stall_index;
        begin
            timeout_count = 0;
            while (!tx_if.tvalid && timeout_count < 2000) begin
                @(posedge clk);
                timeout_count = timeout_count + 1;
            end
            if (!tx_if.tvalid) begin
                $display("E2E_TX_STALL_VALID_TIMEOUT");
                errors = errors + 1;
            end else begin
                held_data = tx_if.tdata;
                held_keep = tx_if.tkeep;
                held_last = tx_if.tlast;
                for (stall_index = 0; stall_index < stall_cycles;
                     stall_index = stall_index + 1) begin
                    @(posedge clk);
                    if (!tx_if.tvalid || tx_if.tdata !== held_data ||
                        tx_if.tkeep !== held_keep || tx_if.tlast !== held_last) begin
                        $display("E2E_TX_BACKPRESSURE_FAIL cycle=%0d",
                                 stall_index);
                        errors = errors + 1;
                    end
                end
            end
            @(negedge clk);
            tx_if.tready = 1'b1;
        end
    endtask

    initial begin
        rx_if.tdata = 64'd0;
        rx_if.tkeep = 8'd0;
        rx_if.tstrb = 8'd0;
        rx_if.tid = 8'd0;
        rx_if.tdest = 8'd0;
        rx_if.tuser = 1'b0;
        rx_if.tlast = 1'b0;
        rx_if.tvalid = 1'b0;
        tx_if.tready = 1'b1;

        build_udp_frame(0, 16'h6f3b, 64'h89abcdef_00000e77);
        build_arp_frame(1, 16'h0001);
        build_udp_frame(2, 16'h6f3a, 64'h89abcdef_00000e77);
        build_arp_frame(3, 16'h0002);

        repeat (12) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        repeat (40) @(posedge clk);

        frame_count_before = out_frames;
        block_count_before = fifo_blocks;
        send_frame(0);
        repeat (300) @(posedge clk);
        if (out_frames != frame_count_before ||
            fifo_blocks != block_count_before) begin
            $display("E2E_WRONG_PORT_RESPONSE frames=%0d blocks=%0d",
                     out_frames - frame_count_before,
                     fifo_blocks - block_count_before);
            errors = errors + 1;
        end

        send_frame(1);
        wait_for_frame_count(1, 1000);
        if (out_frames >= 1) begin
            if (out_mem[0][0] !== 8'h02 || out_mem[0][1] !== 8'h11 ||
                out_mem[0][12] !== 8'h08 || out_mem[0][13] !== 8'h06 ||
                out_mem[0][20] !== 8'h00 || out_mem[0][21] !== 8'h02) begin
                $display("E2E_ARP_REPLY_BAD");
                errors = errors + 1;
            end
        end

        @(negedge clk);
        tx_if.tready = 1'b0;
        block_count_before = fifo_blocks;
        send_frame(2);
        verify_stalled_tx(12);
        wait_for_frame_count(2, 2000);
        if (fifo_blocks <= block_count_before) begin
            $display("E2E_FIFO_LOOPBACK_RESPONSE_MISSING");
            errors = errors + 1;
        end
        if (out_frames >= 2) begin
            if (out_mem[1][12] !== 8'h08 || out_mem[1][13] !== 8'h06 ||
                out_mem[1][20] !== 8'h00 || out_mem[1][21] !== 8'h01 ||
                out_mem[1][38] !== 8'hc0 || out_mem[1][39] !== 8'ha8 ||
                out_mem[1][40] !== 8'h00 || out_mem[1][41] !== 8'h0a) begin
                $display("E2E_ARP_REQUEST_BAD");
                errors = errors + 1;
            end
        end

        @(negedge clk);
        tx_if.tready = 1'b0;
        send_frame(3);
        verify_stalled_tx(12);
        wait_for_frame_count(3, 3000);

        if (out_frames >= 3) begin
            if (out_len[2] !== 74 ||
                out_mem[2][0] !== 8'h02 || out_mem[2][1] !== 8'h11 ||
                out_mem[2][12] !== 8'h08 || out_mem[2][13] !== 8'h00 ||
                out_mem[2][26] !== 8'hc0 || out_mem[2][27] !== 8'ha8 ||
                out_mem[2][28] !== 8'h00 || out_mem[2][29] !== 8'hde ||
                out_mem[2][30] !== 8'hc0 || out_mem[2][31] !== 8'ha8 ||
                out_mem[2][32] !== 8'h00 || out_mem[2][33] !== 8'h0a ||
                out_mem[2][34] !== 8'h6f || out_mem[2][35] !== 8'h3a ||
                out_mem[2][36] !== 8'h30 || out_mem[2][37] !== 8'h39 ||
                out_mem[2][38] !== 8'h00 || out_mem[2][39] !== 8'h28) begin
                $display("E2E_UDP_REPLY_HEADER_BAD len=%0d", out_len[2]);
                errors = errors + 1;
            end

            if (out_mem[2][42] !== 8'hfe ||
                out_mem[2][43] !== 8'hff ||
                out_mem[2][44] !== 8'hff ||
                out_mem[2][45] !== 8'hef ||
                out_mem[2][46] !== 8'h89 ||
                out_mem[2][47] !== 8'hab ||
                out_mem[2][48] !== 8'hcd ||
                out_mem[2][49] !== 8'hef) begin
                $display("E2E_UDP_LOOPBACK_PAYLOAD_BAD status=%h%h%h%h data=%h%h%h%h",
                         out_mem[2][42], out_mem[2][43], out_mem[2][44],
                         out_mem[2][45], out_mem[2][46], out_mem[2][47],
                         out_mem[2][48], out_mem[2][49]);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("UDP_FIFO_E2E_TEST_PASS");
        end else begin
            $display("UDP_FIFO_E2E_TEST_FAIL errors=%0d", errors);
        end
        $finish;
    end

endmodule
