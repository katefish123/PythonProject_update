`timescale 1ns/1ps
`default_nettype none
// Independent, downsampled optical preview. Published banks are immutable until
// the display acknowledges a swap at vertical blanking. Never uses source DDR.
module rx_preview #(
 parameter IN_W=1920,IN_H=1080,DECIMATE=8,
 parameter PW=IN_W/DECIMATE,PH=IN_H/DECIMATE
)(input wire rx_clk,rx_rst_n,rx_vs,rx_de,input wire[23:0]rx_rgb,
 input wire pix_clk,pix_rst_n,scan_de,scan_start,
 input wire[11:0]scan_x,scan_y,
 output reg[23:0]rgb,output reg valid,
 output reg[12:0]observed_width,observed_height,output reg bad_frame);
 localparam N=PW*PH;
 (* syn_ramstyle="block_ram" *) reg[23:0]bank0[0:N-1];
 (* syn_ramstyle="block_ram" *) reg[23:0]bank1[0:N-1];
 wire link_reset=rx_rst_n&&pix_rst_n;
 (* ASYNC_REG="TRUE" *)reg[1:0]rx_reset_pipe,pix_reset_pipe;
 always @(posedge rx_clk or negedge link_reset)begin
  if(!link_reset)rx_reset_pipe<=0;else rx_reset_pipe<={rx_reset_pipe[0],1'b1};
 end
 always @(posedge pix_clk or negedge link_reset)begin
  if(!link_reset)pix_reset_pipe<=0;else pix_reset_pipe<={pix_reset_pipe[0],1'b1};
 end
 wire rx_local_rst_n=rx_reset_pipe[1],pix_local_rst_n=pix_reset_pipe[1];
 (* ASYNC_REG="TRUE" *)reg[2:0]ack_rx,pub_pix;
 reg pub_toggle,ack_toggle,display_bank;
 reg vs_d,de_d,active,bad;reg[12:0]x,y,max_width;
 reg[23:0]count;
 wire sample=active&&rx_de&&x<IN_W&&y<IN_H&&x%DECIMATE==0&&y%DECIMATE==0&&count<N;
 always @(posedge rx_clk)if(sample)begin
  if(!pub_toggle)bank1[count]<=rx_rgb;else bank0[count]<=rx_rgb;
 end
 always @(posedge rx_clk or negedge rx_local_rst_n)begin
  if(!rx_local_rst_n)begin ack_rx<=0;pub_toggle<=0;vs_d<=0;de_d<=0;active<=0;bad<=0;x<=0;y<=0;count<=0;max_width<=0;observed_width<=0;observed_height<=0;bad_frame<=0;end
  else begin
   ack_rx<={ack_rx[1:0],ack_toggle};vs_d<=rx_vs;de_d<=rx_de;
   if(rx_vs&&!vs_d)begin
    if(active)begin
     active<=0;observed_width<=max_width;observed_height<=y;
     bad_frame<=bad||y!=IN_H||x!=0||rx_de||count!=N;
     if(!bad&&y==IN_H&&x==0&&!rx_de&&count==N)begin pub_toggle<=~pub_toggle;end
    end else if(pub_toggle==ack_rx[2])begin active<=1;bad<=0;x<=0;y<=0;count<=0;max_width<=0;end
   end else if(active)begin
    if(rx_de)begin x<=x+1'b1;if(x>=IN_W||y>=IN_H)bad<=1;if(sample)count<=count+1'b1;end
    if(de_d&&!rx_de)begin if(x!=IN_W)bad<=1;if(x>max_width)max_width<=x;x<=0;y<=y+1'b1;end
   end
  end
 end
 wire[23:0]read_addr=(scan_y/DECIMATE)*PW+scan_x/DECIMATE;
 always @(posedge pix_clk)begin
  if(scan_de&&valid&&read_addr<N)begin if(display_bank)rgb<=bank1[read_addr];else rgb<=bank0[read_addr];end
  else rgb<=0;
 end
 always @(posedge pix_clk or negedge pix_local_rst_n)begin
  if(!pix_local_rst_n)begin pub_pix<=0;ack_toggle<=0;display_bank<=0;valid<=0;end
  else begin
   pub_pix<={pub_pix[1:0],pub_toggle};
   if(scan_start&&pub_pix[2]!=ack_toggle)begin display_bank<=pub_pix[2];valid<=1;ack_toggle<=pub_pix[2];end
  end
 end
endmodule
`default_nettype wire
