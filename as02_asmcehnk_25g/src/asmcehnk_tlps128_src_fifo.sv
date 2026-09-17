// Extracted framework helper; source body matches the AS02 reference wrapper.
module asmcehnk_tlps128_src_fifo (
    input                   rst_pcie,
    input                   rst_sys,
    input                   clk_pcie,
    input                   clk_sys,
    input [31:0]            dfifo_tx_data,
    input                   dfifo_tx_last,
    input                   dfifo_tx_valid,
    IfAXIS128.source        tlps_out
);

    // 1: 32-bit -> 128-bit state machine:
    bit [127:0] tdata;
    bit [3:0]   tkeepdw = 0;
    bit         tlast;
    bit         first   = 1;
    wire        tvalid  = tlast || tkeepdw[3];
    
    always @ ( posedge clk_sys )
        if ( rst_sys ) begin
            tkeepdw <= 0;
            tlast   <= 0;
            first   <= 1;
        end
        else begin
            tlast   <= dfifo_tx_valid && dfifo_tx_last;
            tkeepdw <= tvalid ? (dfifo_tx_valid ? 4'b0001 : 4'b0000) : (dfifo_tx_valid ? ((tkeepdw << 1) | 1'b1) : tkeepdw);
            first   <= tvalid ? tlast : first;
            if ( dfifo_tx_valid ) begin
                if ( tvalid || !tkeepdw[0] )
                    tdata[31:0]   <= dfifo_tx_data;
                if ( !tkeepdw[1] )
                    tdata[63:32]  <= dfifo_tx_data;
                if ( !tkeepdw[2] )
                    tdata[95:64]  <= dfifo_tx_data;
                if ( !tkeepdw[3] )
                    tdata[127:96] <= dfifo_tx_data;   
            end
        end
		
    // 2.1 - packet count (w/ safe fifo clock-crossing).
    bit [10:0]  pkt_count       = 0;
    wire        pkt_count_dec   = tlps_out.tvalid && tlps_out.tlast;
    wire        pkt_count_inc;
    wire [10:0] pkt_count_next  = pkt_count + pkt_count_inc - pkt_count_dec;
    assign tlps_out.has_data    = (pkt_count_next > 0);
    
    fifo_1_1_clk2 i_fifo_1_1_clk2(
        .rst            ( rst_pcie                  ),
        .wr_clk         ( clk_sys                   ),
        .rd_clk         ( clk_pcie                  ),
        .din            ( 1'b1                      ),
        .wr_en          ( tvalid && tlast           ),
        .rd_en          ( 1'b1                      ),
        .dout           (                           ),
        .full           (                           ),
        .empty          (                           ),
        .valid          ( pkt_count_inc             )
    );
	
    always @ ( posedge clk_pcie ) begin
        pkt_count <= rst_pcie ? 0 : pkt_count_next;
    end
        
    // 2.2 - submit to output fifo - will feed into mux/pcie core.
    //       together with 2.1 this will form a low-latency "packet fifo".
    fifo_134_134_clk2_rxfifo i_fifo_134_134_clk2_rxfifo(
        .rst            ( rst_pcie                  ),
        .wr_clk         ( clk_sys                   ),
        .rd_clk         ( clk_pcie                  ),
        .din            ( { first, tlast, tkeepdw, tdata } ),
        .wr_en          ( tvalid                    ),
        .rd_en          ( tlps_out.tready && (pkt_count_next > 0) ),
        .dout           ( { tlps_out.tuser[0], tlps_out.tlast, tlps_out.tkeepdw, tlps_out.tdata } ),
        .full           (                           ),
        .empty          (                           ),
        .valid          ( tlps_out.tvalid           )
    );

endmodule
