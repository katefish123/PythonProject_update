`timescale 1ns/1ps
module tb_packet_stream;
reg wr_clk=0,rd_clk=0,rst_n=0;
always #2 wr_clk=~wr_clk;always #3 rd_clk=~rd_clk;
reg s_valid=0;wire s_ready;reg[31:0]s_data=0;
wire m_valid;reg m_ready=0;wire[31:0]m_data;
async_packet_stream #(.DATA_WIDTH(32),.ADDR_BITS(4)) dut(.*);
integer sent=0,received=0,tick=0,run_length=0,max_run=0,rounds=0;reg stalled=0;reg[31:0]held;
always @(negedge wr_clk)begin if(rst_n)begin s_valid=sent<1024;s_data=sent;end else begin s_valid=0;s_data=0;end end
always @(posedge wr_clk)if(rst_n&&s_valid&&s_ready)sent<=sent+1;
always @(negedge rd_clk)begin m_ready=rst_n&&tick>100&&(tick>500||tick%7>2);end
always @(posedge rd_clk)if(rst_n)begin
 tick<=tick+1;if(dut.count>dut.reserved||dut.reserved>4)$fatal(1,"elastic reserved credit invariant");
 if(stalled&&(!m_valid||m_data!==held))$fatal(1,"payload changed while stalled");
 stalled<=m_valid&&!m_ready;held<=m_data;
 if(m_valid&&m_ready)begin
 if(m_data!==received)$fatal(1,"order expected %0d got %0d",received,m_data);
 received<=received+1;run_length<=run_length+1;if(run_length+1>max_run)max_run<=run_length+1;
 end else run_length<=0;
end
initial begin
 repeat(3)@(negedge wr_clk);rst_n=1;wait(sent>=18);
 @(negedge wr_clk);rst_n=0;repeat(5)@(negedge wr_clk);
 sent=0;received=0;tick=0;run_length=0;max_run=0;stalled=0;rst_n=1;
 wait(received==1024);
 if(max_run<64)$fatal(1,"throughput failure max consecutive packets=%0d",max_run);
 @(negedge wr_clk);rst_n=0;repeat(5)@(negedge wr_clk);
 sent=0;received=0;tick=0;run_length=0;max_run=0;stalled=0;rst_n=1;
 wait(received==1024);if(max_run<64)$fatal(1,"reset throughput failure");
 $display("PASS packet stream async stall full reset throughput max_run=%0d",max_run);$finish;
end
initial begin #100000;$fatal(1,"timeout");end
endmodule

