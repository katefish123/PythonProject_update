`timescale 1ns/1ps
module tb_snapshot_cdc;
 reg s_clk=0,d_clk=0,rst_n=0,run_destination=1;reg[31:0]counter=0;
 always #5 s_clk=~s_clk;
 always #7 if(run_destination)d_clk=~d_clk;
 wire[95:0]s_data={counter,~counter,counter^32'h5a5aa5a5};wire[95:0]d_data;wire d_valid;
 snapshot_cdc #(.WIDTH(96)) dut(.*);
 integer checked=0;reg prev_request=0;reg[95:0]saved=0;
 always @(posedge s_clk)begin
 if(!rst_n)begin counter<=0;prev_request<=0;saved<=0;end
 else begin
 counter<=counter+1'b1;
 if(dut.request==prev_request&&dut.request!=dut.ack_sync[2]&&dut.held!==saved)$fatal(1,"held snapshot changed without ACK");
 prev_request<=dut.request;saved<=dut.held;
 end end
 always @(posedge d_clk)begin #1;
 if(rst_n&&d_valid)begin
 if(d_data[63:32]!==~d_data[95:64]||d_data[31:0]!==(d_data[95:64]^32'h5a5aa5a5))$fatal(1,"torn CDC payload");
 checked++;
 end end
 initial begin
 #40;rst_n=1;wait(checked>=20);@(negedge d_clk);run_destination=0;
 #400;run_destination=1;wait(checked>=40);
 rst_n=0;#30;if(d_data!=0||d_valid||dut.request||dut.ack)$fatal(1,"mailbox common reset");
 rst_n=1;wait(checked>=60);$display("PASS SNAPSHOT_CDC atomic payload, ACK hold, stopped destination, coalescing, common reset");$finish;
 end
 initial begin #100000;$fatal(1,"snapshot timeout");end
endmodule
