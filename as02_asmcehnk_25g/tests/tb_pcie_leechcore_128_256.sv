`timescale 1ns / 1ps
`include "asmcehnk_header.svh"

module tb_pcie_leechcore_128_256;

	logic clk = 1'b0;
	logic rst = 1'b1;
	integer errors = 0;

	logic [255:0] cq_data = '0;
	logic [7:0] cq_keep = '0;
	logic cq_valid = 1'b0;
	logic cq_last = 1'b0;
	logic [87:0] cq_user = '0;
	logic cq_raw_ready = 1'b0;

	logic [127:0] rq_raw_data = '0;
	logic [3:0] rq_raw_keep = '0;
	logic rq_raw_valid = 1'b0;
	logic rq_raw_last = 1'b0;
	logic [8:0] rq_raw_user = '0;
	logic rq_ready = 1'b0;

	logic [255:0] rc_data = '0;
	logic [7:0] rc_keep = '0;
	logic rc_valid = 1'b0;
	logic rc_last = 1'b0;
	logic [74:0] rc_user = '0;
	logic rc_raw_ready = 1'b0;

	logic [127:0] cc_raw_data = '0;
	logic [3:0] cc_raw_keep = '0;
	logic cc_raw_valid = 1'b0;
	logic cc_raw_last = 1'b0;
	logic [8:0] cc_raw_user = '0;
	logic cc_ready = 1'b0;

	taxi_axis_if #(
		.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(88)
	) cq_axis();
	taxi_axis_if #(
		.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(62)
	) rq_axis();
	taxi_axis_if #(
		.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(75)
	) rc_axis();
	taxi_axis_if #(
		.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(33)
	) cc_axis();
	taxi_axis_if #(
		.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(33)
	) cq_error_axis();

	IfAXIS128 cq_raw();
	IfAXIS128 rq_raw();
	IfAXIS128 rc_raw();
	IfAXIS128 cc_raw();

	always #2 clk = ~clk;

	assign cq_axis.tdata = cq_data;
	assign cq_axis.tkeep = cq_keep;
	assign cq_axis.tstrb = cq_keep;
	assign cq_axis.tvalid = cq_valid;
	assign cq_axis.tlast = cq_last;
	assign cq_axis.tuser = cq_user;
	assign cq_axis.tid = '0;
	assign cq_axis.tdest = '0;
	assign cq_raw.tready = cq_raw_ready;
	assign cq_error_axis.tready = 1'b1;

	assign rq_raw.tdata = rq_raw_data;
	assign rq_raw.tkeepdw = rq_raw_keep;
	assign rq_raw.tvalid = rq_raw_valid;
	assign rq_raw.tlast = rq_raw_last;
	assign rq_raw.tuser = rq_raw_user;
	assign rq_raw.has_data = rq_raw_valid;
	assign rq_axis.tready = rq_ready;

	assign rc_axis.tdata = rc_data;
	assign rc_axis.tkeep = rc_keep;
	assign rc_axis.tstrb = rc_keep;
	assign rc_axis.tvalid = rc_valid;
	assign rc_axis.tlast = rc_last;
	assign rc_axis.tuser = rc_user;
	assign rc_axis.tid = '0;
	assign rc_axis.tdest = '0;
	assign rc_raw.tready = rc_raw_ready;

	assign cc_raw.tdata = cc_raw_data;
	assign cc_raw.tkeepdw = cc_raw_keep;
	assign cc_raw.tvalid = cc_raw_valid;
	assign cc_raw.tlast = cc_raw_last;
	assign cc_raw.tuser = cc_raw_user;
	assign cc_raw.has_data = cc_raw_valid;
	assign cc_axis.tready = cc_ready;

	asmcehnk_pcie_us_cq_to_tlps128 cq_dut (
		.clk       (clk),
		.rst       (rst),
		.pcie_id   (16'h5678),
		.s_axis_cq (cq_axis),
		.tlps_out  (cq_raw.source),
		.m_axis_cc_error (cq_error_axis)
	);

	asmcehnk_tlps128_to_axis_rq_us #(
		.RQ_SEQ_NUM_W(6)
	) rq_dut (
		.clk                  (clk),
		.rst                  (rst),
		.tlps_in              (rq_raw.sink),
		.m_axis_rq            (rq_axis),
		.pcie_rq_seq_num0     (6'd0),
		.pcie_rq_seq_num_vld0 (1'b0),
		.pcie_rq_seq_num1     (6'd0),
		.pcie_rq_seq_num_vld1 (1'b0),
		.rc_tag_release       (8'd0),
		.rc_tag_release_valid (1'b0),
		.status_outstanding   (),
		.status_blocked       (),
		.status_error         (),
		.status_tag_blocked   (),
		.status_tag_error     ()
	);

	asmcehnk_pcie_us_rc_to_tlps128 rc_dut (
		.clk               (clk),
		.rst               (rst),
		.s_axis_rc         (rc_axis),
		.tlps_out          (rc_raw.source),
		.tag_release       (),
		.tag_release_valid ()
	);

	asmcehnk_tlps128_to_axis_cc_us cc_dut (
		.clk       (clk),
		.rst       (rst),
		.tlps_in   (cc_raw.sink),
		.m_axis_cc (cc_axis)
	);

	initial begin
		repeat (5) @(posedge clk);
		@(negedge clk);
		rst = 1'b0;

		// CQ MRd32 -> AMDUSB4 raw 128-bit TLP.
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_226a_f000;
		cq_data[74:64] = 11'd2;
		cq_data[78:75] = 4'b0000;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'h5a;
		cq_data[114:112] = 3'd0;
		cq_keep = 8'h0f;
		cq_user = '0;
		cq_user[7:0] = 8'hff;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		while (!cq_axis.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		while (!cq_raw.tvalid) @(posedge clk);
		#1;
		if (cq_raw.tdata[31:0] != 32'h00000002 ||
			cq_raw.tdata[63:32] != 32'h12345aff ||
			cq_raw.tdata[95:64] != 32'h89abc000 ||
			cq_raw.tkeepdw != 4'b0111 || !cq_raw.tlast ||
			cq_raw.tuser != 9'h007) begin
			errors = errors + 1;
		end
		repeat (2) begin
			@(posedge clk);
			#1;
			if (!cq_raw.tvalid || cq_raw.tdata[95:64] != 32'h89abc000) begin
				errors = errors + 1;
			end
		end
		@(negedge clk);
		cq_raw_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		cq_raw_ready = 1'b0;

		// CQ MWr32 with two payload DWORDs -> two AMDUSB4 raw beats.
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_226a_f000;
		cq_data[74:64] = 11'd2;
		cq_data[78:75] = 4'b0001;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'h5c;
		cq_data[114:112] = 3'd0;
		cq_data[159:128] = 32'h11223344;
		cq_data[191:160] = 32'ha1b2c3d4;
		cq_keep = 8'h3f;
		cq_user = '0;
		cq_user[7:0] = 8'hff;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		while (!cq_axis.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		while (!cq_raw.tvalid) @(posedge clk);
		#1;
		if (cq_raw.tdata != 128'h44332211_89abc000_12345cff_40000002 ||
			cq_raw.tkeepdw != 4'b1111 || cq_raw.tlast ||
			cq_raw.tuser != 9'h005) begin
			errors = errors + 1;
		end
		@(negedge clk);
		cq_raw_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		cq_raw_ready = 1'b0;
		#1;
		if (!cq_raw.tvalid || cq_raw.tdata[31:0] != 32'hd4c3b2a1 ||
			cq_raw.tkeepdw != 4'b0001 || !cq_raw.tlast ||
			cq_raw.tuser != 9'h002) begin
			errors = errors + 1;
		end
		@(negedge clk);
		cq_raw_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		cq_raw_ready = 1'b0;

		// LeechCore MRd32 raw TLP -> native 256-bit RQ descriptor.
		rq_raw_data = 128'h00000000_89abc000_12345aff_00000002;
		rq_raw_keep = 4'b0111;
		rq_raw_user = 9'h001;
		rq_raw_last = 1'b1;
		rq_raw_valid = 1'b1;
		while (!rq_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		rq_raw_valid = 1'b0;
		while (!rq_axis.tvalid) @(posedge clk);
		#1;
		if (rq_axis.tdata[63:2] != 62'h0000_0000_226a_f000 ||
			rq_axis.tdata[74:64] != 11'd2 ||
			rq_axis.tdata[78:75] != 4'b0000 ||
			rq_axis.tdata[95:80] != 16'h1234 ||
			rq_axis.tdata[103:96] != 8'h5a ||
			rq_axis.tkeep != 8'h0f || !rq_axis.tlast ||
			rq_axis.tuser[7:0] != 8'hff) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rq_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rq_ready = 1'b0;

		// LeechCore MRd64 raw TLP -> native 64-bit-address RQ descriptor.
		rq_raw_data = 128'h34567000_00000012_12345b0f_20000001;
		rq_raw_keep = 4'b1111;
		rq_raw_user = 9'h001;
		rq_raw_last = 1'b1;
		rq_raw_valid = 1'b1;
		while (!rq_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		rq_raw_valid = 1'b0;
		while (!rq_axis.tvalid) @(posedge clk);
		#1;
		if ({rq_axis.tdata[63:2], 2'b00} != 64'h00000012_34567000 ||
			rq_axis.tdata[74:64] != 11'd1 ||
			rq_axis.tdata[78:75] != 4'b0000 ||
			rq_axis.tdata[103:96] != 8'h5b ||
			rq_axis.tuser[7:0] != 8'h0f) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rq_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rq_ready = 1'b0;

		// LeechCore MWr32 raw TLP -> RQ descriptor plus two payload DWORDs.
		rq_raw_data = 128'h44332211_89abc000_12345cff_40000002;
		rq_raw_keep = 4'b1111;
		rq_raw_user = 9'h001;
		rq_raw_last = 1'b0;
		rq_raw_valid = 1'b1;
		while (!rq_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		rq_raw_valid = 1'b0;
		while (!rq_axis.tvalid) @(posedge clk);
		#1;
		if (rq_axis.tdata[78:75] != 4'b0001 ||
			rq_axis.tdata[159:128] != 32'h11223344 ||
			rq_axis.tkeep != 8'h1f || rq_axis.tlast ||
			rq_axis.tuser[7:0] != 8'hff) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rq_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rq_ready = 1'b0;
		rq_raw_data = 128'h0;
		rq_raw_data[31:0] = 32'hd4c3b2a1;
		rq_raw_keep = 4'b0001;
		rq_raw_user = 9'h000;
		rq_raw_last = 1'b1;
		rq_raw_valid = 1'b1;
		while (!rq_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		rq_raw_valid = 1'b0;
		while (!rq_axis.tvalid) @(posedge clk);
		#1;
		if (rq_axis.tdata[31:0] != 32'ha1b2c3d4 ||
			rq_axis.tkeep != 8'h01 || !rq_axis.tlast) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rq_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rq_ready = 1'b0;

		// LeechCore MWr64 keeps the four-DWORD header separate from payload.
		rq_raw_data = 128'h34567000_00000012_12345d0f_60000001;
		rq_raw_keep = 4'b1111;
		rq_raw_user = 9'h001;
		rq_raw_last = 1'b0;
		rq_raw_valid = 1'b1;
		while (!rq_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		rq_raw_valid = 1'b0;
		while (!rq_axis.tvalid) @(posedge clk);
		#1;
		if ({rq_axis.tdata[63:2], 2'b00} != 64'h00000012_34567000 ||
			rq_axis.tdata[78:75] != 4'b0001 ||
			rq_axis.tkeep != 8'h0f || rq_axis.tlast) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rq_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rq_ready = 1'b0;
		rq_raw_data = 128'h0;
		rq_raw_data[31:0] = 32'h78563412;
		rq_raw_keep = 4'b0001;
		rq_raw_user = 9'h000;
		rq_raw_last = 1'b1;
		rq_raw_valid = 1'b1;
		while (!rq_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		rq_raw_valid = 1'b0;
		while (!rq_axis.tvalid) @(posedge clk);
		#1;
		if (rq_axis.tdata[31:0] != 32'h12345678 ||
			rq_axis.tkeep != 8'h01 || !rq_axis.tlast) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rq_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rq_ready = 1'b0;

		// Native RC CplD -> AMDUSB4 raw completion TLP.
		rc_data = '0;
		rc_data[42:32] = 11'd2;
		rc_data[28:16] = 13'd8;
		rc_data[45:43] = 3'd0;
		rc_data[63:48] = 16'h1234;
		rc_data[71:64] = 8'h5a;
		rc_data[87:72] = 16'habcd;
		rc_data[6:0] = 7'h20;
		rc_data[127:96] = 32'h11223344;
		rc_data[159:128] = 32'ha1b2c3d4;
		rc_keep = 8'h1f;
		rc_last = 1'b1;
		rc_valid = 1'b1;
		while (!rc_axis.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		rc_valid = 1'b0;
		while (!rc_raw.tvalid) @(posedge clk);
		#1;
		if (rc_raw.tdata != 128'h44332211_12345a20_abcd0008_4a000002 ||
			rc_raw.tkeepdw != 4'b1111 || rc_raw.tlast ||
			rc_raw.tuser != 9'h001) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rc_raw_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rc_raw_ready = 1'b0;
		#1;
		if (!rc_raw.tvalid || rc_raw.tdata[31:0] != 32'hd4c3b2a1 ||
			rc_raw.tkeepdw != 4'b0001 || !rc_raw.tlast ||
			rc_raw.tuser != 9'h002) begin
			errors = errors + 1;
		end
		@(negedge clk);
		rc_raw_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		rc_raw_ready = 1'b0;

		// AMDUSB4 raw CplD -> native 256-bit CC descriptor and payload.
		cc_raw_data = 128'h44332211_12345a20_abcd0008_4a000002;
		cc_raw_keep = 4'b1111;
		cc_raw_user = 9'h001;
		cc_raw_last = 1'b0;
		cc_raw_valid = 1'b1;
		while (!cc_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		cc_raw_valid = 1'b0;
		cc_raw_data = 128'h0;
		cc_raw_data[31:0] = 32'hd4c3b2a1;
		cc_raw_keep = 4'b0001;
		cc_raw_user = 9'h000;
		cc_raw_last = 1'b1;
		cc_raw_valid = 1'b1;
		while (!cc_raw.tready) @(posedge clk);
		@(posedge clk);
		@(negedge clk);
		cc_raw_valid = 1'b0;
		while (!cc_axis.tvalid) @(posedge clk);
		#1;
		if (cc_axis.tdata[6:0] != 7'h20 ||
			cc_axis.tdata[28:16] != 13'd8 ||
			cc_axis.tdata[42:32] != 11'd2 ||
			cc_axis.tdata[45:43] != 3'd0 ||
			cc_axis.tdata[63:48] != 16'h1234 ||
			cc_axis.tdata[71:64] != 8'h5a ||
			cc_axis.tdata[87:72] != 16'habcd ||
			!cc_axis.tdata[88] ||
			cc_axis.tdata[127:96] != 32'h11223344 ||
			cc_axis.tdata[159:128] != 32'ha1b2c3d4 ||
			cc_axis.tkeep != 8'h1f || !cc_axis.tlast) begin
			errors = errors + 1;
		end

		if (errors == 0) begin
			$display("PCIE_LEECHCORE_128_256_TEST_PASS");
			$finish;
		end
		$fatal(1, "PCIE_LEECHCORE_128_256_TEST_FAIL errors=%0d", errors);
	end

endmodule
