// RGB888 black-marker centroids, one configurable ROI per corner.
// Coordinates supplied by the caller; black pixels outside all ROIs are ignored.
// frame_start/end may coincide with first/last valid pixel (included).
module marker_detector #(
 parameter SRC_W=640,SRC_H=480, MIN_PIXELS=16,MAX_PIXELS=4096,MAX_SPAN=128,
 parameter BLACK_RMIN=0,BLACK_RMAX=64,BLACK_GMIN=0,BLACK_GMAX=64,BLACK_BMIN=0,BLACK_BMAX=64,
 // Inclusive, non-overlapping windows in source coordinates; P0/P1/P2/P3 = TL/TR/BR/BL.
 // Integer division places the center column/row of an odd source in right/bottom ROIs.
 parameter P0_XMIN=0,P0_XMAX=SRC_W/2-1,P0_YMIN=0,P0_YMAX=SRC_H/2-1,
 parameter P1_XMIN=SRC_W/2,P1_XMAX=SRC_W-1,P1_YMIN=0,P1_YMAX=SRC_H/2-1,
 parameter P2_XMIN=SRC_W/2,P2_XMAX=SRC_W-1,P2_YMIN=SRC_H/2,P2_YMAX=SRC_H-1,
 parameter P3_XMIN=0,P3_XMAX=SRC_W/2-1,P3_YMIN=SRC_H/2,P3_YMAX=SRC_H-1
)(
 input wire clk,rst_n,pixel_valid,frame_start,frame_end,
 input wire [11:0] pixel_x,pixel_y,
 input wire [23:0] rgb,
 output reg corners_valid,frame_reject,frame_dropped,
 output wire busy,
 output reg [11:0] x0,y0,x1,y1,x2,y2,x3,y3
);
 wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
 // Reject an invalid static configuration at frame_end even with no black pixels.
 localparam BLACK_VALID=(BLACK_RMIN>=0&&BLACK_RMIN<=BLACK_RMAX&&BLACK_RMAX<=255)
  &&(BLACK_GMIN>=0&&BLACK_GMIN<=BLACK_GMAX&&BLACK_GMAX<=255)
  &&(BLACK_BMIN>=0&&BLACK_BMIN<=BLACK_BMAX&&BLACK_BMAX<=255);
 localparam SOURCE_VALID=SRC_W>=2&&SRC_W<=4096&&SRC_H>=2&&SRC_H<=4096;
 localparam STATS_VALID=MIN_PIXELS>=1&&MIN_PIXELS<=MAX_PIXELS&&MAX_PIXELS<=16777216
  &&MAX_SPAN>=0&&MAX_SPAN<=4095;
 localparam P0_VALID=P0_XMIN>=0&&P0_XMIN<=P0_XMAX&&P0_XMAX<SRC_W
  &&P0_YMIN>=0&&P0_YMIN<=P0_YMAX&&P0_YMAX<SRC_H;
 localparam P1_VALID=P1_XMIN>=0&&P1_XMIN<=P1_XMAX&&P1_XMAX<SRC_W
  &&P1_YMIN>=0&&P1_YMIN<=P1_YMAX&&P1_YMAX<SRC_H;
 localparam P2_VALID=P2_XMIN>=0&&P2_XMIN<=P2_XMAX&&P2_XMAX<SRC_W
  &&P2_YMIN>=0&&P2_YMIN<=P2_YMAX&&P2_YMAX<SRC_H;
 localparam P3_VALID=P3_XMIN>=0&&P3_XMIN<=P3_XMAX&&P3_XMAX<SRC_W
  &&P3_YMIN>=0&&P3_YMIN<=P3_YMAX&&P3_YMAX<SRC_H;
 localparam P01_DISJOINT=P0_XMAX<P1_XMIN||P1_XMAX<P0_XMIN||P0_YMAX<P1_YMIN||P1_YMAX<P0_YMIN;
 localparam P02_DISJOINT=P0_XMAX<P2_XMIN||P2_XMAX<P0_XMIN||P0_YMAX<P2_YMIN||P2_YMAX<P0_YMIN;
 localparam P03_DISJOINT=P0_XMAX<P3_XMIN||P3_XMAX<P0_XMIN||P0_YMAX<P3_YMIN||P3_YMAX<P0_YMIN;
 localparam P12_DISJOINT=P1_XMAX<P2_XMIN||P2_XMAX<P1_XMIN||P1_YMAX<P2_YMIN||P2_YMAX<P1_YMIN;
 localparam P13_DISJOINT=P1_XMAX<P3_XMIN||P3_XMAX<P1_XMIN||P1_YMAX<P3_YMIN||P3_YMAX<P1_YMIN;
 localparam P23_DISJOINT=P2_XMAX<P3_XMIN||P3_XMAX<P2_XMIN||P2_YMAX<P3_YMIN||P3_YMAX<P2_YMIN;
 localparam CONFIG_VALID=BLACK_VALID&&SOURCE_VALID&&STATS_VALID&&P0_VALID&&P1_VALID&&P2_VALID&&P3_VALID
  &&P01_DISJOINT&&P02_DISJOINT&&P03_DISJOINT&&P12_DISJOINT&&P13_DISJOINT&&P23_DISJOINT;
 wire black=r>=BLACK_RMIN&&r<=BLACK_RMAX&&g>=BLACK_GMIN&&g<=BLACK_GMAX&&b>=BLACK_BMIN&&b<=BLACK_BMAX;
 wire [3:0] hit;
 assign hit[0]=black&&pixel_x>=P0_XMIN&&pixel_x<=P0_XMAX&&pixel_y>=P0_YMIN&&pixel_y<=P0_YMAX;
 assign hit[1]=black&&pixel_x>=P1_XMIN&&pixel_x<=P1_XMAX&&pixel_y>=P1_YMIN&&pixel_y<=P1_YMAX;
 assign hit[2]=black&&pixel_x>=P2_XMIN&&pixel_x<=P2_XMAX&&pixel_y>=P2_YMIN&&pixel_y<=P2_YMAX;
 assign hit[3]=black&&pixel_x>=P3_XMIN&&pixel_x<=P3_XMAX&&pixel_y>=P3_YMIN&&pixel_y<=P3_YMAX;
 reg [39:0] sx[0:3],sy[0:3],nsx[0:3],nsy[0:3],snapx[0:3],snapy[0:3];
 reg [24:0] count[0:3],nc[0:3],snapn[0:3];
 reg [11:0] xmin[0:3],xmax[0:3],ymin[0:3],ymax[0:3];
 reg [11:0] nxmin[0:3],nxmax[0:3],nymin[0:3],nymax[0:3];
 reg [11:0] cx[0:3],cy[0:3];
 reg active,bad,nbad;
 reg [1:0] state;
 integer i,k,j;
 reg [2:0] component;
 reg div_start;
 reg [39:0] div_n,div_d;
 wire div_busy,div_done,div_error;
 wire [39:0] div_q;
 unsigned_div_seq #(.WIDTH(40)) u_div(clk,rst_n,div_start,div_n,div_d,div_busy,div_done,div_error,div_q);
 assign busy=state!=0;
 always @* begin
  nbad=frame_start ? !CONFIG_VALID : bad;
  if(pixel_valid && (frame_start||active) && (pixel_x>=SRC_W||pixel_y>=SRC_H)) nbad=1;
  // Also guard against ambiguous hits; a legal ROI configuration cannot produce them.
  if(pixel_valid && (frame_start||active) && (hit!=0) && ((hit & (hit-4'b0001))!=0)) nbad=1;
  for(k=0;k<4;k=k+1) begin
   nsx[k]=frame_start?40'd0:sx[k];nsy[k]=frame_start?40'd0:sy[k];nc[k]=frame_start?25'd0:count[k];
   nxmin[k]=frame_start?12'd4095:xmin[k];nxmax[k]=frame_start?12'd0:xmax[k];
   nymin[k]=frame_start?12'd4095:ymin[k];nymax[k]=frame_start?12'd0:ymax[k];
   if(pixel_valid&&(frame_start||active)&&hit[k]&&pixel_x<SRC_W&&pixel_y<SRC_H) begin
    // Saturate counts/sums after max threshold; frame will be rejected.
    if(nc[k]<=MAX_PIXELS) begin
     nsx[k]=nsx[k]+pixel_x;nsy[k]=nsy[k]+pixel_y;nc[k]=nc[k]+1'b1;
    end
    if(pixel_x<nxmin[k]) nxmin[k]=pixel_x;
    if(pixel_x>nxmax[k]) nxmax[k]=pixel_x;
    if(pixel_y<nymin[k]) nymin[k]=pixel_y;
    if(pixel_y>nymax[k]) nymax[k]=pixel_y;
   end
  end
 end
 reg good;
 always @* begin
  good=CONFIG_VALID&&!nbad;
  for(j=0;j<4;j=j+1)
   if(nc[j]<MIN_PIXELS||nc[j]>MAX_PIXELS||(nxmax[j]-nxmin[j])>MAX_SPAN||(nymax[j]-nymin[j])>MAX_SPAN) good=0;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=0;active<=0;bad<=0;corners_valid<=0;frame_reject<=0;frame_dropped<=0;
   div_start<=0;div_n<=0;div_d<=1;component<=0;x0<=0;y0<=0;x1<=0;y1<=0;x2<=0;y2<=0;x3<=0;y3<=0;
   for(i=0;i<4;i=i+1) begin
    sx[i]<=0;sy[i]<=0;count[i]<=0;xmin[i]<=4095;xmax[i]<=0;ymin[i]<=4095;ymax[i]<=0;
    snapx[i]<=0;snapy[i]<=0;snapn[i]<=0;cx[i]<=0;cy[i]<=0;
   end
  end else begin
   corners_valid<=0;frame_reject<=0;frame_dropped<=0;div_start<=0;
   if(frame_start) active<=1;
   if(frame_end) active<=0;
   bad<=nbad;
   for(i=0;i<4;i=i+1) begin
    sx[i]<=nsx[i];sy[i]<=nsy[i];count[i]<=nc[i];
    xmin[i]<=nxmin[i];xmax[i]<=nxmax[i];ymin[i]<=nymin[i];ymax[i]<=nymax[i];
   end
   if(frame_end) begin
    if(state!=0) frame_dropped<=1;
    else if(!(frame_start||active)||!good) frame_reject<=1;
    else begin
     for(i=0;i<4;i=i+1) begin snapx[i]<=nsx[i];snapy[i]<=nsy[i];snapn[i]<=nc[i];end
     component<=0;state<=1;
    end
   end
   case(state)
    1: begin
     div_n<=(component[0]==1'b0 ? snapx[component[2:1]] : snapy[component[2:1]]) + (snapn[component[2:1]]>>1);
     div_d<=snapn[component[2:1]];div_start<=1;state<=2;
    end
    2: if(div_done) begin
     if(div_error) begin frame_reject<=1;state<=0;end
     else begin
      if(component[0]==1'b0) cx[component[2:1]]<=div_q[11:0];else cy[component[2:1]]<=div_q[11:0];
      if(component==7) state<=3;else begin component<=component+1;state<=1;end
     end
    end
    3: begin
     x0<=cx[0];y0<=cy[0];x1<=cx[1];y1<=cy[1];x2<=cx[2];y2<=cy[2];x3<=cx[3];y3<=cy[3];
     corners_valid<=1;state<=0;
    end
   endcase
  end
 end
endmodule
