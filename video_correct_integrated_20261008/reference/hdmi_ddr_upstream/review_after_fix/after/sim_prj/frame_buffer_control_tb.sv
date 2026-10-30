`timescale 1ns/1ps

module frame_buffer_control_tb;
    reg ddr_clk = 0;
    reg wr_clk = 0;
    reg ddr_rstn = 0;
    reg wr_fsync = 0;
    reg ddr_wdone = 0;

    wire frame_wirq;
    wire frame_ready_bank;
    integer irq_count = 0;

    always #4 ddr_clk = ~ddr_clk;
    always #5 wr_clk = ~wr_clk;
    always @(posedge ddr_clk)
        if(frame_wirq) irq_count = irq_count + 1;

    wr_buf #(
        .H_NUM(8),
        .V_NUM(4),
        .PIX_WIDTH(16),
        .LINE_ADDR_WIDTH(8),
        .FRAME_CNT_WIDTH(2)
    ) dut (
        .ddr_clk(ddr_clk),
        .ddr_rstn(ddr_rstn),
        .wr_clk(wr_clk),
        .wr_fsync(wr_fsync),
        .wr_en(1'b0),
        .wr_data(16'd0),
        .rd_bac(1'b0),
        .ddr_wreq(),
        .ddr_waddr(),
        .ddr_wr_len(),
        .ddr_wrdy(1'b0),
        .ddr_wdone(ddr_wdone),
        .ddr_wdata(),
        .ddr_wdata_req(1'b0),
        .frame_wcnt(),
        .frame_wirq(frame_wirq),
        .frame_ready_bank(frame_ready_bank)
    );

    task frame_start;
        begin
            wr_fsync = 1'b0;
            repeat (5) @(posedge ddr_clk);
            wr_fsync = 1'b1;
            repeat (5) @(posedge ddr_clk);
        end
    endtask

    task complete_line;
        begin
            @(negedge ddr_clk);
            ddr_wdone = 1'b1;
            @(negedge ddr_clk);
            ddr_wdone = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(posedge ddr_clk);
        ddr_rstn = 1'b1;

        frame_start;
        if(irq_count != 0) $fatal(1, "first frame cannot be ready");

        repeat (4) complete_line;
        frame_start;
        if(irq_count != 1 || frame_ready_bank !== 1'b0)
            $fatal(1, "completed bank 0 was not published");

        repeat (3) complete_line;
        frame_start;
        if(irq_count != 1)
            $fatal(1, "incomplete frame was published");

        repeat (4) complete_line;
        frame_start;
        if(irq_count != 2 || frame_ready_bank !== 1'b1)
            $fatal(1, "safe bank 1 was not reused after a dropped frame");

        $display("FRAME_BUFFER_CONTROL_PASS");
        $finish;
    end
endmodule

module wr_fram_buf(
    input [31:0] wr_data,
    input [11:0] wr_addr,
    input wr_en,
    input wr_clk,
    input wr_rst,
    input [8:0] rd_addr,
    output [255:0] rd_data,
    input rd_clk,
    input rd_rst
);
    assign rd_data = 256'd0;
endmodule

module read_bank_control_tb;
    reg ddr_clk = 0;
    reg vout_clk = 0;
    reg ddr_rstn = 0;
    reg init_done = 0;
    reg rd_fsync = 0;
    reg frame_ready_bank = 0;

    wire ddr_rreq;
    wire [11:0] ddr_raddr;

    always #4 ddr_clk = ~ddr_clk;
    always #5 vout_clk = ~vout_clk;

    rd_buf #(
        .ADDR_WIDTH(12),
        .H_NUM(8),
        .V_NUM(4),
        .PIX_WIDTH(16),
        .LINE_ADDR_WIDTH(8),
        .FRAME_CNT_WIDTH(2)
    ) dut (
        .ddr_clk(ddr_clk),
        .ddr_rstn(ddr_rstn),
        .vout_clk(vout_clk),
        .rd_fsync(rd_fsync),
        .rd_en(1'b0),
        .vout_de(),
        .vout_data(),
        .init_done(init_done),
        .frame_ready_bank(frame_ready_bank),
        .ddr_rreq(ddr_rreq),
        .ddr_raddr(ddr_raddr),
        .ddr_rd_len(),
        .ddr_rrdy(1'b0),
        .ddr_rdone(1'b0),
        .ddr_rdata(256'd0),
        .ddr_rdata_en(1'b0)
    );

    task output_frame_start;
        begin
            rd_fsync = 1'b0;
            repeat (5) @(posedge ddr_clk);
            rd_fsync = 1'b1;
            repeat (6) @(posedge ddr_clk);
        end
    endtask

    initial begin
        repeat (3) @(posedge ddr_clk);
        ddr_rstn = 1'b1;
        output_frame_start;
        if(ddr_rreq) $fatal(1, "read started before a complete frame existed");

        frame_ready_bank = 1'b1;
        init_done = 1'b1;
        output_frame_start;
        if(dut.read_bank !== 1'b1 || ddr_raddr[8] !== 1'b1)
            $fatal(1, "reader did not latch completed bank 1");

        frame_ready_bank = 1'b0;
        output_frame_start;
        if(dut.read_bank !== 1'b0 || ddr_raddr[8] !== 1'b0)
            $fatal(1, "reader did not switch to completed bank 0");

        $display("READ_BANK_CONTROL_PASS");
        $finish;
    end
endmodule

module rd_fram_buf(
    input [255:0] wr_data,
    input [8:0] wr_addr,
    input wr_en,
    input wr_clk,
    input wr_rst,
    input [11:0] rd_addr,
    output [31:0] rd_data,
    input rd_clk,
    input rd_rst
);
    assign rd_data = 32'd0;
endmodule
