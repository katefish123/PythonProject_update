`timescale 1ns/1ps
`default_nettype none
// MES2L676-100HP / PG2L100H-6IFBG676 bring-up profile.
// Input: 1920x1080 RGB888. Snapshot: 320x180. Result: 160x226.
// Independent 1080p60 output keeps the last complete result during processing.
module video_correct_board_top(
    input wire sys_clk_27m,rst_n,key1_pattern_n,key2_nearest_n,
    input wire hd_rx_pclk,hd_rx_vs,hd_rx_hs,hd_rx_de,
    input wire [23:0] hd_rx_data,
    output wire hd_tx_pclk,
    output reg hd_tx_vs,hd_tx_hs,hd_tx_de,
    output reg [23:0] hd_tx_data,
    output wire hd_reset_n,hd_scl,
    inout wire hd_sda,
    output wire [7:0] led
);
    wire pix_clk,cfg_clk,pix_locked,cfg_locked;
    video_pll_27m_148m5 vp(.clkin1(sys_clk_27m),.clkout0(pix_clk),.lock(pix_locked));
    config_pll_27m_10m cp(.clkin1(sys_clk_27m),.clkout0(cfg_clk),.lock(cfg_locked));
    wire clocks_ready=rst_n && pix_locked && cfg_locked;
    wire cfg_rst_n,proc_rst_n,rx_rst_n,pix_rst_n;
    reset_sync cfg_reset(.clk(cfg_clk),.arst_n(clocks_ready),.rst_n(cfg_rst_n));
    reg [15:0] reset_count;
    always @(posedge cfg_clk or negedge cfg_rst_n) begin
        if(!cfg_rst_n)reset_count<=0;
        else if(reset_count<10000)reset_count<=reset_count+1'b1;
    end
    assign hd_reset_n=cfg_rst_n && reset_count==10000;
    reset_sync proc_reset(.clk(sys_clk_27m),.arst_n(hd_reset_n),.rst_n(proc_rst_n));
    reset_sync rx_reset(.clk(hd_rx_pclk),.arst_n(hd_reset_n),.rst_n(rx_rst_n));
    reset_sync pix_reset(.clk(pix_clk),.arst_n(hd_reset_n),.rst_n(pix_rst_n));
    wire rx_done,tx_done,ack_error,config_error,startup_retry_seen;
    hdmi_config #(.TX_FIRST(1'b1)) config_bus(.cfg_clk(cfg_clk),.reset_n(hd_reset_n),
        .rx_done(rx_done),.tx_done(tx_done),.scl(hd_scl),.sda(hd_sda),.ack_error(ack_error),
        .config_error(config_error),.startup_retry_seen(startup_retry_seen));
    (* ASYNC_REG="TRUE" *) reg [2:0] ready_pipe,nearest_pipe,pattern_pipe;
    always @(posedge sys_clk_27m or negedge proc_rst_n) begin
        if(!proc_rst_n)begin ready_pipe<=0;nearest_pipe<=0;end
        else begin
            ready_pipe<={ready_pipe[1:0],rx_done && tx_done && !config_error};
            nearest_pipe<={nearest_pipe[1:0],!key2_nearest_n};
        end
    end
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n)pattern_pipe<=0;
        else pattern_pipe<={pattern_pipe[1:0],!key1_pattern_n};
    end
    // Capture external source-synchronous signals in I/O-facing registers.
    reg rx_vs_q,rx_hs_q,rx_de_q;
    reg [23:0] rx_rgb_q;
    always @(posedge hd_rx_pclk or negedge rx_rst_n) begin
        if(!rx_rst_n)begin rx_vs_q<=0;rx_hs_q<=0;rx_de_q<=0;rx_rgb_q<=0;end
        else begin rx_vs_q<=hd_rx_vs;rx_hs_q<=hd_rx_hs;rx_de_q<=hd_rx_de;rx_rgb_q<=hd_rx_data;end
    end
    wire recovered_vs;
    hdmi_vs_recover recover(.clk(hd_rx_pclk),.reset_n(rx_rst_n),
        .de(rx_de_q),.hs(rx_hs_q),.vs_in(rx_vs_q),.vs_out(recovered_vs));
    wire vs,hs,den,image_valid,working,frame_error,input_wait;
    wire [23:0] rgb;
    video_correct_core core(.proc_clk(sys_clk_27m),.proc_rst_n(proc_rst_n),
        .rx_clk(hd_rx_pclk),.rx_rst_n(rx_rst_n),.pix_clk(pix_clk),.pix_rst_n(pix_rst_n),
        .enabled(ready_pipe[2]),.rx_vs(recovered_vs),.rx_de(rx_de_q),.rx_rgb(rx_rgb_q),
        .nearest(nearest_pipe[2]),.force_pattern(pattern_pipe[2]),
        .hsync(hs),.vsync(vs),.de(den),.rgb(rgb),.image_valid(image_valid),
        .working(working),.frame_error(frame_error),.input_wait(input_wait),.good_frames(),.rejected_frames());
    // One final register stage makes RGB and qualifiers launch together.
    always @(posedge pix_clk or negedge pix_rst_n) begin
        if(!pix_rst_n)begin hd_tx_vs<=0;hd_tx_hs<=0;hd_tx_de<=0;hd_tx_data<=0;end
        else begin hd_tx_vs<=vs;hd_tx_hs<=hs;hd_tx_de<=den;hd_tx_data<=rgb;end
    end
    assign hd_tx_pclk=pix_clk;
    reg [25:0] heartbeat;
    always @(posedge sys_clk_27m or negedge proc_rst_n) begin
        if(!proc_rst_n)heartbeat<=0;else heartbeat<=heartbeat+1'b1;
    end
    assign led={clocks_ready,config_error,input_wait,frame_error,image_valid,tx_done,rx_done,heartbeat[24]};
endmodule
`default_nettype wire
