`timescale 1ns/1ps
module tb_ddr_application;
reg clk=0,rst=0;
always #5 clk=~clk;
reg pv=0,last=0,abort_pack=0,ready=0;
reg [23:0] rgb=0;
wire pr,valid,block_last;
wire [255:0] data;
wire [31:0] strb;
rgb888_block_packer pack(clk,rst,pv,pr,rgb,last,abort_pack,valid,ready,data,strb,block_last);
reg start=0,complete=0,abort_frame=0,acquire=0,release_frame=0;
wire grant,drop,writing,latest_valid,locked;
wire [1:0] ws,ls,rs;
wire [31:0] latest_id,read_id;
ddr_frame_slots slots(clk,rst,start,complete,abort_frame,acquire,release_frame,
 grant,drop,writing,ws,latest_valid,ls,latest_id,locked,rs,read_id);
integer test_passed=0,i;
reg [255:0] expected,held;
task tick;
 begin @(posedge clk);#1;end
endtask
task pixel(input integer n,input integer end_frame);
 begin @(negedge clk);pv=1;rgb=24'h102030+n;last=end_frame;tick;
  @(negedge clk);pv=0;last=0;
 end
endtask
task pulse_start;
 begin @(negedge clk);start=1;tick;@(negedge clk);start=0;end
endtask
task pulse_done;
 begin @(negedge clk);complete=1;tick;@(negedge clk);complete=0;end
endtask
initial begin
 tick;@(negedge clk);rst=1;
 expected=0;
 for(i=0;i<8;i=i+1)begin expected[i*32+:32]=32'h00102030+i;pixel(i,i==7);end
 if(!valid || data!==expected || strb!==32'hffffffff || !block_last || pr)
  $fatal(1,"full RGB block/backpressure");
 held=data;repeat(4)tick;
 if(!valid || data!==held)$fatal(1,"blocked output changed");
 @(negedge clk);ready=1;tick;@(negedge clk);ready=0;
 if(valid)$fatal(1,"output did not drain");
 pixel(8,0);pixel(9,0);pixel(10,1);
 if(!valid || strb!==32'hfff || data[95:0]!=={32'h0010203a,32'h00102039,32'h00102038})
  $fatal(1,"partial RGB block");
 @(negedge clk);abort_pack=1;tick;@(negedge clk);abort_pack=0;
 if(valid)$fatal(1,"abort retained block");
 pixel(11,0);@(negedge clk);abort_pack=1;tick;@(negedge clk);abort_pack=0;
 pixel(12,1);
 if(!valid || strb!==32'hf || data[31:0]!==32'h0010203c)$fatal(1,"abort retained partial pixels");
 pulse_start;
 if(!grant || !writing || latest_valid)$fatal(1,"write ownership start");
 pulse_done;
 if(!latest_valid || writing || latest_id!=1)$fatal(1,"complete frame publication");
 @(negedge clk);acquire=1;tick;@(negedge clk);acquire=0;
 if(!locked || read_id!=1 || rs!=ls)$fatal(1,"read frame acquire");
 pulse_start;
 if(!grant || ws==rs)$fatal(1,"locked frame overwritten");
 pulse_done;
 if(latest_id!=2 || read_id!=1 || rs==ls)$fatal(1,"frame lock tearing");
 pulse_start;
 if(ws==rs || ws==ls)$fatal(1,"slot collision");
 @(negedge clk);abort_frame=1;tick;@(negedge clk);abort_frame=0;
 if(!writing)$fatal(1,"aborted writer freed before drain");
 pulse_start;if(!drop || grant)$fatal(1,"accepted while drain pending");
 pulse_done;
 if(latest_id!=2 || writing)$fatal(1,"aborted frame published");
 @(negedge clk);release_frame=1;acquire=1;tick;@(negedge clk);release_frame=0;acquire=0;
 if(!locked || read_id!=2 || rs!=ls)$fatal(1,"safe reacquire latest");
 pulse_start;
 @(negedge clk);abort_frame=1;complete=1;tick;@(negedge clk);abort_frame=0;complete=0;
 if(latest_id!=2 || writing)$fatal(1,"same-cycle abort must win");
 @(negedge clk);rst=0;tick;
 if(latest_valid || locked || writing || valid)$fatal(1,"reset stale state");
 test_passed=1;$display("PASS_DDR_APPLICATION packer=ok slots=ok");$finish;
end
initial begin #100000;$fatal(1,"application timeout");end
endmodule
