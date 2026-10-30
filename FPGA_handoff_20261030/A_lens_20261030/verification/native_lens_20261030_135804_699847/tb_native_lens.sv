`timescale 1ns/1ps
module tb_native_lens;
 localparam N=4075;reg clk=0,rst_n=0,in_valid=0;always #5.387205 clk=~clk;
 reg[19:0]in_x=0,in_y=0;reg[25:0]in_tag=0;wire[63:0]nx={28'd0,in_x,16'd0},ny={28'd0,in_y,16'd0};
 wire out_valid,out_error;wire[25:0]out_tag;wire[39:0]out_x,out_y;
 GTP_GRS GRS_INST(.GRS_N(rst_n));
 lens_distort_coord dut(
  .\core/stream_path/processor/runtime_geometry.algorithm/nx (nx),
 .\core/stream_path/processor/runtime_geometry.algorithm/ny (ny),
 .\core/stream_path/processor/runtime_geometry.algorithm/N120[7]_inv (~in_x[7]),
 .\core/stream_path/processor/runtime_geometry.algorithm/N122[0]_inv (~in_y[0]),
 .\core/stream_path/processor/N1301 (~rst_n),
 .clk(clk),.in_valid(in_valid),.in_x(in_x),.in_y(in_y),.in_tag(in_tag),.out_valid(out_valid),.out_error(out_error),.out_x(out_x),.out_y(out_y),.out_tag(out_tag));
 reg[65:0]vectors[0:N-1];reg[106:0]gold[0:N-1];integer queue[$];integer index=0,sent=0,received=0,cancelled=0,errors=0,bubbles=0;
 integer ignored,k;reg[31:0]rng=32'hae1863db;
 always @(posedge clk)begin
  if(!rst_n)begin cancelled=cancelled+queue.size();queue.delete();end
  else begin
   if(in_valid)begin queue.push_back(index);sent++;end else bubbles++;
   if(out_valid)begin
    if(queue.size()==0)$fatal(1,"NATIVE_UNEXPECTED_OUTPUT");k=queue.pop_front();
    if(out_error!==gold[k][106]||out_x!==gold[k][79:40]||out_y!==gold[k][39:0]||(((out_tag^gold[k][105:80])&26'h3fff7ff)!==0))
     $fatal(1,"NATIVE_LENS_MISMATCH index=%0d actual=%b/%h/%h expected=%h",k,out_error,out_x,out_y,gold[k]);
    received++;if(out_error)errors++;
   end
  end
 end
 initial begin
  $readmemh("input.hex",vectors);$readmemh("expected.hex",gold);
  repeat(8)@(negedge clk);rst_n=1;
  for(integer j=0;j<N;j++)begin
   @(negedge clk);rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
   in_valid=1;index=j;{in_x,in_y,in_tag}=vectors[j];
   if(j==500||j==2000)begin @(negedge clk);in_valid=0;rst_n=0;repeat(5)@(negedge clk);rst_n=1;end
   else if(rng[2:0]==0)begin @(negedge clk);in_valid=0;repeat(3)@(negedge clk);end
  end
  @(negedge clk);in_valid=0;repeat(60)@(negedge clk);
  if(sent!=N||received+cancelled!=N||errors<10||bubbles<10||cancelled==0)$fatal(1,"NATIVE_COVERAGE");
  $display("NATIVE_LENS_PASS points=%0d checked=%0d numerical_errors=%0d cancelled=%0d bubbles=%0d consumed_tag_bits=25 ignored_trimmed_tag_bit=11",N,received,errors,cancelled,bubbles);$finish;
 end
 initial begin #2000000;$fatal(1,"NATIVE_LENS_TIMEOUT");end
endmodule
