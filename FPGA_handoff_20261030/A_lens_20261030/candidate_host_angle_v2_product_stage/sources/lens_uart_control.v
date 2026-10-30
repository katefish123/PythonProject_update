`timescale 1ns/1ps
`default_nettype none

// One stop-and-wait transaction. Accepted coefficients remain stable until the
// consumer handshakes; an ACK is emitted only after matching application commit.
module lens_uart_control #(
 parameter integer CLOCK_HZ=27000000, BAUD=115200
)(
 input wire clk,rst_n,uart_rx,output wire uart_tx,
 output reg cfg_valid,input wire cfg_ready,
 output reg[15:0]cfg_sequence,output reg[239:0]cfg_affine,
 input wire commit_valid,input wire[15:0]commit_sequence
);
 localparam integer BIT_CLKS=(CLOCK_HZ+BAUD/2)/BAUD;
 localparam integer GAP_CLKS=BIT_CLKS*40;
 wire rx_valid;wire[7:0]rx_data;
 reg tx_start;reg[7:0]tx_data;wire tx_busy,tx_done;
 lens_uart_rx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) rx(
  .clk(clk),.rst_n(rst_n),.serial(uart_rx),.valid(rx_valid),.data(rx_data));
 lens_uart_tx #(.CLOCK_HZ(CLOCK_HZ),.BAUD(BAUD)) tx(
  .clk(clk),.rst_n(rst_n),.start(tx_start),.data(tx_data),
  .serial(uart_tx),.busy(tx_busy),.done(tx_done));

 function[15:0]crc_byte(input[15:0]crc,input[7:0]value);
  integer k;reg[15:0]v;
  begin
   v=crc^{value,8'd0};
   for(k=0;k<8;k=k+1)v=v[15]?(v<<1)^16'h1021:v<<1;
   crc_byte=v;
  end
 endfunction

 reg[5:0]index;reg[15:0]crc,packet_sequence;reg[239:0]packet_affine;
 reg[7:0]crc_low;reg packet_ok,packet_busy;
 reg[31:0]gap_count;
 reg pending,accepted;
 reg ack_active,ack_wait;reg[2:0]ack_index;
 reg[15:0]ack_sequence,ack_crc;
 wire transaction_busy=pending||ack_active||tx_busy;
 wire[15:0]commit_crc=crc_byte(crc_byte(crc_byte(crc_byte(16'hffff,8'h81),cfg_sequence[7:0]),cfg_sequence[15:8]),8'h00);

 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   cfg_valid<=0;cfg_sequence<=0;cfg_affine<=0;
   index<=0;crc<=16'hffff;packet_sequence<=0;packet_affine<=0;
   crc_low<=0;packet_ok<=0;packet_busy<=0;gap_count<=0;
   pending<=0;accepted<=0;ack_active<=0;ack_wait<=0;
   ack_index<=0;ack_sequence<=0;ack_crc<=0;tx_start<=0;tx_data<=8'hff;
  end else begin
   tx_start<=0;
   if(cfg_valid&&cfg_ready)begin cfg_valid<=0;accepted<=1;end
   // commit_valid must identify the accepted transaction, including the
   // permitted same-edge ready/commit case. Early and stale commits do nothing.
   if(pending&&(accepted||(cfg_valid&&cfg_ready))&&commit_valid&&commit_sequence==cfg_sequence)begin
    pending<=0;accepted<=0;ack_active<=1;ack_wait<=0;ack_index<=0;
    ack_sequence<=cfg_sequence;ack_crc<=commit_crc;
   end
   if(ack_active)begin
    if(!ack_wait&&!tx_busy)begin
     case(ack_index)
      0:tx_data<=8'ha5;1:tx_data<=8'h5a;2:tx_data<=8'h81;
      3:tx_data<=ack_sequence[7:0];4:tx_data<=ack_sequence[15:8];
      5:tx_data<=8'h00;6:tx_data<=ack_crc[7:0];7:tx_data<=ack_crc[15:8];
     endcase
     tx_start<=1;ack_wait<=1;
    end else if(ack_wait&&tx_done)begin
     ack_wait<=0;
     if(ack_index==7)ack_active<=0;else ack_index<=ack_index+1'b1;
    end
   end

   // A byte gap of four UART characters discards only the partial packet.
   if(index!=0)begin
    if(gap_count==GAP_CLKS-1)begin index<=0;gap_count<=0;end
    else gap_count<=gap_count+1'b1;
   end else gap_count<=0;
   if(rx_valid)begin
    gap_count<=0;
    case(index)
     0:if(rx_data==8'ha5)index<=1;
     1:begin
      if(rx_data==8'h5a)begin
       index<=2;crc<=16'hffff;packet_ok<=1;packet_busy<=transaction_busy;
      end else if(rx_data!=8'ha5)index<=0;
     end
     default:begin
      if(index<=35)begin
       crc<=crc_byte(crc,rx_data);
       if(index==2&&rx_data!=8'h01)packet_ok<=0;
       if(index==3)packet_sequence[7:0]<=rx_data;
       if(index==4)packet_sequence[15:8]<=rx_data;
       if(index==5&&rx_data!=8'h00)packet_ok<=0;
       if(index>=6)packet_affine[(index-6)*8+:8]<=rx_data;
       index<=index+1'b1;
      end else if(index==36)begin crc_low<=rx_data;index<=37;end
      else begin
       index<=0;
       if(packet_ok&&!packet_busy&&!transaction_busy&&{rx_data,crc_low}==crc)begin
        cfg_affine<=packet_affine;cfg_sequence<=packet_sequence;
        cfg_valid<=1;pending<=1;accepted<=0;
       end
      end
     end
    endcase
   end
  end
 end
 // synthesis translate_off
 initial if(BIT_CLKS<8)$fatal(1,"UART requires at least eight clocks/bit");
 // synthesis translate_on
endmodule

module lens_uart_rx #(parameter integer CLOCK_HZ=27000000,BAUD=115200)(
 input wire clk,rst_n,serial,output reg valid,output reg[7:0]data
);
 localparam integer BIT_CLKS=(CLOCK_HZ+BAUD/2)/BAUD;
 reg[1:0]sync;reg[1:0]state;reg[31:0]count;reg[2:0]bit_index;reg[7:0]shift;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sync<=2'b11;state<=0;count<=0;bit_index<=0;shift<=0;valid<=0;data<=0;end
  else begin
   sync<={sync[0],serial};valid<=0;
   case(state)
    0:if(!sync[1])begin state<=1;count<=BIT_CLKS/2-1;end
    1:if(count!=0)count<=count-1'b1;
      else if(!sync[1])begin state<=2;count<=BIT_CLKS-1;bit_index<=0;end
      else state<=0;
    2:if(count!=0)count<=count-1'b1;
      else begin
       shift[bit_index]<=sync[1];count<=BIT_CLKS-1;
       if(bit_index==7)state<=3;else bit_index<=bit_index+1'b1;
      end
    3:if(count!=0)count<=count-1'b1;
      else begin if(sync[1])begin valid<=1;data<=shift;end state<=0;end
   endcase
  end
 end
endmodule

module lens_uart_tx #(parameter integer CLOCK_HZ=27000000,BAUD=115200)(
 input wire clk,rst_n,start,input wire[7:0]data,
 output reg serial,busy,done
);
 localparam integer BIT_CLKS=(CLOCK_HZ+BAUD/2)/BAUD;
 reg[9:0]shift;reg[3:0]bit_index;reg[31:0]count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin serial<=1;busy<=0;done<=0;shift<=10'h3ff;bit_index<=0;count<=0;end
  else begin
   done<=0;
   if(!busy)begin
    serial<=1;
    if(start)begin shift<={1'b1,data,1'b0};serial<=0;busy<=1;bit_index<=0;count<=BIT_CLKS-1;end
   end else if(count!=0)count<=count-1'b1;
   else if(bit_index==9)begin serial<=1;busy<=0;done<=1;end
   else begin shift<={1'b1,shift[9:1]};serial<=shift[1];bit_index<=bit_index+1'b1;count<=BIT_CLKS-1;end
  end
 end
endmodule
`default_nettype wire
