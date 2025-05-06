// SPDX-FileCopyrightText: 2020 Efabless Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

`default_nettype wire

`define MPRJ_IO_PADS_1 19	/* number of user GPIO pads on user1 side */
`define MPRJ_IO_PADS_2 19	/* number of user GPIO pads on user2 side */
`define MPRJ_IO_PADS (`MPRJ_IO_PADS_1 + `MPRJ_IO_PADS_2)

/*
 *-------------------------------------------------------------
 *
 * user_proj_example
 *
 * This is an example of a (trivially simple) user project,
 * showing how the user project can connect to the logic
 * analyzer, the wishbone bus, and the I/O pads.
 *
 * This project generates an integer count, which is output
 * on the user area GPIO pads (digital output only).  The
 * wishbone connection allows the project to be controlled
 * (start and stop) from the management SoC program.
 *
 * See the testbenches in directory "mprj_counter" for the
 * example programs that drive this user project.  The three
 * testbenches are "io_ports", "la_test1", and "la_test2".
 *
 *-------------------------------------------------------------
 */

module user_proj_example #(
    parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32
)(
`ifdef USE_POWER_PINS
    inout vccd1,	// User area 1 1.8V supply
    inout vssd1,	// User area 1 digital ground
`endif

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output reg wbs_ack_o,
    output reg [31:0] wbs_dat_o,

    // Logic Analyzer Signals
    input  [127:0] la_data_in,
    output [127:0] la_data_out,
    input  [127:0] la_oenb,

    // IOs
    input  [`MPRJ_IO_PADS-1:0] io_in,
    output [`MPRJ_IO_PADS-1:0] io_out,
    output [`MPRJ_IO_PADS-1:0] io_oeb,

    // IRQ
    output [2:0] irq
);

    // WB responding signals
    wire        wbs_ack_o_fir;
    wire [31:0] wbs_dat_o_fir;
    wire        wbs_ack_o_user;
    wire [31:0] wbs_dat_o_user;

    wire [3:0]               tap_WE;
    wire                     tap_EN;
    wire [(pDATA_WIDTH-1):0] tap_Di;
    wire [(pADDR_WIDTH-1):0] tap_A;
    wire [(pDATA_WIDTH-1):0] tap_Do;

    // bram for data RAM
    wire [3:0]               data_WE;
    wire                     data_EN;
    wire [(pDATA_WIDTH-1):0] data_Di;
    wire [(pADDR_WIDTH-1):0] data_A;
    wire [(pDATA_WIDTH-1):0] data_Do;

    // AXI LITE
    wire awready;
    wire wready;
    wire awvalid;
    wire [11:0] awaddr;
    wire wvalid;
    wire [31:0] wdata;

    wire arready;
    wire rready;
    wire arvalid;
    wire [11:0] araddr;
    wire rvalid;
    wire [31:0] rdata;

    // AXI stream
    wire ss_tvalid; 
    wire [31:0] ss_tdata; 
    wire ss_tlast; 
    wire ss_tready; 

    wire sm_tready; 
    wire sm_tvalid; 
    wire [31:0] sm_tdata; 
    wire sm_tlast;

    always@(*) begin
        wbs_ack_o = 0;
        wbs_dat_o = 0;
        if(wbs_cyc_i && wbs_stb_i) begin
            if(wbs_adr_i[31:24] == 'h30) begin
                wbs_ack_o = wbs_ack_o_fir;
                wbs_dat_o = wbs_dat_o_fir;
            end
            else if(wbs_adr_i[31:24] == 'h38) begin
                wbs_ack_o = wbs_ack_o_user;
                wbs_dat_o = wbs_dat_o_user;
            end
        end
    end

    WbToUBram w_bto_userbram_u (
         .wb_clk_i(wb_clk_i),
         .wb_rst_i(wb_rst_i),
         .wbs_stb_i(wbs_stb_i),
         .wbs_cyc_i(wbs_cyc_i),
         .wbs_we_i(wbs_we_i),
         .wbs_sel_i(wbs_sel_i),
         .wbs_dat_i(wbs_dat_i),
         .wbs_adr_i(wbs_adr_i),
         .wbs_ack_o(wbs_ack_o_user),
         .wbs_dat_o(wbs_dat_o_user)

    );

    WbToAxi wbtoaxi_u (
        // WB
        .wb_clk_i(wb_clk_i),
        .wb_rst_i(wb_rst_i),
        .wbs_stb_i(wbs_stb_i),
        .wbs_cyc_i(wbs_cyc_i),
        .wbs_we_i(wbs_we_i),
        .wbs_sel_i(wbs_sel_i),
        .wbs_dat_i(wbs_dat_i),
        .wbs_adr_i(wbs_adr_i),
        .wbs_ack_o(wbs_ack_o_fir),
        .wbs_dat_o(wbs_dat_o_fir),

        // AXI LITE
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),

        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),

        // AXI stream
        .ss_tvalid(ss_tvalid), 
        .ss_tdata(ss_tdata), 
        .ss_tlast(ss_tlast), 
        .ss_tready(ss_tready), 

        .sm_tready(sm_tready), 
        .sm_tvalid(sm_tvalid), 
        .sm_tdata(sm_tdata), 
        .sm_tlast(sm_tlast)

    );

    fir fir_1(
        // AXI LITE
        .awready(awready),
        .wready(wready),
        .awvalid(awvalid),
        .awaddr(awaddr),
        .wvalid(wvalid),
        .wdata(wdata),

        .arready(arready),
        .rready(rready),
        .arvalid(arvalid),
        .araddr(araddr),
        .rvalid(rvalid),
        .rdata(rdata),

        // AXI stream
        .ss_tvalid(ss_tvalid), 
        .ss_tdata(ss_tdata), 
        .ss_tlast(ss_tlast), 
        .ss_tready(ss_tready), 

        .sm_tready(sm_tready), 
        .sm_tvalid(sm_tvalid), 
        .sm_tdata(sm_tdata), 
        .sm_tlast(sm_tlast), 
    
        // bram for tap RAM
        .tap_WE(tap_WE),
        .tap_EN(tap_EN),
        .tap_Di(tap_Di),
        .tap_A(tap_A),
        .tap_Do(tap_Do),

        // bram for data RAM
        .data_WE(data_WE),
        .data_EN(data_EN),
        .data_Di(data_Di),
        .data_A(data_A),
        .data_Do(data_Do),

        .axis_clk(wb_clk_i),
        .axis_rst_n(!wb_rst_i)
    );


    bram11 data_ram (
        .clk(wb_clk_i),
        .we(data_WE[0]),
        .re(data_EN),
        .waddr(data_A),
        .raddr(data_A),
        .wdi(data_Di),
        .rdo(data_Do)
    );

    bram11 tap_ram (
        .clk(wb_clk_i),
        .we(tap_WE[0]),
        .re(tap_EN),
        .waddr(tap_A),
        .raddr(tap_A),
        .wdi(tap_Di),
        .rdo(tap_Do)
    );

endmodule

module WbToAxi(
    // WB
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output reg [31:0] wbs_dat_o,

    // AXI LITE
    input awready,
    input wready,
    output reg awvalid,
    output reg [11:0] awaddr,
    output reg wvalid,
    output reg [31:0] wdata,

    input arready,
    output reg rready,
    output reg arvalid,
    output reg [11:0] araddr,
    input rvalid,
    input [31:0] rdata,

    // AXI stream
    output reg ss_tvalid, 
    output reg [31:0] ss_tdata, 
    output reg ss_tlast, 
    input ss_tready, 

    output reg sm_tready, 
    input sm_tvalid, 
    input [31:0] sm_tdata, 
    input sm_tlast 
);

reg wbs_ack_o;
wire fir_valid;
wire axilite;
reg hs_aw;
reg hs_w;
reg hs_ar;

assign fir_valid = (wbs_stb_i == 1 && wbs_cyc_i == 1 && wbs_adr_i[31:24] == 'h30);
assign axilite = wbs_adr_i[7] == 0;

always @(posedge wb_clk_i or posedge wb_rst_i)begin
    if(wb_rst_i)begin
        hs_aw <= 0; hs_w <= 0; hs_ar <= 0;
    end
    else begin
        hs_aw <= hs_aw; hs_w <= hs_w; hs_ar <= hs_ar;

        if(wbs_ack_o) begin
            hs_aw <= 0; hs_w <= 0; hs_ar <= 0;
        end

        if(awvalid && awready) hs_aw <= 1; // Is going to handshake
        if(wvalid && wready)   hs_w <= 1;
        if(arvalid && arready) hs_ar <= 1;

    end
end

always @(*) begin
    if(fir_valid && axilite) begin
        awvalid = (wbs_we_i && !hs_aw);
        wvalid = (wbs_we_i && !hs_w);
        awaddr = wbs_adr_i[11:0];
        wdata = wbs_dat_i;

        rready = (!wbs_we_i);
        arvalid = (!wbs_we_i && !hs_ar);
        araddr = wbs_adr_i[11:0];
    end else begin
        awvalid = 0;
        awaddr  = 0;
        wvalid  = 0;
        wdata   = 0;

        rready  = 0;
        arvalid = 0;
        araddr  = 0;
    end
end

always @(*) begin
    if(fir_valid && !axilite && wbs_adr_i[7:0] == 'h80) begin
        ss_tvalid = wbs_we_i;
        ss_tdata = wbs_dat_i;
        ss_tlast = 1;
    end else begin
        ss_tvalid = 0;
        ss_tdata = 0;
        ss_tlast = 0;
    end
end

always @(*) begin
    if(fir_valid && !axilite && wbs_adr_i[7:0] == 'h84) 
        sm_tready = 1;
    else
        sm_tready = 0;
end

// ack to wb and wbs_dat_o
always @(*) begin
    if(fir_valid && axilite)
        wbs_dat_o = rdata;
    else if(fir_valid && !axilite && wbs_adr_i[7:0] == 'h84)
        wbs_dat_o = sm_tdata;
    else 
        wbs_dat_o = 0;
end

always @(*) begin
    wbs_ack_o = ((hs_w == 1 && hs_aw == 1) || (rready == 1 && rvalid == 1) 
              || (ss_tvalid == 1 && ss_tready == 1) || (sm_tready == 1 && sm_tvalid == 1));    
end

endmodule

module WbToUBram #(
    parameter DELAYS=10
)(

    // Wishbone Slave ports (WB MI A)
    input wb_clk_i,
    input wb_rst_i,
    input wbs_stb_i,
    input wbs_cyc_i,
    input wbs_we_i,
    input [3:0] wbs_sel_i,
    input [31:0] wbs_dat_i,
    input [31:0] wbs_adr_i,
    output wbs_ack_o,
    output [31:0] wbs_dat_o

);
    wire clk;
    wire rst;

    reg [3:0] delay_count;
    reg [31:0] wbs_dat_o;
    reg user_ready;
    wire [31:0] addr;
    wire IsUserAddr;
    wire valid;
    wire [3:0] wstrb;
    wire [31:0] data_out;


    assign clk = wb_clk_i;
    assign rst = wb_rst_i;
    assign valid = wbs_cyc_i && wbs_stb_i;
    assign IsUserAddr = wbs_adr_i[31:24] == 8'h38;
    assign wbs_ack_o = user_ready;
    assign wstrb = wbs_sel_i & {4{wbs_we_i}};
    assign addr = wbs_adr_i-32'h38000000;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            wbs_dat_o <= 0;
            user_ready <= 0;
            delay_count <= 0;
        end
        else begin
            user_ready <= 0;
            if (valid && IsUserAddr && !user_ready) begin
                if (delay_count == DELAYS) begin
                    user_ready <= 1;
                    delay_count <= 0;
                    wbs_dat_o <= data_out;
                end else begin
                    delay_count <= delay_count + 1;
                    user_ready <= 0;
                end
            end
        end
    end

    bram user_bram (
        .CLK(clk),
        .WE0(wstrb),
        .EN0(valid && IsUserAddr),
        .Di0(wbs_dat_i),
        .Do0(data_out),
        .A0(addr)
    );

endmodule

`default_nettype wire
