`resetall
`timescale 1ns / 1ps
`default_nettype none
`include "asmcehnk_header.svh"

// UltraScale+ elastic staging for the reused AMDUSB4 raw-TLP source FIFO.
// The legacy source uses tready as a synchronous FIFO read request and emits
// the returned tvalid pulse one cycle later.  This queue reserves space for
// each in-flight read and presents a conventional stable AXIS contract to RQ.
module asmcehnk_tlps128_src_elastic_us (
    input  wire logic   rst,
    input  wire logic   clk,
    IfAXIS128.sink      tlps_legacy_in,
    IfAXIS128.source    tlps_out
);

    wire logic [133:0] input_word;
    wire logic         input_return_valid;
    wire logic         input_read_issue;
    wire logic         output_consume;
    wire logic [2:0]   stage_reserved_count;

    logic [133:0] stage_head_reg;
    logic [133:0] stage_tail_reg;
    logic [1:0]   stage_count_reg;
    logic [1:0]   read_pending_count_reg;

    assign input_word = {
        tlps_legacy_in.tuser[0],
        tlps_legacy_in.tlast,
        tlps_legacy_in.tkeepdw,
        tlps_legacy_in.tdata
    };
    assign input_return_valid = tlps_legacy_in.tvalid && !rst;
    assign output_consume = tlps_out.tvalid && tlps_out.tready;
    assign stage_reserved_count = {1'b0, stage_count_reg} +
                                  {1'b0, read_pending_count_reg};

    // tready is a read-credit grant at this legacy boundary.  A slot is
    // reserved until the synchronous FIFO return pulse is captured.
    assign tlps_legacy_in.tready = !rst &&
                                  ((stage_reserved_count < 3'd2) ||
                                   ((stage_reserved_count == 3'd2) &&
                                    output_consume));
    assign input_read_issue = tlps_legacy_in.tready &&
                              tlps_legacy_in.has_data;

    assign tlps_out.tdata = stage_head_reg[127:0];
    assign tlps_out.tkeepdw = stage_head_reg[131:128];
    assign tlps_out.tvalid = !rst && (stage_count_reg != 0);
    assign tlps_out.tlast = stage_head_reg[132];
    assign tlps_out.tuser = {8'd0, stage_head_reg[133]};
    assign tlps_out.has_data = !rst &&
                               ((stage_count_reg != 0) ||
                                (read_pending_count_reg != 0) ||
                                tlps_legacy_in.has_data);

    always_ff @(posedge clk) begin
        if (rst) begin
            read_pending_count_reg <= 2'd0;
        end else begin
            case ({input_read_issue, input_return_valid})
                2'b10: read_pending_count_reg <= read_pending_count_reg + 1'b1;
                2'b01: read_pending_count_reg <= read_pending_count_reg - 1'b1;
                default: read_pending_count_reg <= read_pending_count_reg;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            stage_head_reg <= 134'd0;
            stage_tail_reg <= 134'd0;
            stage_count_reg <= 2'd0;
        end else begin
            case ({input_return_valid, output_consume})
                2'b10: begin
                    if (stage_count_reg == 0) begin
                        stage_head_reg <= input_word;
                    end else begin
                        stage_tail_reg <= input_word;
                    end
                    stage_count_reg <= stage_count_reg + 1'b1;
                end
                2'b01: begin
                    stage_head_reg <= stage_tail_reg;
                    stage_count_reg <= stage_count_reg - 1'b1;
                end
                2'b11: begin
                    if (stage_count_reg == 1) begin
                        stage_head_reg <= input_word;
                    end else begin
                        stage_head_reg <= stage_tail_reg;
                        stage_tail_reg <= input_word;
                    end
                    stage_count_reg <= stage_count_reg;
                end
                default: begin
                    stage_head_reg <= stage_head_reg;
                    stage_tail_reg <= stage_tail_reg;
                    stage_count_reg <= stage_count_reg;
                end
            endcase
        end
    end

endmodule

`resetall
