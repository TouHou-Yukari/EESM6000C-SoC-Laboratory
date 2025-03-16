module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
    output  wire                     awready,
    output  wire                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
    output  wire                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  wire                     rvalid,
    output  wire [(pDATA_WIDTH-1):0] rdata,    
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  wire                     ss_tready, 
    input   wire                     sm_tready, 
    output  wire                     sm_tvalid, 
    output  wire [(pDATA_WIDTH-1):0] sm_tdata, 
    output  wire                     sm_tlast, 
    
    // bram for tap RAM
    output  wire [3:0]               tap_WE,
    output  wire                     tap_EN,
    output  wire [(pDATA_WIDTH-1):0] tap_Di,
    output  wire [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  wire [3:0]               data_WE,
    output  wire                     data_EN,
    output  wire [(pDATA_WIDTH-1):0] data_Di,
    output  wire [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

    localparam Idle = 2'd0,
               Start = 2'd1,
               Complete = 2'd2,
               Done = 2'd3;


    reg [2:0] ap_ports;
    reg [31:0] length;
    reg [1:0] cs, ns;
    reg axil_awready;
    reg axil_read_valid;

    wire ap_start;
    wire ap_idle;
    wire ap_done;
    reg [(pDATA_WIDTH-1):0] tap_A_w;
    reg [(pADDR_WIDTH-1):0] wr_ptr_r;
    reg [(pADDR_WIDTH-1):0] rd_ptr_r;

    wire signed [(pDATA_WIDTH-1):0] mult_result;
    wire signed [(pDATA_WIDTH-1):0] mult_input;
    reg signed [(pDATA_WIDTH-1):0] FIR_temp;
    reg [(pDATA_WIDTH-1):0] out_buffer1;
    reg [(pDATA_WIDTH-1):0] out_buffer2;
    

    reg [(pDATA_WIDTH-1):0] rdata_r;
    reg [3:0] reset_cnt;
    reg signed [(pDATA_WIDTH-1):0] SS_data;
    reg [9:0] fir_data_cnt;
    reg [6:0] fir_cycle_cnt;
    wire sm_empty;
    reg data_WE_w;
    reg data_A_w;
    
    assign ap_start = ap_ports[0];
    assign ap_done = ap_ports[1];
    assign ap_idle = ap_ports[2];

    //AXI-Lite internal
    assign awready = axil_awready;
    assign wready = axil_awready;
    assign arready = ~rvalid;
    assign rvalid = axil_read_valid;
    assign rdata = (araddr < 12'h20) ? rdata_r : tap_Do;
    assign ss_tready = (cs == Start && fir_cycle_cnt == 0) ? 1'b1 : 1'b0;

    //tap_RAM internal
    assign tap_A = tap_A_w;
    assign tap_WE = (awaddr >= 12'h20 && awaddr[1:0] == 2'b00) ? {4{axil_awready}} : 4'b0000;
    assign tap_Di = wdata;
    assign tap_EN = 1'b1;
    //Data RAM internal
    assign data_WE = ((cs == Start && fir_cycle_cnt == 11) || cs == Idle) ? 4'b1111 :4'b0000;
    assign data_A = (cs == Idle) ? (reset_cnt << 2) : data_WE ? wr_ptr_r : rd_ptr_r;
    assign data_Di = SS_data;
    assign data_EN = 1'b1;

    assign mult_result = mult_input * tap_Do;
    assign mult_input = (fir_cycle_cnt == 1) ? SS_data : data_Do;
    
    assign sm_tvalid = (fir_cycle_cnt == 12) ? 1'b1:1'b0;
    assign sm_empty = (fir_data_cnt == (length-1)) && (sm_tready && sm_tvalid);
    assign sm_tdata = FIR_temp;

    always@(*) begin
      ns = cs;
      case(cs)
        Idle: begin
          if(ap_start) ns = Start;
        end
        Start:
          if(sm_empty) ns = Done;
        Done: ns = Idle;
      endcase
    end

    //移位寄存器
    always@(*)begin
      if(cs == Idle && axil_awready)
        tap_A_w = (awaddr - 12'h20);
      else if (cs == Start) 
        tap_A_w = fir_cycle_cnt << 2;
      else
        tap_A_w = (araddr - 12'h20);
    end

    //AXI_Lite write
    integer i;
    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n) begin
        ap_ports <= 3'b100;
        length <= 0;
      end
      else begin
        if(cs == Start)
          ap_ports <= 1'b0;
        else if(axil_awready) begin
          case(awaddr)
            12'h00: begin
              if(ap_idle)
                ap_ports[0] <= wdata[0];
            end 
            12'h10: length <= wdata;        
          endcase
        end
        if(ap_start)
          ap_ports[2] <= 1'b0;
        else if(cs == Idle)
          ap_ports[2] <= 1'b1;
        if((rvalid && rready) && araddr == 12'h00)
          ap_ports[1] <= 1'b0;
        else if(cs == Done)
          ap_ports[1] <= 1'b1;
      end
    end

    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n) begin
        rdata_r <= 32'd0;
      end
      else if(!rvalid || rready) begin
        case(araddr)
          12'h00: rdata_r <= {29'd0,ap_ports};
          12'h10: rdata_r <= length;
        endcase
      end
    end

    always @(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n) 
        axil_awready <= 1'b0;
      else
        axil_awready <= !axil_awready && (awvalid && wvalid);
    end


    //AXI_Lite read
    always @(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n) 
        axil_read_valid <= 1'b0;
      else if(arready && arvalid)
        axil_read_valid <= 1'b1;
      else if(rready)
        axil_read_valid <= 1'b0;
      else 
        axil_read_valid <= axil_read_valid; 
    end

    //FSM
    always @(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n) 
        cs <= 2'b00;
      else
        cs <= ns;
    end

    //FIR_cycle_count
    always @(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n)
        fir_cycle_cnt <= 0;
      else if(cs !== Start)
        fir_cycle_cnt <= 0;
      else if(!ss_tvalid && fir_cycle_cnt == 0)
        fir_cycle_cnt <= 0;
      else if(fir_cycle_cnt == 12) begin
        if(!(sm_tready && sm_tvalid))
          fir_cycle_cnt <= fir_cycle_cnt;
        else
          fir_cycle_cnt <= 0;
      end
      else    
        fir_cycle_cnt <= fir_cycle_cnt + 1;
    end


    //DATA_MEM write
    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n)
        wr_ptr_r <= 0;
      else if(cs !== Start && ns == Start)
        wr_ptr_r <= 40;
      else if(cs == Start && fir_cycle_cnt == 11) begin
        if(wr_ptr_r == 40)
          wr_ptr_r <= 0;
        else
          wr_ptr_r <= wr_ptr_r + 4;
      end 
    end

    //Data_mem read
    always@(posedge axis_clk or negedge axis_rst_n)begin
      if(!axis_rst_n)
        rd_ptr_r <= 0;
      else if(cs !== Start && ns == Start)
        rd_ptr_r <= 40;
      else if(cs == Start) begin
        if(fir_cycle_cnt == 12)
          rd_ptr_r <= wr_ptr_r;
        else begin
          if(rd_ptr_r == 0)
            rd_ptr_r <= 40;
          else
            rd_ptr_r <= rd_ptr_r - 4;
        end
      end
    end

    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n)
        SS_data <= 0;
      else if(cs == Start && fir_cycle_cnt == 0 && (ss_tvalid && ss_tready))
        SS_data <= ss_tdata;
    end

    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n)
        FIR_temp <= 32'd0;
      else if(cs == Start) begin
        if(fir_cycle_cnt == 12 && (sm_tready && sm_tvalid))
          FIR_temp <= 0;
        else if(fir_cycle_cnt > 0 && fir_cycle_cnt < 12)
          FIR_temp <= FIR_temp + mult_result; 
      end 
    end

    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n)
        fir_data_cnt <= 0;
      else if(cs == Done)
        fir_data_cnt <= 0;
      else if(fir_cycle_cnt == 12 && (sm_tready && sm_tvalid)) 
        fir_data_cnt <= fir_data_cnt + 1;
    end
    
    //DATA_MEM reset
    reg reset_done;
    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n)
        reset_cnt <= 0;
      else if(cs == Idle && reset_cnt < 12 && !reset_done)
        reset_cnt <= reset_cnt + 1;
      else
        reset_cnt <= 0;
    end

    always@(posedge axis_clk or negedge axis_rst_n) begin
      if(!axis_rst_n)
        reset_done <= 0;
      else if(cs == Done && ns == Idle)
        reset_done <= 0;
      else if(reset_cnt == 11)
        reset_done <= 1'b1;
    end

endmodule
