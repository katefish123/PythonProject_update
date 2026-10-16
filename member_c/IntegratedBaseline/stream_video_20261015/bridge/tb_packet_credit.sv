`timescale 1ns/1ps
module packet_credit_case #(parameter MODE=0)(output reg done=0);
localparam N=4096;
reg wr_clk=0,rd_clk=0,rst_n=0;
always #(MODE==0?2.0:(MODE==1?5.5:3.9))wr_clk=~wr_clk;
always #4 rd_clk=~rd_clk;
reg s_valid=0;wire s_ready;reg[63:0]s_data=0;
wire m_valid;reg m_ready=0;wire[63:0]m_data;
async_packet_stream #(.DATA_WIDTH(64),.ADDR_BITS(5)) dut(.*);
integer sent=0,received=0,tick=0,epoch=0,run_length=0,max_run=0,full_hits=0,write_stalls=0;
reg previous_pop=0,held_valid=0;reg[63:0]held_data=0;reg[31:0]prng=32'h218749ad;
function[63:0]word;input integer i;begin word={8'(epoch),24'(i),32'(~i)};end endfunction
always @(negedge wr_clk)begin
 if(!rst_n)begin s_valid=0;s_data=0;end
 else if(!(s_valid&&!s_ready))begin s_valid=sent<N&&(tick<192||tick>1500||prng[3:0]!=0);s_data=word(sent);end
end
always @(posedge wr_clk)begin
 if(!rst_n)begin sent<=0;write_stalls<=0;end
 else begin if(s_valid&&s_ready)sent<=sent+1;if(s_valid&&!s_ready)write_stalls<=write_stalls+1;end
end
always @(negedge rd_clk)m_ready=rst_n&&tick>100&&(tick<192||tick>1500||(prng[2:0]>2&&tick%53>8));
always @(posedge rd_clk)begin
 if(!rst_n)begin received<=0;tick<=0;previous_pop<=0;held_valid<=0;run_length<=0;max_run<=0;full_hits<=0;prng<=32'h218749ad;end
 else begin
  tick<=tick+1;prng<={prng[30:0],prng[31]^prng[21]^prng[1]^prng[0]};
  // Capacity includes the accepted output awaiting registered reclamation.
  if(dut.reserved!==dut.count+3'(dut.rd_valid)+3'(previous_pop))
   $fatal(1,"delayed-pop credit invariant MODE=%0d R=%0d C=%0d V=%0b P=%0b",MODE,dut.reserved,dut.count,dut.rd_valid,previous_pop);
  if(dut.reserved>4||dut.count>4||dut.count>dut.reserved)$fatal(1,"capacity overflow MODE=%0d",MODE);
  if(dut.rd_en&&dut.reserved>=4)$fatal(1,"unsafe read credit");
  if(dut.count==4)full_hits<=full_hits+1;
  if(held_valid&&(!m_valid||m_data!==held_data))$fatal(1,"payload unstable under stall MODE=%0d",MODE);
  held_valid<=m_valid&&!m_ready;held_data<=m_data;previous_pop<=m_valid&&m_ready;
  if(MODE==0&&tick>100&&tick<192&&!m_valid)$fatal(1,"full-recovery output bubble tick=%0d count=%0d",tick,dut.count);
  if(m_valid&&m_ready)begin
   if(m_data!==word(received))$fatal(1,"data/order/epoch mismatch MODE=%0d received=%0d got=%h",MODE,received,m_data);
   received<=received+1;run_length<=run_length+1;if(run_length+1>max_run)max_run<=run_length+1;
  end else run_length<=0;
 end
end
task reset_all;begin
 @(negedge wr_clk);rst_n=0;epoch=epoch+1;repeat(5)@(negedge wr_clk);rst_n=1;
end endtask
initial begin
 repeat(4)@(negedge wr_clk);rst_n=1;
 // Reset live FIFO/RAM read pipeline and an occupied, stalled skid queue.
 wait(dut.rd_valid);reset_all();
 wait(sent>=24);reset_all();
 repeat(2)begin
  wait(received==N);
  if(full_hits==0||write_stalls==0||(MODE!=1&&max_run<64))$fatal(1,"coverage MODE=%0d full=%0d stalls=%0d max=%0d",MODE,full_hits,write_stalls,max_run);
  $display("PASS packet credit mode=%0d epoch=%0d packets=%0d fullhits=%0d stalls=%0d maxrun=%0d",MODE,epoch,N,full_hits,write_stalls,max_run);
  // Last acceptance leaves a pending delayed-pop credit when reset asserts.
  reset_all();
 end
 done=1;
end
initial begin #2000000;$fatal(1,"credit timeout MODE=%0d",MODE);end
endmodule
module tb_packet_credit;
wire[2:0]done;
packet_credit_case #(.MODE(0)) fast_write(done[0]);
packet_credit_case #(.MODE(1)) slow_write(done[1]);
packet_credit_case #(.MODE(2)) near_rates(done[2]);
initial begin wait(&done);$display("PASS packet registered-pop credit all3 async rate cases,24576 packets, full recovery/reset/capacity/order");$finish;end
endmodule
