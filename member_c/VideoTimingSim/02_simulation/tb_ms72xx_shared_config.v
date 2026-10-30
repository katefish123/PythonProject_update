`timescale 1ns/1ps
module tb_ms72xx_shared_config;
parameter TX_FIRST=0;
parameter SIGNAL_PRESENT=1;
parameter INITIAL_LOCKED=0;
parameter CHECK_PIXEL_CONFIG=0;
parameter [7:0] LOCK_STATUS=2;
parameter [15:0] RX_FREQ=16'h5800;
parameter EXPECT_RX_READY=(SIGNAL_PRESENT && RX_FREQ!=0);
reg clk=0, rst_n=0, present=1;
wire rx_done,tx_done,scl,rx_scratch_ok;
wire [7:0] pixel_config;
wire pixel_config_valid;
tri1 sda;
wire err;
wire [31:0] writes,reads;
wire first_seen,last_seen,scratch_seen;
reg test_failed=0;
integer test_passed=0;
integer writes_at_ready;
always #50 clk=~clk;
ms72xx_shared_config #(.TX_FIRST(TX_FIRST)) dut(.cfg_clk(clk),.reset_n(rst_n),.rx_done(rx_done),.tx_done(tx_done),.rx_scratch_ok(rx_scratch_ok),.rx_status(),.rx_status_reads(),.rx_pixel_config(pixel_config),.rx_pixel_config_valid(pixel_config_valid),.scl(scl),.sda(sda));
ms72xx_i2c_test_device dev(.rx_freq(RX_FREQ),.lock_status(LOCK_STATUS),.initial_locked(INITIAL_LOCKED!=0),.signal_present(SIGNAL_PRESENT!=0),.tx_first(TX_FIRST!=0),.tx_ready(tx_done),.rx_ready(rx_done),.enable(present),.scl(scl),.sda(sda),.error(err),.write_count(writes),.read_count(reads),.first_command_seen(first_seen),.last_command_seen(last_seen),.scratch_read_seen(scratch_seen));
initial begin
 #1000;rst_n=1;
 if(!EXPECT_RX_READY) begin
  wait(tx_done===1);#50000000;
  if(CHECK_PIXEL_CONFIG && (!pixel_config_valid || pixel_config!==8'ha5))begin
   test_failed=1;$display("TEST_FAIL_NO_INPUT_PIXEL_CONFIG");$finish;
  end
  if(rx_done || !rx_scratch_ok || err)begin test_failed=1;$display("TEST_FAIL_NO_INPUT");$finish;end
  test_passed=1;$display("TEST_PASS_NO_INPUT tx=%b rx=%b scratch=%b",tx_done,rx_done,rx_scratch_ok);$finish;
 end
 wait(tx_done===1 && rx_done===1);
 writes_at_ready=writes;
 #5000000;
 if(CHECK_PIXEL_CONFIG && (!pixel_config_valid || pixel_config!==8'ha5))begin
  test_failed=1;$display("TEST_FAIL_PIXEL_CONFIG valid=%b value=%h",pixel_config_valid,pixel_config);$finish;
 end
 if(writes!=writes_at_ready)begin
  test_failed=1;$display("TEST_FAIL_REPEATED_INIT writes_before=%d writes_after=%d",writes_at_ready,writes);$finish;
 end
 if(!rx_done || !rx_scratch_ok || err || !first_seen || !last_seen || writes<350 || dev.rx_status_reads<(INITIAL_LOCKED ? 1 : 2)) begin
  test_failed=1;$display("TEST_FAIL_SHARED writes=%d reads=%d err=%b",writes,reads,err);$finish;
 end
 rst_n=0;#1000;
 if(rx_done!==0 || tx_done!==0 || pixel_config_valid!==0 || pixel_config!==0)begin test_failed=1;$display("TEST_FAIL_RESET");$finish;end
 test_passed=1;$display("TEST_PASS_SHARED_CONFIG writes=%d reads=%d",writes,reads);$finish;
end
initial begin #1500000000;test_failed=1;$display("TEST_FAIL_SHARED_TIMEOUT rx=%b tx=%b writes=%d",rx_done,tx_done,writes);$finish;end
endmodule

module ms72xx_i2c_test_device (
    input wire [15:0] rx_freq,
    input wire [7:0] lock_status, input wire initial_locked,signal_present,tx_first,tx_ready,rx_ready, input wire enable, input wire scl, inout wire sda,
    output reg error = 1'b0,
    output reg [31:0] write_count = 0, read_count = 0,
    output reg first_command_seen = 1'b0, last_command_seen = 1'b0,
    output reg scratch_read_seen = 1'b0
);
localparam RX = 0, RX_ACK = 1, TX = 2, TX_ACK = 3, IGNORE = 4;
integer phase = IGNORE;
integer bit_count = 0;
integer byte_index = 0;
reg drive_low = 1'b0;
reg ack_seen = 1'b0;
reg read_next = 1'b0;
reg [7:0] shift = 0;
reg [7:0] tx_data = 0;
reg [7:0] scratch = 0;
reg [7:0] scratch_rx = 0;
reg [7:0] device_address = 0;
integer rx_status_reads = 0;
reg [15:0] address = 0;
assign sda = (enable && drive_low) ? 1'b0 : 1'bz;

always @(negedge sda) begin
    if (enable && scl === 1'b1) begin
        phase = RX;
        bit_count = 0;
        byte_index = 0;
        shift = 0;
        read_next = 1'b0;
        drive_low = 1'b0;
    end
end

always @(posedge sda) begin
    if (enable && scl === 1'b1) begin
        phase = IGNORE;
        drive_low = 1'b0;
    end
end

always @(posedge scl) begin
    if (enable) begin
        case (phase)
            RX: begin
                if (sda !== 1'b0 && sda !== 1'b1) error = 1'b1;
                shift = {shift[6:0], sda};
                bit_count = bit_count + 1;
                if (bit_count == 8) begin
                    case (byte_index)
                        0: begin
                            if (shift != 8'hB2 && shift != 8'hB3 && shift != 8'h56 && shift != 8'h57) error = 1'b1;
                            device_address = shift & 8'hFE;
                            if(!tx_first && device_address==8'hB2 && !rx_ready) error=1;
                            if(tx_first && device_address==8'h56 && !tx_ready) error=1;
                            read_next = shift[0];
                            if (read_next) begin
                                tx_data = (address == 16'h0003) ? ((device_address==8'h56) ? scratch_rx : scratch) : 8'h00;
                                if (device_address==8'h56 && address==16'h209E) begin
                                    rx_status_reads=rx_status_reads+1;
                                    tx_data=(signal_present && (initial_locked || rx_status_reads>1)) ? lock_status : 8'h00;
                                end
                                if(device_address==8'h56 && signal_present && address==16'h209C)tx_data=rx_freq[7:0];
                                if(device_address==8'h56 && signal_present && address==16'h209D)tx_data=rx_freq[15:8];
                                if(device_address==8'h56 && address==16'h1281)tx_data=8'ha5;
                                read_count = read_count + 1;
                                if (address == 16'h0003 && scratch == 8'h5A)
                                    scratch_read_seen = 1'b1;
                            end
                        end
                        1: address[7:0] = shift;
                        2: address[15:8] = shift;
                        3: begin
                            write_count = write_count + 1;
                            $display("I2C_WRITE %0d address=%04h data=%02h", write_count, address, shift);
                            if (address == 16'h0003) begin
                                if(device_address==8'h56) scratch_rx=shift; else scratch=shift;
                            end
                            if (address == 16'h1281 && shift == 8'h04) first_command_seen = 1'b1;
                            if (address == 16'h0507 && shift == 8'h00) last_command_seen = 1'b1;
                        end
                        default: error = 1'b1;
                    endcase
                    byte_index = byte_index + 1;
                    phase = RX_ACK;
                    ack_seen = 1'b0;
                end
            end
            RX_ACK: ack_seen = 1'b1;
            TX: begin
                bit_count = bit_count + 1;
                if (bit_count == 8) phase = TX_ACK;
            end
            TX_ACK: phase = IGNORE;
            default: begin end
        endcase
    end
end

always @(negedge scl) begin
    if (enable) begin
        case (phase)
            RX_ACK: begin
                if (!ack_seen) drive_low = 1'b1;
                else begin
                    bit_count = 0;
                    if (read_next) begin
                        phase = TX;
                        drive_low = !tx_data[7];
                    end else begin
                        phase = RX;
                        drive_low = 1'b0;
                    end
                end
            end
            TX: drive_low = !tx_data[7-bit_count];
            default: drive_low = 1'b0;
        endcase
    end else drive_low = 1'b0;
end
endmodule
`default_nettype wire
