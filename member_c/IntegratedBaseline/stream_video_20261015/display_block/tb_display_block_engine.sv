`timescale 1ns/1ps
module tb_display_block_engine;
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
    wire fault;wire[2047:0]full_result;

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

    always #4 clk = ~clk;

    ddr_word_engine_result_burst #(.WATCHDOG_CYCLES(80),.READ_AHEAD_ENABLE(1),.RESULT_WORDS(128)) dut (.fault_reason(),.capture_burst_data(2048'd0),
        .clk(clk), .rst_n(rst_n), .init_done(init_done),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_result_block(1'b0),.result_block_data(2048'b0),.cmd_source_block(1'b0),.rsp_source_block(full_result),.cmd_write(cmd_write),
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


    localparam [27:0] B0=28'h0100000,B1=28'h0200000;
    reg [255:0] memory[0:511];
    integer tick=0,mode=0,beat=0,beat_total=0,delay_cycles=0,read_responses=0;
    reg read_pending=0;
    reg [27:0] read_base;
    integer physical_before;
    function integer index_for(input [27:0] address);
        if(address>=B1 && address<B1+256)index_for=256+(address-B1)/8;
        else if(address>=B0 && address<B0+256)index_for=128+(address-B0)/8;
        else index_for=(address/8)%128;
    endfunction
    always @(posedge clk)begin
        if(axi_arvalid&&axi_arready)ar_count=ar_count+1;
        if(axi_awvalid&&axi_awready)begin
            if(!axi_wready||axi_awlen!=0)$fatal(1,"write API changed");
            for(integer byte_index=0;byte_index<32;byte_index=byte_index+1)
                if(axi_wstrb[byte_index])memory[index_for(axi_awaddr)][byte_index*8+:8]=axi_wdata[byte_index*8+:8];
        end
        if(rsp_valid)read_responses=read_responses+1;
    end
    // Inputs are prepared before the next active clock edge. Mode1 supplies
    // beat0 on the same edge as AR acceptance; subsequent beats may be adjacent.
    always @(negedge clk)begin
        tick=tick+1;
        axi_awready=rst_n;axi_wready=rst_n;axi_wusero_id=0;axi_wusero_last=1;
        axi_arready=rst_n&&(tick%7!=0);axi_rvalid=0;axi_rid=0;axi_rlast=0;
        if(!rst_n)begin read_pending=0;beat=0;delay_cycles=0;end
        else if(!read_pending&&axi_arvalid&&axi_arready)begin
            if(axi_arlen!=0 && (axi_arlen!=7 || axi_araddr[5:0]!=0))$fatal(1,"unaligned/incorrect burst");
            read_base=axi_araddr;beat_total=axi_arlen+1;beat=0;delay_cycles=28;read_pending=1;
            if(mode==1)begin
                axi_rvalid=1;axi_rdata=memory[index_for(read_base)];axi_rlast=(beat_total==1);
                beat=1;delay_cycles=0;read_pending=(beat_total!=1);
            end
        end else if(read_pending)begin
            if(mode==5 && beat>=2)begin end
            else if(delay_cycles>0)delay_cycles=delay_cycles-1;
            else begin
                axi_rvalid=1;axi_rdata=memory[index_for(read_base+beat*8)];
                axi_rid=(mode==3&&beat==1)?4'd1:4'd0;
                axi_rlast=(mode==2&&beat==2)?1'b1:(mode==4?1'b0:(beat==beat_total-1));
                beat=beat+1;delay_cycles=(mode==1)?0:((tick%3)==0?2:0);
                if(beat==beat_total)read_pending=0;
            end
        end
    end
    task automatic command(input reg wr,input [27:0] address,input [255:0] data,input [31:0] strobe,input reg expect_fault);
        reg [255:0] expected;
        begin
            @(negedge clk);
            while(!cmd_ready)@(negedge clk);
            expected=wr?256'd0:memory[index_for(address)];
            cmd_write=wr;cmd_addr=address;cmd_wdata=data;cmd_wstrb=strobe;cmd_valid=1;
            @(posedge clk);#0.1;cmd_valid=0;
            wait(rsp_valid);#0.1;
            if(rsp_write!==wr || fault!==expect_fault)$fatal(1,"wrong response/fault addr=%h",address);
            if(expect_fault)begin
                if(rsp_rdata!==0)$fatal(1,"failed transaction exposed incomplete data");
            end else if(rsp_rdata!==expected)$fatal(1,"wrong/cache-stale data addr=%h got=%h expected=%h",address,rsp_rdata,expected);
            if(!wr&&!expect_fault&&((address>=B0&&address<B0+128)||(address>=B1&&address<B1+128)))
             for(integer block_beat=0;block_beat<8;block_beat=block_beat+1)
              if(full_result[block_beat*256+:256]!==memory[index_for({address[27:6],6'b0}+block_beat*8)])
               $fatal(1,"DISPLAY_BLOCK_REQUIRED beat=%0d address=%h",block_beat,address);
            @(posedge clk);#0.1;
            if(rsp_valid)$fatal(1,"more than one public response");
            if(expect_fault && cmd_ready)$fatal(1,"fault did not stop future commands");
        end
    endtask
    task automatic reset_engine;
        begin
            @(negedge clk);rst_n=0;mode=0;
            repeat(4)@(negedge clk);rst_n=1;init_done=1;
            repeat(2)@(negedge clk);
        end
    endtask
    initial begin
        for(integer j=0;j<512;j=j+1)for(integer lane=0;lane<8;lane=lane+1)
            memory[j][lane*32+:32]=32'h80000000+(j<<3)+lane;
        reset_engine;
        command(0,B0+24,0,0,0);
        if(ar_count!=1)$fatal(1,"cold fill should issue one physical burst");
        for(integer k=0;k<8;k=k+1)command(0,B0+k*8,0,0,0);
        if(ar_count!=1)$fatal(1,"cache hit reissued AR");
        command(1,B0+32,256'h12345678,32'h0000000f,0);
        command(0,B0+32,0,0,0);
        if(ar_count!=2)$fatal(1,"overlapping write did not invalidate cache");
        command(1,28'h10,256'hfeedface,32'hffffffff,0);
        command(0,B0+56,0,0,0);
        if(ar_count!=2)$fatal(1,"unrelated write unnecessarily invalidated cache");
        command(0,B0+64,0,0,0);command(0,B0+120,0,0,0);
        if(ar_count!=3)$fatal(1,"second result block not cached");
        command(0,B0+128,0,0,0);
        if(ar_count!=4)$fatal(1,"out-of-result range incorrectly cached");
        command(0,B1+56,0,0,0);command(0,B1,0,0,0);
        if(ar_count!=5)$fatal(1,"bank tag/final-beat forwarding incorrect");
        command(1,B1,256'h11223344,32'hffffffff,0);mode=1;
        command(0,B1+16,0,0,0);
        if(ar_count!=6)$fatal(1,"same-AR-edge response did not refill correctly");
        command(0,28'h20,0,0,0);
        for(integer fault_mode=2;fault_mode<=5;fault_mode=fault_mode+1)begin
            reset_engine;mode=fault_mode;
            command(0,B0+16,0,0,1);
            repeat(4)@(negedge clk);
            if(!fault||cmd_ready)$fatal(1,"fault cleared without shared reset");
        end
        reset_engine;physical_before=ar_count;
        command(0,B0+1,0,0,1);
        if(ar_count!=physical_before)$fatal(1,"misaligned logical command reached IP");
        reset_engine;command(0,B0+24,0,0,0);
        test_passed=1;$display("DDR_READ_AHEAD_PASS hit=1 overlapping_masked_write=1 independent_bank=1 boundaries=1 same_AR_edge=1 adjacent_beats=1 premature_last=1 bad_id=1 missing_last=1 timeout=1 misalignment=1 reset_flush=1 ar=%0d",ar_count);$finish;
    end
    initial begin #3000000;$fatal(1,"read-ahead unit timeout");end
endmodule


