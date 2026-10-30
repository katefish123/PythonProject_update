`timescale 1ns/1ps

module tb_video_timing;

reg clk;
reg rst_n;
reg [1:0] pattern_sel;

wire [11:0] h_cnt;
wire [11:0] v_cnt;
wire hsync;
wire vsync;
wire de;
wire [23:0] rgb;

video_timing_vtc #(
    .H_SYNC       (12'd2),
    .H_BACK       (12'd2),
    .H_ACTIVE     (12'd8),
    .H_FRONT      (12'd2),
    .V_SYNC       (12'd1),
    .V_BACK       (12'd1),
    .V_ACTIVE     (12'd4),
    .V_FRONT      (12'd1),
    .HSYNC_ACTIVE (1'b1),
    .VSYNC_ACTIVE (1'b1)
) dut(
    .clk(clk),
    .rst_n(rst_n),
    .h_cnt(h_cnt),
    .v_cnt(v_cnt),
    .hsync(hsync),
    .vsync(vsync),
    .de(de)
);

test_pattern_generator_tpg #(
    .H_ACTIVE_START (12'd4),
    .H_ACTIVE       (12'd8),
    .V_ACTIVE_START (12'd2),
    .V_ACTIVE       (12'd4)
) tpg(
    .h_cnt       (h_cnt),
    .v_cnt       (v_cnt),
    .de          (de),
    .pattern_sel (pattern_sel),
    .rgb         (rgb)
);

initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    pattern_sel = 2'b00;

    #20;
    rst_n = 1'b1;

    // 一行尚未结束，垂直计数器必须保持为 0。
      #80;
      if(v_cnt !== 12'd0) begin
          $display("TEST_FAIL: v_cnt changed before h_cnt wrapped");
          $finish;
      end
      if(de !== 1'b0) begin
          $display("TEST_FAIL: de asserted outside active area");
          $finish;
      end
      if(rgb !== 24'h000000) begin
          $display("TEST_FAIL: rgb is not black outside active area");
          $finish;
      end
      if(hsync !== 1'b0 || vsync !== 1'b1) begin
          $display("TEST_FAIL: sync levels are wrong during vertical sync");
          $finish;
      end

    // 第一行结束后，垂直计数器应加到 1。
      #56;
      if(v_cnt !== 12'd1) begin
          $display("TEST_FAIL: v_cnt did not increment after one line");
          $finish;
      end
      if(hsync !== 1'b1 || vsync !== 1'b0) begin
          $display("TEST_FAIL: sync levels are wrong at the next line start");
          $finish;
      end

      // 进入有效显示区域后，依次检查红、绿、蓝、白四条彩条。
      #180;
      if(de !== 1'b1) begin
          $display("TEST_FAIL: de did not assert inside active area");
          $finish;
      end
      if(rgb !== 24'hFF0000) begin
          $display("TEST_FAIL: first color bar is not red");
          $finish;
      end

      #20;
      if(rgb !== 24'h00FF00) begin
          $display("TEST_FAIL: second color bar is not green");
          $finish;
      end

      #20;
      if(rgb !== 24'h0000FF) begin
          $display("TEST_FAIL: third color bar is not blue");
          $finish;
      end

      #20;
      if(rgb !== 24'hFFFFFF) begin
          $display("TEST_FAIL: fourth color bar is not white");
          $finish;
      end

      // 水平计数离开有效显示区域后，de 应拉低，rgb 应变黑。
      #20;
      if(de !== 1'b0) begin
          $display("TEST_FAIL: de remained asserted outside active area");
          $finish;
      end
      if(rgb !== 24'h000000) begin
          $display("TEST_FAIL: rgb remained active outside active area");
          $finish;
      end

      // 共完成 7 行后，垂直计数器应从 6 回到 0。
      #580;
      if(v_cnt !== 12'd0) begin
          $display("TEST_FAIL: v_cnt did not wrap from 6 to 0");
          $finish;
      end

      $display("TEST_PASS: complete video timing and RGB output are correct");
    $finish;
end

always #5 clk = ~clk;

endmodule
