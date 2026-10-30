`timescale 1ns/1ps
module tb_iic_dri_diag_v2;
    reg clk = 1'b0;
    reg rstn = 1'b0;
    reg pluse = 1'b0;
    reg [7:0] device_id = 8'hB2;
    reg [15:0] addr = 16'h0003;
    reg owner_tx = 1'b1;
    wire busy, byte_over, scl, sda_out, sda_out_en;
    wire [7:0] data_out;
    wire ack_error, latest_nack_valid, latest_nack_write, latest_nack_owner_tx, latest_nack_scl;
    wire [7:0] latest_nack_device;
    wire [15:0] latest_nack_addr, ack_count, nack_count;
    wire [2:0] latest_nack_state;
    wire [4:0] latest_nack_byte;
    wire [1:0] latest_nack_sda_code;
    tri1 sda;
    assign sda = (sda_out_en && !sda_out) ? 1'b0 : 1'bz;

    iic_dri_diag_v2 #(
        .CLK_FRE(27'd10_000_000), .IIC_FREQ(20'd400_000), .T_WR(10'd1),
        .ADDR_BYTE(2'd2), .LEN_WIDTH(8'd3), .DATA_BYTE(2'd1)
    ) dut (
        .clk(clk), .rstn(rstn), .pluse(pluse), .device_id(device_id), .w_r(1'b1),
        .byte_len(4'd1), .addr(addr), .data_in(8'h5A), .busy(busy),
        .byte_over(byte_over), .data_out(data_out), .ack_error(ack_error), .scl(scl),
        .sda_in(sda), .sda_out(sda_out), .sda_out_en(sda_out_en), .owner_tx(owner_tx),
        .latest_nack_valid(latest_nack_valid), .latest_nack_device(latest_nack_device),
        .latest_nack_addr(latest_nack_addr), .latest_nack_state(latest_nack_state),
        .latest_nack_byte(latest_nack_byte), .latest_nack_write(latest_nack_write),
        .latest_nack_owner_tx(latest_nack_owner_tx), .latest_nack_sda_code(latest_nack_sda_code),
        .latest_nack_scl(latest_nack_scl), .ack_count(ack_count), .nack_count(nack_count)
    );

    always #50 clk = ~clk;
    initial begin
        #300 rstn = 1'b1;
        repeat (5) @(negedge clk);
        pluse = 1'b1;
        @(negedge clk) pluse = 1'b0;
        wait (dut.start);
        @(posedge clk);
        #2;
        // Simulate a controller that advances live command fields immediately
        // after starting this transaction; NACK must retain its START context.
        device_id = 8'h56;
        addr = 16'h1234;
        owner_tx = 1'b0;
        wait (nack_count >= 16'd1);
        if (latest_nack_device !== 8'hB2 || latest_nack_addr !== 16'h0003 ||
            latest_nack_write !== 1'b1 || latest_nack_owner_tx !== 1'b1 ||
            latest_nack_byte !== 5'd1 || latest_nack_sda_code !== 2'b10 ||
            latest_nack_state !== 3'd3)
            $fatal(1, "latest NACK lost START context: dev=%h addr=%h byte=%0d", latest_nack_device, latest_nack_addr, latest_nack_byte);
        wait (busy == 1'b0);
        if (ack_count !== nack_count || ack_count < 16'd4)
            $fatal(1, "ACK/NACK slot counts unexpected: ack=%0d nack=%0d", ack_count, nack_count);
        $display("DIAG_V2_PASS: start context retained; ACK slots=%0d, NACK slots=%0d", ack_count, nack_count);
        $finish;
    end
    initial begin
        #2_000_000 $fatal(1, "transaction timeout");
    end
endmodule
