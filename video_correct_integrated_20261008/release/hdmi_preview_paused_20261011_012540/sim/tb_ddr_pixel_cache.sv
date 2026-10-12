`timescale 1ns/1ps
module tb_ddr_pixel_cache;
    reg clk = 0;
    reg rst_n = 0;
    reg invalidate = 0;
    reg mem_valid = 0;
    wire mem_ready;
    reg [23:0] mem_addr = 0;
    wire mem_rsp_valid;
    wire [23:0] mem_rgb;
    reg [27:0] base_word_addr = 0;

    wire cmd_valid;
    reg cmd_ready = 0;
    wire cmd_write;
    wire [27:0] cmd_addr;
    wire [255:0] cmd_wdata;
    wire [31:0] cmd_wstrb;
    reg rsp_valid = 0;
    reg rsp_write = 0;
    reg [255:0] rsp_rdata = 0;

    integer cmd_count = 0;
    integer seed = 32'h2468ace1;
    integer d, lane;
    reg [27:0] held_cmd_addr;
    reg [23:0] exp_rgb;
    reg [255:0] beat;

    always #5 clk = ~clk;
    always @(posedge clk)
        if (cmd_valid && cmd_ready) cmd_count <= cmd_count + 1;

    ddr_pixel_cache dut (
        .clk(clk), .rst_n(rst_n), .invalidate(invalidate),
        .mem_valid(mem_valid), .mem_ready(mem_ready), .mem_addr(mem_addr),
        .mem_rsp_valid(mem_rsp_valid), .mem_rgb(mem_rgb),
        .base_word_addr(base_word_addr),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_write(cmd_write),
        .cmd_addr(cmd_addr), .cmd_wdata(cmd_wdata), .cmd_wstrb(cmd_wstrb),
        .rsp_valid(rsp_valid), .rsp_write(rsp_write), .rsp_rdata(rsp_rdata)
    );

    function automatic [23:0] expected_pixel(input [27:0] word_addr);
        begin
            expected_pixel = {word_addr[7:0], word_addr[15:8], word_addr[23:16]};
        end
    endfunction

    function automatic [255:0] make_beat(input [27:0] word_addr);
        reg [255:0] value;
        integer k;
        reg [27:0] lane_addr;
        begin
            value = 256'd0;
            for (k=0; k<8; k=k+1) begin
                lane_addr = word_addr + k;
                value[k*32 +: 32] = {8'hA5, expected_pixel(lane_addr)};
            end
            make_beat = value;
        end
    endfunction

    task automatic request_pixel(input [27:0] base,
                                 input [23:0] pixel_index,
                                 input reg expect_miss);
        reg [27:0] expected_line;
        reg [27:0] expected_word;
        reg [24:0] saved_tag;
        integer j;
        begin
            expected_line = base + {4'd0, pixel_index[23:3], 3'b000};
            expected_word = base + pixel_index;
            exp_rgb = expected_pixel(expected_word);
            @(negedge clk);
            base_word_addr = base;
            mem_addr = pixel_index;
            mem_valid = 1;
            #1;
            if (!mem_ready) $fatal(1, "cache did not accept an idle request");
            if (cmd_write || cmd_wdata !== 0 || cmd_wstrb !== 0)
                $fatal(1, "cache emitted a write command");
            @(posedge clk); #1;
            @(negedge clk); mem_valid = 0;

            if (expect_miss) begin
                if (!cmd_valid) $fatal(1, "expected cache miss did not issue a command");
                if (cmd_addr !== expected_line || cmd_addr[2:0] !== 0)
                    $fatal(1, "miss address wrong got=%h expected=%h", cmd_addr, expected_line);
                held_cmd_addr = cmd_addr;
                saved_tag = cmd_addr[27:3];
                if (cmd_write || cmd_wdata !== 0 || cmd_wstrb !== 0)
                    $fatal(1, "miss command was not read-only");
                d = ($urandom(seed) % 4) + 2;
                for (j=0; j<d; j=j+1) begin
                    @(posedge clk); #1;
                    if (!cmd_valid || cmd_addr !== held_cmd_addr || cmd_addr[27:3] !== saved_tag)
                        $fatal(1, "cache miss command changed while stalled");
                    if (mem_rsp_valid) $fatal(1, "cache responded before memory data");
                end

                @(negedge clk); cmd_ready = 1;
                @(posedge clk); #1;
                @(negedge clk); cmd_ready = 0;
                if (cmd_valid) $fatal(1, "cmd_valid did not drop after handshake");
                d = ($urandom(seed) % 4) + 1;
                repeat (d) begin
                    @(posedge clk); #1;
                    if (mem_rsp_valid) $fatal(1, "cache responded before rsp_valid");
                end
                beat = make_beat(held_cmd_addr);
                @(negedge clk); rsp_rdata = beat; rsp_write = 0; rsp_valid = 1;
                @(posedge clk); #1;
                if (!mem_rsp_valid || mem_rgb !== exp_rgb)
                    $fatal(1, "miss response byte/lane mismatch got=%h expected=%h index=%h base=%h", mem_rgb, exp_rgb, pixel_index, base);
                @(negedge clk); rsp_valid = 0;
                @(posedge clk); #1;
                if (mem_rsp_valid) $fatal(1, "miss response valid was not a one-cycle pulse");
            end else begin
                if (cmd_valid) $fatal(1, "cache hit unexpectedly issued a DDR command");
                if (!mem_rsp_valid || mem_rgb !== exp_rgb)
                    $fatal(1, "cache hit RGB mismatch got=%h expected=%h", mem_rgb, exp_rgb);
                @(posedge clk); #1;
                if (mem_rsp_valid) $fatal(1, "hit response valid was not a one-cycle pulse");
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // Fill one line, then read another pixel in that line (including lane 7).
        request_pixel(28'h0000100, 24'd0, 1'b1);
        request_pixel(28'h0000100, 24'd7, 1'b0);

        // Two-line associativity and true two-way LRU replacement.
        request_pixel(28'h0000100, 24'd8, 1'b1);  // B
        request_pixel(28'h0000100, 24'd0, 1'b0);  // A is most recently used
        request_pixel(28'h0000100, 24'd16, 1'b1); // C evicts B
        request_pixel(28'h0000100, 24'd0, 1'b0);  // A still hits
        request_pixel(28'h0000100, 24'd8, 1'b1);  // B was evicted

        // A different frame base forms a different absolute address/tag.
        request_pixel(28'h0000200, 24'd0, 1'b1);
        request_pixel(28'h0000100, 24'd0, 1'b1);

        // Invalidate clears both ways.
        @(negedge clk); invalidate = 1;
        @(posedge clk); #1;
        @(negedge clk); invalidate = 0;
        request_pixel(28'h0000100, 24'd0, 1'b1);

        // Invalidate during a miss is deferred: the in-flight result returns,
        // but is not retained for a later request.
        @(negedge clk);
        base_word_addr = 28'h0000300; mem_addr = 24'd0; mem_valid = 1;
        @(posedge clk); #1;
        @(negedge clk); mem_valid = 0; invalidate = 1;
        if (!cmd_valid) $fatal(1, "expected deferred-invalidate miss absent");
        d = ($urandom(seed) % 3) + 1;
        repeat (d) @(posedge clk);
        @(negedge clk); invalidate = 0; cmd_ready = 1;
        @(posedge clk); #1;
        @(negedge clk); cmd_ready = 0;
        beat = make_beat(cmd_addr);
        @(negedge clk); rsp_rdata = beat; rsp_valid = 1;
        @(posedge clk); #1;
        if (!mem_rsp_valid || mem_rgb !== expected_pixel(28'h0000300))
            $fatal(1, "deferred invalidate did not return in-flight pixel");
        @(negedge clk); rsp_valid = 0;
        @(posedge clk); #1;
        request_pixel(28'h0000300, 24'd0, 1'b1);

        // Upper address boundary remains aligned and selects byte RGB from
        // the highest in-range cache-line offset.
        request_pixel(28'h0ffff00, 24'hfffff8, 1'b1);

        // Reset cancels an outstanding miss and leaves no late response.
        @(negedge clk); base_word_addr = 28'h0000400; mem_addr = 0; mem_valid = 1;
        @(posedge clk); #1;
        @(negedge clk); mem_valid = 0;
        if (!cmd_valid) $fatal(1, "reset test did not create a miss");
        rst_n = 0;
        #1;
        if (mem_ready || cmd_valid || mem_rsp_valid) $fatal(1, "reset failed to cancel pending miss");
        repeat (2) @(negedge clk);
        rst_n = 1;
        @(negedge clk);
        request_pixel(28'h0000400, 24'd0, 1'b1);

        $display("DDR_PIXEL_CACHE_PASS memory_reads=%0d", cmd_count);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "DDR pixel cache testbench timeout");
    end
endmodule
