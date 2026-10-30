`timescale 1ns/1ps
`default_nettype none

// DDR-backed, parameter-sized display for a completed result frame.
// The DDR UI adapter contract is one 256-bit response per accepted command;
// this block permits one command in flight and reads 8 RGB888 pixels/beat.
module ddr_result_display #(
    parameter OUT_W=320, OUT_H=452, SCALE=2,
    parameter H_SYNC=44, H_BACK=148, H_ACTIVE=1920, H_FRONT=88,
    parameter V_SYNC=5, V_BACK=36, V_ACTIVE=1080, V_FRONT=4,
    parameter [27:0] BASE0=28'h0100000,
    parameter [27:0] BASE1=28'h0200000
)(
    input  wire         ui_clk,
    input  wire         ui_rst_n,
    input  wire         pix_clk,
    input  wire         pix_rst_n,
    input  wire         publish_toggle,
    input  wire         publish_bank,
    output reg          ack_toggle,
    input  wire         force_pattern,

    output wire         cmd_valid,
    input  wire         cmd_ready,
    output wire [27:0]  cmd_addr,
    input  wire         rsp_valid,
    input  wire [255:0] rsp_rdata,

    output reg          hsync,
    output reg          vsync,
    output reg          de,
    output reg  [23:0]  rgb,
    output reg          image_valid,
    output reg          underrun
);
    localparam H_TOTAL=H_SYNC+H_BACK+H_ACTIVE+H_FRONT;
    localparam V_TOTAL=V_SYNC+V_BACK+V_ACTIVE+V_FRONT;
    localparam WIN_X=(H_ACTIVE-OUT_W*SCALE)/2;
    localparam WIN_Y=(V_ACTIVE-OUT_H*SCALE)/2;
    localparam X0=H_SYNC+H_BACK+WIN_X;
    localparam Y0=V_SYNC+V_BACK+WIN_Y;
    localparam BURSTS_PER_ROW=OUT_W/8;
    // Include the one-past-last-row sentinel in the mailbox coordinate width.
    localparam ROW_BITS=(OUT_H<2)?1:$clog2(OUT_H+1);
    localparam BURST_BITS=(BURSTS_PER_ROW<2)?1:$clog2(BURSTS_PER_ROW);

    // Any reset assertion resets both ends of the toggle mailbox. Each local
    // reset then releases synchronously in its own clock domain.
    wire link_rst_n=ui_rst_n & pix_rst_n;
    (* ASYNC_REG="TRUE" *) reg [1:0] ui_reset_pipe, pix_reset_pipe;
    always @(posedge ui_clk or negedge link_rst_n) begin
        if(!link_rst_n) ui_reset_pipe<=2'b00;
        else ui_reset_pipe<={ui_reset_pipe[0],1'b1};
    end
    always @(posedge pix_clk or negedge link_rst_n) begin
        if(!link_rst_n) pix_reset_pipe<=2'b00;
        else pix_reset_pipe<={pix_reset_pipe[0],1'b1};
    end
    wire ui_local_rst_n=ui_reset_pipe[1];
    wire pix_local_rst_n=pix_reset_pipe[1];

    // Two packed line buffers. UI stores eight padded RGB words per write;
    // pixel domain reads a word synchronously and selects its aligned lane.
    // A row becomes visible only after its final complete beat is stored.
    (* ram_style="block", ramstyle="M20K" *) reg [255:0] line_mem0[0:BURSTS_PER_ROW-1];
    (* ram_style="block", ramstyle="M20K" *) reg [255:0] line_mem1[0:BURSTS_PER_ROW-1];

    // Pixel -> UI single-entry request mailbox. Payload stays fixed until the
    // corresponding line-complete acknowledgement returns.
    reg req_toggle;
    reg req_bank;
    reg [15:0] req_gen;
    reg [ROW_BITS-1:0] req_row;
    reg want_valid, want_bank;
    reg [15:0] want_gen;
    reg [ROW_BITS-1:0] want_row;
    (* ASYNC_REG="TRUE" *) reg [2:0] req_sync_ui;
    (* ASYNC_REG="TRUE" *) reg [2:0] ack_sync_pix;
    reg ui_ack_toggle;
    reg ack_seen_pix;

    reg display_bank;
    reg [15:0] display_gen;
    reg [1:0] line_valid;
    reg [ROW_BITS-1:0] line_row0, line_row1;
    reg line_bank0, line_bank1;
    reg [15:0] line_gen0, line_gen1;
    reg scan_active_pix;
    reg [ROW_BITS-1:0] scan_row_pix;
    (* ASYNC_REG="TRUE" *) reg [2:0] scan_active_ui;
    (* ASYNC_REG="TRUE" *) reg [ROW_BITS-1:0] scan_row_ui0,scan_row_ui1,scan_row_ui2;

    wire [11:0] hc,vc;
    wire vtc_hs,vtc_vs,vtc_de;
    video_timing_vtc #(
        .H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_ACTIVE(H_ACTIVE),.H_FRONT(H_FRONT),
        .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_ACTIVE(V_ACTIVE),.V_FRONT(V_FRONT)
    ) timing(
        .clk(pix_clk),.rst_n(pix_local_rst_n),.h_cnt(hc),.v_cnt(vc),
        .hsync(vtc_hs),.vsync(vtc_vs),.de(vtc_de)
    );

    // UI reader: serialized single-beat commands, one packed-memory write
    // for each returned 256-bit beat.
    localparam UI_IDLE=2'd0, UI_CMD=2'd1, UI_RSP=2'd2, UI_WRITE=2'd3;
    reg [1:0] ui_state;
    reg ui_req_seen;
    reg [15:0] ui_line_gen;
    reg [ROW_BITS-1:0] ui_line_row;
    reg [BURST_BITS-1:0] burst_index;
    reg [255:0] beat_data;
    reg [27:0] active_base;
    reg [27:0] cmd_addr_r;
    reg cmd_valid_r;
    assign cmd_valid=cmd_valid_r;
    assign cmd_addr=cmd_addr_r;

    always @(posedge ui_clk or negedge ui_local_rst_n) begin
        if(!ui_local_rst_n) begin
            req_sync_ui<=0; ui_ack_toggle<=0; ui_req_seen<=0;
            scan_active_ui<=0;scan_row_ui0<=0;scan_row_ui1<=0;scan_row_ui2<=0;
            ui_state<=UI_IDLE; ui_line_gen<=0;
            ui_line_row<=0; burst_index<=0; beat_data<=0;
            active_base<=BASE0; cmd_addr_r<=0; cmd_valid_r<=0;
        end else begin
            req_sync_ui<={req_sync_ui[1:0],req_toggle};
            scan_active_ui<={scan_active_ui[1:0],scan_active_pix};
            scan_row_ui0<=scan_row_pix;scan_row_ui1<=scan_row_ui0;scan_row_ui2<=scan_row_ui1;
            case(ui_state)
                UI_IDLE: begin
                    cmd_valid_r<=0;
                    if(req_sync_ui[2]!=ui_req_seen) begin
                        ui_req_seen<=req_sync_ui[2];
                        ui_line_gen<=req_gen;
                        ui_line_row<=req_row;
                        active_base<=req_bank?BASE1:BASE0;
                        burst_index<=0;
                        ui_state<=UI_CMD;
                    end
                end
                UI_CMD: begin
                    // OUT_W padded RGB words per row; each command advances eight words.
                    cmd_addr_r<=active_base + ui_line_row*OUT_W + burst_index*8;
                    cmd_valid_r<=1;
                    if(cmd_valid_r && cmd_ready) begin
                        cmd_valid_r<=0;
                        ui_state<=UI_RSP;
                    end
                end
                UI_RSP: begin
                    if(rsp_valid) begin
                        beat_data<=rsp_rdata;
                       
                        ui_state<=UI_WRITE;
                    end
                end
                UI_WRITE: begin
                    // Do not write the ping-pong line currently being scanned.
                    if(!scan_active_ui[2] || ui_line_row[0]!=scan_row_ui2[0]) begin
                        // Store all eight padded RGB888 words on one UI clock.
                        if(ui_line_row[0]) line_mem1[burst_index]<=beat_data;
                        else               line_mem0[burst_index]<=beat_data;
                        if(burst_index==BURSTS_PER_ROW-1) begin
                            ui_ack_toggle<=ui_req_seen;ui_state<=UI_IDLE;
                        end else begin
                            burst_index<=burst_index+1'b1;ui_state<=UI_CMD;
                        end
                    end
                end
                default: ui_state<=UI_IDLE;
            endcase
        end
    end

    // Keep mailbox payload unchanged while UI owns a request. Publish data is
    // sampled only at the frame boundary; producer retains it through ack.
    reg line_ok;
    reg [255:0] line_word_q;
    reg [2:0] line_lane_q;
    wire [23:0] pixel_q=line_word_q[line_lane_q*32 +: 24];
    reg pixel_hs,pixel_vs,pixel_de,pixel_window,pixel_pattern;
    reg [23:0] pixel_pattern_rgb;
    wire frame_start=(hc==0 && vc==0);
    wire first_dest_line=(vc>=Y0 && vc<Y0+OUT_H*SCALE && ((vc-Y0)%SCALE)==0);
    wire [ROW_BITS-1:0] dest_row=(vc-Y0)/SCALE;
    wire [ROW_BITS-1:0] request_row_next=dest_row+1'b1;

    // CDC synchronizers for frame publication and completed-line response.
    (* ASYNC_REG="TRUE" *) reg [2:0] pub_toggle_sync, pub_bank_sync;
    (* ASYNC_REG="TRUE" *) reg [2:0] ui_ack_sync;
    always @(posedge pix_clk or negedge pix_local_rst_n) begin
        if(!pix_local_rst_n) begin
            pub_toggle_sync<=0; pub_bank_sync<=0; ui_ack_sync<=0;
        end else begin
            pub_toggle_sync<={pub_toggle_sync[1:0],publish_toggle};
            pub_bank_sync<={pub_bank_sync[1:0],publish_bank};
            ui_ack_sync<={ui_ack_sync[1:0],ui_ack_toggle};
        end
    end

    wire dest_match0=line_valid[0] && line_row0==dest_row && line_bank0==display_bank && line_gen0==display_gen;
    wire dest_match1=line_valid[1] && line_row1==dest_row && line_bank1==display_bank && line_gen1==display_gen;
    wire next_match0=line_valid[0] && line_row0==request_row_next && line_bank0==display_bank && line_gen0==display_gen;
    wire next_match1=line_valid[1] && line_row1==request_row_next && line_bank1==display_bank && line_gen1==display_gen;
    wire active_window=vtc_de && hc>=X0 && hc<X0+OUT_W*SCALE && vc>=Y0 && vc<Y0+OUT_H*SCALE;
    wire [11:0] cur_x=(hc-X0)/SCALE;
    wire [11:0] cur_y=(vc-Y0)/SCALE;
    wire [11:0] active_x=hc-(H_SYNC+H_BACK);
    wire [23:0] cur_pattern_rgb = (active_x<H_ACTIVE/4) ? 24'hff0000 :
                                  (active_x<H_ACTIVE/2) ? 24'h00ff00 :
                                  (active_x<H_ACTIVE*3/4) ? 24'h0000ff : 24'hffffff;

    always @(posedge pix_clk or negedge pix_local_rst_n) begin
        if(!pix_local_rst_n) begin
            ack_toggle<=0; display_bank<=0; display_gen<=0; image_valid<=0; underrun<=0;
            req_toggle<=0; req_bank<=0; req_gen<=0; req_row<=0;
            want_valid<=0; want_bank<=0; want_gen<=0; want_row<=0;
            ack_sync_pix<=0; ack_seen_pix<=0;
            line_valid<=0; line_row0<=0; line_row1<=0; line_bank0<=0; line_bank1<=0;
            line_gen0<=0; line_gen1<=0;scan_active_pix<=0;scan_row_pix<=0;
            line_ok<=0; line_word_q<=0;line_lane_q<=0;
            pixel_hs<=0;pixel_vs<=0;pixel_de<=0;pixel_window<=0;pixel_pattern<=0;pixel_pattern_rgb<=0;
            hsync<=0;vsync<=0;de<=0;rgb<=0;
        end else begin
            ack_sync_pix<={ack_sync_pix[1:0],ui_ack_toggle};

            // A completed UI write makes the whole row atomically visible.
            if(ui_ack_sync[2]!=ack_seen_pix) begin
                ack_seen_pix<=ui_ack_sync[2];
                if(req_row[0]) begin
                    line_valid[1]<=1;line_row1<=req_row;line_bank1<=req_bank;line_gen1<=req_gen;
                end else begin
                    line_valid[0]<=1;line_row0<=req_row;line_bank0<=req_bank;line_gen0<=req_gen;
                end
            end

            if(frame_start) begin
                if(pub_toggle_sync[2]!=ack_toggle) begin
                    display_bank<=pub_bank_sync[2];display_gen<=display_gen+1'b1;
                    image_valid<=1;ack_toggle<=pub_toggle_sync[2];
                    line_valid<=0;
                    want_valid<=1;want_row<=0;want_bank<=pub_bank_sync[2];want_gen<=display_gen+1'b1;
                end else if(image_valid) begin
                    if(!(line_valid[0] && line_row0==0 && line_bank0==display_bank && line_gen0==display_gen) &&
                       !(line_valid[1] && line_row1==0 && line_bank1==display_bank && line_gen1==display_gen)) begin
                        want_valid<=1;want_row<=0;want_bank<=display_bank;want_gen<=display_gen;
                    end
                end
            end else if(hc==0 && first_dest_line) begin
                // Normally request row N+1 at row N's first physical line.
                // If N itself is late, prioritize refetching N so a congested
                // one-entry mailbox cannot skip it while coalescing requests.
                if(image_valid && !(dest_match0||dest_match1)) begin
                    want_valid<=1;want_row<=dest_row;want_bank<=display_bank;want_gen<=display_gen;
                end else if(request_row_next<OUT_H && image_valid && !(next_match0||next_match1)) begin
                    want_valid<=1;want_row<=request_row_next;want_bank<=display_bank;want_gen<=display_gen;
                end
                if(!force_pattern && image_valid && !(dest_match0||dest_match1)) underrun<=1;
            end

            // Coalesce requests while a slow/old request drains. The newest
            // requested row/frame is launched as soon as the mailbox is free.
            if(!(frame_start || (hc==0 && first_dest_line)) && want_valid && req_toggle==ack_sync_pix[2]) begin
                req_row<=want_row;req_bank<=want_bank;req_gen<=want_gen;
                req_toggle<=~req_toggle;want_valid<=0;
            end

            if(hc==0) begin
                if(first_dest_line) begin
                    line_ok<=image_valid && (dest_match0||dest_match1);
                    scan_active_pix<=1;scan_row_pix<=dest_row;
                end else if(vc<Y0 || vc>=Y0+OUT_H*SCALE) begin
                    line_ok<=0;scan_active_pix<=0;
                end
            end

            line_lane_q<=cur_x[2:0];
            if(active_window && line_ok) begin
                if(cur_y[0]) line_word_q<=line_mem1[cur_x>>3];
                else line_word_q<=line_mem0[cur_x>>3];
            end else line_word_q<=0;

            pixel_hs<=vtc_hs;pixel_vs<=vtc_vs;pixel_de<=vtc_de;
            pixel_window<=active_window;
            // Missing rows in a published frame remain black for both
            // physical scanlines. Startup/forced bars cover full HDMI DE.
            pixel_pattern<=force_pattern || !image_valid;
            pixel_pattern_rgb<=cur_pattern_rgb;
            hsync<=pixel_hs;vsync<=pixel_vs;de<=pixel_de;
            if(!pixel_de) rgb<=0;
            else if(pixel_pattern) rgb<=pixel_pattern_rgb;
            else if(pixel_window) rgb<=pixel_q;
            else rgb<=0;
        end
    end
endmodule

`default_nettype wire
