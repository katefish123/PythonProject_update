`timescale 1ns/1ps
`default_nettype none
// Two hot beats give one-cycle hits; a synchronous two-way L2 retains nearby
// source rows. The source is immutable until invalidate/reset. One DDR miss
// remains outstanding, and an invalidated in-flight read is returned uncached.
module ddr_pixel_cache #(
    parameter L2_SET_BITS=7
)(
    input wire clk,rst_n,invalidate,
    input wire mem_valid,output wire mem_ready,input wire [23:0] mem_addr,
    output reg mem_rsp_valid,output reg [23:0] mem_rgb,
    input wire [27:0] base_word_addr,
    output wire cmd_valid,input wire cmd_ready,output wire cmd_write,
    output reg [27:0] cmd_addr,output wire [255:0] cmd_wdata,
    output wire [31:0] cmd_wstrb,
    input wire rsp_valid,rsp_write,input wire [255:0] rsp_rdata
);
    localparam SETS=1<<L2_SET_BITS, TAG_BITS=25-L2_SET_BITS;
    localparam ST_IDLE=0,ST_LOOKUP=1,ST_CMD=2,ST_RSP=3;
    reg [1:0] state;
    reg valid0,valid1,replace_way;
    reg [24:0] tag0,tag1,miss_tag;
    reg [255:0] data0,data1;
    reg [2:0] miss_offset;
    reg miss_way,miss_l2_way,invalidate_pending;
    reg [SETS-1:0] l2_valid0,l2_valid1,l2_replace;
    reg [TAG_BITS-1:0] l2_tag0[0:SETS-1],l2_tag1[0:SETS-1];
    reg [255:0] l2_data0[0:SETS-1],l2_data1[0:SETS-1];
    reg [255:0] l2_read0,l2_read1;
    wire [27:0] req_line=base_word_addr+{4'd0,mem_addr[23:3],3'b000};
    wire [24:0] req_tag=req_line[27:3];
    wire [L2_SET_BITS-1:0] req_set=req_tag[L2_SET_BITS-1:0];
    wire [L2_SET_BITS-1:0] saved_set=miss_tag[L2_SET_BITS-1:0];
    wire [TAG_BITS-1:0] saved_tag=miss_tag[24:L2_SET_BITS];
    wire hit0=valid0&&tag0==req_tag,hit1=valid1&&tag1==req_tag;
    wire l2_hit0=l2_valid0[saved_set]&&l2_tag0[saved_set]==saved_tag;
    wire l2_hit1=l2_valid1[saved_set]&&l2_tag1[saved_set]==saved_tag;
    wire lookup_hit=state==ST_LOOKUP&&!invalidate&&!invalidate_pending&&(l2_hit0||l2_hit1);
    wire ddr_complete=((state==ST_CMD&&cmd_ready)||(state==ST_RSP))&&rsp_valid;
    wire fill_valid=rst_n&&ddr_complete&&!invalidate&&!invalidate_pending&&!rsp_write;
    wire [255:0] lookup_data=l2_hit0?l2_read0:l2_read1;
    wire [255:0] return_data=lookup_hit?lookup_data:rsp_rdata;
    assign mem_ready=rst_n&&state==ST_IDLE;
    assign cmd_valid=rst_n&&state==ST_CMD;
    assign cmd_write=1'b0;
    assign cmd_wdata=256'd0;
    assign cmd_wstrb=32'd0;

    // No data-array reset: validity owns lifetime and permits RAM inference.
    // Registered full-beat reads have settled by ST_LOOKUP's clock edge.
    always @(posedge clk)begin
        if(mem_valid&&mem_ready)begin
            l2_read0<=l2_data0[req_set];
            l2_read1<=l2_data1[req_set];
        end
        if(fill_valid)begin
            if(miss_l2_way)begin l2_data1[saved_set]<=rsp_rdata;l2_tag1[saved_set]<=saved_tag;end
            else begin l2_data0[saved_set]<=rsp_rdata;l2_tag0[saved_set]<=saved_tag;end
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=ST_IDLE;valid0<=0;valid1<=0;replace_way<=0;
            tag0<=0;tag1<=0;data0<=0;data1<=0;miss_tag<=0;
            miss_offset<=0;miss_way<=0;miss_l2_way<=0;invalidate_pending<=0;
            l2_valid0<=0;l2_valid1<=0;l2_replace<=0;
            mem_rsp_valid<=0;mem_rgb<=0;cmd_addr<=0;
        end else begin
            mem_rsp_valid<=0;
            if(invalidate)begin
                valid0<=0;valid1<=0;l2_valid0<=0;l2_valid1<=0;
                if(state!=ST_IDLE)invalidate_pending<=1;
            end
            case(state)
                ST_IDLE:begin
                    invalidate_pending<=invalidate;
                    if(mem_valid&&mem_ready)begin
                        if(!invalidate&&(hit0||hit1))begin
                            mem_rgb<=hit0?data0[mem_addr[2:0]*32+:24]:data1[mem_addr[2:0]*32+:24];
                            mem_rsp_valid<=1;replace_way<=hit0;
                            // Touch L2 LRU even when the hot beat serves the request.
                            if(l2_valid0[req_set]&&l2_tag0[req_set]==req_tag[24:L2_SET_BITS])l2_replace[req_set]<=1;
                            else if(l2_valid1[req_set]&&l2_tag1[req_set]==req_tag[24:L2_SET_BITS])l2_replace[req_set]<=0;
                        end else begin
                            miss_tag<=req_tag;miss_offset<=mem_addr[2:0];cmd_addr<=req_line;
                            miss_way<=(invalidate||!valid0)?1'b0:(!valid1?1'b1:replace_way);
                            state<=ST_LOOKUP;
                        end
                    end
                end
                ST_LOOKUP:begin
                    if(lookup_hit)begin
                        l2_replace[saved_set]<=l2_hit0;
                        state<=ST_IDLE;invalidate_pending<=0;
                    end else begin
                        miss_l2_way<=!l2_valid0[saved_set]?1'b0:(!l2_valid1[saved_set]?1'b1:l2_replace[saved_set]);
                        state<=ST_CMD;
                    end
                end
                ST_CMD:if(cmd_ready)begin
                    if(rsp_valid)begin state<=ST_IDLE;invalidate_pending<=0;end
                    else state<=ST_RSP;
                end
                ST_RSP:if(rsp_valid)begin state<=ST_IDLE;invalidate_pending<=0;end
                default:begin state<=ST_IDLE;valid0<=0;valid1<=0;l2_valid0<=0;l2_valid1<=0;end
            endcase
            if(lookup_hit||ddr_complete)begin
                mem_rgb<=(!lookup_hit&&rsp_write)?24'd0:return_data[miss_offset*32+:24];
                mem_rsp_valid<=1;
                if(lookup_hit||fill_valid)begin
                    if(miss_way)begin valid1<=1;tag1<=miss_tag;data1<=return_data;replace_way<=0;end
                    else begin valid0<=1;tag0<=miss_tag;data0<=return_data;replace_way<=1;end
                end else begin valid0<=0;valid1<=0;l2_valid0<=0;l2_valid1<=0;end
            end
            if(fill_valid)begin
                if(miss_l2_way)begin l2_valid1[saved_set]<=1;l2_replace[saved_set]<=0;end
                else begin l2_valid0[saved_set]<=1;l2_replace[saved_set]<=1;end
            end
        end
    end
endmodule
`default_nettype wire
