`timescale 1ns/1ps
`default_nettype none
// 27 MHz internal raster source for the DDR processing path.
module internal_fixture_video #(
 parameter H_SYNC=44,H_BACK=148,H_ACTIVE=1920,H_FRONT=88,
 parameter V_SYNC=5,V_BACK=36,V_ACTIVE=1080,V_FRONT=4
)(
 input wire clk,reset_n,
 output wire vsync,hsync,de,
 output wire [23:0] rgb,
 output wire [11:0] raster_x,raster_y
);
 localparam H_TOTAL=H_SYNC+H_BACK+H_ACTIVE+H_FRONT;
 localparam V_TOTAL=V_SYNC+V_BACK+V_ACTIVE+V_FRONT;
 localparam X_START=H_SYNC+H_BACK;
 localparam Y_START=V_SYNC+V_BACK;
 reg [11:0] hc,vc;
 wire active=(hc>=X_START)&&(hc<X_START+H_ACTIVE)&&(vc>=Y_START)&&(vc<Y_START+V_ACTIVE);
 assign de=active;
 assign hsync=hc<H_SYNC;
 assign vsync=vc<V_SYNC;
 assign raster_x=hc-X_START;
 assign raster_y=vc-Y_START;
 wire [11:0] sx=raster_x/3;
 // ceil(raster_y*4/9), saturating the two unsampled final lines to row 479.
 wire [13:0] sy_ceil=({2'b0,raster_y,2'b00}+14'd8)/14'd9;
 wire [11:0] sy=(sy_ceil>=480)?12'd479:sy_ceil[11:0];
 wire [7:0] shade=(((sx>>5)^(sy>>5))&1'b1)?8'd200:8'd152;
 wire [23:0] gray={shade,shade,shade};
 wire marker_red=(sx>=96&&sx<=103&&sy>=56&&sy<=63);
 wire marker_green=(sx>=536&&sx<=543&&sy>=86&&sy<=93);
 wire marker_yellow=(sx>=566&&sx<=573&&sy>=416&&sy<=423);
 wire marker_blue=(sx>=66&&sx<=73&&sy>=386&&sy<=393);
 assign rgb=!active?24'd0:marker_red?24'hff0000:marker_green?24'h00ff00:
            marker_yellow?24'hffff00:marker_blue?24'h0000ff:gray;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n)begin hc<=0;vc<=0;end
  else if(hc==H_TOTAL-1)begin
   hc<=0;if(vc==V_TOTAL-1)vc<=0;else vc<=vc+1'b1;
  end else hc<=hc+1'b1;
 end
endmodule
`default_nettype wire
