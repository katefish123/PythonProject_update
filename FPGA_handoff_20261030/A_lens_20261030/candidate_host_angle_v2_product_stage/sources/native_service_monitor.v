`timescale 1ns/1ps
`default_nettype none
// Read-only UI-domain pressure observation, independent of command/protection.
// Maxima count UI cycles; no claim is made about the physical cause of a gap.
module native_service_monitor(
 input wire clk,rst_n,cmd_valid,cmd_ready,awvalid,awready,wready,wlast,arvalid,arready,rvalid,rlast,
 output reg[31:0]max_aw,max_first_w,max_w_gap,max_first_r,max_r_gap,max_cmd_wait,
 output wire[3:0]stage
);
 reg writing,reading,seen_w,seen_r;
 reg[31:0]aw_gap,w_gap,r_gap,cmd_gap;
 assign stage=writing?4'd2:reading?4'd4:awvalid?4'd1:arvalid?4'd3:4'd0;
 function[31:0]inc(input[31:0]n);inc=&n?n:n+1'b1;endfunction
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin writing<=0;reading<=0;seen_w<=0;seen_r<=0;aw_gap<=0;w_gap<=0;r_gap<=0;cmd_gap<=0;
 max_aw<=0;max_first_w<=0;max_w_gap<=0;max_first_r<=0;max_r_gap<=0;max_cmd_wait<=0;end
 else begin
 if(cmd_valid&&!cmd_ready)begin cmd_gap<=inc(cmd_gap);if(cmd_gap>=max_cmd_wait)max_cmd_wait<=inc(cmd_gap);end else cmd_gap<=0;
 if(awvalid&&!awready)begin aw_gap<=inc(aw_gap);if(aw_gap>=max_aw)max_aw<=inc(aw_gap);end else aw_gap<=0;
 if(awvalid&&awready)begin writing<=! (wready&&wlast);seen_w<=wready;w_gap<=0;end
 else if(writing)begin
 if(wready)begin w_gap<=0;seen_w<=1;if(wlast)writing<=0;end
 else begin w_gap<=inc(w_gap);
 if(!seen_w&&w_gap>=max_first_w)max_first_w<=inc(w_gap);
 if(seen_w&&w_gap>=max_w_gap)max_w_gap<=inc(w_gap);end end
 if(arvalid&&arready)begin reading<=!(rvalid&&rlast);seen_r<=rvalid;r_gap<=0;end
 else if(reading)begin
 if(rvalid)begin r_gap<=0;seen_r<=1;if(rlast)reading<=0;end
 else begin r_gap<=inc(r_gap);
 if(!seen_r&&r_gap>=max_first_r)max_first_r<=inc(r_gap);
 if(seen_r&&r_gap>=max_r_gap)max_r_gap<=inc(r_gap);end end
 end end
endmodule
`default_nettype wire
