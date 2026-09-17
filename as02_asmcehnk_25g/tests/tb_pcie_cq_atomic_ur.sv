`timescale 1ns / 1ps
`include "asmcehnk_header.svh"

module tb_pcie_cq_atomic_malformed;

	logic clk = 1'b0;
	logic rst = 1'b1;
	logic [255:0] cq_data = 256'd0;
	logic [7:0] cq_keep = 8'd0;
	logic cq_valid = 1'b0;
	logic cq_last = 1'b0;
	logic [2:0] phase = 3'd0;
	logic [2:0] valid_output_count = 3'd0;
	logic [2:0] multibeat_output_count = 3'd0;
	integer malformed_output_count = 0;
	integer malformed_mrd_output_count = 0;
	integer errors = 0;

	taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(88)) cq_axis();
	taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(33)) cc_error_axis();
	IfAXIS128 cq_raw();

	always #2 clk = ~clk;

	assign cq_axis.tdata = cq_data;
	assign cq_axis.tkeep = cq_keep;
	assign cq_axis.tstrb = cq_keep;
	assign cq_axis.tvalid = cq_valid;
	assign cq_axis.tlast = cq_last;
	assign cq_axis.tuser = {{80{1'b0}}, 4'h0, 4'hf};
	assign cq_axis.tid = '0;
	assign cq_axis.tdest = '0;
	assign cq_raw.tready = 1'b1;
	assign cc_error_axis.tready = 1'b1;

	asmcehnk_pcie_us_cq_to_tlps128 dut (
		.clk       (clk),
		.rst       (rst),
		.pcie_id   (16'h5678),
		.s_axis_cq (cq_axis),
		.tlps_out  (cq_raw.source),
		.m_axis_cc_error (cc_error_axis)
	);

	always_ff @(posedge clk) begin
		if (rst) begin
			malformed_output_count <= 0;
			malformed_mrd_output_count <= 0;
			valid_output_count <= 3'd0;
			multibeat_output_count <= 3'd0;
		end else if (cq_raw.tvalid && cq_raw.tready) begin
			if (phase == 3'd1) begin
				malformed_output_count <= malformed_output_count + 1;
			end else if (phase == 3'd2) begin
				if (valid_output_count == 3'd0) begin
					if (cq_raw.tdata != 128'h44332211_00000400_12345c0f_40000002 ||
						cq_raw.tkeepdw != 4'b1111 || cq_raw.tlast ||
						cq_raw.tuser != 9'h005) begin
						errors <= errors + 1;
					end
				end else if (valid_output_count == 3'd1) begin
					if (cq_raw.tdata[31:0] != 32'hd4c3b2a1 ||
						cq_raw.tkeepdw != 4'b0001 || !cq_raw.tlast ||
						cq_raw.tuser != 9'h002) begin
						errors <= errors + 1;
					end
				end else begin
					errors <= errors + 1;
				end
				valid_output_count <= valid_output_count + 1'b1;
			end else if (phase == 3'd3) begin
				case (multibeat_output_count)
					3'd0: if (cq_raw.tdata != 128'h04030201_00000600_12345d0f_40000005 ||
						cq_raw.tkeepdw != 4'b1111 || cq_raw.tlast ||
						cq_raw.tuser != 9'h005) errors <= errors + 1;
					3'd1: if (cq_raw.tdata != 128'h00000000_34333231_24232221_14131211 ||
						cq_raw.tkeepdw != 4'b0111 || cq_raw.tlast ||
						cq_raw.tuser != 9'h000) errors <= errors + 1;
					3'd2: if (cq_raw.tdata[31:0] != 32'hd4c3b2a1 ||
						cq_raw.tkeepdw != 4'b0001 || !cq_raw.tlast ||
						cq_raw.tuser != 9'h002) errors <= errors + 1;
					default: errors <= errors + 1;
				endcase
				multibeat_output_count <= multibeat_output_count + 1'b1;
			end else if (phase == 3'd4) begin
				malformed_mrd_output_count <= malformed_mrd_output_count + 1;
			end
		end
	end

	initial begin
		repeat (5) @(posedge clk);
		@(negedge clk);
		rst = 1'b0;
		phase = 3'd1;

		// A five-DWORD MWr needs a second CQ beat.  Its first beat must stay
		// private until the final beat proves the length, keep, and last tuple.
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_0100;
		cq_data[74:64] = 11'd5;
		cq_data[78:75] = 4'b0001;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'h5a;
		cq_data[114:112] = 3'd0;
		cq_data[255:128] = 128'h04030201_14131211_24232221_34333231;
		cq_keep = 8'hff;
		cq_last = 1'b0;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;

		repeat (4) @(posedge clk);
		if (malformed_output_count != 0) begin
			errors = errors + 1;
		end

		// One DWORD remains, therefore tkeep 03 is malformed even though tlast
		// is asserted.  The complete request must be discarded atomically.
		@(negedge clk);
		cq_data = '0;
		cq_data[63:0] = 64'h88776655_44332211;
		cq_keep = 8'h03;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		cq_keep = 8'd0;
		cq_last = 1'b0;
		repeat (8) @(posedge clk);
		if (malformed_output_count != 0) begin
			errors = errors + 1;
		end

		// A valid single-beat MWr still produces the original two raw beats.
		@(negedge clk);
		phase = 3'd2;
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_0100;
		cq_data[74:64] = 11'd2;
		cq_data[78:75] = 4'b0001;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'h5c;
		cq_data[114:112] = 3'd0;
		cq_data[159:128] = 32'h11223344;
		cq_data[191:160] = 32'ha1b2c3d4;
		cq_keep = 8'h3f;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		cq_keep = 8'd0;
		cq_last = 1'b0;
		wait (valid_output_count == 3'd2);
		repeat (3) @(posedge clk);

		// A valid two-beat MWr remains byte-for-byte compatible after the
		// complete native request passes the atomic validation gate.
		@(negedge clk);
		phase = 3'd3;
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_0180;
		cq_data[74:64] = 11'd5;
		cq_data[78:75] = 4'b0001;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'h5d;
		cq_data[114:112] = 3'd0;
		cq_data[255:128] = 128'h31323334_21222324_11121314_01020304;
		cq_keep = 8'hff;
		cq_last = 1'b0;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		repeat (4) @(posedge clk);
		if (multibeat_output_count != 3'd0) errors = errors + 1;

		@(negedge clk);
		cq_data = '0;
		cq_data[31:0] = 32'ha1b2c3d4;
		cq_keep = 8'h01;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		cq_keep = 8'd0;
		cq_last = 1'b0;
		wait (multibeat_output_count == 3'd3);
		repeat (3) @(posedge clk);

		// A supported MRd is descriptor-only in this non-straddled profile.
		// A missing tlast must not leak the first beat into the BAR framework.
		@(negedge clk);
		phase = 3'd4;
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_01c0;
		cq_data[74:64] = 11'd1;
		cq_data[78:75] = 4'b0000;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'h5e;
		cq_keep = 8'h0f;
		cq_last = 1'b0;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		repeat (4) @(posedge clk);
		if (malformed_mrd_output_count != 0) errors = errors + 1;

		// Drain the malformed tail.  It is not a second raw MRd beat.
		@(negedge clk);
		cq_data = '0;
		cq_data[31:0] = 32'hdeadbeef;
		cq_keep = 8'h01;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		cq_keep = 8'd0;
		cq_last = 1'b0;
		repeat (6) @(posedge clk);
		if (malformed_mrd_output_count != 0) errors = errors + 1;

		// Upper keep bits on a descriptor-only MRd are malformed as well.
		@(negedge clk);
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_0200;
		cq_data[74:64] = 11'd1;
		cq_data[78:75] = 4'b0000;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'h5f;
		cq_keep = 8'h1f;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		cq_keep = 8'd0;
		cq_last = 1'b0;
		repeat (6) @(posedge clk);
		if (malformed_mrd_output_count != 0) errors = errors + 1;

		if (errors == 0 && malformed_output_count == 0 &&
			malformed_mrd_output_count == 0 && valid_output_count == 3'd2 &&
			multibeat_output_count == 3'd3) begin
			$display("PCIE_CQ_ATOMIC_MALFORMED_TEST_PASS");
			$finish;
		end
		$fatal(1, "PCIE_CQ_ATOMIC_MALFORMED_TEST_FAIL errors=%0d malformed_outputs=%0d malformed_mrd_outputs=%0d valid_outputs=%0d multibeat_outputs=%0d",
			errors, malformed_output_count, malformed_mrd_output_count, valid_output_count,
			multibeat_output_count);
	end

	initial begin
		#3000;
		$fatal(1, "PCIE_CQ_ATOMIC_MALFORMED_TEST_TIMEOUT errors=%0d malformed_outputs=%0d valid_outputs=%0d",
			errors, malformed_output_count, valid_output_count);
	end

endmodule

module tb_pcie_cq_unsupported_ur;

	logic clk = 1'b0;
	logic rst = 1'b1;
	logic [255:0] cq_data = 256'd0;
	logic [7:0] cq_keep = 8'h0f;
	logic cq_last = 1'b1;
	logic [87:0] cq_user = 88'd0;
	logic cq_valid = 1'b0;
	logic cc_ready = 1'b0;
	logic [255:0] expected_cc_data = 256'd0;
	logic [255:0] stalled_cc_data = 256'd0;
	logic [7:0] stalled_cc_keep = 8'd0;
	logic stalled_cc_last = 1'b0;
	integer raw_output_count = 0;
	integer cc_output_count = 0;
	integer errors = 0;

	taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(88)) cq_axis();
	taxi_axis_if #(.DATA_W(256), .KEEP_EN(1), .KEEP_W(8),
		.USER_EN(1), .USER_W(33)) cc_axis();
	IfAXIS128 cq_raw();

	always #2 clk = ~clk;

	assign cq_axis.tdata = cq_data;
	assign cq_axis.tkeep = cq_keep;
	assign cq_axis.tstrb = cq_axis.tkeep;
	assign cq_axis.tvalid = cq_valid;
	assign cq_axis.tlast = cq_last;
	assign cq_axis.tuser = cq_user;
	assign cq_axis.tid = '0;
	assign cq_axis.tdest = '0;
	assign cc_axis.tready = cc_ready;
	assign cq_raw.tready = 1'b1;

	asmcehnk_pcie_us_cq_to_tlps128 cq_dut (
		.clk       (clk),
		.rst       (rst),
		.pcie_id   (16'hbeef),
		.s_axis_cq (cq_axis),
		.tlps_out  (cq_raw.source),
		.m_axis_cc_error (cc_axis)
	);

	always_ff @(posedge clk) begin
		if (rst) begin
			raw_output_count <= 0;
			cc_output_count <= 0;
		end else begin
			if (cq_raw.tvalid && cq_raw.tready) raw_output_count <= raw_output_count + 1;
			if (cc_axis.tvalid && cc_axis.tready) cc_output_count <= cc_output_count + 1;
		end
	end

	initial begin
		repeat (5) @(posedge clk);
		@(negedge clk);
		rst = 1'b0;

		// I/O Read is non-posted and unsupported by the BAR adapter, therefore
		// it must receive one no-data Unsupported Request completion.
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_0120;
		cq_data[74:64] = 11'd1;
		cq_data[78:75] = 4'b0010;
		cq_data[95:80] = 16'h1234;
		cq_data[103:96] = 8'ha5;
		cq_data[123:121] = 3'b011;
		cq_data[126:124] = 3'b101;
		cq_user = 88'd0;
		cq_user[7:0] = 8'ha5;
		cq_user[42] = 1'b1;
		cq_user[44:43] = 2'b10;
		cq_user[52:45] = 8'h3c;

		expected_cc_data = 256'd0;
		expected_cc_data[28:16] = 13'd20;
		expected_cc_data[42:32] = 11'd5;
		expected_cc_data[45:43] = 3'b001;
		expected_cc_data[63:48] = 16'h1234;
		expected_cc_data[71:64] = 8'ha5;
		expected_cc_data[87:72] = 16'hbeef;
		expected_cc_data[88] = 1'b1;
		expected_cc_data[91:89] = 3'b011;
		expected_cc_data[94:92] = 3'b101;
		expected_cc_data[127:96] = {8'b0, 8'h3c, 5'b0, 2'b10, 1'b1, 8'ha5};
		expected_cc_data[255:128] = cq_data[127:0];
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;

		wait (cc_axis.tvalid);
		#1;
		stalled_cc_data = cc_axis.tdata;
		stalled_cc_keep = cc_axis.tkeep;
		stalled_cc_last = cc_axis.tlast;
		if (cc_axis.tdata != expected_cc_data || cc_axis.tkeep != 8'hff ||
			cc_axis.tstrb != 8'hff || !cc_axis.tlast || cc_axis.tuser != 33'd0) begin
			errors = errors + 1;
		end
		repeat (4) begin
			@(posedge clk);
			#1;
			if (!cc_axis.tvalid || cc_axis.tdata != stalled_cc_data ||
				cc_axis.tkeep != stalled_cc_keep || cc_axis.tlast != stalled_cc_last) begin
				errors = errors + 1;
			end
		end
		cc_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		cc_ready = 1'b0;
		repeat (4) @(posedge clk);
		if (cc_output_count != 1 || raw_output_count != 0 || cc_axis.tvalid) begin
			errors = errors + 1;
		end

		// A multi-beat unsupported request captures the trusted first descriptor,
		// drains the packet, and emits exactly one UR after the final CQ beat.
		@(negedge clk);
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_0180;
		cq_data[74:64] = 11'd1;
		cq_data[78:75] = 4'b0010;
		cq_data[95:80] = 16'h5678;
		cq_data[103:96] = 8'hb6;
		cq_data[123:121] = 3'b010;
		cq_data[126:124] = 3'b011;
		cq_user = 88'd0;
		cq_user[7:0] = 8'h3c;
		cq_user[42] = 1'b1;
		cq_user[44:43] = 2'b01;
		cq_user[52:45] = 8'hc3;
		cq_keep = 8'hff;
		cq_last = 1'b0;

		expected_cc_data = 256'd0;
		expected_cc_data[28:16] = 13'd20;
		expected_cc_data[42:32] = 11'd5;
		expected_cc_data[45:43] = 3'b001;
		expected_cc_data[63:48] = 16'h5678;
		expected_cc_data[71:64] = 8'hb6;
		expected_cc_data[87:72] = 16'hbeef;
		expected_cc_data[88] = 1'b1;
		expected_cc_data[91:89] = 3'b010;
		expected_cc_data[94:92] = 3'b011;
		expected_cc_data[127:96] = {8'b0, 8'hc3, 5'b0, 2'b01, 1'b1, 8'h3c};
		expected_cc_data[255:128] = cq_data[127:0];

		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		repeat (4) @(posedge clk);
		if (cc_axis.tvalid) errors = errors + 1;

		@(negedge clk);
		cq_data = 256'hfeedface_deadbeef_c001c0de_76543210_0_0_0_0;
		cq_user = 88'h0123456789abcdef012345;
		cq_keep = 8'h01;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		cq_keep = 8'd0;
		cq_last = 1'b0;

		wait (cc_axis.tvalid);
		#1;
		if (cc_axis.tdata != expected_cc_data || cc_axis.tkeep != 8'hff ||
			!cc_axis.tlast) errors = errors + 1;
		cc_ready = 1'b1;
		@(posedge clk);
		@(negedge clk);
		cc_ready = 1'b0;
		repeat (5) @(posedge clk);
		if (cc_output_count != 2 || raw_output_count != 0 || cc_axis.tvalid) begin
			errors = errors + 1;
		end

		// An unsupported request without all four descriptor DWORDs is dropped.
		@(negedge clk);
		cq_data = '0;
		cq_data[74:64] = 11'd1;
		cq_data[78:75] = 4'b0010;
		cq_data[95:80] = 16'h9999;
		cq_data[103:96] = 8'h99;
		cq_keep = 8'h03;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		repeat (8) @(posedge clk);
		if (cc_output_count != 2 || raw_output_count != 0 || cc_axis.tvalid) begin
			errors = errors + 1;
		end

		// Unsupported posted requests are discarded and never receive CC traffic.
		@(negedge clk);
		cq_data = '0;
		cq_data[63:2] = 62'h0000_0000_0000_0140;
		cq_data[74:64] = 11'd1;
		cq_data[78:75] = 4'b1100;
		cq_data[95:80] = 16'h4321;
		cq_data[103:96] = 8'h5a;
		cq_keep = 8'h0f;
		cq_last = 1'b1;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		repeat (8) @(posedge clk);
		if (cc_output_count != 2 || raw_output_count != 0 || cc_axis.tvalid) begin
			errors = errors + 1;
		end

		// A pending error completion is cleared by reset before it is accepted.
		@(negedge clk);
		cq_data[78:75] = 4'b0010;
		cq_valid = 1'b1;
		wait (cq_axis.tready);
		@(posedge clk);
		@(negedge clk);
		cq_valid = 1'b0;
		wait (cc_axis.tvalid);
		@(negedge clk);
		rst = 1'b1;
		repeat (2) @(posedge clk);
		@(negedge clk);
		rst = 1'b0;
		repeat (4) @(posedge clk);
		if (cc_axis.tvalid || cc_output_count != 0 || raw_output_count != 0) begin
			errors = errors + 1;
		end

		if (errors == 0) begin
			$display("PCIE_CQ_UNSUPPORTED_UR_TEST_PASS");
			$finish;
		end
		$fatal(1, "PCIE_CQ_UNSUPPORTED_UR_TEST_FAIL errors=%0d", errors);
	end

	initial begin
		#1200;
		$fatal(1, "PCIE_CQ_UNSUPPORTED_UR_TEST_TIMEOUT errors=%0d", errors);
	end

endmodule
