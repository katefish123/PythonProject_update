`timescale 1ns/1ps
module tb_continuous_manager #(parameter NATIVE=0);
reg clk=0;always #5 clk=~clk;reg rst_n=0;
reg allocation_valid=0,terminal_valid=0,metadata_valid=0,frame_ready=0,release_valid=0,release_bank=0,return_ready=0;
reg[32:0]allocation_data=0;reg[37:0]terminal_data=0;reg[129:0]metadata_data=0;reg[31:0]release_generation=0;
wire allocation_ready,terminal_ready,metadata_ready,frame_valid,frame_bank,frame_geometry_valid,return_valid,fault;
wire[31:0]frame_generation,rejected_frames;wire[95:0]frame_corners;wire[32:0]return_data;wire[3:0]last_failure_reason;
wire[31:0]frame_capture_ms;wire[511:0]reject_reason_counts;
continuous_capture_manager #(.PROC_CYCLES_PER_MS(4)) dut(.*);
integer allocation_ms[0:1];
integer returns=0,accepted=0;reg[32:0]seen_return[0:7];
always @(posedge clk)begin if(rst_n&&return_valid&&return_ready)begin seen_return[returns]=return_data;returns<=returns+1;end if(rst_n&&frame_valid&&frame_ready)accepted<=accepted+1;end
task allocate;input bit bank;input integer gen;begin @(negedge clk);allocation_valid=1;allocation_data={bank,32'(gen)};allocation_ms[bank]=dut.now_ms;@(negedge clk);allocation_valid=0;end endtask
task reset;begin @(negedge clk);rst_n=0;allocation_valid=0;terminal_valid=0;metadata_valid=0;frame_ready=0;release_valid=0;return_ready=0;repeat(3)@(negedge clk);returns=0;accepted=0;rst_n=1;end endtask
initial begin
reset();allocate(0,1);allocate(1,2);
@(negedge clk);metadata_valid=1;metadata_data={1'b0,32'd1,1'b0,96'd0};terminal_valid=1;terminal_data={1'b1,32'd2,1'b0,4'd12};
@(negedge clk);metadata_data={1'b1,32'd2,1'b0,96'd0};terminal_data={1'b0,32'd1,1'b0,4'd12};
@(negedge clk);metadata_valid=0;terminal_valid=0;
repeat(4)@(negedge clk);
if(rejected_frames!=2)$fatal(1,"simultaneous two-bank rejection count expected2 got%0d",rejected_frames);
if(reject_reason_counts[12*32+:32]!=2)$fatal(1,"same-reason rejection collision lost an increment");
return_ready=1;wait(returns==2);@(negedge clk);
if(seen_return[0]!={1'b0,32'd1}||seen_return[1]!={1'b1,32'd2})$fatal(1,"incorrect rejected bank credit identity");
$display("PASS simultaneous joins and per-generation invalid frame credits");
reset();
allocate(0,1);allocate(1,2);
@(negedge clk);metadata_valid=1;metadata_data={1'b0,32'd1,1'b1,96'd0};terminal_valid=1;terminal_data={1'b1,32'd2,1'b1,4'd0};
@(negedge clk);metadata_data={1'b1,32'd2,1'b0,96'd0};terminal_data={1'b0,32'd1,1'b0,4'd13};
@(negedge clk);metadata_valid=0;terminal_valid=0;repeat(4)@(negedge clk);
if(rejected_frames!=2||reject_reason_counts[13*32+:32]!=1||reject_reason_counts[3*32+:32]!=1)$fatal(1,"different-reason simultaneous counters wrong");
$display("PASS simultaneous same/different reason rejection counters");
reset();
// A future geometry descriptor is retained while its BEGIN is behind DDR data.
metadata_valid=1;metadata_data={1'b0,32'd9,1'b1,96'habc};
repeat(4)@(negedge clk);if(metadata_ready||fault)$fatal(1,"future metadata not backpressured before allocation");
allocate(0,9);wait(metadata_ready);@(negedge clk);metadata_valid=0;
terminal_valid=1;terminal_data={1'b0,32'd9,1'b1,4'd0};@(negedge clk);terminal_valid=0;wait(frame_valid);
allocate(1,10);@(negedge clk);metadata_valid=1;metadata_data={1'b1,32'd10,1'b1,96'hdef};terminal_valid=1;terminal_data={1'b1,32'd10,1'b1,4'd0};
@(negedge clk);metadata_valid=0;terminal_valid=0;
repeat(8)begin @(negedge clk);if(!frame_valid||frame_bank!=0||frame_generation!=9||frame_corners!=96'habc||frame_capture_ms!=allocation_ms[0])$fatal(1,"descriptor/timestamp not immutable during stall");end
if(dut.capture_ms[1]<=dut.capture_ms[0])$fatal(1,"BEGIN timestamps not monotonic");
frame_ready=1;wait(accepted==2);@(negedge clk);frame_ready=0;
release_valid=1;release_bank=0;release_generation=8;@(negedge clk);release_valid=0;repeat(3)@(negedge clk);
if(!fault||return_valid)$fatal(1,"stale release freed active source");
release_valid=1;release_generation=9;@(negedge clk);release_bank=1;release_generation=10;@(negedge clk);release_valid=0;return_ready=1;wait(returns==2);
@(negedge clk);release_valid=1;release_bank=0;release_generation=9;@(negedge clk);release_valid=0;repeat(4)@(negedge clk);
if(returns!=2||return_valid)$fatal(1,"duplicate release returned duplicate bank credit");
$display("PASS future metadata ordering, immutable descriptors, stale/duplicate release rejection");
reset();if(frame_valid||return_valid||fault||dut.now_ms!=0||reject_reason_counts!=0||dut.capture_ms[0]!=0||dut.capture_ms[1]!=0)$fatal(1,"manager hard reset/timestamp/reason reset failed");
$display("PASS continuous manager tests");$finish;
end
initial begin #100000;$fatal(1,"manager timeout");end
endmodule
