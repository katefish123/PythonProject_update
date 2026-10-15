`timescale 1ns/1ps
module tb_ddr_word_engine;
 reg test_passed=0;
    reg clk = 0;
    reg rst_n = 0;
    reg init_done = 0;

    reg cmd_valid = 0;
    wire cmd_ready;
    reg cmd_write = 0;
    reg [27:0] cmd_addr = 0;
    reg [255:0] cmd_wdata = 0;
    reg [31:0] cmd_wstrb = 0;
    wire rsp_valid;
    wire rsp_write;
    wire [255:0] rsp_rdata;
    wire fault;

    wire [27:0] axi_awaddr;
    wire axi_awuser_ap;
    wire [3:0] axi_awuser_id, axi_awlen;
    wire axi_awvalid;
    reg axi_awready = 0;
    wire [255:0] axi_wdata;
    wire [31:0] axi_wstrb;
    reg axi_wready = 0;
    reg [3:0] axi_wusero_id = 0;
    reg axi_wusero_last = 0;
    wire [27:0] axi_araddr;
    wire axi_aruser_ap;
    wire [3:0] axi_aruser_id, axi_arlen;
    wire axi_arvalid;
    reg axi_arready = 0;
    reg [255:0] axi_rdata = 0;
    reg [3:0] axi_rid = 0;
    reg axi_rlast = 0;
    reg axi_rvalid = 0;

    integer aw_count = 0;
    integer w_count = 0;
    integer ar_count = 0;
    reg write_address_accepted = 0;
    integer seed = 32'h13579bdf;
    integer d, n;
    reg [27:0] held_addr;
    reg [255:0] held_data;
    reg [31:0] held_strb;
    reg [255:0] read_pattern;

    always #5 clk = ~clk;

    ddr_word_engine #(.WATCHDOG_CYCLES(12)) dut (.fault_reason(),.capture_burst_data(2048'd0),
        .clk(clk), .rst_n(rst_n), .init_done(init_done),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_source_block(1'b0),.rsp_source_block(),.cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .cmd_wstrb(cmd_wstrb),
        .rsp_valid(rsp_valid), .rsp_write(rsp_write), .rsp_rdata(rsp_rdata),
        .fault(fault),
        .axi_awaddr(axi_awaddr), .axi_awuser_ap(axi_awuser_ap),
        .axi_awuser_id(axi_awuser_id), .axi_awlen(axi_awlen),
        .axi_awvalid(axi_awvalid), .axi_awready(axi_awready),
        .axi_wdata(axi_wdata), .axi_wstrb(axi_wstrb),
        .axi_wready(axi_wready), .axi_wusero_id(axi_wusero_id),
        .axi_wusero_last(axi_wusero_last),
        .axi_araddr(axi_araddr), .axi_aruser_ap(axi_aruser_ap),
        .axi_aruser_id(axi_aruser_id), .axi_arlen(axi_arlen),
        .axi_arvalid(axi_arvalid), .axi_arready(axi_arready),
        .axi_rdata(axi_rdata), .axi_rid(axi_rid),
        .axi_rlast(axi_rlast), .axi_rvalid(axi_rvalid)
    );

    always @(posedge clk) begin
        if (axi_awvalid && axi_awready) begin
            aw_count <= aw_count + 1;
            if (axi_wready) w_count <= w_count + 1;
            else write_address_accepted <= 1'b1;
        end else if (write_address_accepted && axi_wready) begin
            w_count <= w_count + 1;
            write_address_accepted <= 1'b0;
        end
        if (axi_arvalid && axi_arready) ar_count <= ar_count + 1;
    end

    task automatic expect_no_response(input integer cycles);
        integer j;
        begin
            for (j=0; j<cycles; j=j+1) begin
                @(posedge clk); #1;
                if (rsp_valid) $fatal(1, "unexpected rsp_valid during stall");
            end
        end
    endtask

    task automatic start_command(input reg wr, input [27:0] addr,
                                 input [255:0] data, input [31:0] strb);
        begin
            @(negedge clk);
            cmd_write = wr;
            cmd_addr = addr;
            cmd_wdata = data;
            cmd_wstrb = strb;
            cmd_valid = 1;
            #1;
            if (!cmd_ready) $fatal(1, "command was not ready for acceptance");
            @(posedge clk); #1;
            @(negedge clk); cmd_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        if (cmd_ready) $fatal(1, "cmd_ready asserted before init_done");
        init_done = 1;
        @(negedge clk);
        if (!cmd_ready) $fatal(1, "cmd_ready did not follow init_done");
        if (axi_awuser_ap || axi_aruser_ap || axi_awuser_id !== 0 ||
            axi_aruser_id !== 0 || axi_awlen !== 0 || axi_arlen !== 0)
            $fatal(1, "AXI ID/length/AP constants are wrong");

        // AW and WREADY on the same edge must consume one write beat.
        start_command(1'b1, 28'h0012340,
                      256'h0123456789abcdef_fedcba9876543210_0011223344556677_8899aabbccddeeff,
                      32'hffff00ff);
        held_addr = 28'h0012340;
        held_data = 256'h0123456789abcdef_fedcba9876543210_0011223344556677_8899aabbccddeeff;
        held_strb = 32'hffff00ff;
        @(negedge clk);
        axi_awready = 1;
        axi_wready = 1;
        axi_wusero_id = 0;
        axi_wusero_last = 1;
        #1;
        if (!axi_awvalid || axi_awaddr !== held_addr || axi_wdata !== held_data || axi_wstrb !== held_strb)
            $fatal(1, "write command outputs incorrect on AW/WREADY edge");
        @(posedge clk); #1;
        if (!rsp_valid || !rsp_write || rsp_rdata !== 0)
            $fatal(1, "same-cycle AW/WREADY response incorrect");
        @(posedge clk); #1;
        if (rsp_valid) $fatal(1, "write response was not a one-cycle pulse");

        // Randomized AW stalls and WREADY high before AW: no early completion.
        start_command(1'b1, 28'h0008a20, 256'hdeadcafe, 32'h0000ffff);
        held_addr = 28'h0008a20;
        held_data = 256'hdeadcafe;
        held_strb = 32'h0000ffff;
        axi_wready = 1;
        axi_wusero_last = 1;
        axi_awready = 0;
        d = ($urandom(seed) % 4) + 2;
        for (n=0; n<d; n=n+1) begin
            @(posedge clk); #1;
            if (!axi_awvalid || axi_awaddr !== held_addr || axi_wdata !== held_data || axi_wstrb !== held_strb)
                $fatal(1, "write address/data changed during AW stall");
            if (rsp_valid) $fatal(1, "WREADY before AW incorrectly completed write");
        end
        @(negedge clk); axi_awready = 1; axi_wready = 0;
        @(posedge clk); #1;
        if (axi_awvalid) $fatal(1, "AWVALID remained asserted after AW handshake");
        axi_awready = 0;
        d = ($urandom(seed) % 4) + 2;
        for (n=0; n<d; n=n+1) begin
            @(posedge clk); #1;
            if (axi_wdata !== held_data || axi_wstrb !== held_strb)
                $fatal(1, "write data/strb changed while awaiting WREADY");
            if (rsp_valid) $fatal(1, "write completed before WREADY");
        end
        @(negedge clk); axi_wusero_last = 1; axi_wready = 1;
        @(posedge clk); #1;
        if (!rsp_valid || !rsp_write) $fatal(1, "delayed WREADY did not finish write");
        @(posedge clk); #1;
        axi_wready = 0;

        // AR handshake and the no-backpressure R beat may share a clock.
        read_pattern = 256'h0011223344556677_8899aabbccddeeff_fedcba9876543210_0123456789abcdef;
        start_command(1'b0, 28'h00fedc8, 0, 0);
        @(negedge clk); axi_arready = 1; axi_rvalid = 1;
        axi_rid = 0; axi_rlast = 1; axi_rdata = read_pattern;
        @(posedge clk); #1;
        if (!rsp_valid || rsp_write || rsp_rdata !== read_pattern)
            $fatal(1, "same-cycle AR/RVALID response incorrect");
        @(negedge clk); axi_arready = 0; axi_rvalid = 0;
        @(posedge clk); #1;

        // Delayed read response with malformed RID and missing RLAST.
        start_command(1'b0, 28'h0004560, 0, 0);
        @(negedge clk); axi_arready = 1; axi_rvalid = 0;
        @(posedge clk); #1;
        @(negedge clk); axi_arready = 0; axi_rvalid = 1;
        axi_rid = 4'h3; axi_rlast = 0; axi_rdata = read_pattern ^ 256'h1;
        @(posedge clk); #1;
        if (!rsp_valid || rsp_rdata !== (read_pattern ^ 256'h1) || !fault)
            $fatal(1, "malformed RID/RLAST was not captured and flagged");
        @(negedge clk); axi_rvalid = 0;
        @(posedge clk); #1;
        if (fault !== 1'b1) $fatal(1, "fault did not remain sticky");

        // Reset clears sticky fault and a pending transaction.
        @(negedge clk); rst_n = 0; init_done = 0;
        #1;
        if (cmd_ready || rsp_valid || fault || axi_awvalid || axi_arvalid)
            $fatal(1, "reset did not flush the outstanding transaction");
        repeat (2) @(negedge clk);
        rst_n = 1; init_done = 1;
        @(negedge clk);

        // Watchdog retires a stalled address command and reports sticky fault.
        start_command(1'b1, 28'h0000100, 256'h55aa, 32'hffffffff);
        @(negedge clk); axi_awready = 0; axi_wready = 0;
        n = 0;
        while (!rsp_valid && n < 16) begin
            @(posedge clk); #1; n = n + 1;
        end
        if (!rsp_valid || !fault || !rsp_write || rsp_rdata !== 0)
            $fatal(1, "watchdog did not return a fault response");

        // A late read beat must not be mistaken for a later command. Fault
        // locks command acceptance and AXI traffic until common reset.
        @(posedge clk); #1;
        @(negedge clk);
        cmd_write = 0; cmd_addr = 28'h0000180; cmd_wdata = 0; cmd_wstrb = 0; cmd_valid = 1;
        axi_arready = 1; axi_rvalid = 1; axi_rid = 0; axi_rlast = 1;
        axi_rdata = 256'hface;
        #1;
        if (cmd_ready || axi_arvalid || rsp_valid)
            $fatal(1, "sticky fault did not block the next command");
        repeat (2) begin
            @(posedge clk); #1;
            if (cmd_ready || axi_arvalid || rsp_valid || rsp_rdata !== 0)
                $fatal(1, "late rvalid was mis-associated after timeout");
        end
        @(negedge clk); cmd_valid = 0; axi_arready = 0; axi_rvalid = 0;

        // A fresh reset also cancels an in-flight command before response.
        @(negedge clk); rst_n = 0; init_done = 0;
        #1;
        if (cmd_ready || rsp_valid || fault) $fatal(1, "reset failed to cancel timeout response/fault");
        repeat (2) @(negedge clk);
        rst_n = 1; init_done = 1;
        @(negedge clk);
        start_command(1'b0, 28'h0000200, 0, 0);
        @(negedge clk); axi_arready = 0;
        if (!axi_arvalid) $fatal(1, "reset-cancel test did not enter AR stall");
        @(negedge clk); rst_n = 0; init_done = 0;
        #1;
        if (cmd_ready || rsp_valid || axi_arvalid || fault) $fatal(1, "reset did not cancel active AR transaction");
        repeat (2) @(negedge clk);
        test_passed=1;$display("DDR_WORD_ENGINE_PASS aw=%0d w=%0d ar=%0d", aw_count, w_count, ar_count);
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "DDR word engine testbench timeout");
    end
endmodule

