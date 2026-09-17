`timescale 1ns / 1ps
`default_nettype none

// Minimal FIFO stubs keep this focused test on the AS02 DRP boundary.  The
// production project supplies the generated XCI implementations.
module fifo_64_64 (
    input  wire        rst,
    input  wire        wr_clk,
    input  wire        rd_clk,
    input  wire [63:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output wire [63:0] dout,
    output wire        full,
    output wire        empty,
    output wire        valid
);
    assign dout  = 64'd0;
    assign full   = 1'b0;
    assign empty  = 1'b1;
    assign valid  = 1'b0;
endmodule

module fifo_32_32_clk2 (
    input  wire        rst,
    input  wire        wr_clk,
    input  wire        rd_clk,
    input  wire [31:0] din,
    input  wire        wr_en,
    input  wire        rd_en,
    output wire [31:0] dout,
    output wire        full,
    output wire        almost_full,
    output wire        empty,
    output wire        valid
);
    assign dout        = 32'd0;
    assign full        = 1'b0;
    assign almost_full = 1'b0;
    assign empty       = 1'b1;
    assign valid       = 1'b0;
endmodule

module tb_pcie_drp_bar_info;
    logic clk_pcie = 1'b0;
    logic clk_sys = 1'b0;
    logic rst_pcie = 1'b1;
    logic rst_sys = 1'b1;
    always #2 clk_pcie = !clk_pcie;
    always #5 clk_sys = !clk_sys;

    IfPCIeFifoCfg dcfg();
    IfPCIeFifoCore dpcie();

    logic        drp_en = 1'b0;
    logic        drp_we = 1'b0;
    logic [8:0]  drp_addr = 9'd0;
    logic [15:0] drp_di = 16'd0;

    assign dpcie.drp_en = drp_en;
    assign dpcie.drp_we = drp_we;
    assign dpcie.drp_addr = drp_addr;
    assign dpcie.drp_di = drp_di;
    assign dpcie.pcie_rst_core = 1'b0;
    assign dpcie.pcie_rst_subsys = 1'b0;

    logic [31:0] errors = 32'd0;
    logic [15:0] observed = 16'd0;
    logic        observed_rdy = 1'b0;
    integer      word_index;
    logic [15:0] expected_word;
    logic        user_lnk_up = 1'b0;
    logic        cfg_phy_link_down = 1'b1;
    logic [1:0]  cfg_phy_link_status = 2'd0;
    logic [2:0]  cfg_negotiated_width = 3'd0;
    logic [1:0]  cfg_current_speed = 2'd0;
    logic [9:0]  cfg_mgmt_addr;
    logic        cfg_mgmt_read;
    logic        cfg_mgmt_write;
    logic [31:0] cfg_mgmt_write_data;
    logic [3:0]  cfg_mgmt_byte_enable;
    logic [31:0] cfg_mgmt_read_data = 32'd0;
    logic        cfg_mgmt_read_write_done = 1'b0;
    logic [31:0] base_address_register;
    logic        maintenance_read_seen = 1'b0;

    asmcehnk_pcie_cfg_us #(
        .PARAM_BAR0_DRP_MASK(32'hfffff000)
    ) dut (
        .clk_pcie(clk_pcie),
        .rst_pcie(rst_pcie),
        .clk_sys(clk_sys),
        .rst_sys(rst_sys),
        .dcfg(dcfg.mp_pcie),
        .dpcie(dpcie.mp_pcie),
        .user_lnk_up(user_lnk_up),
        .cfg_phy_link_down(cfg_phy_link_down),
        .cfg_phy_link_status(cfg_phy_link_status),
        .cfg_negotiated_width(cfg_negotiated_width),
        .cfg_current_speed(cfg_current_speed),
        .cfg_function_status(16'd0),
        .cfg_function_power_state(12'd0),
        .cfg_link_power_state(2'd0),
        .cfg_ltssm_state(6'd0),
        .cfg_rx_pm_state(2'd0),
        .cfg_tx_pm_state(2'd0),
        .cfg_bus_number(8'd0),
        .cfg_max_payload(2'd0),
        .cfg_max_read_req(3'd0),
        .cfg_rcb_status(4'd0),
        .cfg_mgmt_addr(cfg_mgmt_addr),
        .cfg_mgmt_function_number(),
        .cfg_mgmt_write(cfg_mgmt_write),
        .cfg_mgmt_write_data(cfg_mgmt_write_data),
        .cfg_mgmt_byte_enable(cfg_mgmt_byte_enable),
        .cfg_mgmt_read(cfg_mgmt_read),
        .cfg_mgmt_read_data(cfg_mgmt_read_data),
        .cfg_mgmt_read_write_done(cfg_mgmt_read_write_done),
        .cfg_dsn(),
        .pcie_id(),
        .base_address_register(base_address_register),
        .cfg_fc_sel(),
        .cfg_interrupt_msi_enable(4'd0),
        .cfg_interrupt_msi_mmenable(12'd0),
        .cfg_interrupt_msi_mask_update(1'b0),
        .cfg_interrupt_msi_data(32'd0),
        .cfg_interrupt_msi_select(),
        .cfg_interrupt_msi_int(),
        .cfg_interrupt_msi_pending_status(),
        .cfg_interrupt_msi_pending_status_data_enable(),
        .cfg_interrupt_msi_pending_status_function_num(),
        .cfg_interrupt_msi_sent(1'b0),
        .cfg_interrupt_msi_fail(1'b0),
        .cfg_interrupt_msi_attr(),
        .cfg_interrupt_msi_tph_present(),
        .cfg_interrupt_msi_tph_type(),
        .cfg_interrupt_msi_tph_st_tag(),
        .cfg_interrupt_msi_function_number()
    );

    always @(posedge clk_sys) begin
        observed = dpcie.drp_do;
        observed_rdy = dpcie.drp_rdy;
    end

    initial begin
        repeat (3) @(posedge clk_sys);
        rst_sys = 1'b0;
        rst_pcie = 1'b0;
        repeat (2) @(posedge clk_sys);

        // UltraScale+ and the legacy LeechCore PHY register use the same
        // width index, but cfg_phy_link_status is not that width.  A Gen3 x2
        // link must therefore publish width index 1 and the saturated legacy
        // Gen2 rate bit even while phy_link_status is 2'b11.
        user_lnk_up = 1'b1;
        cfg_phy_link_down = 1'b0;
        cfg_phy_link_status = 2'b11;
        cfg_negotiated_width = 3'd1;
        cfg_current_speed = 2'd2;
        #1;
        if (dut.ro[97:96] !== 2'd1 || dut.ro[98] !== 1'b1 ||
            dut.ro[99] !== 1'b1 || dut.ro[100] !== 1'b1 ||
            dut.ro[101] !== 1'b0 || dut.ro[102] !== 1'b1) begin
            $display("PCIE_PHY_GEN3_X2_FAIL legacy=%h", dut.ro[103:96]);
            errors = errors + 1;
        end

        // The checked-in endpoint is x8, whose negotiated-width index is 3.
        cfg_negotiated_width = 3'd3;
        #1;
        if (dut.ro[97:96] !== 2'd3) begin
            $display("PCIE_PHY_X8_FAIL width=%h", dut.ro[97:96]);
            errors = errors + 1;
        end

        cfg_current_speed = 2'd0;
        #1;
        if (dut.ro[99] !== 1'b1 || dut.ro[100] !== 1'b0 ||
            dut.ro[101] !== 1'b0 || dut.ro[102] !== 1'b0) begin
            $display("PCIE_PHY_GEN1_FAIL legacy=%h", dut.ro[103:96]);
            errors = errors + 1;
        end

        cfg_phy_link_down = 1'b1;
        #1;
        if (dut.ro[98] !== 1'b0) begin
            $display("PCIE_PHY_LINK_DOWN_FAIL up=%b", dut.ro[98]);
            errors = errors + 1;
        end

        // BAR0 low mask (DRP word 7) and high mask (word 8).
        drp_addr = 9'd7;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'hf000) begin
            $display("DRP_BAR0_LOW_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        drp_addr = 9'd8;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'hffff) begin
            $display("DRP_BAR0_HIGH_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        // Unknown words are deterministic zeroes.
        drp_addr = 9'd31;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'h0000) begin
            $display("DRP_UNKNOWN_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        // Writes are acknowledged and remain readable without touching the
        // generated PCIe IP itself.
        drp_addr = 9'd31;
        drp_di = 16'h55aa;
        drp_we = 1'b1;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'h55aa) begin
            $display("DRP_WRITE_ACK_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        drp_we = 1'b0;
        @(posedge clk_sys);

        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'h55aa) begin
            $display("DRP_WRITE_READBACK_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        // The highest valid word uses the same persistent writeback path.
        drp_addr = 9'd127;
        drp_di = 16'ha55a;
        drp_we = 1'b1;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'ha55a) begin
            $display("DRP_LAST_WRITE_ACK_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        drp_we = 1'b0;
        @(posedge clk_sys);

        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'ha55a) begin
            $display("DRP_LAST_WRITE_READBACK_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        // Reset invalidates writes and restores deterministic defaults without
        // resetting every bit of the inferred mirror RAM.
        rst_sys = 1'b1;
        repeat (2) @(posedge clk_sys);
        rst_sys = 1'b0;
        repeat (2) @(posedge clk_sys);

        drp_addr = 9'd31;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'h0000) begin
            $display("DRP_RESET_ZERO_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        drp_addr = 9'd7;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'hf000) begin
            $display("DRP_RESET_BAR0_LOW_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        // Addresses outside LeechCore's 0x100-byte DRP window return zero.
        drp_addr = 9'd128;
        drp_en = 1'b1;
        @(posedge clk_sys);
        #1;
        if (!dpcie.drp_rdy || dpcie.drp_do !== 16'h0000) begin
            $display("DRP_OUT_OF_RANGE_FAIL rdy=%b do=%h", dpcie.drp_rdy, dpcie.drp_do);
            errors = errors + 1;
        end
        drp_en = 1'b0;
        @(posedge clk_sys);

        // Golden-vector sweep for the complete 0x100-byte LeechCore DRP
        // contract: every word is readable, only BAR0 mask words have
        // defaults, and all other reset-invalid words return zero.
        for (word_index = 0; word_index < 128; word_index = word_index + 1) begin
            drp_addr = word_index[8:0];
            drp_en = 1'b1;
            @(posedge clk_sys);
            #1;
            expected_word = 16'h0000;
            if (word_index == 7) begin
                expected_word = 16'hf000;
            end else if (word_index == 8) begin
                expected_word = 16'hffff;
            end
            if (!dpcie.drp_rdy || dpcie.drp_do !== expected_word) begin
                $display("DRP_DEFAULT_SWEEP_FAIL word=%0d rdy=%b do=%h expected=%h",
                         word_index, dpcie.drp_rdy, dpcie.drp_do, expected_word);
                errors = errors + 1;
            end
            drp_en = 1'b0;
            @(posedge clk_sys);
        end

        // Write and read back every valid word to prove the full mirror, not
        // only the previously sampled boundary addresses.
        for (word_index = 0; word_index < 128; word_index = word_index + 1) begin
            drp_addr = word_index[8:0];
            drp_di = 16'h4000 | word_index[15:0];
            drp_we = 1'b1;
            drp_en = 1'b1;
            @(posedge clk_sys);
            #1;
            if (!dpcie.drp_rdy || dpcie.drp_do !== drp_di) begin
                $display("DRP_SWEEP_WRITE_FAIL word=%0d rdy=%b do=%h expected=%h",
                         word_index, dpcie.drp_rdy, dpcie.drp_do, drp_di);
                errors = errors + 1;
            end
            drp_en = 1'b0;
            drp_we = 1'b0;
            @(posedge clk_sys);
            drp_en = 1'b1;
            @(posedge clk_sys);
            #1;
            if (!dpcie.drp_rdy || dpcie.drp_do !== drp_di) begin
                $display("DRP_SWEEP_READBACK_FAIL word=%0d rdy=%b do=%h expected=%h",
                         word_index, dpcie.drp_rdy, dpcie.drp_do, drp_di);
                errors = errors + 1;
            end
            drp_en = 1'b0;
            @(posedge clk_sys);
        end

        // BAR0 reads continue through both reset/default zero and the sizing
        // mask returned while enumeration probes the BAR aperture.  Polling
        // stops only after the host assigns a real address.
        wait (cfg_mgmt_read);
        #1;
        if (cfg_mgmt_addr !== 10'd4) begin
            $display("CFG_BAR0_ZERO_ADDR_FAIL addr=%h", cfg_mgmt_addr);
            errors = errors + 1;
        end
        cfg_mgmt_read_data = 32'h00000000;
        dut.rwi_count_cfgspace_status_cl = 32'd250000;
        cfg_mgmt_read_write_done = 1'b1;
        @(posedge clk_pcie);
        #1;
        cfg_mgmt_read_write_done = 1'b0;
        if (base_address_register !== 32'h00000000) begin
            $display("CFG_BAR0_ZERO_CAPTURE_FAIL bar=%h", base_address_register);
            errors = errors + 1;
        end

        // Force the periodic status-maintenance deadline while BAR0 still
        // requires polling.  The write must win this single-cycle arbitration;
        // otherwise the BAR0 read overwrites its address/data/byte enables.
        @(posedge clk_pcie);
        #1;
        wait (cfg_mgmt_write || cfg_mgmt_read);
        #1;
        maintenance_read_seen = cfg_mgmt_read;
        if (!cfg_mgmt_write || cfg_mgmt_read || cfg_mgmt_addr !== 10'd1 ||
            cfg_mgmt_write_data !== 32'hff000007 || cfg_mgmt_byte_enable !== 4'b1000) begin
            $display("CFG_MAINTENANCE_ARBITRATION_FAIL rd=%b wr=%b addr=%h data=%h be=%h",
                     cfg_mgmt_read, cfg_mgmt_write, cfg_mgmt_addr,
                     cfg_mgmt_write_data, cfg_mgmt_byte_enable);
            errors = errors + 1;
        end
        cfg_mgmt_read_write_done = 1'b1;
        @(posedge clk_pcie);
        #1;
        cfg_mgmt_read_write_done = 1'b0;

        // The unfixed scheduler leaves the maintenance write pending after
        // incorrectly launching the BAR read first.  Drain that transaction so
        // the red test terminates and reports the arbitration failure cleanly.
        if (maintenance_read_seen) begin
            wait (cfg_mgmt_write);
            cfg_mgmt_read_write_done = 1'b1;
            @(posedge clk_pcie);
            #1;
            cfg_mgmt_read_write_done = 1'b0;
        end

        wait (cfg_mgmt_read);
        #1;
        if (cfg_mgmt_addr !== 10'd4) begin
            $display("CFG_BAR0_MASK_ADDR_FAIL addr=%h", cfg_mgmt_addr);
            errors = errors + 1;
        end
        cfg_mgmt_read_data = 32'hfffff000;
        cfg_mgmt_read_write_done = 1'b1;
        @(posedge clk_pcie);
        #1;
        cfg_mgmt_read_write_done = 1'b0;
        if (base_address_register !== 32'hfffff000) begin
            $display("CFG_BAR0_MASK_CAPTURE_FAIL bar=%h", base_address_register);
            errors = errors + 1;
        end

        wait (cfg_mgmt_read);
        #1;
        if (cfg_mgmt_addr !== 10'd4) begin
            $display("CFG_BAR0_ASSIGNED_ADDR_FAIL addr=%h", cfg_mgmt_addr);
            errors = errors + 1;
        end
        cfg_mgmt_read_data = 32'h80000000;
        cfg_mgmt_read_write_done = 1'b1;
        @(posedge clk_pcie);
        #1;
        cfg_mgmt_read_write_done = 1'b0;
        if (base_address_register !== 32'h80000000) begin
            $display("CFG_BAR0_ASSIGNED_CAPTURE_FAIL bar=%h", base_address_register);
            errors = errors + 1;
        end
        repeat (8) begin
            @(posedge clk_pcie);
            #1;
            if (cfg_mgmt_read) begin
                $display("CFG_BAR0_ASSIGNED_REPOLL_FAIL addr=%h", cfg_mgmt_addr);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("PCIE_DRP_BAR_INFO_TEST_PASS");
        end else begin
            $display("PCIE_DRP_BAR_INFO_TEST_FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule

`resetall
