`timescale 1ns/1ps
module ms72xx_shared_config #(parameter TX_FIRST=0)(input cfg_clk,reset_n,output rx_done,tx_done,scl,output reg rx_scratch_ok,output reg [31:0] rx_status,output reg [15:0] rx_status_reads,output reg [7:0] rx_pixel_config,output reg rx_pixel_config_valid,inout sda);
wire [7:0] rx_id,tx_id,rx_data,tx_data,read_data;
wire [15:0] rx_addr,tx_addr;
wire rx_trig,tx_trig,rx_wr,tx_wr,busy,byte_done,sda_out,sda_en;
wire select_tx=TX_FIRST ? !tx_done : (rx_done && !tx_done);
ms7200_ctl rx(.clk(cfg_clk),.rstn(reset_n && (!TX_FIRST || tx_done)),.init_over(rx_done),.device_id(rx_id),.iic_trig(rx_trig),.w_r(rx_wr),.addr(rx_addr),.data_in(rx_data),.busy(select_tx ? 1'b0 : busy),.data_out(select_tx ? 8'd0 : read_data),.byte_over(select_tx ? 1'b0 : byte_done));
ms7210_ctl tx(.clk(cfg_clk),.rstn(reset_n && (TX_FIRST || rx_done)),.init_over(tx_done),.device_id(tx_id),.iic_trig(tx_trig),.w_r(tx_wr),.addr(tx_addr),.data_in(tx_data),.busy(select_tx ? busy : 1'b0),.data_out(select_tx ? read_data : 8'd0),.byte_over(select_tx ? byte_done : 1'b0));
iic_dri #(.CLK_FRE(27'd10000000),.IIC_FREQ(20'd400000),.T_WR(10'd1),.ADDR_BYTE(2'd2),.LEN_WIDTH(8'd3),.DATA_BYTE(2'd1)) bus_driver(
.clk(cfg_clk),.rstn(reset_n),.pluse(select_tx ? tx_trig : rx_trig),.device_id(select_tx ? tx_id : rx_id),.w_r(select_tx ? tx_wr : rx_wr),.byte_len(4'd1),.addr(select_tx ? tx_addr : rx_addr),.data_in(select_tx ? tx_data : rx_data),.busy(busy),.byte_over(byte_done),.data_out(read_data),.scl(scl),.sda_in(sda),.sda_out(sda_out),.sda_out_en(sda_en));
always @(posedge cfg_clk or negedge reset_n) begin
 if(!reset_n) rx_scratch_ok<=0;
 else if(!select_tx && !rx_wr && rx_addr==16'h0003 && byte_done && read_data==8'h5a) rx_scratch_ok<=1;
end
always @(posedge cfg_clk or negedge reset_n)begin
 if(!reset_n)begin rx_status<=0;rx_status_reads<=0;rx_pixel_config<=0;rx_pixel_config_valid<=0;end
 else if(!select_tx && !rx_wr && byte_done)begin
  case(rx_addr)
   16'h209c:rx_status[7:0]<=read_data;
   16'h209d:rx_status[15:8]<=read_data;
   16'h209e:begin rx_status[23:16]<=read_data;rx_status_reads<=rx_status_reads+1'b1;end
   16'h209f:rx_status[31:24]<=read_data;
   16'h1281:begin rx_pixel_config<=read_data;rx_pixel_config_valid<=1;end
  endcase
 end
end
assign sda=sda_en ? sda_out : 1'bz;
endmodule
