`timescale 1ns/1fs
module tb_vendor_pll;
reg clkin1=0;always #(500.0/27.0)clkin1=~clkin1;
wire clkout0,clkout54,lock;
video_pll_clock_test dut(.*);
real locked_at;integer completed=0;
task automatic measure(input bit select_f,input real expected_mhz,input integer samples);
 real first,last,previous,now_t,min_period,max_period,period,mean_period,mhz;
 begin
 min_period=1e9;max_period=0;
 if(select_f)@(posedge clkout54);else @(posedge clkout0);
 first=$realtime;previous=first;
 for(integer i=0;i<samples;i=i+1)begin
 if(select_f)@(posedge clkout54);else @(posedge clkout0);
 now_t=$realtime;period=now_t-previous;previous=now_t;
 if(period<min_period)min_period=period;
 if(period>max_period)max_period=period;
 if(!lock)$fatal(1,"PLL lost lock during measurement");
 end
 last=$realtime;mean_period=(last-first)/samples;mhz=1000.0/mean_period;
 $display("MEASURE output=%s periods=%0d avg_period_ns=%0.9f min_period_ns=%0.9f max_period_ns=%0.9f frequency_MHz=%0.9f",select_f?"CLKOUTF":"CLKOUT0",samples,mean_period,min_period,max_period,mhz);
 if(mhz<expected_mhz*0.9999||mhz>expected_mhz*1.0001)$fatal(1,"frequency mismatch expected %0.6fMHz got %0.9fMHz",expected_mhz,mhz);
 completed=completed+1;
 end
endtask
initial begin
 wait(lock===1'b1);locked_at=$realtime;$display("LOCK asserted at %0.9f ns",locked_at);
 repeat(64)@(posedge clkin1);
 fork measure(0,148.5,4096);measure(1,54.0,4096);join
 if(completed!=2)$fatal(1,"missing PLL measurement");
 $display("PASS native GTP_GPLL binding pixel148.5MHz process54MHz");$finish;
end
initial begin #200000;$fatal(1,"PLL lock/measurement timeout");end
endmodule
