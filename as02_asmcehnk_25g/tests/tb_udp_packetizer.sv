`timescale 1ns/1ps
module tb_udp_packetizer;
reg clk=0; always #1 clk=~clk;
reg rstn=0;
reg [255:0] data=0;
reg data_valid=0;
wire data_ready;
wire axis_valid;
reg axis_ready=1;
wire axis_last;
wire [255:0] axis_data;
wire [31:0] axis_keep;
wire [15:0] desc_length;
wire desc_valid;
reg desc_ready=1;
integer errors=0;
integer out_count=0;
integer last_count=0;
reg [15:0] last_desc=0;
asmcehnk_udp_tx_packetizer_256 #(.C_MAX_WORDS(32),.C_IDLE_CYCLES(16)) dut(
 .i_clk(clk),.i_rstn(rstn),.i_data(data),.i_data_valid(data_valid),.o_data_ready(data_ready),
 .o_axis_tvalid(axis_valid),.i_axis_tready(axis_ready),.o_axis_tlast(axis_last),.o_axis_tdata(axis_data),.o_axis_tkeep(axis_keep),
 .o_desc_length(desc_length),.o_desc_valid(desc_valid),.i_desc_ready(desc_ready));
always @(posedge clk) begin
 if(axis_valid && axis_ready) begin out_count=out_count+1; if(axis_keep!==32'hffffffff) errors=errors+1; if(axis_last) last_count=last_count+1; end
 if(desc_valid && desc_ready) last_desc=desc_length;
 if((axis_valid && axis_ready && axis_last) !== (desc_valid && desc_ready)) begin $display("ATOMIC_FAIL t=%0t",$time); errors=errors+1; end
end
initial begin
 repeat(4) @(posedge clk); rstn=1;
 // short one-word frame
 @(negedge clk); data=256'h11; data_valid=1; @(negedge clk); data_valid=0;
 repeat(20) @(posedge clk);
 if(out_count!=1 || last_count!=1 || last_desc!=16'd40) begin $display("SHORT_FAIL out=%0d last=%0d desc=%0d",out_count,last_count,last_desc); errors=errors+1; end
 // continuous maximum frame
 out_count=0; last_count=0; last_desc=0;
 repeat(32) begin @(negedge clk); data=data+1; data_valid=1; end
 @(negedge clk); data_valid=0;
 repeat(4) @(posedge clk);
 if(out_count!=32 || last_count!=1 || last_desc!=16'd1032) begin $display("MAX_FAIL out=%0d last=%0d desc=%0d",out_count,last_count,last_desc); errors=errors+1; end
 // tail stalls until both sinks can accept
 out_count=0; last_count=0; last_desc=0;
 @(negedge clk); data=256'h55; data_valid=1; @(negedge clk); data_valid=0;
 repeat(15) @(posedge clk); desc_ready=0;
 repeat(5) @(posedge clk);
 if(out_count!=0 || last_desc!=0) begin $display("DESC_STALL_FAIL"); errors=errors+1; end
 desc_ready=1; axis_ready=0; repeat(3) @(posedge clk);
 if(out_count!=0 || last_desc!=0) begin $display("PAYLOAD_STALL_FAIL"); errors=errors+1; end
 axis_ready=1; repeat(3) @(posedge clk);
 if(out_count!=1 || last_count!=1 || last_desc!=16'd40) begin $display("RELEASE_FAIL out=%0d last=%0d desc=%0d",out_count,last_count,last_desc); errors=errors+1; end
 // reset flush
 @(negedge clk); data_valid=1; @(negedge clk); data_valid=0; rstn=0; repeat(3) @(posedge clk); rstn=1; repeat(20) @(posedge clk);
 if(out_count!=1) begin $display("RESET_FLUSH_FAIL out=%0d",out_count); errors=errors+1; end
 if(errors==0) $display("UDP_PACKETIZER_TEST_PASS"); else $display("UDP_PACKETIZER_TEST_FAIL errors=%0d",errors);
 $finish;
end
endmodule
