`timescale 1ns/1ps
module tb_ddr_display;
    localparam OUT_W=16,OUT_H=4,SCALE=2;
    localparam H_SYNC=2,H_BACK=4,H_ACTIVE=64,H_FRONT=2;
    localparam V_SYNC=1,V_BACK=1,V_ACTIVE=16,V_FRONT=1;
    localparam H_TOTAL=72,V_TOTAL=19;
    localparam X0=H_SYNC+H_BACK+(H_ACTIVE-OUT_W*SCALE)/2;
    localparam Y0=V_SYNC+V_BACK+(V_ACTIVE-OUT_H*SCALE)/2;
    localparam PIXELS_PER_RESULT_ROW=OUT_W*SCALE*SCALE;
    reg ui_clk=0,pix_clk=0;
    always #1 ui_clk=~ui_clk;
    always #5 pix_clk=~pix_clk;
    reg ui_rst_n=0,pix_rst_n=0;
    reg publish_toggle=0,publish_bank=0,force_pattern=1;
    reg test_passed=0;
    wire ack_toggle,cmd_valid;
    reg cmd_ready=1;
    wire [27:0] cmd_addr;
    reg rsp_valid=0;
    reg [255:0] rsp_rdata=0;
    wire hsync,vsync,de;
    wire [23:0] rgb;
    wire image_valid,underrun;

    integer command_count=0,mem_row,mem_col,beat_lane;
    integer out_h,out_v,out_x,out_y,active_x;
    integer expected_pixel,mem_bank_code,expected_bank_code;
    integer seen_bank0[0:OUT_H-1];
    integer seen_bank1[0:OUT_H-1];
    integer black_seen[0:OUT_H-1];
    integer k;
    reg expected_bank=0;
    reg expect_black=0;
    reg [11:0] h_d1=0,h_d2=0,v_d1=0,v_d2=0;
    reg hs_d1=0,hs_d2=0,vs_d1=0,vs_d2=0,de_d1=0,de_d2=0;
    integer timing_check_count=0;

    ddr_result_display #(
        .OUT_W(OUT_W),.OUT_H(OUT_H),.SCALE(SCALE),
        .H_SYNC(H_SYNC),.H_BACK(H_BACK),.H_ACTIVE(H_ACTIVE),.H_FRONT(H_FRONT),
        .V_SYNC(V_SYNC),.V_BACK(V_BACK),.V_ACTIVE(V_ACTIVE),.V_FRONT(V_FRONT)
    ) dut(
        .ui_clk(ui_clk),.ui_rst_n(ui_rst_n),.pix_clk(pix_clk),.pix_rst_n(pix_rst_n),
        .publish_toggle(publish_toggle),.publish_bank(publish_bank),.ack_toggle(ack_toggle),
        .force_pattern(force_pattern),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_addr(cmd_addr),
        .rsp_valid(rsp_valid),.rsp_rdata(rsp_rdata),.hsync(hsync),.vsync(vsync),.de(de),
        .rgb(rgb),.image_valid(image_valid),.underrun(underrun)
    );

    initial begin
        for(k=0;k<OUT_H;k=k+1) begin
            seen_bank0[k]=0;seen_bank1[k]=0;black_seen[k]=0;
        end
    end

    // The fake memory encodes frame bank, row, and x in each RGB word. Eight
    // 32-bit words are returned per command; RGB occupies each word's [23:0].
    always @(posedge ui_clk) begin
        rsp_valid<=0;
        if(!ui_rst_n) begin
            rsp_valid<=0;
            rsp_rdata<=0;
        end else if(cmd_valid && cmd_ready) begin
            command_count<=command_count+1;
            if(cmd_addr[2:0]!=0) $fatal(1,"command address is not 8-word aligned");
            if(cmd_addr>=28'h0200000) begin
                mem_row=(cmd_addr-28'h0200000)/OUT_W;
                mem_col=(cmd_addr-28'h0200000)%OUT_W;
                mem_bank_code=2;
            end else begin
                mem_row=(cmd_addr-28'h0100000)/OUT_W;
                mem_col=(cmd_addr-28'h0100000)%OUT_W;
                mem_bank_code=1;
            end
            for(beat_lane=0;beat_lane<8;beat_lane=beat_lane+1)
                rsp_rdata[beat_lane*32 +:24]<= (mem_bank_code<<20) | ((mem_row&8'hff)<<8) | ((mem_col+beat_lane)&8'hff);
            rsp_valid<=1;
        end
    end

    // Scoreboard from the actual output pins, not the internal line RAM. The
    // test checks startup/forced bars over full DE, two complete bank images,
    // and a delayed-fetch frame whose rows must remain black for whole lines.
    always @(posedge pix_clk) begin
        h_d1<=dut.hc;h_d2<=h_d1;v_d1<=dut.vc;v_d2<=v_d1;
        hs_d1<=dut.vtc_hs;hs_d2<=hs_d1;
        vs_d1<=dut.vtc_vs;vs_d2<=vs_d1;
        de_d1<=dut.vtc_de;de_d2<=de_d1;
        #0.1;
        if(pix_rst_n) begin
            timing_check_count=timing_check_count+1;
            if(timing_check_count>4 && (hsync!==hs_d2 || vsync!==vs_d2 || de!==de_d2))
                $fatal(1,"VTC latency mismatch");
            if(!de && rgb!==24'd0) $fatal(1,"RGB is nonblack outside HDMI DE");
            if(de) begin
                out_h=h_d2;out_v=v_d2;
                if(force_pattern || !image_valid) begin
                    active_x=out_h-(H_SYNC+H_BACK);
                    if(active_x<H_ACTIVE/4) expected_pixel=24'hff0000;
                    else if(active_x<H_ACTIVE/2) expected_pixel=24'h00ff00;
                    else if(active_x<H_ACTIVE*3/4) expected_pixel=24'h0000ff;
                    else expected_pixel=24'hffffff;
                    if(rgb!==expected_pixel[23:0]) $fatal(1,"full-DE test pattern mismatch at h=%0d",out_h);
                end else if(out_h>=X0 && out_h<X0+OUT_W*SCALE && out_v>=Y0 && out_v<Y0+OUT_H*SCALE) begin
                    out_x=(out_h-X0)/SCALE;out_y=(out_v-Y0)/SCALE;
                    if(expect_black) begin
                        if(rgb!==24'd0) $fatal(1,"late row changed from black during a scaled line: row=%0d x=%0d rgb=%h",out_y,out_x,rgb);
                        black_seen[out_y]=black_seen[out_y]+1;
                    end else begin
                        expected_bank_code=expected_bank?2:1;
                        expected_pixel=(expected_bank_code<<20) | ((out_y&8'hff)<<8) | (out_x&8'hff);
                        if(rgb!==expected_pixel[23:0])
                            $fatal(1,"DDR pixel mismatch bank=%0d row=%0d x=%0d got=%h expected=%h",expected_bank,out_y,out_x,rgb,expected_pixel[23:0]);
                        if(expected_bank) seen_bank1[out_y]=seen_bank1[out_y]+1;
                        else seen_bank0[out_y]=seen_bank0[out_y]+1;
                    end
                end else if(rgb!==24'd0) $fatal(1,"published image is nonblack outside its centered window");
            end
        end
    end

    task wait_for_frame_pixels(input integer bank);
        begin
            wait((bank==0 && seen_bank0[0]>=PIXELS_PER_RESULT_ROW && seen_bank0[1]>=PIXELS_PER_RESULT_ROW &&
                  seen_bank0[2]>=PIXELS_PER_RESULT_ROW && seen_bank0[3]>=PIXELS_PER_RESULT_ROW) ||
                 (bank==1 && seen_bank1[0]>=PIXELS_PER_RESULT_ROW && seen_bank1[1]>=PIXELS_PER_RESULT_ROW &&
                  seen_bank1[2]>=PIXELS_PER_RESULT_ROW && seen_bank1[3]>=PIXELS_PER_RESULT_ROW));
        end
    endtask

    initial begin
        repeat(5) @(posedge pix_clk);
        ui_rst_n=1;pix_rst_n=1;
        // Verify initial pattern reaches the entire active DE, including areas
        // outside the image window, before any result frame is published.
        repeat(20) @(posedge pix_clk);
        publish_bank=1;publish_toggle=1;
        wait(ack_toggle==1);
        if(!image_valid) $fatal(1,"image_valid did not set on publication");
        expected_bank=1;force_pattern=0;
        wait_for_frame_pixels(1);
        if(command_count<OUT_H*(OUT_W/8)) $fatal(1,"not enough bank-1 reads: %0d",command_count);

        // Toggle to the other immutable display bank and check every output
        // pixel for each result row, including both 2x replicas.
        publish_bank=0;publish_toggle=0;
        wait(ack_toggle==0);
        expected_bank=0;
        wait_for_frame_pixels(0);

        // Reuse bank 1 on a new frame generation. Stall its row-0 fetch until
        // scanning has begun, then release it. Each missing row must stay black
        // across its complete pair of physical lines even as data arrives.
        cmd_ready=0;
        publish_bank=1;publish_toggle=1;
        wait(ack_toggle==1 && image_valid);
        expected_bank=1;expect_black=1;
        force_pattern=0;
        wait((dut.vc==Y0) && (dut.hc==X0+4));
        cmd_ready=1;
        wait(black_seen[0]>=PIXELS_PER_RESULT_ROW && black_seen[1]>=PIXELS_PER_RESULT_ROW &&
             black_seen[2]>=PIXELS_PER_RESULT_ROW && black_seen[3]>=PIXELS_PER_RESULT_ROW);
        if(!underrun) $fatal(1,"late DDR fetch did not set sticky underrun");
        if(dut.display_gen!=3) $fatal(1,"display frame generation did not advance across bank reuse");
        test_passed=1;
        $display("DDR_DISPLAY_PASS full-DE bars, exact multirow output pixels for both banks, VTC/RGB alignment, and whole-line black on late fetch; commands=%0d",command_count);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1,"timeout");
    end
endmodule
