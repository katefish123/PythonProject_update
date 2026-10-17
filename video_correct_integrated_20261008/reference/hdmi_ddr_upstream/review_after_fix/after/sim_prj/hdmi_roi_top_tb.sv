`timescale 1ns/1ps

module hdmi_roi_top_tb;
    reg sys_clk = 0;
    reg rst_in = 0;

    wire pix_clk;
    wire vs_out, hs_out, de_out;
    wire [7:0] r_out, g_out, b_out;
    wire rstn_out;

    always #1 sys_clk = ~sys_clk;

    HDMI_IN_DDR3_ROI_top #(
        .DEBUG_FORCE_BOX(1),
        .BOX_THICK(1),
        .FIX_BOX_X1(2), .FIX_BOX_Y1(2),
        .FIX_BOX_X2(5), .FIX_BOX_Y2(5)
    ) dut (
        .sys_clk(sys_clk), .clk_p(1'b0), .clk_n(1'b0), .rst_in(rst_in),
        .mem_rst_n(), .mem_ck(), .mem_ck_n(), .mem_cke(), .mem_cs_n(),
        .mem_ras_n(), .mem_cas_n(), .mem_we_n(), .mem_odt(),
        .mem_a(), .mem_ba(), .mem_dqs(), .mem_dqs_n(), .mem_dq(), .mem_dm(),
        .heart_beat_led(), .ddr_init_done(), .init_over_rx(),
        .rstn_out(rstn_out), .hd_scl(), .hd_sda(), .hdmi_int_led(),
        .pixclk_in(sys_clk), .vs_in(1'b0), .hs_in(1'b0), .de_in(1'b0),
        .r_in(8'd0), .g_in(8'd0), .b_in(8'd0),
        .pix_clk(pix_clk), .vs_out(vs_out), .hs_out(hs_out), .de_out(de_out),
        .r_out(r_out), .g_out(g_out), .b_out(b_out)
    );

    initial begin
        force dut.cfg_clk = sys_clk;
        force dut.locked = 1'b1;
        force dut.pix_clk = sys_clk;
        force dut.pix_clk_rst_n = 1'b1;
        force dut.vs_reg = 1'b0;
        force dut.hs_reg = 1'b0;
        force dut.de_o = 1'b1;
        force dut.o_rgb565 = 16'hF81F;

        repeat (3) @(posedge sys_clk);
        if(rstn_out !== 1'b0) $fatal(1, "reset output ignored rst_in low");
        rst_in = 1'b1;
        repeat (10005) @(posedge sys_clk);
        #1;
        if(rstn_out !== 1'b1) $fatal(1, "reset release delay did not complete");

        force dut.act_x = 12'd10;
        force dut.act_y = 12'd10;
        @(posedge sys_clk); #1;
        if({r_out,g_out,b_out} !== 24'hF800F8)
            $fatal(1, "pixels outside ROI were not preserved");

        force dut.act_x = 12'd2;
        force dut.act_y = 12'd3;
        @(posedge sys_clk); #1;
        if({r_out,g_out,b_out} !== 24'h00FF00)
            $fatal(1, "ROI border was not green");

        force dut.act_x = 12'd3;
        force dut.act_y = 12'd3;
        @(posedge sys_clk); #1;
        if({r_out,g_out,b_out} !== 24'hF800F8)
            $fatal(1, "ROI interior altered the source image");

        rst_in = 1'b0;
        repeat (2) @(posedge sys_clk);
        if(rstn_out !== 1'b0) $fatal(1, "reset did not reassert");

        $display("HDMI_ROI_TOP_PASS");
        $finish;
    end
endmodule
