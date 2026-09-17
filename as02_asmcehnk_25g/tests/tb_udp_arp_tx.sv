`timescale 1ns/1ps
module tb_udp_arp_tx;
reg clk=0;always #1.241 clk=~clk;reg rst=1;
taxi_axis_if #(.DATA_W(64),.KEEP_EN(1),.KEEP_W(8),.USER_EN(1),.USER_W(1)) rx_if();
taxi_axis_if #(.DATA_W(64),.KEEP_EN(1),.KEEP_W(8),.USER_EN(1),.USER_W(1)) tx_if();
wire [63:0] com_rx_data;wire com_rx_valid;reg [255:0] com_tx_data=0;reg com_tx_valid=0;wire com_tx_ready;
reg [7:0] in_mem[0:1][0:59];integer in_len[0:1];reg [7:0] out_mem[0:3][0:127];integer out_len[0:3];
integer fi,bi,lane,beat_bytes,out_frames=0,out_pos=0,errors=0,k,m;
asmcehnk_eth_axis_udp_25g dut(.clk(clk),.rst(rst),.s_axis_rx(rx_if),.m_axis_tx(tx_if),.com_rx_data(com_rx_data),.com_rx_valid(com_rx_valid),.com_tx_data(com_tx_data),.com_tx_valid(com_tx_valid),.com_tx_ready(com_tx_ready));
always @(posedge clk) if(tx_if.tvalid&&tx_if.tready) begin
 for(m=0;m<8;m=m+1) if(tx_if.tkeep[m]) begin out_mem[out_frames][out_pos]=tx_if.tdata[m*8 +: 8];out_pos=out_pos+1;end
 if(tx_if.tlast) begin out_len[out_frames]=out_pos;out_frames=out_frames+1;out_pos=0;end
end
initial begin
 rx_if.tdata=0;rx_if.tkeep=0;rx_if.tstrb=0;rx_if.tid=0;rx_if.tdest=0;rx_if.tuser=0;rx_if.tlast=0;rx_if.tvalid=0;tx_if.tready=1;
        in_mem[0][0]=8'hff;
        in_mem[0][1]=8'hff;
        in_mem[0][2]=8'hff;
        in_mem[0][3]=8'hff;
        in_mem[0][4]=8'hff;
        in_mem[0][5]=8'hff;
        in_mem[0][6]=8'h02;
        in_mem[0][7]=8'h11;
        in_mem[0][8]=8'h22;
        in_mem[0][9]=8'h33;
        in_mem[0][10]=8'h44;
        in_mem[0][11]=8'h55;
        in_mem[0][12]=8'h08;
        in_mem[0][13]=8'h06;
        in_mem[0][14]=8'h00;
        in_mem[0][15]=8'h01;
        in_mem[0][16]=8'h08;
        in_mem[0][17]=8'h00;
        in_mem[0][18]=8'h06;
        in_mem[0][19]=8'h04;
        in_mem[0][20]=8'h00;
        in_mem[0][21]=8'h01;
        in_mem[0][22]=8'h02;
        in_mem[0][23]=8'h11;
        in_mem[0][24]=8'h22;
        in_mem[0][25]=8'h33;
        in_mem[0][26]=8'h44;
        in_mem[0][27]=8'h55;
        in_mem[0][28]=8'hc0;
        in_mem[0][29]=8'ha8;
        in_mem[0][30]=8'h00;
        in_mem[0][31]=8'h0a;
        in_mem[0][32]=8'h00;
        in_mem[0][33]=8'h00;
        in_mem[0][34]=8'h00;
        in_mem[0][35]=8'h00;
        in_mem[0][36]=8'h00;
        in_mem[0][37]=8'h00;
        in_mem[0][38]=8'hc0;
        in_mem[0][39]=8'ha8;
        in_mem[0][40]=8'h00;
        in_mem[0][41]=8'hde;
        in_mem[0][42]=8'h00;
        in_mem[0][43]=8'h00;
        in_mem[0][44]=8'h00;
        in_mem[0][45]=8'h00;
        in_mem[0][46]=8'h00;
        in_mem[0][47]=8'h00;
        in_mem[0][48]=8'h00;
        in_mem[0][49]=8'h00;
        in_mem[0][50]=8'h00;
        in_mem[0][51]=8'h00;
        in_mem[0][52]=8'h00;
        in_mem[0][53]=8'h00;
        in_mem[0][54]=8'h00;
        in_mem[0][55]=8'h00;
        in_mem[0][56]=8'h00;
        in_mem[0][57]=8'h00;
        in_mem[0][58]=8'h00;
        in_mem[0][59]=8'h00;
        in_mem[1][0]=8'h02;
        in_mem[1][1]=8'h00;
        in_mem[1][2]=8'h00;
        in_mem[1][3]=8'h00;
        in_mem[1][4]=8'h00;
        in_mem[1][5]=8'hde;
        in_mem[1][6]=8'h02;
        in_mem[1][7]=8'h11;
        in_mem[1][8]=8'h22;
        in_mem[1][9]=8'h33;
        in_mem[1][10]=8'h44;
        in_mem[1][11]=8'h55;
        in_mem[1][12]=8'h08;
        in_mem[1][13]=8'h00;
        in_mem[1][14]=8'h45;
        in_mem[1][15]=8'h00;
        in_mem[1][16]=8'h00;
        in_mem[1][17]=8'h2c;
        in_mem[1][18]=8'h12;
        in_mem[1][19]=8'h34;
        in_mem[1][20]=8'h00;
        in_mem[1][21]=8'h00;
        in_mem[1][22]=8'h40;
        in_mem[1][23]=8'h11;
        in_mem[1][24]=8'he6;
        in_mem[1][25]=8'h54;
        in_mem[1][26]=8'hc0;
        in_mem[1][27]=8'ha8;
        in_mem[1][28]=8'h00;
        in_mem[1][29]=8'h0a;
        in_mem[1][30]=8'hc0;
        in_mem[1][31]=8'ha8;
        in_mem[1][32]=8'h00;
        in_mem[1][33]=8'hde;
        in_mem[1][34]=8'h30;
        in_mem[1][35]=8'h39;
        in_mem[1][36]=8'h6f;
        in_mem[1][37]=8'h3a;
        in_mem[1][38]=8'h00;
        in_mem[1][39]=8'h18;
        in_mem[1][40]=8'h00;
        in_mem[1][41]=8'h00;
        in_mem[1][42]=8'h00;
        in_mem[1][43]=8'h01;
        in_mem[1][44]=8'h02;
        in_mem[1][45]=8'h03;
        in_mem[1][46]=8'h04;
        in_mem[1][47]=8'h05;
        in_mem[1][48]=8'h06;
        in_mem[1][49]=8'h07;
        in_mem[1][50]=8'h08;
        in_mem[1][51]=8'h09;
        in_mem[1][52]=8'h0a;
        in_mem[1][53]=8'h0b;
        in_mem[1][54]=8'h0c;
        in_mem[1][55]=8'h0d;
        in_mem[1][56]=8'h0e;
        in_mem[1][57]=8'h0f;
        in_mem[1][58]=8'h00;
        in_mem[1][59]=8'h00;
        in_len[0]=60;
        in_len[1]=60;

 repeat(10)@(posedge clk);rst=0;repeat(10)@(posedge clk);
 for(fi=0;fi<2;fi=fi+1) begin
  bi=0;while(bi<in_len[fi]) begin
   @(negedge clk);rx_if.tdata=0;rx_if.tkeep=0;rx_if.tstrb=0;beat_bytes=(in_len[fi]-bi>8)?8:(in_len[fi]-bi);
   for(lane=0;lane<beat_bytes;lane=lane+1)begin rx_if.tdata[lane*8 +: 8]=in_mem[fi][bi+lane];rx_if.tkeep[lane]=1;rx_if.tstrb[lane]=1;end
   rx_if.tlast=(bi+beat_bytes>=in_len[fi]);rx_if.tvalid=1;@(posedge clk);while(!rx_if.tready)@(posedge clk);bi=bi+beat_bytes;
  end
  @(negedge clk);rx_if.tvalid=0;rx_if.tlast=0;rx_if.tkeep=0;repeat(100)@(posedge clk);
 end
 if(out_frames<1)begin $display("ARP_REPLY_MISSING");errors=errors+1;end else begin
  if(out_mem[0][0]!==8'h02||out_mem[0][1]!==8'h11||out_mem[0][12]!==8'h08||out_mem[0][13]!==8'h06||out_mem[0][20]!==8'h00||out_mem[0][21]!==8'h02)begin $display("ARP_REPLY_BAD");errors=errors+1;end
 end
 while(!com_tx_ready)@(posedge clk);@(negedge clk);com_tx_data=256'h1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100;com_tx_valid=1;
 @(posedge clk);while(!com_tx_ready)@(posedge clk);@(negedge clk);com_tx_valid=0;
 while(out_frames<2)@(posedge clk);
 in_mem[0][0]=8'h02;in_mem[0][1]=8'h00;in_mem[0][2]=8'h00;in_mem[0][3]=8'h00;in_mem[0][4]=8'h00;in_mem[0][5]=8'hde;
 in_mem[0][20]=8'h00;in_mem[0][21]=8'h02;
 in_mem[0][32]=8'h02;in_mem[0][33]=8'h00;in_mem[0][34]=8'h00;in_mem[0][35]=8'h00;in_mem[0][36]=8'h00;in_mem[0][37]=8'hde;
 bi=0;
 while(bi<in_len[0]) begin
  @(negedge clk);rx_if.tdata=0;rx_if.tkeep=0;rx_if.tstrb=0;beat_bytes=(in_len[0]-bi>8)?8:(in_len[0]-bi);
  for(lane=0;lane<beat_bytes;lane=lane+1)begin rx_if.tdata[lane*8 +: 8]=in_mem[0][bi+lane];rx_if.tkeep[lane]=1;rx_if.tstrb[lane]=1;end
  rx_if.tlast=(bi+beat_bytes>=in_len[0]);rx_if.tvalid=1;@(posedge clk);while(!rx_if.tready)@(posedge clk);bi=bi+beat_bytes;
 end
 @(negedge clk);rx_if.tvalid=0;rx_if.tlast=0;rx_if.tkeep=0;
 repeat(1200)@(posedge clk);
 for(k=0;k<out_frames;k=k+1)$display("TX_FRAME index=%0d len=%0d type=%h%h",k,out_len[k],out_mem[k][12],out_mem[k][13]);
 if(out_frames<3)begin $display("UDP_REPLY_MISSING frames=%0d",out_frames);errors=errors+1;end else begin
  if(out_mem[2][12]!==8'h08||out_mem[2][13]!==8'h00||out_mem[2][26]!==8'hc0||out_mem[2][29]!==8'hde||out_mem[2][30]!==8'hc0||out_mem[2][33]!==8'h0a)begin $display("UDP_IP_BAD");errors=errors+1;end
  if(out_mem[2][34]!==8'h6f||out_mem[2][35]!==8'h3a||out_mem[2][36]!==8'h30||out_mem[2][37]!==8'h39||out_mem[2][38]!==8'h00||out_mem[2][39]!==8'h28)begin $display("UDP_HEADER_BAD");errors=errors+1;end
  for(k=0;k<32;k=k+1)if(out_mem[2][42+k]!==(8'd31-k))begin $display("LEECHCORE_TX_ORDER_BAD k=%0d got=%h",k,out_mem[2][42+k]);errors=errors+1;end
 end
 if(errors==0)$display("UDP_ARP_TX_TEST_PASS");else $display("UDP_ARP_TX_TEST_FAIL errors=%0d",errors);$finish;
end
endmodule
