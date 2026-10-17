`timescale 1ns/1ps
module tb_iic_dri_read_bytes;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    reg pluse = 1'b0;
    wire busy, byte_over, scl, sda_out, sda_out_en;
    wire [7:0] data_out;
    tri1 sda;
    reg slave_ack = 1'b0;
    assign sda = slave_ack ? 1'b0 : 1'bz;
    assign sda = (sda_out_en && !sda_out) ? 1'b0 : 1'bz;

    iic_dri #(
        .CLK_FRE(27'd10_000_000), .IIC_FREQ(20'd400_000), .T_WR(10'd1),
        .ADDR_BYTE(2'd2), .LEN_WIDTH(8'd3), .DATA_BYTE(2'd1)
    ) dut (
        .clk(clk), .rstn(rstn), .pluse(pluse), .device_id(8'hB2), .w_r(1'b0),
        .byte_len(4'd1), .addr(16'h0003), .data_in(8'h5A), .busy(busy),
        .byte_over(byte_over), .data_out(data_out), .ack_error(), .scl(scl),
        .sda_in(sda), .sda_out(sda_out), .sda_out_en(sda_out_en), .owner_tx(1'b0),
        .nack_pulse(), .transaction_device(), .transaction_addr(), .transaction_write(),
        .transaction_owner_tx(), .transaction_nack()
    );

    reg [7:0] shift = 8'd0;
    integer bit_count = 0;
    integer byte_count = 0;
    reg ack_byte = 1'b0;
    reg done = 1'b0;
    reg restart_edge_skipped = 1'b0;
    reg [7:0] observed;
    always #50 clk = ~clk;

    // Strict slave timing: sample each transmitted bit on SCL rising, and
    // assert ACK during the following low phase before the ninth rising edge.
    always @(negedge scl) begin
        if (rstn) begin
            slave_ack = (bit_count == 8) && ack_byte;
        end
        else slave_ack = 1'b0;
    end

    always @(posedge scl) begin
        if (rstn && !done) begin
            #2;
            // A repeated START includes an SCL rising edge while SDA is high;
            // that edge is a bus condition, not one of the B3 data bits.
            if (byte_count == 3 && !restart_edge_skipped && dut.state == 3'd1) begin
                restart_edge_skipped = 1'b1;
            end else if (bit_count < 8) begin
                shift = {shift[6:0], sda};
                bit_count = bit_count + 1;
                if (bit_count == 8) begin
                    observed = shift;
                    case (byte_count)
                        0: if (observed !== 8'hB2) $fatal(1, "device write byte expected B2, saw %02h", observed);
                        1: if (observed !== 8'h03) $fatal(1, "register low byte expected 03, saw %02h", observed);
                        2: if (observed !== 8'h00) $fatal(1, "register high byte expected 00, saw %02h", observed);
                        3: if (observed !== 8'hB3) $fatal(1, "device read byte expected B3, saw %02h", observed);
                        default: $fatal(1, "unexpected extra master byte %0d: %02h", byte_count, observed);
                    endcase
                    $display("I2C_MASTER_BYTE[%0d]=%02h", byte_count, observed);
                    ack_byte = 1'b1;
                end
            end else begin
                if (sda !== 1'b0) $fatal(1, "strict slave ACK missing after master byte %0d", byte_count);
                bit_count = 0;
                shift = 8'd0;
                byte_count = byte_count + 1;
                ack_byte = 1'b0;
                if (byte_count == 4) begin
                    done = 1'b1;
                    $display("I2C_READ_SEQUENCE_PASS: B2 03 00 B3; LSBs valid at SCL rising edges");
                end
            end
        end
    end

    initial begin
        #300 rstn = 1'b1;
        repeat (5) @(negedge clk);
        pluse = 1'b1;
        @(negedge clk) pluse = 1'b0;
        wait (done);
        #10 $finish;
    end

    initial begin
        #2_000_000 $fatal(1, "transaction timeout");
    end
endmodule
