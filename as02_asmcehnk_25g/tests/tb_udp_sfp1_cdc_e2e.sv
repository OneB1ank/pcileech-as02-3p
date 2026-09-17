`timescale 1ns/1ps
module tb_udp_sfp1_cdc_e2e;
reg rx_clk=0; always #1.307 rx_clk=~rx_clk;
reg net_clk=0; always #1.241 net_clk=~net_clk;
reg rx_rst=1;
reg net_rst=1;
taxi_axis_if #(.DATA_W(64),.KEEP_EN(1),.KEEP_W(8),.USER_EN(1),.USER_W(1)) sfp1_rx_if();
taxi_axis_if #(.DATA_W(64),.KEEP_EN(1),.KEEP_W(8),.USER_EN(1),.USER_W(1)) rx_if();
taxi_axis_if #(.DATA_W(64),.KEEP_EN(1),.KEEP_W(8),.USER_EN(1),.USER_W(1)) tx_if();
wire [63:0] com_rx_data; wire com_rx_valid;
reg [255:0] com_tx_data=0; reg com_tx_valid=0; wire com_tx_ready;
reg [7:0] frame_mem [0:5][0:59]; integer frame_len [0:5];
integer fi,bi,lane,beat_bytes,rx_count=0,errors=0,before_count;
integer good_frame_count=0;
reg [63:0] rx_words [0:15];
wire rx_cdc_good_frame;
wire rx_cdc_overflow;
wire rx_cdc_bad_frame;

taxi_axis_async_fifo #(
 .DEPTH(32768),.RAM_PIPELINE(2),.FRAME_FIFO(1),
 .USER_BAD_FRAME_VALUE(1'b1),.USER_BAD_FRAME_MASK(1'b1),
 .DROP_OVERSIZE_FRAME(1),.DROP_BAD_FRAME(1),.DROP_WHEN_FULL(1)
) sfp1_rx_cdc_inst (
 .s_clk(rx_clk),.s_rst(rx_rst),.s_axis(sfp1_rx_if),
 .m_clk(net_clk),.m_rst(net_rst),.m_axis(rx_if),
 .s_pause_req(1'b0),.s_pause_ack(),.m_pause_req(1'b0),.m_pause_ack(),
 .s_status_depth(),.s_status_depth_commit(),.s_status_overflow(),
 .s_status_bad_frame(),.s_status_good_frame(),.m_status_depth(),
 .m_status_depth_commit(),.m_status_overflow(rx_cdc_overflow),
 .m_status_bad_frame(rx_cdc_bad_frame),.m_status_good_frame(rx_cdc_good_frame)
);

asmcehnk_eth_axis_udp_25g dut(.clk(net_clk),.rst(net_rst),.s_axis_rx(rx_if),.m_axis_tx(tx_if),.com_rx_data(com_rx_data),.com_rx_valid(com_rx_valid),.com_tx_data(com_tx_data),.com_tx_valid(com_tx_valid),.com_tx_ready(com_tx_ready));
always @(posedge net_clk) begin
 if(com_rx_valid) begin rx_words[rx_count]=com_rx_data; rx_count=rx_count+1; end
 if(rx_cdc_good_frame) good_frame_count=good_frame_count+1;
end
initial begin
 sfp1_rx_if.tdata=0;sfp1_rx_if.tkeep=0;sfp1_rx_if.tstrb=0;sfp1_rx_if.tid=0;sfp1_rx_if.tdest=0;sfp1_rx_if.tuser=0;sfp1_rx_if.tlast=0;sfp1_rx_if.tvalid=0;tx_if.tready=1;
        frame_mem[0][0] = 8'h02;
        frame_mem[0][1] = 8'h00;
        frame_mem[0][2] = 8'h00;
        frame_mem[0][3] = 8'h00;
        frame_mem[0][4] = 8'h00;
        frame_mem[0][5] = 8'hde;
        frame_mem[0][6] = 8'h02;
        frame_mem[0][7] = 8'h11;
        frame_mem[0][8] = 8'h22;
        frame_mem[0][9] = 8'h33;
        frame_mem[0][10] = 8'h44;
        frame_mem[0][11] = 8'h55;
        frame_mem[0][12] = 8'h08;
        frame_mem[0][13] = 8'h00;
        frame_mem[0][14] = 8'h45;
        frame_mem[0][15] = 8'h00;
        frame_mem[0][16] = 8'h00;
        frame_mem[0][17] = 8'h2c;
        frame_mem[0][18] = 8'h12;
        frame_mem[0][19] = 8'h34;
        frame_mem[0][20] = 8'h00;
        frame_mem[0][21] = 8'h00;
        frame_mem[0][22] = 8'h40;
        frame_mem[0][23] = 8'h11;
        frame_mem[0][24] = 8'he6;
        frame_mem[0][25] = 8'h54;
        frame_mem[0][26] = 8'hc0;
        frame_mem[0][27] = 8'ha8;
        frame_mem[0][28] = 8'h00;
        frame_mem[0][29] = 8'h0a;
        frame_mem[0][30] = 8'hc0;
        frame_mem[0][31] = 8'ha8;
        frame_mem[0][32] = 8'h00;
        frame_mem[0][33] = 8'hde;
        frame_mem[0][34] = 8'h30;
        frame_mem[0][35] = 8'h39;
        frame_mem[0][36] = 8'h6f;
        frame_mem[0][37] = 8'h3a;
        frame_mem[0][38] = 8'h00;
        frame_mem[0][39] = 8'h18;
        frame_mem[0][40] = 8'h00;
        frame_mem[0][41] = 8'h00;
        frame_mem[0][42] = 8'h01;
        frame_mem[0][43] = 8'h00;
        frame_mem[0][44] = 8'h01;
        frame_mem[0][45] = 8'h00;
        frame_mem[0][46] = 8'h80;
        frame_mem[0][47] = 8'h02;
        frame_mem[0][48] = 8'h23;
        frame_mem[0][49] = 8'h77;
        frame_mem[0][50] = 8'h00;
        frame_mem[0][51] = 8'h00;
        frame_mem[0][52] = 8'h00;
        frame_mem[0][53] = 8'h00;
        frame_mem[0][54] = 8'h01;
        frame_mem[0][55] = 8'h00;
        frame_mem[0][56] = 8'h03;
        frame_mem[0][57] = 8'h77;
        frame_mem[0][58] = 8'h00;
        frame_mem[0][59] = 8'h00;
        frame_mem[1][0] = 8'h02;
        frame_mem[1][1] = 8'h00;
        frame_mem[1][2] = 8'h00;
        frame_mem[1][3] = 8'h00;
        frame_mem[1][4] = 8'h00;
        frame_mem[1][5] = 8'hde;
        frame_mem[1][6] = 8'h02;
        frame_mem[1][7] = 8'h11;
        frame_mem[1][8] = 8'h22;
        frame_mem[1][9] = 8'h33;
        frame_mem[1][10] = 8'h44;
        frame_mem[1][11] = 8'h55;
        frame_mem[1][12] = 8'h08;
        frame_mem[1][13] = 8'h00;
        frame_mem[1][14] = 8'h45;
        frame_mem[1][15] = 8'h00;
        frame_mem[1][16] = 8'h00;
        frame_mem[1][17] = 8'h2c;
        frame_mem[1][18] = 8'h12;
        frame_mem[1][19] = 8'h34;
        frame_mem[1][20] = 8'h00;
        frame_mem[1][21] = 8'h00;
        frame_mem[1][22] = 8'h40;
        frame_mem[1][23] = 8'h11;
        frame_mem[1][24] = 8'he6;
        frame_mem[1][25] = 8'h54;
        frame_mem[1][26] = 8'hc0;
        frame_mem[1][27] = 8'ha8;
        frame_mem[1][28] = 8'h00;
        frame_mem[1][29] = 8'h0a;
        frame_mem[1][30] = 8'hc0;
        frame_mem[1][31] = 8'ha8;
        frame_mem[1][32] = 8'h00;
        frame_mem[1][33] = 8'hde;
        frame_mem[1][34] = 8'h30;
        frame_mem[1][35] = 8'h39;
        frame_mem[1][36] = 8'h6f;
        frame_mem[1][37] = 8'h3b;
        frame_mem[1][38] = 8'h00;
        frame_mem[1][39] = 8'h18;
        frame_mem[1][40] = 8'h00;
        frame_mem[1][41] = 8'h00;
        frame_mem[1][42] = 8'h00;
        frame_mem[1][43] = 8'h01;
        frame_mem[1][44] = 8'h02;
        frame_mem[1][45] = 8'h03;
        frame_mem[1][46] = 8'h04;
        frame_mem[1][47] = 8'h05;
        frame_mem[1][48] = 8'h06;
        frame_mem[1][49] = 8'h07;
        frame_mem[1][50] = 8'h08;
        frame_mem[1][51] = 8'h09;
        frame_mem[1][52] = 8'h0a;
        frame_mem[1][53] = 8'h0b;
        frame_mem[1][54] = 8'h0c;
        frame_mem[1][55] = 8'h0d;
        frame_mem[1][56] = 8'h0e;
        frame_mem[1][57] = 8'h0f;
        frame_mem[1][58] = 8'h00;
        frame_mem[1][59] = 8'h00;
        frame_mem[2][0] = 8'h02;
        frame_mem[2][1] = 8'h00;
        frame_mem[2][2] = 8'h00;
        frame_mem[2][3] = 8'h00;
        frame_mem[2][4] = 8'h00;
        frame_mem[2][5] = 8'hde;
        frame_mem[2][6] = 8'h02;
        frame_mem[2][7] = 8'h11;
        frame_mem[2][8] = 8'h22;
        frame_mem[2][9] = 8'h33;
        frame_mem[2][10] = 8'h44;
        frame_mem[2][11] = 8'h55;
        frame_mem[2][12] = 8'h08;
        frame_mem[2][13] = 8'h00;
        frame_mem[2][14] = 8'h45;
        frame_mem[2][15] = 8'h00;
        frame_mem[2][16] = 8'h00;
        frame_mem[2][17] = 8'h2c;
        frame_mem[2][18] = 8'h12;
        frame_mem[2][19] = 8'h34;
        frame_mem[2][20] = 8'h20;
        frame_mem[2][21] = 8'h00;
        frame_mem[2][22] = 8'h40;
        frame_mem[2][23] = 8'h11;
        frame_mem[2][24] = 8'hc6;
        frame_mem[2][25] = 8'h54;
        frame_mem[2][26] = 8'hc0;
        frame_mem[2][27] = 8'ha8;
        frame_mem[2][28] = 8'h00;
        frame_mem[2][29] = 8'h0a;
        frame_mem[2][30] = 8'hc0;
        frame_mem[2][31] = 8'ha8;
        frame_mem[2][32] = 8'h00;
        frame_mem[2][33] = 8'hde;
        frame_mem[2][34] = 8'h30;
        frame_mem[2][35] = 8'h39;
        frame_mem[2][36] = 8'h6f;
        frame_mem[2][37] = 8'h3a;
        frame_mem[2][38] = 8'h00;
        frame_mem[2][39] = 8'h18;
        frame_mem[2][40] = 8'h00;
        frame_mem[2][41] = 8'h00;
        frame_mem[2][42] = 8'h00;
        frame_mem[2][43] = 8'h01;
        frame_mem[2][44] = 8'h02;
        frame_mem[2][45] = 8'h03;
        frame_mem[2][46] = 8'h04;
        frame_mem[2][47] = 8'h05;
        frame_mem[2][48] = 8'h06;
        frame_mem[2][49] = 8'h07;
        frame_mem[2][50] = 8'h08;
        frame_mem[2][51] = 8'h09;
        frame_mem[2][52] = 8'h0a;
        frame_mem[2][53] = 8'h0b;
        frame_mem[2][54] = 8'h0c;
        frame_mem[2][55] = 8'h0d;
        frame_mem[2][56] = 8'h0e;
        frame_mem[2][57] = 8'h0f;
        frame_mem[2][58] = 8'h00;
        frame_mem[2][59] = 8'h00;
        frame_mem[3][0] = 8'h02;
        frame_mem[3][1] = 8'h00;
        frame_mem[3][2] = 8'h00;
        frame_mem[3][3] = 8'h00;
        frame_mem[3][4] = 8'h00;
        frame_mem[3][5] = 8'hde;
        frame_mem[3][6] = 8'h02;
        frame_mem[3][7] = 8'h11;
        frame_mem[3][8] = 8'h22;
        frame_mem[3][9] = 8'h33;
        frame_mem[3][10] = 8'h44;
        frame_mem[3][11] = 8'h55;
        frame_mem[3][12] = 8'h08;
        frame_mem[3][13] = 8'h00;
        frame_mem[3][14] = 8'h45;
        frame_mem[3][15] = 8'h00;
        frame_mem[3][16] = 8'h00;
        frame_mem[3][17] = 8'h28;
        frame_mem[3][18] = 8'h12;
        frame_mem[3][19] = 8'h34;
        frame_mem[3][20] = 8'h00;
        frame_mem[3][21] = 8'h00;
        frame_mem[3][22] = 8'h40;
        frame_mem[3][23] = 8'h11;
        frame_mem[3][24] = 8'he6;
        frame_mem[3][25] = 8'h58;
        frame_mem[3][26] = 8'hc0;
        frame_mem[3][27] = 8'ha8;
        frame_mem[3][28] = 8'h00;
        frame_mem[3][29] = 8'h0a;
        frame_mem[3][30] = 8'hc0;
        frame_mem[3][31] = 8'ha8;
        frame_mem[3][32] = 8'h00;
        frame_mem[3][33] = 8'hde;
        frame_mem[3][34] = 8'h30;
        frame_mem[3][35] = 8'h39;
        frame_mem[3][36] = 8'h6f;
        frame_mem[3][37] = 8'h3a;
        frame_mem[3][38] = 8'h00;
        frame_mem[3][39] = 8'h14;
        frame_mem[3][40] = 8'h00;
        frame_mem[3][41] = 8'h00;
        frame_mem[3][42] = 8'h00;
        frame_mem[3][43] = 8'h01;
        frame_mem[3][44] = 8'h02;
        frame_mem[3][45] = 8'h03;
        frame_mem[3][46] = 8'h04;
        frame_mem[3][47] = 8'h05;
        frame_mem[3][48] = 8'h06;
        frame_mem[3][49] = 8'h07;
        frame_mem[3][50] = 8'h08;
        frame_mem[3][51] = 8'h09;
        frame_mem[3][52] = 8'h0a;
        frame_mem[3][53] = 8'h0b;
        frame_mem[3][54] = 8'h00;
        frame_mem[3][55] = 8'h00;
        frame_mem[3][56] = 8'h00;
        frame_mem[3][57] = 8'h00;
        frame_mem[3][58] = 8'h00;
        frame_mem[3][59] = 8'h00;
        frame_mem[4][0] = 8'h02;
        frame_mem[4][1] = 8'h00;
        frame_mem[4][2] = 8'h00;
        frame_mem[4][3] = 8'h00;
        frame_mem[4][4] = 8'h00;
        frame_mem[4][5] = 8'hde;
        frame_mem[4][6] = 8'h02;
        frame_mem[4][7] = 8'h11;
        frame_mem[4][8] = 8'h22;
        frame_mem[4][9] = 8'h33;
        frame_mem[4][10] = 8'h44;
        frame_mem[4][11] = 8'h55;
        frame_mem[4][12] = 8'h08;
        frame_mem[4][13] = 8'h00;
        frame_mem[4][14] = 8'h45;
        frame_mem[4][15] = 8'h00;
        frame_mem[4][16] = 8'h00;
        frame_mem[4][17] = 8'h2c;
        frame_mem[4][18] = 8'h12;
        frame_mem[4][19] = 8'h34;
        frame_mem[4][20] = 8'h00;
        frame_mem[4][21] = 8'h00;
        frame_mem[4][22] = 8'h40;
        frame_mem[4][23] = 8'h11;
        frame_mem[4][24] = 8'he7;
        frame_mem[4][25] = 8'h54;
        frame_mem[4][26] = 8'hc0;
        frame_mem[4][27] = 8'ha8;
        frame_mem[4][28] = 8'h00;
        frame_mem[4][29] = 8'h0a;
        frame_mem[4][30] = 8'hc0;
        frame_mem[4][31] = 8'ha8;
        frame_mem[4][32] = 8'h00;
        frame_mem[4][33] = 8'hde;
        frame_mem[4][34] = 8'h30;
        frame_mem[4][35] = 8'h39;
        frame_mem[4][36] = 8'h6f;
        frame_mem[4][37] = 8'h3a;
        frame_mem[4][38] = 8'h00;
        frame_mem[4][39] = 8'h18;
        frame_mem[4][40] = 8'h00;
        frame_mem[4][41] = 8'h00;
        frame_mem[4][42] = 8'h00;
        frame_mem[4][43] = 8'h01;
        frame_mem[4][44] = 8'h02;
        frame_mem[4][45] = 8'h03;
        frame_mem[4][46] = 8'h04;
        frame_mem[4][47] = 8'h05;
        frame_mem[4][48] = 8'h06;
        frame_mem[4][49] = 8'h07;
        frame_mem[4][50] = 8'h08;
        frame_mem[4][51] = 8'h09;
        frame_mem[4][52] = 8'h0a;
        frame_mem[4][53] = 8'h0b;
        frame_mem[4][54] = 8'h0c;
        frame_mem[4][55] = 8'h0d;
        frame_mem[4][56] = 8'h0e;
        frame_mem[4][57] = 8'h0f;
        frame_mem[4][58] = 8'h00;
        frame_mem[4][59] = 8'h00;
        frame_mem[5][0] = 8'h02;
        frame_mem[5][1] = 8'h00;
        frame_mem[5][2] = 8'h00;
        frame_mem[5][3] = 8'h00;
        frame_mem[5][4] = 8'h00;
        frame_mem[5][5] = 8'hde;
        frame_mem[5][6] = 8'h02;
        frame_mem[5][7] = 8'h11;
        frame_mem[5][8] = 8'h22;
        frame_mem[5][9] = 8'h33;
        frame_mem[5][10] = 8'h44;
        frame_mem[5][11] = 8'h55;
        frame_mem[5][12] = 8'h08;
        frame_mem[5][13] = 8'h00;
        frame_mem[5][14] = 8'h45;
        frame_mem[5][15] = 8'h00;
        frame_mem[5][16] = 8'h00;
        frame_mem[5][17] = 8'h2c;
        frame_mem[5][18] = 8'h12;
        frame_mem[5][19] = 8'h34;
        frame_mem[5][20] = 8'h00;
        frame_mem[5][21] = 8'h00;
        frame_mem[5][22] = 8'h40;
        frame_mem[5][23] = 8'h11;
        frame_mem[5][24] = 8'he6;
        frame_mem[5][25] = 8'h54;
        frame_mem[5][26] = 8'hc0;
        frame_mem[5][27] = 8'ha8;
        frame_mem[5][28] = 8'h00;
        frame_mem[5][29] = 8'h0a;
        frame_mem[5][30] = 8'hc0;
        frame_mem[5][31] = 8'ha8;
        frame_mem[5][32] = 8'h00;
        frame_mem[5][33] = 8'hde;
        frame_mem[5][34] = 8'h30;
        frame_mem[5][35] = 8'h39;
        frame_mem[5][36] = 8'h6f;
        frame_mem[5][37] = 8'h3a;
        frame_mem[5][38] = 8'h00;
        frame_mem[5][39] = 8'h18;
        frame_mem[5][40] = 8'h00;
        frame_mem[5][41] = 8'h00;
        frame_mem[5][42] = 8'h01;
        frame_mem[5][43] = 8'h00;
        frame_mem[5][44] = 8'h01;
        frame_mem[5][45] = 8'h00;
        frame_mem[5][46] = 8'h80;
        frame_mem[5][47] = 8'h02;
        frame_mem[5][48] = 8'h23;
        frame_mem[5][49] = 8'h77;
        frame_mem[5][50] = 8'h00;
        frame_mem[5][51] = 8'h00;
        frame_mem[5][52] = 8'h00;
        frame_mem[5][53] = 8'h00;
        frame_mem[5][54] = 8'h01;
        frame_mem[5][55] = 8'h00;
        frame_mem[5][56] = 8'h03;
        frame_mem[5][57] = 8'h77;
        frame_mem[5][58] = 8'h00;
        frame_mem[5][59] = 8'h00;
        frame_len[0] = 60;
        frame_len[1] = 60;
        frame_len[2] = 60;
        frame_len[3] = 60;
        frame_len[4] = 60;
        frame_len[5] = 60;

 repeat(12) @(posedge rx_clk);
 @(negedge rx_clk);rx_rst=0;
 repeat(12) @(posedge net_clk);
 @(negedge net_clk);net_rst=0;
 repeat(24) @(posedge net_clk);

 // Source-side reset drops an uncommitted partial Ethernet frame.
 before_count=rx_count;bi=0;
 repeat(3) begin
  @(negedge rx_clk);sfp1_rx_if.tdata=0;sfp1_rx_if.tkeep=8'hff;sfp1_rx_if.tstrb=8'hff;
  for(lane=0;lane<8;lane=lane+1) sfp1_rx_if.tdata[lane*8 +: 8]=frame_mem[0][bi+lane];
  sfp1_rx_if.tlast=0;sfp1_rx_if.tvalid=1;@(posedge rx_clk);while(!sfp1_rx_if.tready) @(posedge rx_clk);bi=bi+8;
 end
 @(negedge rx_clk);sfp1_rx_if.tvalid=0;sfp1_rx_if.tkeep=0;sfp1_rx_if.tlast=0;rx_rst=1;
 repeat(6) @(posedge rx_clk);@(negedge rx_clk);rx_rst=0;repeat(30) @(posedge net_clk);
 if(rx_count!=before_count) begin $display("SFP1_SOURCE_RESET_STALE_FAIL delta=%0d",rx_count-before_count);errors=errors+1;end

 // Network-side reset propagates through the real Taxi FIFO and also flushes
 // a partial source frame instead of releasing stale UDP data afterward.
 bi=0;
 repeat(3) begin
  @(negedge rx_clk);sfp1_rx_if.tdata=0;sfp1_rx_if.tkeep=8'hff;sfp1_rx_if.tstrb=8'hff;
  for(lane=0;lane<8;lane=lane+1) sfp1_rx_if.tdata[lane*8 +: 8]=frame_mem[0][bi+lane];
  sfp1_rx_if.tlast=0;sfp1_rx_if.tvalid=1;@(posedge rx_clk);while(!sfp1_rx_if.tready) @(posedge rx_clk);bi=bi+8;
 end
 @(negedge rx_clk);sfp1_rx_if.tvalid=0;sfp1_rx_if.tkeep=0;sfp1_rx_if.tlast=0;
 @(negedge net_clk);net_rst=1;repeat(7) @(posedge net_clk);@(negedge net_clk);net_rst=0;
 repeat(30) @(posedge net_clk);
 if(rx_count!=before_count) begin $display("SFP1_NET_RESET_STALE_FAIL delta=%0d",rx_count-before_count);errors=errors+1;end

 // Simultaneous source/network reset is the board-level recovery path.
 @(negedge rx_clk);rx_rst=1;
 @(negedge net_clk);net_rst=1;
 repeat(6) @(posedge rx_clk);@(negedge rx_clk);rx_rst=0;
 repeat(6) @(posedge net_clk);@(negedge net_clk);net_rst=0;
 repeat(24) @(posedge net_clk);

 for(fi=0;fi<6;fi=fi+1) begin
  before_count=rx_count;bi=0;
  while(bi<frame_len[fi]) begin
   @(negedge rx_clk);sfp1_rx_if.tdata=0;sfp1_rx_if.tkeep=0;sfp1_rx_if.tstrb=0;beat_bytes=(frame_len[fi]-bi>8)?8:(frame_len[fi]-bi);
   for(lane=0;lane<beat_bytes;lane=lane+1) begin sfp1_rx_if.tdata[lane*8 +: 8]=frame_mem[fi][bi+lane];sfp1_rx_if.tkeep[lane]=1;sfp1_rx_if.tstrb[lane]=1;end
   sfp1_rx_if.tlast=(bi+beat_bytes>=frame_len[fi]);sfp1_rx_if.tvalid=1;@(posedge rx_clk);while(!sfp1_rx_if.tready) @(posedge rx_clk);bi=bi+beat_bytes;
  end
  @(negedge rx_clk);sfp1_rx_if.tvalid=0;sfp1_rx_if.tlast=0;sfp1_rx_if.tkeep=0;repeat(80) @(posedge net_clk);
  if(fi==0||fi==5) begin
   if(rx_count-before_count!=2) begin $display("SFP1_VALID_COUNT_FAIL frame=%0d delta=%0d",fi,rx_count-before_count);errors=errors+1;end
   if(rx_words[before_count]!==64'h0100010080022377||rx_words[before_count+1]!==64'h0000000001000377) begin $display("SFP1_LEECHCORE_WIRE_DATA_FAIL frame=%0d w0=%h w1=%h",fi,rx_words[before_count],rx_words[before_count+1]);errors=errors+1;end
  end else if(rx_count!=before_count) begin $display("SFP1_FILTER_FAIL frame=%0d delta=%0d",fi,rx_count-before_count);errors=errors+1;end
 end
 if(good_frame_count<6||rx_cdc_overflow||rx_cdc_bad_frame) begin $display("SFP1_CDC_STATUS_FAIL good=%0d overflow=%b bad=%b",good_frame_count,rx_cdc_overflow,rx_cdc_bad_frame);errors=errors+1;end
 if(errors==0)$display("UDP_SFP1_CDC_E2E_TEST_PASS");else $display("UDP_SFP1_CDC_E2E_TEST_FAIL errors=%0d",errors);$finish;
end
endmodule
