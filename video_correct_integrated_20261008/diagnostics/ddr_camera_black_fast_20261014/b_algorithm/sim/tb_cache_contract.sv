`timescale 1ns/1ps
module tb_cache_contract;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,iv=0,nn=0,geom=0;
reg [11:0] dx=0,dy=0;
reg signed [39:0] h[0:8];
wire rv,ri,re;wire [23:0] rt,a00,a10,a01,a11;wire [7:0] fx,fy;
reg pv=0,pi=0;reg [23:0] pt=0,p00=0,p10=0,p01=0,p11=0;reg [7:0] pfx=0,pfy=0;
wire ov;wire [23:0] rgb,ot;
perspective_core #(.SRC_W(8),.SRC_H(6)) dut(clk,rst_n,iv,nn,geom,dx,dy,
h[0],h[1],h[2],h[3],h[4],h[5],h[6],h[7],h[8],rv,ri,re,rt,a00,a10,a01,a11,fx,fy,pv,pi,pt,p00,p10,p01,p11,pfx,pfy,ov,rgb,ot);
reg [23:0] memory[0:47],expected_rgb[0:65535];
reg expected_inside[0:65535];
integer expected_fx[0:65535],expected_fy[0:65535],expected_addr[0:65535][0:3];
integer tags[0:511],due[0:511],ins[0:511],xf[0:511],yf[0:511],aa[0:511][0:3];
integer cycle=0,head=0,tail=0,sent=0,seen=0,requests=0,responses=0,last_due=0,tagidx,delay;
reg test_passed=0,hold_response=0;
function automatic [23:0] blend(input [23:0] q00,q10,q01,q11,input integer xf,yf);
integer r,g,b;
begin
r=((q00[23:16]*(256-xf)+q10[23:16]*xf)*(256-yf)+(q01[23:16]*(256-xf)+q11[23:16]*xf)*yf)>>16;
g=((q00[15:8]*(256-xf)+q10[15:8]*xf)*(256-yf)+(q01[15:8]*(256-xf)+q11[15:8]*xf)*yf)>>16;
b=((q00[7:0]*(256-xf)+q10[7:0]*xf)*(256-yf)+(q01[7:0]*(256-xf)+q11[7:0]*xf)*yf)>>16;
blend={r[7:0],g[7:0],b[7:0]};end
endfunction
always @(posedge clk)begin
cycle=cycle+1;
if(!rst_n)begin pv<=0;head=0;tail=0;last_due=0;end
else begin
 pv<=0;
 if(rv)begin
  tagidx=rt;
  if(re!==0 || ri!==expected_inside[tagidx] || fx!==expected_fx[tagidx][7:0] || fy!==expected_fy[tagidx][7:0])$fatal(1,"request metadata tag=%0d",rt);
  if(a00!==expected_addr[tagidx][0] || a10!==expected_addr[tagidx][1] || a01!==expected_addr[tagidx][2] || a11!==expected_addr[tagidx][3])$fatal(1,"request addresses tag=%0d",rt);
  tags[tail]=rt;ins[tail]=ri;xf[tail]=fx;yf[tail]=fy;aa[tail][0]=a00;aa[tail][1]=a10;aa[tail][2]=a01;aa[tail][3]=a11;
  delay=1+(requests*7)%13;due[tail]=cycle+delay;
  if(due[tail]<=last_due)due[tail]=last_due+1+((requests%11)==0);
  last_due=due[tail];tail=tail+1;requests=requests+1;
 end
 if(!hold_response && head<tail && due[head]<=cycle)begin
  pv<=1;pi<=ins[head];pt<=tags[head];pfx<=xf[head];pfy<=yf[head];
  if(ins[head])begin p00<=memory[aa[head][0]];p10<=memory[aa[head][1]];p01<=memory[aa[head][2]];p11<=memory[aa[head][3]];end
  else begin p00<=0;p10<=0;p01<=0;p11<=0;end
  head=head+1;responses=responses+1;
 end
end
#1;
if(rst_n&&ov)begin
 if(ot!==((seen/8)<<12 | (seen%8)))$fatal(1,"output order got=%0d index=%0d",ot,seen);
 if(rgb!==expected_rgb[ot])$fatal(1,"output RGB tag=%0d got=%h expected=%h",ot,rgb,expected_rgb[ot]);
 seen=seen+1;
end
end
task prepare_request(input integer i,input integer geometry);
begin
 iv=1;nn=i%2;geom=geometry;dx=i%8;dy=i/8;tagidx=(dy<<12)|dx;
 expected_inside[tagidx]=geom && (nn ? (dy+1<6) : (dx<7&&dy<5));
 expected_fx[tagidx]=expected_inside[tagidx]&&!nn?64:0;
 expected_fy[tagidx]=expected_inside[tagidx]&&!nn?128:0;
 expected_addr[tagidx][0]=expected_inside[tagidx]?(nn?(dy+1)*8+dx:dy*8+dx):0;
 expected_addr[tagidx][1]=expected_inside[tagidx]?(nn?expected_addr[tagidx][0]:dy*8+dx+1):0;
 expected_addr[tagidx][2]=expected_inside[tagidx]?(nn?expected_addr[tagidx][0]:(dy+1)*8+dx):0;
 expected_addr[tagidx][3]=expected_inside[tagidx]?(nn?expected_addr[tagidx][0]:(dy+1)*8+dx+1):0;
 expected_rgb[tagidx]=expected_inside[tagidx]?blend(memory[expected_addr[tagidx][0]],memory[expected_addr[tagidx][1]],memory[expected_addr[tagidx][2]],memory[expected_addr[tagidx][3]],expected_fx[tagidx],expected_fy[tagidx]):0;
 sent=sent+1;
end
endtask
initial begin
 for(integer i=0;i<48;i=i+1)memory[i]={8'((i%8)*13+(i/8)*7),8'((i%8)*5+(i/8)*19),8'((i%8)*17+(i/8)*3)};
 for(integer i=0;i<9;i=i+1)h[i]=0;
 h[0]=16777216;h[4]=16777216;h[8]=16777216;h[2]=4194304;h[5]=8388608;
 repeat(3)@(negedge clk);rst_n=1;
 for(integer i=0;i<48;i=i+1)begin
  @(negedge clk);prepare_request(i,i>=5);
  // First 32 requests form an uninterrupted burst longer than E22.
  if(i>=32&&i%7==6)begin @(negedge clk);iv=0;end
 end
 @(negedge clk);iv=0;repeat(200)@(negedge clk);
 if(seen!=48||requests!=48||responses!=48||sent!=48)$fatal(1,"main counts sent=%0d req=%0d rsp=%0d seen=%0d",sent,requests,responses,seen);
 // Hold responses to establish an external queue before shared reset.
 @(negedge clk);hold_response=1;sent=0;seen=0;requests=0;responses=0;
 for(integer i=0;i<10;i=i+1)begin @(negedge clk);prepare_request(i,1);end
 @(negedge clk);iv=0;repeat(30)@(negedge clk);
 if(requests!=10||tail-head!=10||responses!=0||seen!=0)$fatal(1,"reset setup did not have ten queued requests");
 @(negedge clk);rst_n=0;iv=0;geom=0;
 repeat(3)@(negedge clk);
 sent=0;seen=0;requests=0;responses=0;hold_response=0;rst_n=1;
 // A's cache queue is cleared by the same reset. No old valid may return.
 repeat(30)begin @(negedge clk);if(rv||ov||pv)$fatal(1,"stale valid after reset");end
 for(integer i=0;i<4;i=i+1)begin @(negedge clk);prepare_request(i,0);end
 @(negedge clk);iv=0;repeat(80)@(negedge clk);
 if(seen!=4||requests!=4||responses!=4||sent!=4)$fatal(1,"bootstrap counts");
 test_passed=1;
 $display("CACHE_CONTRACT_PASS main=48 reset_discarded=10 fresh_black=4 continuous_burst=32 queued_variable_delay=yes mixed_modes=yes");
 $finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
