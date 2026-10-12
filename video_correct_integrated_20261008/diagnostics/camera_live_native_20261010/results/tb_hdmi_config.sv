`timescale 1ns/1ps
module tb_hdmi_config;
parameter TX_FIRST = 1'b1;
reg clk=0, reset_n=0, present=1, external_low=0;
reg bootstrap_nack_once=0, postprobe_nack_c3=0;
wire rx_done, tx_done, scl, ack_error, config_error, startup_retry_seen;
tri1 sda;
assign sda = external_low ? 1'b0 : 1'bz;
wire dev_error;
wire [31:0] writes, reads;
wire first_seen, last_seen, scratch_seen;
wire postprobe_nack_seen;
integer writes_at_ready;
integer test_failed=0;
always #50 clk=~clk;

hdmi_config #(.TX_FIRST(TX_FIRST)) dut(
    .cfg_clk(clk), .reset_n(reset_n), .rx_done(rx_done), .tx_done(tx_done),
    .scl(scl), .sda(sda), .ack_error(ack_error), .config_error(config_error),
    .startup_retry_seen(startup_retry_seen)
);
ms72xx_i2c_test_device dev(
    .rx_freq(16'h5800), .lock_status(8'h02), .initial_locked(1'b0),
    .signal_present(1'b1), .tx_first(TX_FIRST != 0), .tx_ready(tx_done),
    .rx_ready(rx_done), .enable(present), .scl(scl), .sda(sda),
    .error(dev_error), .write_count(writes), .read_count(reads),
    .first_command_seen(first_seen), .last_command_seen(last_seen),
    .scratch_read_seen(scratch_seen), .bootstrap_nack_once(bootstrap_nack_once),
    .postprobe_nack_c3(postprobe_nack_c3), .postprobe_nack_seen(postprobe_nack_seen)
);

initial begin
    #1000 reset_n=1;
    wait(rx_done===1'b1 && tx_done===1'b1);
    writes_at_ready=writes;
    #5000000;
    if (ack_error || config_error || startup_retry_seen || dev_error || !first_seen || !last_seen || !scratch_seen || writes<350 || writes!=writes_at_ready) begin
        test_failed=1;
        $display("TEST_FAIL_CONFIG rx=%b tx=%b ack_error=%b dev_error=%b writes=%0d", rx_done,tx_done,ack_error,dev_error,writes);
        $finish;
    end
    $display("TEST_PASS_CONFIG writes=%0d reads=%0d", writes, reads);

    // A low external participant must be able to pull SDA low while the
    // controller's data output is high (released), proving open-drain wiring.
    reset_n=0;
    #1000;
    external_low=1;
    #100;
    if (sda !== 1'b0) begin
        test_failed=1;
        $display("TEST_FAIL_SDA_NOT_OPEN_DRAIN sda=%b",sda);
        $finish;
    end
    $display("TEST_PASS_OPEN_DRAIN");
    external_low=0;

    // The first 0003 scratch write may NACK during startup. The controller
    // retries, verifies 5A, and becomes ready while raw history stays set.
    #1000;
    bootstrap_nack_once=1;
    reset_n=1;
    wait(rx_done===1'b1 && tx_done===1'b1);
    if (!ack_error || config_error || !startup_retry_seen || !scratch_seen) begin
        test_failed=1;
        $display("TEST_FAIL_BOOTSTRAP_RECOVERY raw=%b fatal=%b retry=%b",ack_error,config_error,startup_retry_seen);
        $finish;
    end
    $display("TEST_PASS_BOOTSTRAP_NACK_RECOVERY raw=%b retry=%b",ack_error,startup_retry_seen);

    // A later INIT write of C3 to the same address is fatal after probe success.
    reset_n=0;
    #1000;
    bootstrap_nack_once=0;
    postprobe_nack_c3=1;
    reset_n=1;
    wait(config_error===1'b1);
    if (!ack_error || startup_retry_seen || !postprobe_nack_seen) begin
        test_failed=1;
        $display("TEST_FAIL_POSTPROBE_NACK raw=%b fatal=%b retry=%b",ack_error,config_error,startup_retry_seen);
        $finish;
    end
    $display("TEST_PASS_POSTPROBE_NACK_FATAL raw=%b fatal=%b",ack_error,config_error);

    // Remove the device and prove NACK is visible and initialization does not
    // report success. The test model only pulls SDA low for acknowledged bits.
    reset_n=0;
    #1000;
    postprobe_nack_c3=0;
    present=0;
    reset_n=1;
    wait(ack_error===1'b1);
    #5000000;
    if (rx_done || tx_done || config_error || dev_error) begin
        test_failed=1;
        $display("TEST_FAIL_NO_DEVICE rx=%b tx=%b raw_ack=%b fatal=%b", rx_done,tx_done,ack_error,config_error);
        $finish;
    end
    $display("TEST_PASS_NO_DEVICE raw_ack=%b fatal=%b rx=%b tx=%b",ack_error,config_error,rx_done,tx_done);
    $finish;
end

initial begin
    #(64'd3000000000);
    test_failed=1;
    $display("TEST_FAIL_TIMEOUT rx=%b tx=%b raw_ack=%b fatal=%b writes=%0d",rx_done,tx_done,ack_error,config_error,writes);
    $finish;
end
endmodule
module ms72xx_i2c_test_device (
    input wire [15:0] rx_freq,
    input wire [7:0] lock_status, input wire initial_locked,signal_present,tx_first,tx_ready,rx_ready, input wire enable, input wire scl, inout wire sda,
    input wire bootstrap_nack_once, postprobe_nack_c3,
    output reg error = 1'b0,
    output reg [31:0] write_count = 0, read_count = 0,
    output reg first_command_seen = 1'b0, last_command_seen = 1'b0,
    output reg scratch_read_seen = 1'b0, postprobe_nack_seen = 1'b0
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
reg bootstrap_failed = 1'b0, fail_this_transaction = 1'b0;
assign sda = (enable && drive_low) ? 1'b0 : 1'bz;

always @(negedge sda) begin
    if (enable && scl === 1'b1) begin
        if (phase == IGNORE || phase == RX_ACK || phase == TX_ACK)
            fail_this_transaction = (bootstrap_nack_once === 1'b1) && !bootstrap_failed;
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
        if (fail_this_transaction) bootstrap_failed = 1'b1;
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
                if (!ack_seen) begin
                    if (fail_this_transaction ||
                        ((postprobe_nack_c3 === 1'b1) && !postprobe_nack_seen && scratch_read_seen &&
                         address == 16'h0003 && byte_index == 4 && shift == 8'hC3)) begin
                        drive_low = 1'b0;
                        if ((postprobe_nack_c3 === 1'b1) && scratch_read_seen &&
                            address == 16'h0003 && byte_index == 4 && shift == 8'hC3)
                            postprobe_nack_seen = 1'b1;
                    end else drive_low = 1'b1;
                end
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

