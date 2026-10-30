`timescale 1ns/1ps
module tb_ddr_helpers;
    reg src_clk=0, dst_clk=0, core_clk=0;
    reg bridge_rst_n=0, arb_rst_n=0, writer_rst_n=0, selftest_rst_n=0;
    always #5 src_clk = ~src_clk;
    always #7 dst_clk = ~dst_clk;
    always #4 core_clk = ~core_clk;

    // ------------------------------------------------------------------
    // Async command bridge: bundled-data stability, response return, reset.
    reg src_cmd_valid=0, src_cmd_write=0;
    reg [27:0] src_cmd_addr=0;
    reg [255:0] src_cmd_wdata=0;
    reg [31:0] src_cmd_wstrb=0;
    wire src_cmd_ready, src_rsp_valid, src_rsp_write;
    wire [255:0] src_rsp_rdata;
    wire dst_cmd_valid, dst_cmd_write;
    wire [27:0] dst_cmd_addr;
    wire [255:0] dst_cmd_wdata;
    wire [31:0] dst_cmd_wstrb;
    reg dst_cmd_ready=0, dst_rsp_valid=0, dst_rsp_write=0;
    reg [255:0] dst_rsp_rdata=0;

    ddr_command_bridge bridge (
        .src_clk(src_clk), .src_rst_n(bridge_rst_n),
        .dst_clk(dst_clk), .dst_rst_n(bridge_rst_n),
        .src_cmd_valid(src_cmd_valid), .src_cmd_ready(src_cmd_ready),
        .src_cmd_write(src_cmd_write), .src_cmd_addr(src_cmd_addr),
        .src_cmd_wdata(src_cmd_wdata), .src_cmd_wstrb(src_cmd_wstrb),
        .src_rsp_valid(src_rsp_valid), .src_rsp_write(src_rsp_write),
        .src_rsp_rdata(src_rsp_rdata),
        .dst_cmd_valid(dst_cmd_valid), .dst_cmd_ready(dst_cmd_ready),
        .dst_cmd_write(dst_cmd_write), .dst_cmd_addr(dst_cmd_addr),
        .dst_cmd_wdata(dst_cmd_wdata), .dst_cmd_wstrb(dst_cmd_wstrb),
        .dst_rsp_valid(dst_rsp_valid), .dst_rsp_write(dst_rsp_write),
        .dst_rsp_rdata(dst_rsp_rdata)
    );

    // ------------------------------------------------------------------
    // Three-client arbiter: priority and response ownership.
    reg arb_enabled=0, arb_cmd_ready=0, arb_rsp_valid=0, arb_rsp_write=0;
    reg c0_valid=0,c0_write=0,c1_valid=0,c1_write=0,c2_valid=0,c2_write=0;
    reg [27:0] c0_addr=0,c1_addr=0,c2_addr=0;
    reg [255:0] c0_wdata=0,c1_wdata=0,c2_wdata=0;
    reg [31:0] c0_wstrb=0,c1_wstrb=0,c2_wstrb=0;
    wire c0_ready,c1_ready,c2_ready,c0_rsp_valid,c1_rsp_valid,c2_rsp_valid;
    wire c0_rsp_write,c1_rsp_write,c2_rsp_write;
    wire [255:0] c0_rdata,c1_rdata,c2_rdata;
    wire arb_cmd_valid,arb_cmd_write;
    wire [27:0] arb_cmd_addr;
    wire [255:0] arb_cmd_wdata;
    reg [255:0] arb_rdata=0;
    wire [31:0] arb_cmd_wstrb;

    ddr_arbiter3 arbiter (
        .clk(core_clk), .rst_n(arb_rst_n), .enabled(arb_enabled),
        .c0_valid(c0_valid), .c0_write(c0_write), .c0_addr(c0_addr),
        .c0_wdata(c0_wdata), .c0_wstrb(c0_wstrb), .c0_ready(c0_ready),
        .c0_rsp_valid(c0_rsp_valid), .c0_rsp_write(c0_rsp_write), .c0_rdata(c0_rdata),
        .c1_valid(c1_valid), .c1_write(c1_write), .c1_addr(c1_addr),
        .c1_wdata(c1_wdata), .c1_wstrb(c1_wstrb), .c1_ready(c1_ready),
        .c1_rsp_valid(c1_rsp_valid), .c1_rsp_write(c1_rsp_write), .c1_rdata(c1_rdata),
        .c2_valid(c2_valid), .c2_write(c2_write), .c2_addr(c2_addr),
        .c2_wdata(c2_wdata), .c2_wstrb(c2_wstrb), .c2_ready(c2_ready),
        .c2_rsp_valid(c2_rsp_valid), .c2_rsp_write(c2_rsp_write), .c2_rdata(c2_rdata),
        .cmd_valid(arb_cmd_valid), .cmd_write(arb_cmd_write), .cmd_addr(arb_cmd_addr),
        .cmd_wdata(arb_cmd_wdata), .cmd_wstrb(arb_cmd_wstrb),
        .cmd_ready(arb_cmd_ready), .rsp_valid(arb_rsp_valid),
        .rsp_write(arb_rsp_write), .rsp_rdata(arb_rdata)
    );

    // ------------------------------------------------------------------
    // Result writer: 5x3 exercises a full line and a partial final line.
    reg frame_start=0, abort_frame=0, frame_bank=1;
    reg write_valid=0;
    reg [23:0] write_addr=0, write_rgb=0;
    wire write_ready, drained, writer_fault, writer_cmd_valid, writer_cmd_write;
    wire [27:0] writer_cmd_addr;
    wire [255:0] writer_cmd_wdata;
    wire [31:0] writer_cmd_wstrb;
    reg writer_cmd_ready=0, writer_rsp_valid=0, writer_rsp_write=0;

    ddr_result_writer #(
        .OUT_W(5), .OUT_H(3), .BASE0(28'h0001000), .BASE1(28'h0002000)
    ) result_writer (
        .clk(core_clk), .rst_n(writer_rst_n), .frame_start(frame_start),
        .abort_frame(abort_frame), .frame_bank(frame_bank),
        .write_valid(write_valid), .write_ready(write_ready),
        .write_addr(write_addr), .write_rgb(write_rgb),
        .drained(drained), .fault(writer_fault),
        .cmd_valid(writer_cmd_valid), .cmd_ready(writer_cmd_ready),
        .cmd_write(writer_cmd_write), .cmd_addr(writer_cmd_addr),
        .cmd_wdata(writer_cmd_wdata), .cmd_wstrb(writer_cmd_wstrb),
        .rsp_valid(writer_rsp_valid), .rsp_write(writer_rsp_write)
    );

    // ------------------------------------------------------------------
    // Self-test with real write/read memory model, plus one corrupted word.
    reg selftest_good_enable=0, selftest_bad_enable=0;
    wire good_cmd_valid, good_cmd_write, good_cmd_ready;
    wire [27:0] good_cmd_addr;
    wire [255:0] good_cmd_wdata;
    wire [31:0] good_cmd_wstrb;
    reg good_rsp_valid=0, good_rsp_write=0;
    reg [255:0] good_rsp_rdata=0;
    wire good_passed,good_failed;
    wire bad_cmd_valid,bad_cmd_write,bad_cmd_ready;
    wire [27:0] bad_cmd_addr;
    wire [255:0] bad_cmd_wdata;
    wire [31:0] bad_cmd_wstrb;
    reg bad_rsp_valid=0,bad_rsp_write=0;
    reg [255:0] bad_rsp_rdata=0;
    wire bad_passed,bad_failed;
    reg [255:0] good_mem[0:3];
    reg [255:0] bad_mem[0:3];
    reg good_pending=0,bad_pending=0;
    integer good_mem_index,bad_mem_index,bad_read_count=0;
    integer k;

    ddr_self_test #(.BEATS(4), .BASE(28'h0004000)) selftest_good (
        .clk(core_clk), .rst_n(selftest_rst_n), .enabled(selftest_good_enable),
        .passed(good_passed), .failed(good_failed),
        .cmd_valid(good_cmd_valid), .cmd_ready(good_cmd_ready),
        .cmd_write(good_cmd_write), .cmd_addr(good_cmd_addr),
        .cmd_wdata(good_cmd_wdata), .cmd_wstrb(good_cmd_wstrb),
        .rsp_valid(good_rsp_valid), .rsp_write(good_rsp_write), .rsp_rdata(good_rsp_rdata)
    );
    ddr_self_test #(.BEATS(4), .BASE(28'h0005000)) selftest_bad (
        .clk(core_clk), .rst_n(selftest_rst_n), .enabled(selftest_bad_enable),
        .passed(bad_passed), .failed(bad_failed),
        .cmd_valid(bad_cmd_valid), .cmd_ready(bad_cmd_ready),
        .cmd_write(bad_cmd_write), .cmd_addr(bad_cmd_addr),
        .cmd_wdata(bad_cmd_wdata), .cmd_wstrb(bad_cmd_wstrb),
        .rsp_valid(bad_rsp_valid), .rsp_write(bad_rsp_write), .rsp_rdata(bad_rsp_rdata)
    );
    assign good_cmd_ready = 1'b1;
    assign bad_cmd_ready = 1'b1;

    function automatic [31:0] test_pattern(input [23:0] beat, input integer lane);
        begin test_pattern = 32'h5a3cc3a5 ^ (beat*32'h00010001) ^ (lane*32'h01010101); end
    endfunction
    function automatic [23:0] pixel_rgb(input integer idx);
        begin pixel_rgb = 24'h210000 + idx; end
    endfunction

    always @(posedge core_clk or negedge selftest_rst_n) begin
        if (!selftest_rst_n) begin
            good_pending <= 0; bad_pending <= 0;
            good_rsp_valid <= 0; bad_rsp_valid <= 0;
            good_rsp_write <= 0; bad_rsp_write <= 0;
            good_rsp_rdata <= 0; bad_rsp_rdata <= 0;
            bad_read_count <= 0;
            for (k=0; k<4; k=k+1) begin good_mem[k] <= 0; bad_mem[k] <= 0; end
        end else begin
            good_rsp_valid <= 0;
            bad_rsp_valid <= 0;
            if (good_pending) begin good_rsp_valid <= 1; good_pending <= 0; end
            if (bad_pending) begin bad_rsp_valid <= 1; bad_pending <= 0; end

            if (good_cmd_valid && good_cmd_ready) begin
                good_mem_index = (good_cmd_addr - 28'h0004000) >> 3;
                if (good_mem_index < 0 || good_mem_index > 3) $fatal(1, "good self-test address out of range");
                good_pending <= 1;
                good_rsp_write <= good_cmd_write;
                if (good_cmd_write) good_mem[good_mem_index] <= good_cmd_wdata;
                else good_rsp_rdata <= good_mem[good_mem_index];
            end

            if (bad_cmd_valid && bad_cmd_ready) begin
                bad_mem_index = (bad_cmd_addr - 28'h0005000) >> 3;
                if (bad_mem_index < 0 || bad_mem_index > 3) $fatal(1, "bad self-test address out of range");
                bad_pending <= 1;
                bad_rsp_write <= bad_cmd_write;
                if (bad_cmd_write) bad_mem[bad_mem_index] <= bad_cmd_wdata;
                else begin
                    bad_rsp_rdata <= bad_mem[bad_mem_index];
                    if (bad_read_count == 0) bad_rsp_rdata <= bad_mem[bad_mem_index] ^ 256'h1;
                    bad_read_count <= bad_read_count + 1;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    integer i;
    reg [255:0] expected_pack;
    reg [31:0] expected_strobes;
    reg [27:0] bridge_saved_addr;
    reg [255:0] bridge_saved_data;
    reg [31:0] bridge_saved_strb;

    task automatic push_pixel(input integer idx);
        begin
            @(negedge core_clk);
            write_addr = idx;
            write_rgb = 24'h210000 + idx;
            write_valid = 1;
            #1;
            if (!write_ready) $fatal(1, "result writer refused expected sequential pixel %0d", idx);
            @(posedge core_clk); #1;
            @(negedge core_clk); write_valid = 0;
        end
    endtask

    initial begin
        repeat (3) @(negedge src_clk);
        bridge_rst_n=1; arb_rst_n=1; writer_rst_n=1; selftest_rst_n=1;

        // Cross unrelated source/destination clocks; hold payload while stalled.
        @(negedge src_clk);
        if (!src_cmd_ready) $fatal(1, "bridge source not initially ready");
        src_cmd_valid=1; src_cmd_write=1; src_cmd_addr=28'h0012340;
        src_cmd_wdata=256'h0123456789abcdef_fedcba9876543210_0011223344556677_8899aabbccddeeff;
        src_cmd_wstrb=32'hff00ff00;
        bridge_saved_addr=src_cmd_addr; bridge_saved_data=src_cmd_wdata; bridge_saved_strb=src_cmd_wstrb;
        @(posedge src_clk); #1;
        @(negedge src_clk); src_cmd_valid=0;
        src_cmd_write=0; src_cmd_addr=0; src_cmd_wdata=0; src_cmd_wstrb=0;
        wait(dst_cmd_valid); #1;
        if (!dst_cmd_write || dst_cmd_addr!==bridge_saved_addr ||
            dst_cmd_wdata!==bridge_saved_data || dst_cmd_wstrb!==bridge_saved_strb)
            $fatal(1, "bridge bundled command payload mismatch");
        repeat (3) begin
            @(posedge dst_clk); #1;
            if (!dst_cmd_valid || dst_cmd_addr!==bridge_saved_addr ||
                dst_cmd_wdata!==bridge_saved_data || dst_cmd_wstrb!==bridge_saved_strb)
                $fatal(1, "bridge payload changed while destination stalled");
            if (src_cmd_ready) $fatal(1, "bridge accepted a second outstanding command");
        end
        @(negedge dst_clk); dst_cmd_ready=1;
        @(posedge dst_clk); #1;
        @(negedge dst_clk); dst_cmd_ready=0;
        repeat (2) @(negedge dst_clk);
        dst_rsp_write=1; dst_rsp_rdata=256'h89abcdef;
        dst_rsp_valid=1;
        @(posedge dst_clk); #1;
        @(negedge dst_clk); dst_rsp_valid=0;
        wait(src_rsp_valid); #1;
        if (!src_rsp_write || src_rsp_rdata!==256'h89abcdef || !src_cmd_ready)
            $fatal(1, "bridge response did not return to source domain");

        // A coordinated reset flushes a second unaccepted destination command.
        @(negedge src_clk);
        src_cmd_valid=1; src_cmd_write=0; src_cmd_addr=28'h0000800;
        @(posedge src_clk); #1;
        @(negedge src_clk); src_cmd_valid=0;
        wait(dst_cmd_valid);
        bridge_rst_n=0;
        #1;
        if (dst_cmd_valid || src_rsp_valid) $fatal(1, "bridge reset did not cancel request/response");
        repeat (3) @(negedge dst_clk);
        bridge_rst_n=1;
        repeat (6) @(negedge dst_clk);
        if (dst_cmd_valid || src_rsp_valid) $fatal(1, "bridge produced stale traffic after reset");

        // Priority order is client 2 > client 1 > client 0; retain owner to response.
        @(negedge core_clk);
        c0_valid=1; c0_write=0; c0_addr=28'h10; c0_wdata=256'h10;
        c1_valid=1; c1_write=1; c1_addr=28'h20; c1_wdata=256'h20;
        c2_valid=1; c2_write=1; c2_addr=28'h30; c2_wdata=256'h30;
        arb_enabled=1; arb_cmd_ready=0;
        #1;
        if (!arb_cmd_valid || arb_cmd_addr!==28'h30 || !arb_cmd_write || arb_cmd_wdata!==256'h30)
            $fatal(1, "arbiter display priority/data selection wrong");
        repeat (2) begin @(posedge core_clk); #1; if (c2_ready || c1_ready || c0_ready) $fatal(1, "arbiter ready asserted during engine stall"); end
        @(negedge core_clk); arb_cmd_ready=1;
        #1;
        if (!c2_ready || c1_ready || c0_ready) $fatal(1, "arbiter did not acknowledge client 2");
        @(posedge core_clk); #1;
        @(negedge core_clk); arb_cmd_ready=0; c2_valid=0;
        c0_valid=0; c1_valid=1;
        arb_rsp_write=1; arb_rdata=256'hfacefeed; arb_rsp_valid=1;
        #1;
        if (!c2_rsp_valid || c1_rsp_valid || c0_rsp_valid || c2_rdata!==256'hfacefeed)
            $fatal(1, "arbiter response owner was not retained");
        @(posedge core_clk); #1;
        @(negedge core_clk); arb_rsp_valid=0;

        // Client 1 wins over client 0 and receives only its response.
        @(negedge core_clk); c0_valid=1; c1_valid=1; c2_valid=0; arb_cmd_ready=1;
        #1;
        if (arb_cmd_addr!==28'h20 || !arb_cmd_write) $fatal(1, "arbiter capture priority wrong");
        if (!c1_ready || c0_ready || c2_ready) $fatal(1, "arbiter did not accept client 1");
        @(posedge core_clk); #1;
        @(negedge core_clk); c1_valid=0; arb_cmd_ready=0; arb_rsp_valid=1;
        #1;
        if (!c1_rsp_valid || c0_rsp_valid || c2_rsp_valid) $fatal(1, "arbiter client 1 response route wrong");
        @(posedge core_clk); #1;
        @(negedge core_clk); arb_rsp_valid=0; c0_valid=0;

        // Client 0 is the fallback when neither capture nor display requests.
        @(negedge core_clk); c0_valid=1; c0_addr=28'h40; arb_cmd_ready=1;
        #1;
        if (arb_cmd_addr!==28'h40 || !c0_ready || c1_ready || c2_ready)
            $fatal(1, "arbiter processor fallback/ready routing wrong");
        @(posedge core_clk); #1;
        @(negedge core_clk); c0_valid=0; arb_cmd_ready=0;
        arb_rsp_valid=1; arb_rsp_write=0; arb_rdata=256'h1234;
        #1;
        if (!c0_rsp_valid || c1_rsp_valid || c2_rsp_valid || c0_rdata!==256'h1234)
            $fatal(1, "arbiter client 0 response route wrong");
        @(posedge core_clk); #1;
        @(negedge core_clk); arb_rsp_valid=0;

        // Reset cancels an accepted arbiter owner before its engine response.
        @(negedge core_clk); c0_valid=1; arb_cmd_ready=1;
        #1; if (!c0_ready) $fatal(1, "arbiter reset-cancel request not ready");
        @(posedge core_clk); #1;
        @(negedge core_clk); c0_valid=0; arb_cmd_ready=0; arb_rst_n=0;
        #1;
        if (c0_rsp_valid || c1_rsp_valid || c2_rsp_valid)
            $fatal(1, "arbiter reset did not clear pending owner");
        repeat (2) @(negedge core_clk);
        arb_rst_n=1;

        // Pixel packing, full beat stall stability, and accepted-write draining.
        @(negedge core_clk); frame_start=1; frame_bank=1;
        @(posedge core_clk); #1;
        @(negedge core_clk); frame_start=0;
        for (i=0; i<8; i=i+1) push_pixel(i);
        if (!writer_cmd_valid || writer_cmd_addr!==28'h0002000 ||
            !writer_cmd_write || writer_cmd_wstrb!==32'hffffffff)
            $fatal(1, "full packed result beat metadata wrong");
        for (i=0; i<8; i=i+1)
            if (writer_cmd_wdata[i*32 +: 32] !== {8'd0, pixel_rgb(i)})
                $fatal(1, "full beat pixel packing/order mismatch lane=%0d", i);
        expected_pack=writer_cmd_wdata;
        repeat (2) begin
            @(posedge core_clk); #1;
            if (!writer_cmd_valid || writer_cmd_wdata!==expected_pack || writer_cmd_addr!==28'h0002000)
                $fatal(1, "writer changed packed payload while stalled");
        end
        @(negedge core_clk); writer_cmd_ready=1;
        @(posedge core_clk); #1;
        @(negedge core_clk); writer_cmd_ready=0; abort_frame=1;
        if (drained) $fatal(1, "writer drained before accepted DDR response");
        repeat (2) @(posedge core_clk);
        @(negedge core_clk); writer_rsp_write=1; writer_rsp_valid=1;
        @(posedge core_clk); #1;
        @(negedge core_clk); writer_rsp_valid=0; abort_frame=0;
        if (!drained || writer_fault) $fatal(1, "accepted write did not drain cleanly on abort");

        // Final partial beat writes seven RGB words and zero-pads lane seven.
        for (i=8; i<15; i=i+1) push_pixel(i);
        if (!writer_cmd_valid || writer_cmd_addr!==28'h0002008 ||
            writer_cmd_wstrb!==32'h0fffffff)
            $fatal(1, "partial final beat address/strobes wrong");
        for (i=0; i<7; i=i+1)
            if (writer_cmd_wdata[i*32 +: 32] !== {8'd0, pixel_rgb(8+i)})
                $fatal(1, "partial beat lane mismatch lane=%0d", i);
        if (writer_cmd_wdata[255:224] !== 0) $fatal(1, "partial final lane was not zero padded");
        @(negedge core_clk); writer_cmd_ready=1; writer_rsp_valid=1; writer_rsp_write=1;
        @(posedge core_clk); #1;
        @(negedge core_clk); writer_cmd_ready=0; writer_rsp_valid=0;
        if (!drained || writer_fault) $fatal(1, "same-cycle writer response did not drain final beat");

        // Abort discards an uncommitted partial pack and restores drained.
        @(negedge core_clk); frame_start=1; frame_bank=0;
        @(posedge core_clk); #1;
        @(negedge core_clk); frame_start=0;
        push_pixel(0);
        if (drained) $fatal(1, "partial pack incorrectly reported drained");
        @(negedge core_clk); abort_frame=1;
        @(posedge core_clk); #1;
        @(negedge core_clk); abort_frame=0;
        if (!drained || writer_cmd_valid || writer_fault)
            $fatal(1, "abort did not flush uncommitted partial data");

        // Self-test writes all eight words, reads them back, then catches damage.
        @(negedge core_clk); selftest_good_enable=1;
        wait(good_passed || good_failed);
        if (!good_passed || good_failed) $fatal(1, "self-test rejected a correct memory model");
        @(negedge core_clk); selftest_good_enable=0; selftest_bad_enable=1;
        wait(bad_passed || bad_failed);
        if (!bad_failed || bad_passed) $fatal(1, "self-test did not detect corrupted readback");
        @(negedge core_clk); selftest_rst_n=0;
        #1;
        if (good_passed || good_failed || bad_passed || bad_failed)
            $fatal(1, "self-test reset did not clear terminal status");
        repeat (2) @(negedge core_clk);

        $display("DDR_HELPERS_PASS bridge_async_rsp_reset arbiter_routes writer_pack_flush selftest_good_bad_reset");
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "DDR helper testbench timeout");
    end
endmodule
