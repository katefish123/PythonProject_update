`timescale 1ns/1ps
module tb_div_equivalence;
 reg clk=0,rst_n=0,start=0;always #5 clk=~clk;
 reg[1:0]op=0;reg signed[63:0]a=0,b=0;
 wire old_ready,old_done,old_error,fast_ready,fast_done,fast_error;
 wire signed[63:0]old_value,fast_value;
 q30_alu reference(.clk(clk),.rst_n(rst_n),.start(start),.op(op),.a(a),.b(b),.ready(old_ready),.done(old_done),.error(old_error),.value(old_value));
 q30_alu_fast candidate(.clk(clk),.rst_n(rst_n),.start(start),.op(op),.a(a),.b(b),.ready(fast_ready),.done(fast_done),.error(fast_error),.value(fast_value));
 integer count=0,max_fast_div=0,old_cycles=0,new_cycles=0;
 reg[63:0]random_state=64'h12345678abcdef01;
 function[63:0]next_random(input[63:0]x);reg[63:0]v;begin v=x^(x<<13);v=v^(v>>7);next_random=v^(v<<17);end endfunction
 task check(input[1:0]o,input signed[63:0]x,y);
 reg got_old,got_fast,bad_old,bad_fast;reg signed[63:0]v_old,v_fast;integer cycles,fc,oc;
 begin
 @(negedge clk);if(!old_ready||!fast_ready)$fatal(1,"overlap test request");op=o;a=x;b=y;start=1;
 @(negedge clk);start=0;got_old=0;got_fast=0;cycles=0;fc=0;oc=0;
 while(!got_old||!got_fast)begin
 if(old_done&&!got_old)begin got_old=1;bad_old=old_error;v_old=old_value;oc=cycles;end
 if(fast_done&&!got_fast)begin got_fast=1;bad_fast=fast_error;v_fast=fast_value;fc=cycles;end
 @(negedge clk);cycles++;if(cycles>140)$fatal(1,"division timeout");
 end
 if(bad_old!==bad_fast||v_old!==v_fast)$fatal(1,"division equivalence op%0d a=%h b=%h old=%h/%b fast=%h/%b",o,x,y,v_old,bad_old,v_fast,bad_fast);
 if(o==2)begin
 if(fc>66)$fatal(1,"FAST_DIV_STILL_ITERATES_UNNEEDED_BITS cycles=%0d",fc);
 if(fc>max_fast_div)max_fast_div=fc;
 old_cycles+=oc;new_cycles+=fc;end
 count++;end endtask
 initial begin
 repeat(3)@(negedge clk);rst_n=1;
 check(2,64'sd1073741824,64'sd1073741824);
 check(2,64'sh8000000000000000,64'sd1073741824);
 check(2,64'sh8000000000000000,64'sh8000000000000000);
 check(2,64'sh7fffffffffffffff,64'sd1073741824);
 check(2,64'sh7fffffffffffffff,64'sd1073741823);
 check(2,64'sd51539607551,64'sd3); // leading quotient test bit64 must be zero
 check(2,0,7);
 check(2,64'sh7fffffffffffffff,1);check(2,1,0);
 check(2,3,64'sd2147483648);check(2,-3,64'sd2147483648);
 check(2,1,64'sd2147483648);check(2,-1,64'sd2147483648);
 for(integer i=0;i<2048;i++)begin
 random_state=next_random(random_state);a=random_state;
 random_state=next_random(random_state);b=random_state;
 if(i%3==0)begin a=a>>>16;b=b>>>24;end
 check(2,a,b);
 if(i<256)begin check(0,a,b);check(1,a,b);end
 end
 @(negedge clk);op=2;a=64'sh7fffffffffffffff;b=1073741824;start=1;
 @(negedge clk);start=0;repeat(4)@(negedge clk);rst_n=0;@(negedge clk);rst_n=1;
 repeat(140)begin @(negedge clk);if(old_done||fast_done)$fatal(1,"old operation survived reset");end
 $display("PASS DIV_EQUIVALENCE cases=%0d max_fast_div_cycles=%0d old_div_cycles_sum=%0d fast_div_cycles_sum=%0d",count,max_fast_div,old_cycles,new_cycles);$finish;
 end
 initial begin #4000000;$fatal(1,"bench timeout");end
endmodule
