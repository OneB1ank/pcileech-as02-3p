`resetall
`timescale 1ns / 1ps
`default_nettype none
`include "asmcehnk_header.svh"

// UltraScale+ read-side staging for the reused AMDUSB4 raw-TLP destination FIFO.
// The two-word elastic queue removes the FIFO BRAM output from the 402.8 MHz
// asmcehnk_mux input path while preserving its one-cycle request/return contract.
module asmcehnk_tlps128_dst_fifo_us (
    input  wire logic          rst_pcie,
    input  wire logic          rst_sys,
    input  wire logic          clk_pcie,
    input  wire logic          clk_sys,
    IfAXIS128.sink_lite        tlps_in,
    IfPCIeFifoTlp.mp_pcie      dfifo
);

    wire logic [133:0] fifo_dout;
    wire logic         fifo_empty;
    wire logic         fifo_valid;
    wire logic         fifo_read_complete;
    wire logic         fifo_read_issue;
    wire logic         stage_consume;
    wire logic         stage_output_valid;
    wire logic [2:0]   stage_reserved_count;

    logic [133:0] stage_head_reg = 134'd0;
    logic [133:0] stage_tail_reg = 134'd0;
    logic [1:0]   stage_count_reg = 2'd0;
    logic [1:0]   read_pending_count_reg = 2'd0;
    logic         request_delay_reg = 1'b0;

    assign stage_reserved_count = {1'b0, stage_count_reg} +
                                  {1'b0, read_pending_count_reg};
    assign stage_consume = !rst_sys && request_delay_reg &&
                           (stage_count_reg != 0);
    assign stage_output_valid = !rst_sys && request_delay_reg &&
                                (stage_count_reg != 0);
    assign fifo_read_complete = fifo_valid && (read_pending_count_reg != 0);

    // A same-cycle consume reserves its released slot for the next FIFO read.
    assign fifo_read_issue = !rst_sys && !fifo_empty &&
                             ((stage_reserved_count < 3'd2) ||
                              ((stage_reserved_count == 3'd2) && stage_consume));

    fifo_134_134_clk2 tlp_cdc_fifo_inst (
        .rst    (rst_pcie),
        .wr_clk (clk_pcie),
        .rd_clk (clk_sys),
        .din    ({tlps_in.tuser[0], tlps_in.tlast, tlps_in.tkeepdw, tlps_in.tdata}),
        .wr_en  (tlps_in.tvalid),
        .rd_en  (fifo_read_issue),
        .dout   (fifo_dout),
        .full   (),
        .empty  (fifo_empty),
        .valid  (fifo_valid)
    );

    always_ff @(posedge clk_sys) begin
        if (rst_sys) begin
            request_delay_reg <= 1'b0;
        end else begin
            request_delay_reg <= dfifo.rx_rd_en;
        end
    end

    always_ff @(posedge clk_sys) begin
        if (rst_sys) begin
            read_pending_count_reg <= 2'd0;
        end else begin
            case ({fifo_read_issue, fifo_read_complete})
                2'b10: read_pending_count_reg <= read_pending_count_reg + 1'b1;
                2'b01: read_pending_count_reg <= read_pending_count_reg - 1'b1;
                default: read_pending_count_reg <= read_pending_count_reg;
            endcase
        end
    end

    always_ff @(posedge clk_sys) begin
        if (rst_sys) begin
            stage_count_reg <= 2'd0;
            stage_head_reg <= 134'd0;
            stage_tail_reg <= 134'd0;
        end else begin
            case ({fifo_valid, stage_consume})
                2'b10: begin
                    if (stage_count_reg == 0) begin
                        stage_head_reg <= fifo_dout;
                    end else begin
                        stage_tail_reg <= fifo_dout;
                    end
                    stage_count_reg <= stage_count_reg + 1'b1;
                end
                2'b01: begin
                    stage_head_reg <= stage_tail_reg;
                    stage_count_reg <= stage_count_reg - 1'b1;
                end
                2'b11: begin
                    if (stage_count_reg == 1) begin
                        stage_head_reg <= fifo_dout;
                    end else begin
                        stage_head_reg <= stage_tail_reg;
                        stage_tail_reg <= fifo_dout;
                    end
                    stage_count_reg <= stage_count_reg;
                end
                default: begin
                    stage_count_reg <= stage_count_reg;
                    stage_head_reg <= stage_head_reg;
                    stage_tail_reg <= stage_tail_reg;
                end
            endcase
        end
    end

    assign dfifo.rx_data[0] = stage_head_reg[31:0];
    assign dfifo.rx_data[1] = stage_head_reg[63:32];
    assign dfifo.rx_data[2] = stage_head_reg[95:64];
    assign dfifo.rx_data[3] = stage_head_reg[127:96];
    assign dfifo.rx_first[0] = stage_head_reg[133];
    assign dfifo.rx_first[1] = 1'b0;
    assign dfifo.rx_first[2] = 1'b0;
    assign dfifo.rx_first[3] = 1'b0;
    assign dfifo.rx_last[0] = stage_head_reg[132] && (stage_head_reg[131:128] == 4'b0001);
    assign dfifo.rx_last[1] = stage_head_reg[132] && (stage_head_reg[131:128] == 4'b0011);
    assign dfifo.rx_last[2] = stage_head_reg[132] && (stage_head_reg[131:128] == 4'b0111);
    assign dfifo.rx_last[3] = stage_head_reg[132] && (stage_head_reg[131:128] == 4'b1111);
    assign dfifo.rx_valid[0] = stage_output_valid && stage_head_reg[128];
    assign dfifo.rx_valid[1] = stage_output_valid && stage_head_reg[129];
    assign dfifo.rx_valid[2] = stage_output_valid && stage_head_reg[130];
    assign dfifo.rx_valid[3] = stage_output_valid && stage_head_reg[131];

endmodule

`resetall
