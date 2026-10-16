`timescale 1ns/1ps
module tb_timing_boundaries #(parameter NATIVE=0);
reg clk=0,rst_n=0,enabled=0,rx_vs=0,rx_de=0;
reg[23:0]rx_rgb=0;
reg release_valid=0,release_bank=0;reg[31:0]release_generation=0;
wire packet_valid;reg packet_ready=1;wire[319:0]packet_data;
wire sample_valid,sample_first,sample_bank,close_valid,close_bank,close_ok;
wire[11:0]sample_x,sample_y;wire[31:0]sample_generation,close_generation;
wire[3:0]close_reason;wire[31:0]dropped_frames,admitted_frames;wire fault;wire[1:0]owned_banks;
continuous_capture_rx #(.IN_W(8),.IN_H(1),.SRC_W(8),.SRC_H(1)) dut(.*);
always #3.367003367 clk=~clk;
integer records=0,ends=0,expected_gen=1;
reg expected_bank=0;reg[1:0]expected_kind=0;
always @(posedge clk)if(rst_n&&packet_valid&&packet_ready)begin
 if(packet_data[319:318]!==expected_kind||packet_data[317]!==expected_bank||packet_data[316:285]!==expected_gen)
  $fatal(1,"ordered terminal/admission record mismatch record=%0d packet=%h",records,packet_data[319:256]);
 if(!packet_data[260]||packet_data[259:256]!=0)$fatal(1,"valid frame rejected");
 if(expected_kind==1)begin
  if(packet_data[284:261]!=0)$fatal(1,"data address mismatch");
  for(integer k=0;k<8;k=k+1)if(packet_data[k*32+:32]!=={8'd0,8'd0,8'(expected_gen),8'(k)})$fatal(1,"packed RGB mismatch");
 end
 records=records+1;
 if(expected_kind==2)begin ends=ends+1;expected_gen=expected_gen+1;expected_bank=~expected_bank;expected_kind=0;end
 else expected_kind=expected_kind+1;
end
task tick;begin @(posedge clk);#1;end endtask
task vs;begin @(negedge clk);rx_vs=1;tick();@(negedge clk);rx_vs=0;tick();end endtask
task pixels;input integer gen;begin
 for(integer k=0;k<8;k=k+1)begin @(negedge clk);rx_de=1;rx_rgb={8'd0,8'(gen),8'(k)};end
 @(negedge clk);rx_de=0;repeat(3)tick();
end endtask
initial begin
 repeat(4)tick();rst_n=1;enabled=1;repeat(5)tick();
 vs();pixels(1);vs();pixels(2);
 if(owned_banks!=3||admitted_frames!=2)$fatal(1,"expected two owned banks");
 // First credit enters validation; duplicate straddles VS and reallocation.
 @(negedge clk);release_valid=1;release_bank=0;release_generation=1;tick();
 @(negedge clk);rx_vs=1;tick();
 if(admitted_frames!=3||owned_banks!=3)$fatal(1,"validated credit not reusable at VS");
 @(negedge clk);release_valid=0;rx_vs=0;repeat(3)tick();
 if(!fault||owned_banks!=3)$fatal(1,"duplicate freed new generation or missing fault");
 // Stale generation and a matching but active generation must both preserve ownership.
 @(negedge clk);release_valid=1;release_generation=1;tick();
 @(negedge clk);release_generation=3;tick();
 @(negedge clk);release_valid=0;repeat(3)tick();
 if(owned_banks!=3)$fatal(1,"active/stale credit freed active bank");
 pixels(3);vs();repeat(12)tick();
 if(admitted_frames!=3||dropped_frames!=1||records!=9||ends!=3||owned_banks!=3)$fatal(1,"boundary ownership/count mismatch");
 // An unused pipeline stage cannot survive the shared hard reset.
 @(negedge clk);release_valid=1;release_generation=3;tick();
 @(negedge clk);rst_n=0;release_valid=0;enabled=0;repeat(3)tick();rst_n=1;repeat(5)tick();
 if(owned_banks!=0||fault||packet_valid||admitted_frames||dropped_frames)$fatal(1,"reset failed to flush credit and queues");
 $display("PASS timing boundaries: duplicate credit at VS/reallocation, stale/active credit, ordered END+BEGIN, RGB packing and shared reset");$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule
