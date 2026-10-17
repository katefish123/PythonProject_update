`timescale 1ns/1ps
`default_nettype none
// Captures one requested RX frame, nearest-subsamples it, and emits eight RGB888
// pixels per token/address-tagged 256-bit FIFO beat. Source memory base is word 0.
module ddr_snapshot_capture #(
 parameter IN_W=1920,IN_H=1080,SRC_W=640,SRC_H=480
)(
 input wire rx_clk,rx_rst_n,rx_vs,rx_de,
 input wire [23:0] rx_rgb,
 input wire request_toggle,
 output reg rx_complete_toggle,output reg capture_ok,
 output wire fifo_wr_en,output reg [284:0] fifo_wr_data,input wire fifo_full
);
 localparam EXPECTED_PIXELS=SRC_W*SRC_H;
 localparam EXPECTED_WORDS=EXPECTED_PIXELS/8;
 localparam X_STEP_Q=IN_W/SRC_W,X_STEP_R=IN_W%SRC_W;
 localparam Y_STEP_Q=IN_H/SRC_H,Y_STEP_R=IN_H%SRC_H;
 (* ASYNC_REG="TRUE" *) reg [2:0] request_sync;
 reg vs_d,de_d,active,frame_bad,fifo_overflow;
 reg active_token;
 reg [12:0] x_count,x_next,y_line_count,y_next;
 reg [12:0] x_remainder,y_remainder;
 reg [23:0] sampled_pixels;
 reg [27:0] packet_word_addr;
 reg [2:0] pack_count;
 reg [255:0] pixel_pack;
 reg packet_pending,finish_pending,finish_candidate,finish_token;
 wire vs_rise=rx_vs&&!vs_d;
 assign fifo_wr_en=packet_pending;
 reg [255:0] assembled_pixels;
 always @*begin
  assembled_pixels=pixel_pack;
  case(pack_count)
   3'd0:assembled_pixels[31:0]={8'd0,rx_rgb};
   3'd1:assembled_pixels[63:32]={8'd0,rx_rgb};
   3'd2:assembled_pixels[95:64]={8'd0,rx_rgb};
   3'd3:assembled_pixels[127:96]={8'd0,rx_rgb};
   3'd4:assembled_pixels[159:128]={8'd0,rx_rgb};
   3'd5:assembled_pixels[191:160]={8'd0,rx_rgb};
   3'd6:assembled_pixels[223:192]={8'd0,rx_rgb};
   3'd7:assembled_pixels[255:224]={8'd0,rx_rgb};
  endcase
 end
 always @(posedge rx_clk or negedge rx_rst_n)begin
  if(!rx_rst_n)begin
   request_sync<=0;rx_complete_toggle<=0;capture_ok<=0;vs_d<=0;de_d<=0;
   active<=0;active_token<=0;frame_bad<=0;fifo_overflow<=0;
   x_count<=0;x_next<=0;y_line_count<=0;y_next<=0;x_remainder<=0;y_remainder<=0;
   sampled_pixels<=0;packet_word_addr<=0;pack_count<=0;pixel_pack<=0;
   packet_pending<=0;fifo_wr_data<=0;finish_pending<=0;finish_candidate<=0;finish_token<=0;
  end else begin
   request_sync<={request_sync[1:0],request_toggle};vs_d<=rx_vs;de_d<=rx_de;
   if(packet_pending)begin
    packet_pending<=0;
    if(fifo_full)fifo_overflow<=1;
   end
   if(vs_rise)begin
    if(active)begin
     active<=0;finish_pending<=1;finish_token<=active_token;
     finish_candidate<=!frame_bad&&(y_line_count==IN_H)&&!rx_de&&
       (x_count==0)&&(sampled_pixels==EXPECTED_PIXELS)&&
       (packet_word_addr==EXPECTED_PIXELS)&&(pack_count==0);
    end else if(request_sync[2]!=rx_complete_toggle)begin
     active<=1;active_token<=request_sync[2];frame_bad<=0;fifo_overflow<=0;
     x_count<=0;x_next<=0;y_line_count<=0;y_next<=0;x_remainder<=0;y_remainder<=0;
     sampled_pixels<=0;packet_word_addr<=0;pack_count<=0;pixel_pack<=0;
    end
   end else if(active)begin
    if(rx_de)begin
     if(x_count>=IN_W)frame_bad<=1;
     else if(y_line_count>=IN_H)frame_bad<=1;
     if((x_count==x_next)&&(y_line_count==y_next)&&x_count<IN_W&&y_line_count<IN_H)begin
      sampled_pixels<=sampled_pixels+1'b1;
      if(pack_count==3'd7)begin
       if(!fifo_overflow)begin
        fifo_wr_data<={active_token,packet_word_addr,assembled_pixels};
        packet_pending<=1;
       end
       packet_word_addr<=packet_word_addr+8'd8;
       pack_count<=0;pixel_pack<=0;
      end else begin pixel_pack<=assembled_pixels;pack_count<=pack_count+1'b1;end
      begin : advance_x
       reg [13:0] sum;
       sum=x_remainder+X_STEP_R;
       x_next<=x_next+X_STEP_Q+((sum>=SRC_W)?1:0);
       x_remainder<=sum-((sum>=SRC_W)?SRC_W:0);
      end
     end
     x_count<=x_count+1'b1;
    end
    if(de_d&&!rx_de)begin
     if(x_count!=IN_W)frame_bad<=1;
     if(y_line_count>=IN_H)frame_bad<=1;
     y_line_count<=y_line_count+1'b1;
     x_count<=0;x_next<=0;x_remainder<=0;
     if(y_line_count==y_next)begin
      begin : advance_y
       reg [13:0] sum;
       sum=y_remainder+Y_STEP_R;
       y_next<=y_next+Y_STEP_Q+((sum>=SRC_H)?1:0);
       y_remainder<=sum-((sum>=SRC_H)?SRC_H:0);
      end
     end
    end
   end
   if(finish_pending&&!packet_pending)begin
    rx_complete_toggle<=finish_token;
    capture_ok<=finish_candidate&&!frame_bad&&!fifo_overflow;
    finish_pending<=0;
   end
  end
 end
endmodule
`default_nettype wire

