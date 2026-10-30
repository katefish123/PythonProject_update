`timescale 1ns/1ps
`default_nettype none

// Single-outstanding word/burst adapter for the PG2L100H DDR IP.
// cmd_source_block explicitly requests a safe aligned 64-word source block.
// Shared block return is valid only with the arbiter-owned response.
// It also returns complete result cache lines for display reads.
// rsp_source_block packs beat0 in bits255:0 through beat7 in bits2047:1792.
// Addresses are 32-bit word addresses; one beat covers eight words.
module ddr_word_engine_result_burst #(
    parameter integer WATCHDOG_CYCLES = 1024,
    parameter integer CAPTURE_BURST_BEATS=1,
    parameter integer READ_AHEAD_ENABLE = 0,
    parameter integer SOURCE_PREFETCH_ENABLE = 0,
    parameter integer READ_PREFETCH_BEATS = 8,
    parameter integer SOURCE_WORDS = 1920*1080,
    parameter [27:0] SOURCE_BASE0 = 28'd0,
    parameter [27:0] SOURCE_BASE1 = 28'h0800000,
    parameter integer RESULT_WORDS = 640*904,
    parameter [27:0] RESULT_BASE0 = 28'h0100000,
    parameter [27:0] RESULT_BASE1 = 28'h0200000
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          init_done,

    input  wire          cmd_valid,
    output wire          cmd_ready,
    input  wire          cmd_write,
    input wire cmd_source_block,
    input wire cmd_result_block,input wire[2047:0]result_block_data,
    input  wire [27:0]   cmd_addr,
    input  wire [255:0]  cmd_wdata,
    input  wire [31:0]   cmd_wstrb,
    input wire [(CAPTURE_BURST_BEATS>8?CAPTURE_BURST_BEATS:8)*256-1:0] capture_burst_data,

    output wire          rsp_valid,
    output reg           rsp_write,
    output wire [255:0]  rsp_rdata,
    output wire [2047:0] rsp_source_block,
    output wire [4095:0] rsp_source_line,
    output reg           fault,
    output reg [3:0] fault_reason,

    output wire [27:0]   axi_awaddr,
    output wire          axi_awuser_ap,
    output wire [3:0]    axi_awuser_id,
    output wire [3:0]    axi_awlen,
    output wire          axi_awvalid,
    input  wire          axi_awready,

    output wire [255:0]  axi_wdata,
    output wire [31:0]   axi_wstrb,
    input  wire          axi_wready,
    input  wire [3:0]    axi_wusero_id,
    input  wire          axi_wusero_last,

    output wire [27:0]   axi_araddr,
    output wire          axi_aruser_ap,
    output wire [3:0]    axi_aruser_id,
    output wire [3:0]    axi_arlen,
    output wire          axi_arvalid,
    input  wire          axi_arready,

    input  wire [255:0]  axi_rdata,
    input  wire [3:0]    axi_rid,
    input  wire          axi_rlast,
    input  wire          axi_rvalid
);

    localparam READ_BITS=$clog2(READ_PREFETCH_BEATS), BLOCK_BITS=READ_BITS+3;
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_AW   = 3'd1;
    localparam [2:0] ST_W    = 3'd2;
    localparam [2:0] ST_AR   = 3'd3;
    localparam [2:0] ST_R    = 3'd4;
    localparam [2:0] ST_RSP  = 3'd5;
    localparam [2:0] ST_WPREP= 3'd6;

    reg [2:0] state;
    reg [27:0] addr_hold;
    reg [255:0] wdata_hold;
    reg [31:0] wstrb_hold;
    reg [31:0] watchdog_count;
    reg write_burst;
    reg [3:0] write_index,write_last;
    wire force_result_block=(cmd_result_block === 1'b1);
    reg [(CAPTURE_BURST_BEATS>8?CAPTURE_BURST_BEATS:8)*256-1:0] capture_hold;
    reg [2047:0] result_hold;
    reg write_result;
    reg [255:0] native_wdata;
    wire [3:0] next_write_index=write_index+4'd1;
    // Private until command acceptance, then held throughout AW/W.
    // Sampling idle/RSP slots also samples the actual acceptance edge,
    // without putting live arbiter controls on6144 payload CE pins.
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin capture_hold<=0;result_hold<=0;end
        else if(state==ST_IDLE||state==ST_RSP)begin
            capture_hold<=capture_burst_data;result_hold<=result_block_data;
        end
    end
    // Capture writes must fit their entire burst, not only a 64-word half.
    localparam CAP_BLOCK_BITS=$clog2(CAPTURE_BURST_BEATS*8);
    localparam [31:0] CAP_MASK=CAPTURE_BURST_BEATS*8-1;
    localparam [31:0] CAP_FIRST0=({4'd0,SOURCE_BASE0}+CAP_MASK)>>CAP_BLOCK_BITS;
    localparam [31:0] CAP_FIRST1=({4'd0,SOURCE_BASE1}+CAP_MASK)>>CAP_BLOCK_BITS;
    localparam [31:0] CAP_LIMIT0=({4'd0,SOURCE_BASE0}+SOURCE_WORDS)>>CAP_BLOCK_BITS;
    localparam [31:0] CAP_LIMIT1=({4'd0,SOURCE_BASE1}+SOURCE_WORDS)>>CAP_BLOCK_BITS;
    wire [27-CAP_BLOCK_BITS:0] cap_request_tag=cmd_addr[27:CAP_BLOCK_BITS];
    wire capture_block_safe=(cap_request_tag>=CAP_FIRST0&&cap_request_tag<CAP_LIMIT0)||
                            (cap_request_tag>=CAP_FIRST1&&cap_request_tag<CAP_LIMIT1);
    wire source_write=cmd_write &&
        ((cmd_addr>=SOURCE_BASE0 && cmd_addr<SOURCE_BASE0+SOURCE_WORDS) ||
         (cmd_addr>=SOURCE_BASE1 && cmd_addr<SOURCE_BASE1+SOURCE_WORDS));
    wire capture_command=CAPTURE_BURST_BEATS>1 && source_write && !force_result_block;
    reg cache_valid,read_burst;
    reg [27-BLOCK_BITS:0] cache_tag;
    reg [READ_BITS-1:0] read_index;
    reg[READ_PREFETCH_BEATS-1:0]read_lane_hot;integer lane_index;
    reg [255:0] result_cache[0:READ_PREFETCH_BEATS-1];
    // A complete aligned 64-word block fits [BASE, BASE+WORDS) exactly
    // when its tag is in [ceil(BASE/64), floor((BASE+WORDS)/64)).
    // Precompute both ends in 32 bits: BASE need not be aligned, WORDS may
    // be zero/short, and BASE+WORDS may exceed the 28-bit address domain.
    // WORDS parameters are nonnegative signed integers (0 through 2^31-1).
    // Only 22 request tag bits now traverse the live command validation path.
    localparam [31:0] RESULT_BLOCK_FIRST0=({4'd0,RESULT_BASE0}+32'd63)>>6;
    localparam [31:0] RESULT_BLOCK_FIRST1=({4'd0,RESULT_BASE1}+32'd63)>>6;
    localparam [31:0] RESULT_BLOCK_LIMIT0=({4'd0,RESULT_BASE0}+RESULT_WORDS)>>6;
    localparam [31:0] RESULT_BLOCK_LIMIT1=({4'd0,RESULT_BASE1}+RESULT_WORDS)>>6;
    localparam [31:0] SOURCE_BLOCK_FIRST0=({4'd0,SOURCE_BASE0}+32'd63)>>6;
    localparam [31:0] SOURCE_BLOCK_FIRST1=({4'd0,SOURCE_BASE1}+32'd63)>>6;
    localparam [31:0] SOURCE_BLOCK_LIMIT0=({4'd0,SOURCE_BASE0}+SOURCE_WORDS)>>6;
    localparam [31:0] SOURCE_BLOCK_LIMIT1=({4'd0,SOURCE_BASE1}+SOURCE_WORDS)>>6;
    wire [21:0] request_block_tag=cmd_addr[27:6];
    wire force_source_block=(cmd_source_block === 1'b1);
    reg source_cache_valid,read_source,source_next_valid;
    reg [27-BLOCK_BITS:0] source_cache_tag;
    reg [27:0] source_next_addr;
    reg [255:0] source_cache[0:READ_PREFETCH_BEATS-1];
    // Cache words already hold the final R beat on entry to ST_RSP. Select
    // those registered words instead of copying/clearing 2048 bits under a
    // live command address decode. Only these five response-control bits
    // depend on cache hit/address selection; retirement latency is unchanged.
    localparam [1:0] RESPONSE_ZERO=0, RESPONSE_NATIVE=1,
                     RESPONSE_SOURCE=2, RESPONSE_RESULT=3;
    reg [1:0] response_kind;
    reg [READ_BITS-1:0] response_word;
    reg [255:0] native_response;
    assign rsp_rdata = response_kind==RESPONSE_NATIVE ? native_response :
                       response_kind==RESPONSE_SOURCE ? source_cache[response_word] :
                       response_kind==RESPONSE_RESULT ? result_cache[response_word] : 256'd0;
    wire [2047:0] source_low={source_cache[7],source_cache[6],source_cache[5],source_cache[4],source_cache[3],source_cache[2],source_cache[1],source_cache[0]};
    wire [2047:0] result_low={result_cache[7],result_cache[6],result_cache[5],result_cache[4],result_cache[3],result_cache[2],result_cache[1],result_cache[0]};
    generate if(READ_PREFETCH_BEATS==16)begin: double_block
      wire[2047:0] source_high={source_cache[15],source_cache[14],source_cache[13],source_cache[12],source_cache[11],source_cache[10],source_cache[9],source_cache[8]};
      wire[2047:0] result_high={result_cache[15],result_cache[14],result_cache[13],result_cache[12],result_cache[11],result_cache[10],result_cache[9],result_cache[8]};
      // Only an owned source response qualifies this private cache-fill bus.
      assign rsp_source_line={source_high,source_low};
      assign rsp_source_block=response_kind==RESPONSE_SOURCE?(response_word[3]?source_high:source_low):response_kind==RESPONSE_RESULT?(response_word[3]?result_high:result_low):2048'd0;
    end else begin: single_block
      assign rsp_source_line={2048'd0,source_low};
      assign rsp_source_block=response_kind==RESPONSE_SOURCE?source_low:response_kind==RESPONSE_RESULT?result_low:2048'd0;
    end endgenerate

    wire source_read=(SOURCE_PREFETCH_ENABLE || force_source_block) && !cmd_write &&
        ((cmd_addr>=SOURCE_BASE0 && cmd_addr<SOURCE_BASE0+SOURCE_WORDS) ||
         (cmd_addr>=SOURCE_BASE1 && cmd_addr<SOURCE_BASE1+SOURCE_WORDS));
    wire result_block_safe=
        ((request_block_tag>=RESULT_BLOCK_FIRST0 && request_block_tag<RESULT_BLOCK_LIMIT0) ||
         (request_block_tag>=RESULT_BLOCK_FIRST1 && request_block_tag<RESULT_BLOCK_LIMIT1));
    wire source_block_safe=
        ((request_block_tag>=SOURCE_BLOCK_FIRST0 && request_block_tag<SOURCE_BLOCK_LIMIT0) ||
         (request_block_tag>=SOURCE_BLOCK_FIRST1 && request_block_tag<SOURCE_BLOCK_LIMIT1));
    wire result_read=READ_AHEAD_ENABLE && !force_source_block && !cmd_write && result_block_safe;
    wire source_prefetch=source_read && source_block_safe &&
        (force_source_block || cmd_addr==SOURCE_BASE0 || cmd_addr==SOURCE_BASE1 ||
         (source_next_valid && cmd_addr==source_next_addr));
    wire source_hit=source_read && source_cache_valid && source_cache_tag==cmd_addr[27:BLOCK_BITS];
    wire result_hit=result_read && cache_valid && cache_tag==cmd_addr[27:BLOCK_BITS];
    wire cache_hit=result_hit || source_hit;

    // Public clients still receive exactly one response for one accepted command.
    // A cache fill consumes every unbackpressurable IP beat before responding.
    task receive_read;
        begin
            if(read_burst)begin
                if(axi_rid!==4'd0 || axi_rlast!==(read_index==READ_PREFETCH_BEATS-1))begin
                    fault_reason<=3;fault<=1;cache_valid<=0;source_cache_valid<=0;response_kind<=RESPONSE_ZERO;state<=ST_RSP;
                end else begin
                    // Registered one-hot beat ownership replaces a binary
                    // read_index -> wide cache write-enable decode.
                    for(lane_index=0;lane_index<READ_PREFETCH_BEATS;lane_index=lane_index+1)if(read_lane_hot[lane_index])begin
                     if(read_source)source_cache[lane_index]<=axi_rdata;
                     else result_cache[lane_index]<=axi_rdata;
                    end
                    if(read_index==READ_PREFETCH_BEATS-1)begin
                        if(read_source)begin
                            source_cache_tag<=addr_hold[27:BLOCK_BITS];source_cache_valid<=1;
                        end else begin cache_tag<=addr_hold[27:BLOCK_BITS];cache_valid<=1;end
                        response_kind<=read_source?RESPONSE_SOURCE:RESPONSE_RESULT;
                        state<=ST_RSP;
                    end else begin
                        read_index<=read_index+1'b1;read_lane_hot<=read_lane_hot<<1;watchdog_count<=0;state<=ST_R;
                    end
                end
            end else begin
                native_response<=axi_rdata;
                response_kind<=RESPONSE_NATIVE;
                if(axi_rid!==4'd0 || axi_rlast!==1'b1)begin fault_reason<=3;fault<=1;cache_valid<=0;source_cache_valid<=0;end
                state<=ST_RSP;
            end
        end
    endtask

    // A sticky protocol/timeout fault is a hard stop until the shared DDR
    // reset flushes both this adapter and the DDR IP's in-flight responses.
    assign cmd_ready = rst_n && init_done && !fault && ((state == ST_IDLE)||(state == ST_RSP));
    assign rsp_valid = rst_n && (state == ST_RSP);

    assign axi_awaddr = addr_hold;
    assign axi_awuser_ap = 1'b0;
    assign axi_awuser_id = 4'b0000;
    assign axi_awlen = write_burst?write_last:4'd0;
    assign axi_awvalid = (state == ST_AW);

    // There is no WVALID on this IP. Keep the beat stable from command
    // acceptance through the WREADY consumption edge.
    assign axi_wdata = native_wdata;
    assign axi_wstrb = wstrb_hold;

    assign axi_araddr = read_burst?{addr_hold[27:BLOCK_BITS],{BLOCK_BITS{1'b0}}}:addr_hold;
    assign axi_aruser_ap = 1'b0;
    assign axi_aruser_id = 4'b0000;
    assign axi_arlen = read_burst?(READ_PREFETCH_BEATS-1):4'd0;
    assign axi_arvalid = (state == ST_AR);

    task receive_write;
        begin
            if(axi_wusero_id!==4'd0 || axi_wusero_last!==(write_burst?(write_index==write_last):1'b1))begin
                fault_reason<=2;fault<=1;state<=ST_RSP;
            end else if(!write_burst || write_index==write_last)begin
                write_burst<=0;state<=ST_RSP;
            end else begin
                native_wdata<=write_result?result_hold[next_write_index[2:0]*256+:256]:capture_hold[next_write_index*256+:256];
                write_index<=write_index+1'b1;watchdog_count<=0;state<=ST_W;
            end
        end
    endtask

    task accept_command;
        begin
                        write_burst<=force_result_block||capture_command;write_index<=0;
                        write_last<=force_result_block?4'd7:CAPTURE_BURST_BEATS-1;
                        write_result<=force_result_block;

                        // Single outstanding: capture the response word for
                        // every command here, before hit/miss/legality decode.
                        // A miss keeps it through the final R beat. An old
                        // ST_RSP response is consumed before this NBA update.
                        response_word<=cmd_addr[BLOCK_BITS-1:3];
                        addr_hold <= cmd_addr;
                        wdata_hold <= cmd_wdata;
                        wstrb_hold <= cmd_wstrb;
                        rsp_write <= cmd_write;
                        response_kind<=RESPONSE_ZERO;
                        read_burst<=0;read_index<=0;read_lane_hot<=1;read_source<=0;
                        // Explicit source-block clients do not use the sequential-word hint.
                        if(SOURCE_PREFETCH_ENABLE&&source_read)begin source_next_valid<=1;source_next_addr<=cmd_addr+28'd8;end
                        if(cmd_write && source_cache_valid && source_cache_tag==cmd_addr[27:BLOCK_BITS])source_cache_valid<=0;
                        if(cmd_write && cache_valid && cache_tag==cmd_addr[27:BLOCK_BITS])cache_valid<=0;
                        if (cmd_addr[2:0] != 3'b000 || (capture_command && (({4'd0,cmd_addr}&CAP_MASK)!=0 || !capture_block_safe)) ||
                            (force_source_block && (cmd_write || cmd_addr[5:0]!=0 || !source_block_safe)) ||
                            (force_result_block && (!cmd_write || force_source_block || cmd_addr[5:0]!=0 || !result_block_safe))) begin
                            // Misaligned block commands cannot be represented
                            // by one 256-bit beat. Retire with zero data.
                            fault_reason<=1;fault <= 1'b1;
                            state <= ST_RSP;
                        end else if (cmd_write) begin
                            state <= ST_WPREP;
                        end else if(cache_hit)begin
                            response_kind<=source_hit?RESPONSE_SOURCE:RESPONSE_RESULT;
                            state<=ST_RSP;
                        end else begin
                            read_burst<=result_read || source_prefetch;read_source<=source_prefetch;
                            if(source_prefetch)source_cache_valid<=0;
                            if(result_read)cache_valid<=0;
                            state <= ST_AR;
                        end
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;write_burst<=0;write_index<=0;write_last<=0;write_result<=0;native_wdata<=0;fault_reason<=0;
            addr_hold <= 28'd0;
            wdata_hold <= 256'd0;
            wstrb_hold <= 32'd0;
            watchdog_count <= 32'd0;
            rsp_write <= 1'b0;
            response_kind<=RESPONSE_ZERO;response_word<=0;native_response<=0;
            source_cache_valid<=0;source_cache_tag<=0;source_next_valid<=0;source_next_addr<=0;read_source<=0;
            fault <= 1'b0;cache_valid<=0;cache_tag<=0;read_burst<=0;read_index<=0;read_lane_hot<=1;
        end else begin
            case (state)
                ST_IDLE: begin
                    watchdog_count <= 32'd0;
                    if (cmd_valid && cmd_ready) begin
                        accept_command;
                    end
                end

                ST_WPREP: begin
                    // Payload and classification are registered together on
                    // acceptance. Select the first beat in this local stage,
                    // keeping the live arbiter/address decode off256 data FFs.
                    native_wdata<=write_burst?(write_result?result_hold[255:0]:capture_hold[255:0]):wdata_hold;
                    watchdog_count<=0;state<=ST_AW;
                end

                ST_AW: begin
                    if (axi_awready) begin
                        if (axi_wready) begin
                            receive_write;
                        end else begin
                            state <= ST_W;
                        end
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault_reason<=4'd4;fault <= 1'b1;
                        response_kind<=RESPONSE_ZERO;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_W: begin
                    if (axi_wready) begin
                        receive_write;
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault_reason<=4'd5;fault <= 1'b1;
                        response_kind<=RESPONSE_ZERO;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_AR: begin
                    if (axi_arready) begin
                        if (axi_rvalid) begin
                            receive_read;
                        end else begin
                            state <= ST_R;
                        end
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault_reason<=4'd6;fault <= 1'b1;
                        response_kind<=RESPONSE_ZERO;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_R: begin
                    if (axi_rvalid) begin
                        // No RREADY exists; consecutive beats cannot be dropped.
                        receive_read;
                    end else if (watchdog_count >= WATCHDOG_CYCLES-1) begin
                        fault_reason<=4'd7;fault <= 1'b1;
                        response_kind<=RESPONSE_ZERO;
                        state <= ST_RSP;
                    end else begin
                        watchdog_count <= watchdog_count + 1'b1;
                    end
                end

                ST_RSP: begin
                    watchdog_count <= 32'd0;
                    if(cmd_valid&&cmd_ready)accept_command;
                    else state <= ST_IDLE;
                end

                default: begin
                    fault <= 1'b1;
                    response_kind<=RESPONSE_ZERO;
                    rsp_write <= 1'b0;
                    state <= ST_RSP;
                end
            endcase
        end
    end

    generate if((READ_PREFETCH_BEATS!=8&&READ_PREFETCH_BEATS!=16)||
      (READ_PREFETCH_BEATS==16&&((SOURCE_BASE0%128)!=0||(SOURCE_BASE1%128)!=0||(RESULT_BASE0%128)!=0||(RESULT_BASE1%128)!=0||(SOURCE_WORDS%128)!=0||(RESULT_WORDS%128)!=0)))begin: invalid_prefetch_contract
      READ_PREFETCH_WINDOWS_MUST_ALIGN_TO_FULL_BLOCK parameter_error();
    end endgenerate

// synthesis translate_off
    always @(posedge clk)if(rst_n&&read_burst&&read_lane_hot!=({{(READ_PREFETCH_BEATS-1){1'b0}},1'b1}<<read_index))$fatal(1,"Read beat lane ownership mismatch");
    // synthesis translate_on
endmodule

`default_nettype wire




