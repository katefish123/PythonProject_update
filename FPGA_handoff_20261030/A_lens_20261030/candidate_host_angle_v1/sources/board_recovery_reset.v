`timescale 1ns/1ps
// This is a request for a FULL memory/application reset, never a local FIFO
// clear. Diagnostic history and the HDMI configuration/PLLs use external reset.
module board_recovery_reset #(
 parameter HOLD_CYCLES=100000,LOCK_TIMEOUT=5000000,SETTLE_CYCLES=1000000,MAX_RETRIES=3
)(
 input wire cfg_clk,external_rst_n,fault_request_async,ddr_ready_async,
 output wire memory_release_n,output wire recovering,
 output reg exhausted,output reg[7:0]recovery_count,output reg[2:0]state
);
 localparam TRAIN=0,RUN=1,HOLD=2,SETTLE=3,STOP=4;
 (* ASYNC_REG="TRUE" *)reg[2:0]fault_sync,ready_sync;
 reg[31:0]count;
 assign memory_release_n=external_rst_n&&state!=HOLD&&state!=STOP;
 assign recovering=state!=RUN;
 task restart_or_stop;
  begin
   count<=0;
   if(recovery_count<MAX_RETRIES)begin recovery_count<=recovery_count+1'b1;state<=HOLD;end
   else begin exhausted<=1;state<=STOP;end
  end
 endtask
 always @(posedge cfg_clk or negedge external_rst_n)begin
  if(!external_rst_n)begin fault_sync<=0;ready_sync<=0;recovery_count<=0;exhausted<=0;state<=TRAIN;count<=0;end
  else begin
   fault_sync<={fault_sync[1:0],fault_request_async};ready_sync<={ready_sync[1:0],ddr_ready_async};
   case(state)
    TRAIN:begin
     if(ready_sync[2])begin state<=SETTLE;count<=0;end
     else if(count==LOCK_TIMEOUT-1)restart_or_stop();else count<=count+1'b1;
    end
    RUN:if(fault_sync[2]||!ready_sync[2])restart_or_stop();
    HOLD:if(count==HOLD_CYCLES-1)begin state<=TRAIN;count<=0;end else count<=count+1'b1;
    SETTLE:begin
     if(!ready_sync[2])begin state<=TRAIN;count<=0;end
     else if(fault_sync[2])restart_or_stop();
     else if(count==SETTLE_CYCLES-1)begin state<=RUN;count<=0;end
     else count<=count+1'b1;
    end
    STOP:begin end
    default:begin exhausted<=1;state<=STOP;end
   endcase
  end
 end
 // synthesis translate_off
 initial if(HOLD_CYCLES<4||LOCK_TIMEOUT<4||SETTLE_CYCLES<4||MAX_RETRIES<0||MAX_RETRIES>255)$fatal(1,"recovery parameter contract");
 // synthesis translate_on
endmodule
