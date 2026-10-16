`timescale 1ns/1ps
module tb_status_timing;
 reg clk=0;always #3.367 clk=~clk;
 reg rst_n=0,scan_de=0,scan_start=0;
 reg[11:0]x=0,y=0;reg[4:0]status=0;
 wire on,on_original;wire[23:0]rgb,rgb_original;
 status_overlay dut(.*);
 status_overlay_original golden(.clk(clk),.rst_n(rst_n),.scan_de(scan_de),.scan_start(scan_start),.x(x),.y(y),.status(status),.on(on_original),.rgb(rgb_original));
 integer st,hc,vc,checked=0,ink=0,blank=0,states=0;
 initial begin
 #1;if(on!==0 || rgb!==0)$fatal(1,"reset outputs wrong");
 repeat(3)@(negedge clk);rst_n=1;
 for(st=0;st<32;st=st+1)begin
 for(vc=0;vc<1125;vc=vc+1)for(hc=0;hc<2200;hc=hc+1)begin
 @(negedge clk);
 // Exact fullHD VTC coordinate mapping, including 192-clock leading blank.
 x=hc-192;y=vc-41;
 scan_de=(hc>=192&&hc<2112&&vc>=41&&vc<1121);
 scan_start=(hc==0&&vc==0);
 if(scan_start)status=st;
 // Live status changes during a line must wait for next scan_start.
 if(hc==1100&&vc==45)status=st^5'b10101;
 @(posedge clk);#0.001;
 if(on!==on_original)$fatal(1,"on mismatch status=%0d hc=%0d vc=%0d",st,hc,vc);
 if(on && rgb!==rgb_original)$fatal(1,"pixel mismatch status=%0d x=%0d y=%0d new=%h original=%h",st,x,y,rgb,rgb_original);
 if(on)begin checked=checked+1;if(rgb==24'hffffff)ink=ink+1;end
 else blank=blank+1;
 if(dut.shown!==golden.shown)$fatal(1,"scan_start status state mismatch");
 end
 states=states+1;
 end
 rst_n=0;#1;if(on!==0 || rgb!==0)$fatal(1,"second reset outputs wrong");
 if(states!=32 || checked!=32*1920*64 || ink<10000)$fatal(1,"coverage missing");
 $display("PASS status timing fullVTC states=%0d visible=%0d ink=%0d blank=%0d allglyphrows exactcoordinates scanstart midframestatus reset",states,checked,ink,blank);$finish;
 end
 initial begin #1000000000;$fatal(1,"timeout");end
endmodule
