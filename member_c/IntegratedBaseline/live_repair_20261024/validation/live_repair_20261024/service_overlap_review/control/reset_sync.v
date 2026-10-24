`default_nettype none
module reset_sync(input wire clk,arst_n,output wire rst_n);
 (* ASYNC_REG="TRUE" *) reg [2:0] pipe;
 always @(posedge clk or negedge arst_n)begin
  if(!arst_n)pipe<=0;else pipe<={pipe[1:0],1'b1};
 end
 assign rst_n=pipe[2];
endmodule
`default_nettype wire
