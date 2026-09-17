// ------------------------------------------------------------------------
// TLP-AXI-STREAM FILTER:
// Filter away certain packet types such as CfgRd/CfgWr or non-Cpl/CplD
// ------------------------------------------------------------------------
module asmcehnk_tlps128_filter(
    input  wire logic       rst,
    input  wire logic       clk_pcie,
    input  wire logic       alltlp_filter,
    input  wire logic       cfgtlp_filter,
    IfAXIS128.sink_lite     tlps_in,
    IfAXIS128.source_lite   tlps_out
);

    logic [127:0]   tdata;
    logic [3:0]     tkeepdw;
    logic           tvalid;
    logic [8:0]     tuser;
    logic           tlast;

    assign tlps_out.tdata   = tdata;
    assign tlps_out.tkeepdw = tkeepdw;
    assign tlps_out.tvalid  = tvalid;
    assign tlps_out.tuser   = tuser;
    assign tlps_out.tlast   = tlast;

    logic filter;
    wire first;
    wire is_tlphdr_cpl;
    wire is_tlphdr_cfg;
    wire filter_next;

    assign first = tlps_in.tuser[0];
    assign is_tlphdr_cpl = first && (
                        (tlps_in.tdata[31:25] == 7'b0000101) ||      // Cpl:  Fmt[2:0]=000b (3 DW header, no data), Cpl=0101xb
                        (tlps_in.tdata[31:25] == 7'b0100101)         // CplD: Fmt[2:0]=010b (3 DW header, data),    CplD=0101xb
                      );
    assign is_tlphdr_cfg = first && (
                        (tlps_in.tdata[31:25] == 7'b0000010) ||      // CfgRd: Fmt[2:0]=000b (3 DW header, no data), CfgRd0/CfgRd1=0010xb
                        (tlps_in.tdata[31:25] == 7'b0100010)         // CfgWr: Fmt[2:0]=010b (3 DW header, data),    CfgWr0/CfgWr1=0010xb
                      );
    assign filter_next = (filter && !first) ||
                         (cfgtlp_filter && first && is_tlphdr_cfg) ||
                         (alltlp_filter && first && !is_tlphdr_cpl && !is_tlphdr_cfg);

    always_ff @(posedge clk_pcie) begin
        if (rst) begin
            tvalid <= 1'b0;
            filter  <= 1'b0;
        end else begin
            tvalid <= tlps_in.tvalid && !filter_next;
            filter <= filter_next;
        end
        tdata   <= tlps_in.tdata;
        tkeepdw <= tlps_in.tkeepdw;
        tuser   <= tlps_in.tuser;
        tlast   <= tlps_in.tlast;
    end

endmodule
