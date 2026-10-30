`timescale 1ns/1ps
`default_nettype none
// Two physical frame banks. Writer publishes only a fully completed frame.
// req_toggle and publish_bank remain stable until acknowledgement returns.
// Banks change only at the beginning of vertical blanking. Pixel read latency=2.
module result_display #(
 parameter OUT_W=160,OUT_H=226,SCALE=4,
 parameter H_SYNC=44,H_BACK=148,H_ACTIVE=1920,H_FRONT=88,
 parameter V_SYNC=5,V_BACK=36,V_ACTIVE=1080,V_FRONT=4
)(
 input wire wr_clk,wr_en,wr_bank,
 input wire [23:0] wr_addr,wr_rgb,
 input wire pix_clk,rst_n,publish_toggle,publish_bank,force_pattern,
 output reg ack_toggle,
 output reg hsync,vsync,de,output reg [23:0] rgb,
 output reg image_valid
);
 localparam N=OUT_W*OUT_H;
 localparam WIN_X=(H_ACTIVE-OUT_W*SCALE)/2;
 localparam WIN_Y=(V_ACTIVE-OUT_H*SCALE)/2;
 (* ram_style="block" *) reg [23:0] bank0[0:N-1];
 (* ram_style="block" *) reg [23:0] bank1[0:N-1];
 always @(posedge wr_clk)if(wr_en&&wr_addr<N)begin
  if(wr_bank)bank1[wr_addr]<=wr_rgb;else bank0[wr_addr]<=wr_rgb;
 end
 (* ASYNC_REG="TRUE" *) reg [2:0] req_sync,bank_sync;
 reg display_bank;
 wire [11:0] hc,vc;
 wire hs,vs,den;
 video_timing_vtc #(.H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_ACTIVE(H_ACTIVE),.H_FRONT(H_FRONT),
  .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_ACTIVE(V_ACTIVE),.V_FRONT(V_FRONT)) timing(
  .clk(pix_clk),.rst_n(rst_n),.h_cnt(hc),.v_cnt(vc),.hsync(hs),.vsync(vs),.de(den));
 wire window_on=den&&hc>=H_SYNC+H_BACK+WIN_X&&hc<H_SYNC+H_BACK+WIN_X+OUT_W*SCALE&&
  vc>=V_SYNC+V_BACK+WIN_Y&&vc<V_SYNC+V_BACK+WIN_Y+OUT_H*SCALE;
 wire [11:0] xx=(hc-(H_SYNC+H_BACK+WIN_X))/SCALE;
 wire [11:0] yy=(vc-(V_SYNC+V_BACK+WIN_Y))/SCALE;
 wire [23:0] rd_addr=yy*OUT_W+xx;
 wire [23:0] bars=(hc<H_SYNC+H_BACK+H_ACTIVE/4)?24'hff0000:
  (hc<H_SYNC+H_BACK+H_ACTIVE/2)?24'h00ff00:
  (hc<H_SYNC+H_BACK+H_ACTIVE*3/4)?24'h0000ff:24'hffffff;
 reg [23:0] rd_addr_stage;
 reg window_stage,bank_stage,valid_stage,pattern_stage;
 reg hsync_stage,vsync_stage,de_stage;
 reg [23:0] pattern_rgb_stage;
 reg [23:0] q0,q1;
 reg delayed_window,delayed_bank,delayed_valid,delayed_pattern;
 reg [23:0] pattern_d;
 // Stage 1 breaks the timing-counter to BRAM-address path. The BRAM read and
 // stage-2 metadata registers advance together, preserving pixel alignment.
 always @(posedge pix_clk)if(window_stage)begin
  q0<=bank0[rd_addr_stage];q1<=bank1[rd_addr_stage];
 end
 always @(posedge pix_clk or negedge rst_n)begin
  if(!rst_n)begin
   req_sync<=0;bank_sync<=0;ack_toggle<=0;display_bank<=0;image_valid<=0;
   rd_addr_stage<=0;window_stage<=0;bank_stage<=0;valid_stage<=0;pattern_stage<=0;
   hsync_stage<=0;vsync_stage<=0;de_stage<=0;pattern_rgb_stage<=0;
   hsync<=0;vsync<=0;de<=0;delayed_window<=0;delayed_bank<=0;
   delayed_valid<=0;delayed_pattern<=0;pattern_d<=0;
  end else begin
   req_sync<={req_sync[1:0],publish_toggle};bank_sync<={bank_sync[1:0],publish_bank};
   if(hc==0&&vc==0&&req_sync[2]!=ack_toggle)begin
    display_bank<=bank_sync[2];image_valid<=1;ack_toggle<=req_sync[2];
   end
   rd_addr_stage<=rd_addr;window_stage<=window_on;bank_stage<=display_bank;
   valid_stage<=image_valid;pattern_stage<=force_pattern;pattern_rgb_stage<=den?bars:24'd0;
   hsync_stage<=hs;vsync_stage<=vs;de_stage<=den;
   hsync<=hsync_stage;vsync<=vsync_stage;de<=de_stage;
   delayed_window<=window_stage;delayed_bank<=bank_stage;
   delayed_valid<=valid_stage;delayed_pattern<=pattern_stage;pattern_d<=pattern_rgb_stage;
  end
 end
 always @*begin
  if(!de)rgb=0;
  else if(delayed_pattern||!delayed_valid)rgb=pattern_d;
  else if(delayed_window)rgb=delayed_bank?q1:q0;
  else rgb=0;
 end
endmodule
`default_nettype wire
