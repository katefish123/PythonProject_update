`timescale 1ns/1ps
`include "examples/r50_18mm_calibration.vh"
// The leaf has ten register stages: input E0, output E9 (nine edge intervals).
module tb_lens_distort_coord;
 localparam integer TAG_W=26, STAGES=10, MAX_VECTORS=100000;
 reg clk=0; always #5 clk=~clk;
 reg rst_n=0,in_valid=0,in_error=0;
 reg [19:0] in_x=0,in_y=0;
 reg [TAG_W-1:0] in_tag=0;
 wire out_valid,out_error,zero_valid,zero_error,disabled_valid,disabled_error;
 wire signed [39:0] out_x,out_y,zero_x,zero_y,disabled_x,disabled_y;
 wire [TAG_W-1:0] out_tag,zero_tag,disabled_tag;
 reg test_passed=0;
 // Quantized from calibration/r50_18mm_hdmi_trial.json, nearest/ties away.
 lens_distort_coord #(.TAG_W(TAG_W),
  .FX_Q16(`LENS_FX_Q16),.FY_Q16(`LENS_FY_Q16),
  .CX_Q16(`LENS_CX_Q16),.CY_Q16(`LENS_CY_Q16),
  .INV_FX_Q30(`LENS_INV_FX_Q30),.INV_FY_Q30(`LENS_INV_FY_Q30),
  .K1_Q26(`LENS_K1_Q26),.K2_Q26(`LENS_K2_Q26),
  .P1_Q26(`LENS_P1_Q26),.P2_Q26(`LENS_P2_Q26)) dut (
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_error(in_error),
  .in_x(in_x),.in_y(in_y),.in_tag(in_tag),.out_valid(out_valid),
  .out_error(out_error),.out_x(out_x),.out_y(out_y),.out_tag(out_tag));
 // Deliberately tiny focal lengths would reject many inputs if bypass did math.
 lens_distort_coord #(.TAG_W(TAG_W),.FX_Q16(32'sd65536),
  .FY_Q16(32'sd65536),.INV_FX_Q30(32'sd1073741824),
  .INV_FY_Q30(32'sd1073741824)) zero_distortion (
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_error(in_error),
  .in_x(in_x),.in_y(in_y),.in_tag(in_tag),.out_valid(zero_valid),
  .out_error(zero_error),.out_x(zero_x),.out_y(zero_y),.out_tag(zero_tag));
 lens_distort_coord #(.ENABLE(0),.TAG_W(TAG_W),.K1_Q26(32'sd134217728),
  .K2_Q26(-32'sd134217728),.P1_Q26(32'sd134217728),
  .P2_Q26(-32'sd134217728)) disabled (
  .clk(clk),.rst_n(rst_n),.in_valid(in_valid),.in_error(in_error),
  .in_x(in_x),.in_y(in_y),.in_tag(in_tag),.out_valid(disabled_valid),
  .out_error(disabled_error),.out_x(disabled_x),.out_y(disabled_y),.out_tag(disabled_tag));

 reg expected_error_in=0;
 reg signed [39:0] expected_x_in=0,expected_y_in=0;
 reg pv[0:STAGES-1],pe[0:STAGES-1],be[0:STAGES-1];
 reg signed [39:0] px[0:STAGES-1],py[0:STAGES-1],bx[0:STAGES-1],by[0:STAGES-1];
 reg [TAG_W-1:0] pt[0:STAGES-1];
 integer accepted_cycle[0:STAGES-1];
 integer cycle=0,seen=0,sent=0,flushed=0,i;
 always @(posedge clk) begin
  cycle=cycle+1;
  if(!rst_n) begin
   for(i=0;i<STAGES;i=i+1) begin
    pv[i]=0;pe[i]=0;be[i]=0;px[i]=0;py[i]=0;bx[i]=0;by[i]=0;pt[i]=0;accepted_cycle[i]=0;
   end
  end else begin
   for(i=STAGES-1;i>0;i=i-1) begin
    pv[i]=pv[i-1];pe[i]=pe[i-1];be[i]=be[i-1];
    px[i]=px[i-1];py[i]=py[i-1];bx[i]=bx[i-1];by[i]=by[i-1];
    pt[i]=pt[i-1];accepted_cycle[i]=accepted_cycle[i-1];
   end
   pv[0]=in_valid;pe[0]=expected_error_in;be[0]=in_error;
   px[0]=expected_x_in;py[0]=expected_y_in;
   bx[0]=in_error?40'sd0:$signed({20'd0,in_x});
   by[0]=in_error?40'sd0:$signed({20'd0,in_y});
   pt[0]=in_tag;accepted_cycle[0]=cycle;
   if(in_valid)sent=sent+1;
  end
  #1;
  if(out_valid!==pv[STAGES-1]||zero_valid!==pv[STAGES-1]||disabled_valid!==pv[STAGES-1])
   $fatal(1,"LENS valid/flush mismatch cycle=%0d exp=%0b actual=%0b,%0b,%0b",cycle,pv[STAGES-1],out_valid,zero_valid,disabled_valid);
  if(rst_n&&out_valid)begin
   if(out_tag!==pt[STAGES-1]||out_error!==pe[STAGES-1]||out_x!==px[STAGES-1]||out_y!==py[STAGES-1])
    $fatal(1,"LENS mismatch tag=%0d/%0d actual=%0d,%0d,%0b expected=%0d,%0d,%0b",out_tag,pt[STAGES-1],out_x,out_y,out_error,px[STAGES-1],py[STAGES-1],pe[STAGES-1]);
   if(zero_tag!==pt[STAGES-1]||disabled_tag!==pt[STAGES-1]||zero_error!==be[STAGES-1]||disabled_error!==be[STAGES-1]||
      zero_x!==bx[STAGES-1]||zero_y!==by[STAGES-1]||disabled_x!==bx[STAGES-1]||disabled_y!==by[STAGES-1])
    $fatal(1,"LENS exact bypass mismatch tag=%0d",pt[STAGES-1]);
   if(cycle-accepted_cycle[STAGES-1]!=STAGES-1)$fatal(1,"LENS latency mismatch");
   seen=seen+1;
  end
 end

 integer f,n,rows=0,tag_value,u_value,v_value,inerr_value,err_value,gaps;
 reg signed [39:0] sx_value,sy_value;
 reg [31:0] rng=32'h1865b4c3;
 reg [1023:0] vector_path;
 integer first_tag,first_u,first_v,first_inerr,first_err;
 reg signed [39:0] first_sx,first_sy;
 initial begin
  if(!$value$plusargs("VECTORS=%s",vector_path))vector_path="vectors/lens_coord.txt";
  f=$fopen(vector_path,"r");if(!f)$fatal(1,"missing lens vectors: %0s",vector_path);
  repeat(3)@(negedge clk);rst_n=1;
  while(!$feof(f))begin
   n=$fscanf(f,"%d %d %d %d %d %d %d\n",tag_value,u_value,v_value,inerr_value,err_value,sx_value,sy_value);
   if(n==7)begin
    if(u_value<0||u_value>1048575||v_value<0||v_value>1048575||tag_value<0||tag_value>67108863)
     $fatal(1,"vector input outside port range");
    if(rows==0)begin
     first_tag=tag_value;first_u=u_value;first_v=v_value;first_inerr=inerr_value;
     first_err=err_value;first_sx=sx_value;first_sy=sy_value;
    end
    rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
    // Begin with uninterrupted traffic, then introduce deterministic random gaps.
    gaps=(rows<128)?0:rng[2:1];
    repeat(gaps)begin @(negedge clk);in_valid=0;end
    @(negedge clk);in_valid=1;in_x=u_value;in_y=v_value;in_tag=tag_value;in_error=inerr_value;
    expected_error_in=err_value;expected_x_in=sx_value;expected_y_in=sy_value;
    rows=rows+1;if(rows>MAX_VECTORS)$fatal(1,"too many lens vectors");
   end else if(n!=-1&&n!=0)$fatal(1,"malformed lens vector: %0d fields",n);
  end
  $fclose(f);
  @(negedge clk);in_valid=0;repeat(STAGES+2)@(negedge clk);
  if(rows<10||seen!=rows)$fatal(1,"LENS initial count rows=%0d seen=%0d",rows,seen);
  // Five numerical errors remain in flight when reset is asserted; all flush.
  repeat(5)begin
   @(negedge clk);in_valid=1;in_error=1;in_x=1048575;in_y=1048575;
   in_tag=in_tag+1;expected_error_in=1;expected_x_in=0;expected_y_in=0;
  end
  @(negedge clk);rst_n=0;in_valid=0;flushed=5;
  repeat(3)@(negedge clk);rst_n=1;
  repeat(STAGES+2)@(negedge clk);
  // A normal vector after reset proves the pipeline restarts with the same latency.
  in_valid=1;in_x=first_u;in_y=first_v;in_tag=first_tag;in_error=first_inerr;
  expected_error_in=first_err;expected_x_in=first_sx;expected_y_in=first_sy;
  @(negedge clk);in_valid=0;repeat(STAGES+2)@(negedge clk);
  if(seen!=sent-flushed)$fatal(1,"LENS final count seen=%0d sent=%0d flushed=%0d",seen,sent,flushed);
  test_passed=1;$display("LENS_COORD_PASS vectors=%0d returned=%0d stages=%0d",rows,seen,STAGES);$finish;
 end
 initial begin #20000000;$fatal(1,"LENS timeout");end
endmodule
