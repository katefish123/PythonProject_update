`timescale 1ns/1ps
module tb_rx_reconnect;
parameter INITIAL_STATUS=3;
reg clk=0,reset_n=0,signal_present=1;
reg [7:0] lock_status=INITIAL_STATUS;
wire rx_done,tx_done,scl,raw_error,fatal_error,retry_seen;
tri1 sda;
wire device_error;
wire [31:0] writes,reads;
integer test_failed=0,test_passed=0;
integer stable_writes,status_reads_before_loss,reconnected_writes;
always #50 clk=~clk;
hdmi_config #(.TX_FIRST(1)) dut(.cfg_clk(clk),.reset_n(reset_n),
 .rx_done(rx_done),.tx_done(tx_done),.scl(scl),.sda(sda),
 .ack_error(raw_error),.config_error(fatal_error),.startup_retry_seen(retry_seen));
ms72xx_i2c_test_device dev(.rx_freq(16'h57ea),.lock_status(lock_status),
 .initial_locked(1'b1),.signal_present(signal_present),.tx_first(1'b1),
 .tx_ready(tx_done),.rx_ready(rx_done),.enable(1'b1),.scl(scl),.sda(sda),
 .bootstrap_nack_once(1'b0),.postprobe_nack_c3(1'b0),.error(device_error),
 .write_count(writes),.read_count(reads),.first_command_seen(),.last_command_seen(),
 .scratch_read_seen(),.postprobe_nack_seen());
task fail(input [511:0] reason);
 begin test_failed=1;$display("TEST_FAIL_RECONNECT %0s writes=%0d reads=%0d",reason,writes,reads);$finish;end
endtask
initial begin
 #1000;reset_n=1;
 wait(rx_done===1'b1&&tx_done===1'b1);
 stable_writes=writes;
 #5000000;
 if(writes!=stable_writes||raw_error||fatal_error||device_error)fail("unstable initial lock");
 $display("TEST_PASS_INITIAL_LOCK status=%h writes=%0d",lock_status,writes);

 // Loss is an actual I2C-visible change. No forced controller internals.
 status_reads_before_loss=dev.rx_status_reads;
 signal_present=0;
 wait(dev.rx_status_reads>=status_reads_before_loss+5);
 #1000000;
 if(writes!=stable_writes)fail("reconfigured while no signal");
 $display("TEST_PASS_NO_SIGNAL_NO_WRITES");
 signal_present=1;
 #10000000;
 if(writes!=stable_writes+7)fail("source relock did not produce exactly one receiver setup");
 if(raw_error||fatal_error||device_error)fail("I2C error on recovery");
 $display("TEST_PASS_RELOCK status=%h setup_writes=%0d",lock_status,writes-stable_writes);
 reconnected_writes=writes;
 #5000000;
 if(writes!=reconnected_writes)fail("stable lock repeatedly reconfigured");

 // Bit16 alone may differ; a continuously locked source must remain stable.
 lock_status=lock_status^8'h01;
 #5000000;
 if(writes!=reconnected_writes)fail("mode bit alone triggered receiver setup");
 $display("TEST_PASS_LOCKED_MODE_BIT_CHANGE_NO_WRITES");

 // A second loss must also recover without KEY0.
 status_reads_before_loss=dev.rx_status_reads;
 signal_present=0;
 wait(dev.rx_status_reads>=status_reads_before_loss+5);
 #1000000;signal_present=1;
 #10000000;
 if(writes!=reconnected_writes+7)fail("second source relock failed");
 if(raw_error||fatal_error||device_error)fail("error on second recovery");
 test_passed=1;
 $display("TEST_PASS_TWO_RECONNECTS_WITHOUT_RESET initial_status=%0d",INITIAL_STATUS);
 $finish;
end
initial begin #500000000;fail("test timeout");end
endmodule
