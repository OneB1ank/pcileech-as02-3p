`resetall
`timescale 1ns / 1ps
`default_nettype none
`include "asmcehnk_header.svh"

/*
 * UltraScale+ PCIe CFG bridge for AS02MC04.
 *
 * AMDUSB4/75T used a generated 7-series pcie_7x core and asmcehnk_pcie_cfg_a7.
 * AS02MC04 must not reuse that generated 75T wrapper.  The AS02 build imports
 * ip/pcie4_uscale_plus_0.xci directly, then this module maps
 * the same asmcehnk IfPCIeFifoCfg command/register view onto the UltraScale+
 * cfg_mgmt/status/control pins.
 *
 * This is still intentionally scoped to CFG/config-space bring-up.  Raw TLP
 * RQ/RC is handled separately by asmcehnk_pcie_tlp_us.
 */
module asmcehnk_pcie_cfg_us #(
    // The XCI profile exposes one non-prefetchable 4 KiB, 32-bit BAR0.
    // LeechCore consumes the PCIe core's DRP BAR masks in addition to the
    // config-space BAR values; keep this mirror local to the AS02 boundary.
    // 32-bit, non-prefetchable BAR0: the DRP mask must keep BAR[2]=0.
    // LeechCore uses that bit to distinguish a 64-bit BAR.
    parameter logic [31:0] PARAM_BAR0_DRP_MASK = 32'hfffff000
)(
    input  wire logic clk_pcie,
    input  wire logic rst_pcie,
    input  wire logic clk_sys,
    input  wire logic rst_sys,

    IfPCIeFifoCfg.mp_pcie  dcfg,
    IfPCIeFifoCore.mp_pcie dpcie,

    input  wire logic        user_lnk_up,
    input  wire logic        cfg_phy_link_down,
    input  wire logic [1:0]  cfg_phy_link_status,
    input  wire logic [2:0]  cfg_negotiated_width,
    input  wire logic [1:0]  cfg_current_speed,
    input  wire logic [15:0] cfg_function_status,
    input  wire logic [11:0] cfg_function_power_state,
    input  wire logic [1:0]  cfg_link_power_state,
    input  wire logic [5:0]  cfg_ltssm_state,
    input  wire logic [1:0]  cfg_rx_pm_state,
    input  wire logic [1:0]  cfg_tx_pm_state,
    input  wire logic [7:0]  cfg_bus_number,

    input  wire logic [1:0]  cfg_max_payload,
    input  wire logic [2:0]  cfg_max_read_req,
    input  wire logic [3:0]  cfg_rcb_status,

    output wire logic [9:0]  cfg_mgmt_addr,
    output wire logic [7:0]  cfg_mgmt_function_number,
    output wire logic        cfg_mgmt_write,
    output wire logic [31:0] cfg_mgmt_write_data,
    output wire logic [3:0]  cfg_mgmt_byte_enable,
    output wire logic        cfg_mgmt_read,
    input  wire logic [31:0] cfg_mgmt_read_data,
    input  wire logic        cfg_mgmt_read_write_done,
    output wire logic [63:0] cfg_dsn,
    output wire logic [15:0] pcie_id,
    output wire logic [31:0] base_address_register,

    output wire logic [2:0]  cfg_fc_sel,

    input  wire logic [3:0]  cfg_interrupt_msi_enable,
    input  wire logic [11:0] cfg_interrupt_msi_mmenable,
    input  wire logic        cfg_interrupt_msi_mask_update,
    input  wire logic [31:0] cfg_interrupt_msi_data,
    output wire logic [1:0]  cfg_interrupt_msi_select,
    output wire logic [31:0] cfg_interrupt_msi_int,
    output wire logic [31:0] cfg_interrupt_msi_pending_status,
    output wire logic        cfg_interrupt_msi_pending_status_data_enable,
    output wire logic [1:0]  cfg_interrupt_msi_pending_status_function_num,
    input  wire logic        cfg_interrupt_msi_sent,
    input  wire logic        cfg_interrupt_msi_fail,
    output wire logic [2:0]  cfg_interrupt_msi_attr,
    output wire logic        cfg_interrupt_msi_tph_present,
    output wire logic [1:0]  cfg_interrupt_msi_tph_type,
    output wire logic [7:0]  cfg_interrupt_msi_tph_st_tag,
    output wire logic [7:0]  cfg_interrupt_msi_function_number
);

    localparam int RW_BITS = 32'd704;
    localparam int RO_BITS = 32'd384;

    localparam int RWPOS_CFG_RD_EN                 = 32'd16;
    localparam int RWPOS_CFG_WR_EN                 = 32'd17;
    localparam int RWPOS_CFG_WAIT_COMPLETE         = 32'd18;
    localparam int RWPOS_CFG_STATIC_TLP_TX_EN      = 32'd19;
    localparam int RWPOS_CFG_CFGSPACE_STATUS_CL_EN = 32'd20;
    localparam int RWPOS_CFG_CFGSPACE_COMMAND_EN   = 32'd21;
    localparam [17:0] RW_LAST_WORD_BIT = 18'd688;
    localparam [17:0] RO_LAST_WORD_BIT = 18'd368;

    logic [RW_BITS-1:0] rw = '0;
    logic [RO_BITS-1:0] ro;

    logic [31:0] cfg_rx_data_reg = '0;
    logic        cfg_rx_valid_reg = 1'b0;
    logic        drp_rdy_sys_reg = 1'b0;
    logic [15:0] drp_do_sys_reg = 16'h0000;
    logic [127:0] drp_mirror_valid = '0;
    (* ram_style = "distributed" *) logic [15:0] drp_mirror_data [0:127];
    logic [63:0] tickcount64 = '0;

    logic        rwi_cfg_mgmt_rd_en = 1'b0;
    logic        rwi_cfg_mgmt_wr_en = 1'b0;
    logic [9:0]  rwi_cfgrd_addr = '0;
    logic [31:0] rwi_cfgrd_data = '0;
    logic [3:0]  rwi_cfgrd_byte_en = '0;
    logic        rwi_cfgrd_valid = 1'b0;
    logic [31:0] rwi_count_cfgspace_status_cl = '0;
    logic [31:0] base_address_register_reg = '0;
    logic [15:0] cfg_command_shadow = 16'h0000;
    logic [15:0] cfg_status_shadow = 16'h0000;

    wire [63:0] cmd_rx_dout;
    wire        cmd_rx_valid;
    wire        cmd_rx_full;
    wire        cfg_rsp_almost_full;
    wire        pcie_cfg_rw_en;
    wire        cmd_rx_rd_en;
    wire        cfgspace_maintenance_due;

    // Preserve the AMDUSB4 CFG boundary: commands enter in the asmcehnk
    // system clock domain and are consumed by cfg_mgmt in the PCIe domain.
    fifo_64_64 cfg_cmd_cdc_fifo_inst (
        .rst     (rst_pcie),
        .wr_clk  (clk_sys),
        .rd_clk  (clk_pcie),
        .din     (dcfg.tx_data),
        .wr_en   (dcfg.tx_valid),
        .rd_en   (cmd_rx_rd_en),
        .dout    (cmd_rx_dout),
        .full    (cmd_rx_full),
        .empty   (),
        .valid   (cmd_rx_valid)
    );

    // CFG replies return to the network/system domain through the matching
    // asynchronous FIFO; almost-full throttles new register reads.
    fifo_32_32_clk2 cfg_rsp_cdc_fifo_inst (
        .rst         (rst_pcie),
        .wr_clk      (clk_pcie),
        .rd_clk      (clk_sys),
        .din         (cfg_rx_data_reg),
        .wr_en       (cfg_rx_valid_reg),
        .rd_en       (dcfg.rx_rd_en),
        .dout        (dcfg.rx_data),
        .full        (),
        .almost_full (cfg_rsp_almost_full),
        .empty       (),
        .valid       (dcfg.rx_valid)
    );

    wire [15:0] in_cmd_address_byte;
    wire [17:0] in_cmd_address_bit;
    wire [15:0] in_cmd_value;
    wire [15:0] in_cmd_mask;
    wire        f_rw;
    wire        accept_cmd;
    wire        in_cmd_read;
    wire        in_cmd_write;

    logic [15:0] in_cmd_data_in;

    assign cmd_rx_rd_en = tickcount64[1] && !cfg_rsp_almost_full &&
                          (!rw[RWPOS_CFG_WAIT_COMPLETE] || !pcie_cfg_rw_en);
    assign in_cmd_address_byte = cmd_rx_dout[31:16];
    assign in_cmd_address_bit = {in_cmd_address_byte[14:0], 3'b000};
    assign in_cmd_value = {cmd_rx_dout[48+:8], cmd_rx_dout[56+:8]};
    assign in_cmd_mask = {cmd_rx_dout[32+:8], cmd_rx_dout[40+:8]};
    assign f_rw = in_cmd_address_byte[15];

    assign pcie_cfg_rw_en = rwi_cfg_mgmt_rd_en | rwi_cfg_mgmt_wr_en |
                            rw[RWPOS_CFG_RD_EN] | rw[RWPOS_CFG_WR_EN];
    assign cfgspace_maintenance_due =
        (rw[RWPOS_CFG_CFGSPACE_STATUS_CL_EN] |
         rw[RWPOS_CFG_CFGSPACE_COMMAND_EN]) &&
        !in_cmd_read && !in_cmd_write && !pcie_cfg_rw_en &&
        (rwi_count_cfgspace_status_cl >= rw[672+:32]);
    assign accept_cmd = cmd_rx_valid && !cfg_rsp_almost_full &&
                        (!rw[RWPOS_CFG_WAIT_COMPLETE] || !pcie_cfg_rw_en);
    assign in_cmd_read = cmd_rx_dout[12] & accept_cmd;
    assign in_cmd_write = cmd_rx_dout[13] & in_cmd_address_byte[15] & accept_cmd;

    always_comb begin
        in_cmd_data_in = 16'h0000;

        if (f_rw) begin
            if (in_cmd_address_bit <= RW_LAST_WORD_BIT) begin
                in_cmd_data_in = rw[in_cmd_address_bit +: 16];
            end
        end else begin
            if (in_cmd_address_bit <= RO_LAST_WORD_BIT) begin
                in_cmd_data_in = ro[in_cmd_address_bit +: 16];
            end
        end
    end

    always_comb begin
        ro = '0;

        // Keep AMDUSB4 cfg register layout so host-side cfg commands do not
        // need to know whether the endpoint is 7-series or UltraScale+.
        ro[15:0]    = 16'h2301;              // +000: MAGIC
        ro[16]      = rwi_cfg_mgmt_rd_en;    // +002: cfg mgmt read busy
        ro[17]      = rwi_cfg_mgmt_wr_en;    //       cfg mgmt write busy
        ro[63:32]   = RO_BITS >> 3;          // +004: bytecount

        // PCIe bus/device/function.  UltraScale+ pcie4 exposes bus number; AS02
        // is a single PF0 endpoint, so device/function are fixed at zero.
        ro[71:64]   = cfg_bus_number;        // +008
        ro[76:72]   = 5'd0;
        ro[79:77]   = 3'd0;

        // Link/PHY status mapped from pcie4_uscale_plus CFG status.
        ro[85:80]   = cfg_ltssm_state;       // +00A
        ro[87:86]   = cfg_rx_pm_state;
        ro[90:88]   = {1'b0, cfg_tx_pm_state};
        ro[93:91]   = cfg_negotiated_width;
        ro[95:94]   = 2'd0;                  // lane reversal not exposed
        // LeechCore's legacy PHY view expects the 7-series width index here:
        // 0/1/2/3 = x1/x2/x4/x8.  UltraScale+ negotiated_width uses the same
        // index for this x8 endpoint; phy_link_status is a separate LTSSM flag.
        ro[97:96]   = cfg_negotiated_width[1:0]; // +00C
        ro[98]      = user_lnk_up & !cfg_phy_link_down;
        // The legacy 7-series view reports endpoint/partner Gen2 capability
        // separately from the current link rate.  The AS02 endpoint is
        // Gen2-capable, while pcie4_uscale_plus does not expose a matching
        // directed-change/upconfigure-capable status bit at this boundary.
        ro[99]      = 1'b1;
        ro[100]     = |cfg_current_speed;
        ro[101]     = 1'b0;
        // The legacy field is one bit (Gen1/Gen2).  Preserve compatibility by
        // saturating an UltraScale+ Gen2 or Gen3 indication to legacy Gen2.
        ro[102]     = |cfg_current_speed;
        ro[103]     = 1'b0;
        ro[104]     = 1'b0;
        ro[127]     = cfg_mgmt_read_write_done;

        // CFG management data and coarse status.
        ro[159:128] = cfg_mgmt_read_data;    // +010
        ro[175:160] = cfg_command_shadow;    // +014
        ro[191:176] = {10'd0, cfg_link_power_state, cfg_current_speed, cfg_phy_link_down, user_lnk_up};
        ro[207:192] = {6'd0, cfg_max_read_req, 5'd0, cfg_max_payload};
        ro[223:208] = 16'd0;
        ro[239:224] = cfg_function_status;
        ro[255:240] = {12'd0, cfg_rcb_status};
        ro[271:256] = {12'd0, cfg_function_power_state[3:0]};
        ro[287:272] = cfg_status_shadow;

        // Flow-control and interrupt snapshot.
        ro[293:288] = 6'd0;
        ro[302:296] = 7'd0;
        ro[327:320] = cfg_interrupt_msi_data[7:0];
        ro[330:328] = cfg_interrupt_msi_mmenable[2:0];
        ro[331]     = cfg_interrupt_msi_enable[0];
        ro[332]     = 1'b0;                  // MSI-X not enabled in current IP
        ro[333]     = cfg_interrupt_msi_mask_update;
        ro[334]     = !cfg_interrupt_msi_fail;

        // Last CFG mgmt transaction result.
        ro[345:336] = rwi_cfgrd_addr;        // +02A
        ro[347]     = rwi_cfgrd_valid;
        ro[351:348] = rwi_cfgrd_byte_en;
        ro[383:352] = rwi_cfgrd_data;        // +02C
    end

    assign cfg_mgmt_addr = rw[169:160];
    assign cfg_mgmt_function_number = 8'd0;
    assign cfg_mgmt_write = rwi_cfg_mgmt_wr_en & !cfg_mgmt_read_write_done;
    assign cfg_mgmt_write_data = rw[159:128];
    assign cfg_mgmt_byte_enable = rw[175:172];
    assign cfg_mgmt_read = rwi_cfg_mgmt_rd_en & !cfg_mgmt_read_write_done;
    assign cfg_dsn = rw[127:64];
    // AMDUSB4 raw-TLP helpers keep pcie_id in 7-series byte order: {devfn,bus}.
    // Completion builders call `_bs16(pcie_id)` before placing completer ID in TLP headers.
    assign pcie_id = {5'd0, 3'd0, cfg_bus_number};
    assign base_address_register = base_address_register_reg;
    assign cfg_fc_sel = 3'b100;

    assign cfg_interrupt_msi_select = 2'd0;
    assign cfg_interrupt_msi_int = 32'd0;
    assign cfg_interrupt_msi_pending_status = 32'd0;
    assign cfg_interrupt_msi_pending_status_data_enable = 1'b0;
    assign cfg_interrupt_msi_pending_status_function_num = 2'd0;
    assign cfg_interrupt_msi_attr = 3'd0;
    assign cfg_interrupt_msi_tph_present = 1'b0;
    assign cfg_interrupt_msi_tph_type = 2'd0;
    assign cfg_interrupt_msi_tph_st_tag = 8'd0;
    assign cfg_interrupt_msi_function_number = 8'd0;

    assign dpcie.drp_do = drp_do_sys_reg;
    assign dpcie.drp_rdy = drp_rdy_sys_reg;

    integer i_write;

    always_ff @(posedge clk_sys) begin
        if (rst_sys) begin
            drp_rdy_sys_reg <= 1'b0;
            drp_do_sys_reg <= 16'h0000;
            // Clearing only the validity map lets Vivado infer compact RAM for
            // the writable mirror instead of 2048 resettable data flip-flops.
            drp_mirror_valid <= '0;
        end else begin
            drp_rdy_sys_reg <= dpcie.drp_en;
            if (dpcie.drp_en) begin
                if (dpcie.drp_addr < 9'd128) begin
                    if (dpcie.drp_we) begin
                        drp_mirror_data[dpcie.drp_addr] <= dpcie.drp_di;
                        drp_mirror_valid[dpcie.drp_addr] <= 1'b1;
                        drp_do_sys_reg <= dpcie.drp_di;
                    end else if (drp_mirror_valid[dpcie.drp_addr]) begin
                        drp_do_sys_reg <= drp_mirror_data[dpcie.drp_addr];
                    end else if (dpcie.drp_addr == 9'd7) begin
                        // Native 16-bit halves are byte-swapped by asmcehnk_fifo.
                        drp_do_sys_reg <= PARAM_BAR0_DRP_MASK[15:0];
                    end else if (dpcie.drp_addr == 9'd8) begin
                        drp_do_sys_reg <= PARAM_BAR0_DRP_MASK[31:16];
                    end else begin
                        drp_do_sys_reg <= 16'h0000;
                    end
                end else begin
                    drp_do_sys_reg <= 16'h0000;
                end
            end
        end
    end

    always_ff @(posedge clk_pcie) begin
        tickcount64 <= tickcount64 + 1'b1;
        cfg_rx_valid_reg <= 1'b0;

        // Host-visible read of RO/RW cfg register file.
        if (in_cmd_read) begin
            cfg_rx_data_reg <= {in_cmd_address_byte, in_cmd_data_in[7:0], in_cmd_data_in[15:8]};
            cfg_rx_valid_reg <= 1'b1;
        end

        // Host-visible masked write of RW cfg register file.
        if (in_cmd_write) begin
            for (i_write = 32'd0; i_write < 16; i_write = i_write + 32'd1) begin
                if (in_cmd_mask[i_write] && (in_cmd_address_bit+i_write < RW_BITS)) begin
                    rw[in_cmd_address_bit+i_write] <= in_cmd_value[i_write];
                end
            end
        end

        // Optional A7-compatible status/command maintenance.  Default only
        // status RW1C byte clear is enabled; command auto-set remains disabled.
        if ((rw[RWPOS_CFG_CFGSPACE_STATUS_CL_EN] | rw[RWPOS_CFG_CFGSPACE_COMMAND_EN]) &&
            !in_cmd_read && !in_cmd_write && !pcie_cfg_rw_en) begin
            if (rwi_count_cfgspace_status_cl < rw[672+:32]) begin
                rwi_count_cfgspace_status_cl <= rwi_count_cfgspace_status_cl + 1'b1;
            end else begin
                rwi_count_cfgspace_status_cl <= '0;
                rw[RWPOS_CFG_WR_EN] <= 1'b1;
                rw[143:128] <= 16'h0007;                            // command
                rw[159:144] <= 16'hff00;                            // status RW1C
                rw[169:160] <= 10'd1;                               // dwaddr 1
                rw[170]     <= 1'b0;
                rw[171]     <= 1'b0;
                rw[172]     <= rw[RWPOS_CFG_CFGSPACE_COMMAND_EN];
                rw[173]     <= rw[RWPOS_CFG_CFGSPACE_COMMAND_EN];
                rw[174]     <= 1'b0;
                rw[175]     <= rw[RWPOS_CFG_CFGSPACE_STATUS_CL_EN];
            end
        end

        // Read BAR0 until enumeration programs it; mirrors AMDUSB4 behavior.
        if ((base_address_register_reg == 32'h00000000 ||
             base_address_register_reg == PARAM_BAR0_DRP_MASK ||
             base_address_register_reg == 32'hfff00004 ||
             base_address_register_reg == 32'h00000004) &&
            !in_cmd_read && !in_cmd_write && !pcie_cfg_rw_en &&
            !cfgspace_maintenance_due) begin
            rw[RWPOS_CFG_RD_EN] <= 1'b1;
            rw[169:160] <= 10'd4;       // BAR0 low dword
            rw[175:172] <= 4'h0;
        end

        // Launch and complete UltraScale+ CFG management transactions.
        if (cfg_mgmt_read_write_done) begin
            rwi_cfg_mgmt_rd_en <= 1'b0;
            rwi_cfg_mgmt_wr_en <= 1'b0;
            rwi_cfgrd_valid <= 1'b1;
            rwi_cfgrd_addr <= cfg_mgmt_addr;
            rwi_cfgrd_data <= cfg_mgmt_read_data;
            rwi_cfgrd_byte_en <= cfg_mgmt_byte_enable;

            if (cfg_mgmt_addr == 10'd1) begin
                cfg_command_shadow <= cfg_mgmt_read_data[15:0];
                cfg_status_shadow <= cfg_mgmt_read_data[31:16];
            end
            if (cfg_mgmt_addr == 10'd4 && rwi_cfg_mgmt_rd_en) begin
                base_address_register_reg <= cfg_mgmt_read_data;
            end
        end else if (!rwi_cfg_mgmt_rd_en && !rwi_cfg_mgmt_wr_en && rw[RWPOS_CFG_RD_EN]) begin
            rw[RWPOS_CFG_RD_EN] <= 1'b0;
            rwi_cfg_mgmt_rd_en <= 1'b1;
            rwi_cfgrd_valid <= 1'b0;
        end else if (!rwi_cfg_mgmt_rd_en && !rwi_cfg_mgmt_wr_en && rw[RWPOS_CFG_WR_EN]) begin
            rw[RWPOS_CFG_WR_EN] <= 1'b0;
            rwi_cfg_mgmt_wr_en <= 1'b1;
            rwi_cfgrd_valid <= 1'b0;
        end

        if (rst_pcie) begin
            cfg_rx_data_reg <= '0;
            cfg_rx_valid_reg <= 1'b0;
            tickcount64 <= '0;
            rwi_cfg_mgmt_rd_en <= 1'b0;
            rwi_cfg_mgmt_wr_en <= 1'b0;
            rwi_cfgrd_addr <= '0;
            rwi_cfgrd_data <= '0;
            rwi_cfgrd_byte_en <= '0;
            rwi_cfgrd_valid <= 1'b0;
            rwi_count_cfgspace_status_cl <= '0;
            base_address_register_reg <= '0;
            cfg_command_shadow <= 16'h0000;
            cfg_status_shadow <= 16'h0000;

            rw <= '0;
            rw[15:0]    <= 16'h6745;        // +000: MAGIC
            rw[63:32]   <= RW_BITS >> 3;    // +004: bytecount
            rw[127:64]  <= 64'h001000203ef540;
            rw[175:172] <= 4'hf;
            rw[179]     <= 1'b1;
            rw[182]     <= 1'b1;
            rw[217]     <= 1'b1;            // rx_np_ok
            rw[218]     <= 1'b1;            // rx_np_req
            rw[219]     <= 1'b1;            // tx_cfg_gnt
            rw[RWPOS_CFG_CFGSPACE_STATUS_CL_EN] <= 1'b1; // clear status RW1C flags periodically
            rw[RWPOS_CFG_CFGSPACE_COMMAND_EN]   <= 1'b0; // keep command auto-set disabled
            rw[672+:32] <= 32'd250000;      // 1 ms at 250 MHz pcie user clock
        end
    end

endmodule

`resetall

