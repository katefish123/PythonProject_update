`timescale 1ns/1ps
`default_nettype none

// Test the real controller and driver through SCL/SDA, without forcing DUT state.
module tb_ms7210_config;
reg cfg_clk = 1'b0;
reg reset_n = 1'b0;
reg device_present = 1'b0;
wire init_done;
wire scl;
tri1 sda;
wire model_error;
wire [31:0] write_count;
wire [31:0] read_count;
wire first_command_seen, last_command_seen, scratch_read_seen;
reg test_failed = 1'b0;
integer test_passed = 0;

always #50 cfg_clk = ~cfg_clk; // Real 10 MHz configuration clock.
ms7210_config dut (
    .cfg_clk(cfg_clk), .reset_n(reset_n), .init_done(init_done),
    .iic_scl(scl), .iic_sda(sda)
);
ms7210_i2c_test_device device (
    .enable(device_present), .scl(scl), .sda(sda), .error(model_error),
    .write_count(write_count), .read_count(read_count),
    .first_command_seen(first_command_seen),
    .last_command_seen(last_command_seen), .scratch_read_seen(scratch_read_seen)
);

task fail;
    input [8*96-1:0] reason;
    begin
        test_failed = 1'b1;
        $display("TEST_FAIL_MS7210: %0s", reason);
        $display("writes=%0d reads=%0d", write_count, read_count);
        $finish;
    end
endtask

initial begin
    repeat (10) @(negedge cfg_clk);
    reset_n = 1'b1;
    // With no device the scratch-register read cannot return 0x5A.
    #350000000; // Longer than the normal ~325 ms configuration sequence.
    if (init_done !== 1'b0) fail("missing device reported initialization complete");
    $display("CHECK_PASS_NO_DEVICE");
    reset_n = 1'b0;
    repeat (10) @(negedge cfg_clk);
    device_present = 1'b1;
    reset_n = 1'b1;
    wait (init_done === 1'b1);
    #200000; // Let the status-read transaction complete as well.
    if (model_error) fail("invalid address, unknown bit or bus contention");
    if (!scratch_read_seen) fail("scratch register was not read back as 0x5A");
    if (!first_command_seen || !last_command_seen) fail("register sequence incomplete");
    // Upstream controller repeats 0x000B=0x00 at the WAIT transition.
    if (write_count != 51) fail("expected scratch write plus 50 upstream configuration transfers");
    if (read_count < 2) fail("expected scratch read and status read");
    $display("CHECK_PASS_REAL_I2C writes=%0d reads=%0d", write_count, read_count);
    reset_n = 1'b0;
    repeat (10) @(negedge cfg_clk);
    if (init_done !== 1'b0) fail("reset did not clear initialization complete");
    test_passed = 1;
    $display("TEST_PASS_MS7210_CONFIG");
    $finish;
end

initial begin
    #750000000;
    fail("timeout waiting for real register initialization");
end
endmodule

// Minimal external I2C slave: ACKs writes, stores 0x0003, returns status 0.
// MS72xx register addresses are transferred low byte first in this driver.
module ms7210_i2c_test_device (
    input wire enable, input wire scl, inout wire sda,
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
                            if (shift != 8'hB2 && shift != 8'hB3) error = 1'b1;
                            read_next = shift[0];
                            if (read_next) begin
                                tx_data = (address == 16'h0003) ? scratch : 8'h00;
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
                            if (address == 16'h0003) scratch = shift;
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
