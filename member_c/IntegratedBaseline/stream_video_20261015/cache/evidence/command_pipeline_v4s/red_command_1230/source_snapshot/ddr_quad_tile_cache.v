`timescale 1ns/1ps
`default_nettype none
// UI-clock four-neighbour cache. Addresses are 32-bit source WORD addresses.
// Source rows must be multiples of64 words and frame height a multiple of4.
// Fill interface returns one aligned64-word block per command. Shared hard
// reset must also reset its owner/DDR engine; soft abort does not reset cache.
module ddr_quad_tile_cache #(
 parameter SRC_W=1920, SRC_H=1080, LINES=64, WATCHDOG_CYCLES=8192
)(
 input wire clk,rst_n,
 input wire req_valid, output wire req_ready,
 input wire[27:0]req_base,input wire[31:0]req_generation,
 input wire[11:0]req_x,req_y,input wire req_inside,req_nearest,
 input wire[23:0]req_tag,input wire[7:0]req_fx,req_fy,
 output wire rsp_valid,input wire rsp_ready,output reg rsp_inside,
 output reg[23:0]rsp_p00,rsp_p10,rsp_p01,rsp_p11,rsp_tag,
 output reg[7:0]rsp_fx,rsp_fy,output reg[31:0]rsp_generation,
 output wire cmd_valid,input wire cmd_ready,output wire cmd_block,
 output wire[27:0]cmd_addr,
 input wire mem_rsp_valid,mem_rsp_write,input wire[2047:0]rsp_block,
 output reg fault
);
 localparam WB=$clog2(LINES),AB=WB+5;
 localparam[2:0]F_IDLE=0,F_CMD=1,F_WAIT=2,F_WRITE=3,F_PREP=4;
 (* ram_style="block" *) reg[255:0]ram[0:LINES*32-1];
 reg[255:0]read_a,read_b;
 reg[LINES-1:0]line_valid;
 // Requests are ordered. A new immutable source-generation key invalidates
 // all tags before its lookup; per-way tags then need only tile coordinates.
 // New frame invalidation waits for the old L RAM issue. M/R retain their
 // data independently, and a miss fill waits for M to drain.
 reg[15:0]tags[0:LINES-1];
 reg[59:0]frame_key;
 reg[WB-1:0]replace_way,fill_way;
 reg[75:0]fill_tag;
 reg fill_victim_found;
 reg[2:0]fill_state;reg[1:0]fill_row;
 reg[2:0]fill_word;
 reg[2047:0]fill_data;
 reg[31:0]watchdog;
 reg s_valid,s_inside,s_nearest;
 reg[27:0]s_base;reg[31:0]s_generation;
 reg[11:0]s_x,s_y,s_x1,s_y1;reg[23:0]s_tag;reg[7:0]s_fx,s_fy;
 // L holds a registered lookup decision and RAM addresses. Neither RAM CE
 // nor input capacity depends on the current combinational tag lookup.
 reg l_valid,l_inside,l_missing,l_relookup,l_boundary,l_victim_found;
 reg[27:0]l_base;reg[31:0]l_generation;
 reg[11:0]l_x,l_y,l_x1,l_y1;reg[23:0]l_tag;reg[7:0]l_fx,l_fy;
 reg[2:0]l_left_offset,l_right_offset;
 reg[AB-1:0]l_left_a,l_left_b,l_right_a,l_right_b;
 reg[WB-1:0]l_victim;reg[75:0]l_miss_tag;
 reg m_valid,m_inside,m_boundary,m_phase;
 reg[23:0]m_tag,left_top,left_bot;reg[31:0]m_generation;
 reg[7:0]m_fx,m_fy;reg[2:0]m_left_offset,m_right_offset;
 reg[AB-1:0]m_right_a,m_right_b;
 reg r_valid;
 wire r_space=!r_valid||rsp_ready;
 wire m_complete=m_valid&&(!m_boundary||m_phase)&&r_space;
 wire m_space=!m_valid||m_complete;
 reg[11:0]xx[0:3],yy[0:3];
 reg[75:0]key[0:3];
 reg[WB-1:0]ways[0:3];
 reg[3:0]hits;
 reg[LINES-1:0]protected_ways;
 reg missing;reg[1:0]missing_corner;
 reg victim_found;reg[WB-1:0]victim;
 // A missing L keeps its own coordinates through all fills. S can hold the
 // next frame, but cannot invalidate that frame key until L has issued its read.
 wire lookup_l=l_valid&&l_missing;
 wire[11:0]lookup_x=lookup_l?l_x:s_x,lookup_y=lookup_l?l_y:s_y;
 wire[11:0]lookup_x1=lookup_l?l_x1:s_x1,lookup_y1=lookup_l?l_y1:s_y1;
 wire[27:0]lookup_base=lookup_l?l_base:s_base;
 wire[31:0]lookup_generation=lookup_l?l_generation:s_generation;
 integer p,w,v;
 always @*begin
  xx[0]=lookup_x;xx[1]=lookup_x1;
  xx[2]=xx[0];xx[3]=xx[1];
  yy[0]=lookup_y;yy[1]=lookup_y;
  yy[2]=lookup_y1;yy[3]=yy[2];
  hits=0;protected_ways=0;
  for(p=0;p<4;p=p+1)begin
   key[p]={lookup_generation,lookup_base,yy[p][11:2],xx[p][11:6]};ways[p]=0;
   // Tags are unique: only a missing key is ever installed. OR-encode the
   // one-hot matches, avoiding an unnecessary64-way priority encoder.
   for(w=0;w<LINES;w=w+1)if(line_valid[w]&&tags[w]==key[p][15:0])begin hits[p]=1;ways[p]=ways[p]|w;protected_ways[w]=1;end
  end
  missing=0;missing_corner=0;
  for(p=3;p>=0;p=p-1)if(!hits[p])begin missing=1;missing_corner=p;end
  victim_found=0;victim=replace_way;
  // At most four distinct ways are protected by a quad; five candidates
  // suffice and keep the replacement chain bounded independently of LINES.
  for(v=0;v<5;v=v+1)if(!victim_found&&!protected_ways[(replace_way+v)%LINES])begin victim=(replace_way+v)%LINES;victim_found=1;end
 end
 wire l_advance=l_valid&&!l_missing&&!l_relookup&&m_space&&fill_state==F_IDLE&&!fault;
 wire l_space=!l_valid||l_advance;
 wire s_key_change=s_valid&&l_space&&fill_state==F_IDLE&&frame_key!={s_generation,s_base}&&!fault;
 wire s_advance=s_valid&&l_space&&fill_state==F_IDLE&&frame_key=={s_generation,s_base}&&!fault;
 wire fill_start=l_valid&&l_inside&&l_missing&&!l_relookup&&!m_valid&&fill_state==F_IDLE&&!fault;
 assign req_ready=rst_n&&!fault&&fill_state==F_IDLE&&(!s_valid||s_advance);
 assign rsp_valid=rst_n&&!fault&&r_valid;
 assign cmd_valid=rst_n&&!fault&&fill_state==F_CMD;
 assign cmd_block=1'b1;
 assign cmd_addr=fill_tag[43:16]+((fill_tag[15:6]*4+fill_row)*SRC_W)+{fill_tag[5:0],6'b0};
 wire[AB-1:0]left_a={ways[0],yy[0][1:0],xx[0][5:3]};
 wire[AB-1:0]left_b={ways[2],yy[2][1:0],xx[2][5:3]};
 wire[AB-1:0]right_a={ways[1],yy[1][1:0],xx[1][5:3]};
 wire[AB-1:0]right_b={ways[3],yy[3][1:0],xx[3][5:3]};
 wire read_right=m_valid&&m_boundary&&!m_phase&&!fault;
 wire read_en=read_right||(l_advance&&l_inside);
 wire[AB-1:0]read_addr_a=read_right?m_right_a:l_left_a;
 wire[AB-1:0]read_addr_b=read_right?m_right_b:l_left_b;
 wire fill_we=fill_state==F_WRITE&&!fault;
 // Exactly two synchronous RAM ports, no reset on data array or RAM outputs.
 always @(posedge clk)begin
  if(fill_we)ram[{fill_way,fill_row,fill_word}]<=fill_data[fill_word*256+:256];
  else if(read_en)read_a<=ram[read_addr_a];
  if(read_en)read_b<=ram[read_addr_b];
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   line_valid<=0;frame_key<=0;replace_way<=0;fill_way<=0;fill_tag<=0;fill_state<=F_IDLE;fill_victim_found<=0;fill_row<=0;fill_word<=0;fill_data<=0;watchdog<=0;fault<=0;
   s_valid<=0;s_inside<=0;s_nearest<=0;s_base<=0;s_generation<=0;s_x<=0;s_y<=0;s_x1<=0;s_y1<=0;s_tag<=0;s_fx<=0;s_fy<=0;
   l_valid<=0;l_inside<=0;l_missing<=0;l_relookup<=0;l_boundary<=0;l_victim_found<=0;
   l_base<=0;l_generation<=0;l_x<=0;l_y<=0;l_x1<=0;l_y1<=0;l_tag<=0;l_fx<=0;l_fy<=0;l_left_offset<=0;l_right_offset<=0;
   l_left_a<=0;l_left_b<=0;l_right_a<=0;l_right_b<=0;l_victim<=0;l_miss_tag<=0;
   m_valid<=0;m_inside<=0;m_boundary<=0;m_phase<=0;m_tag<=0;m_generation<=0;m_fx<=0;m_fy<=0;m_left_offset<=0;m_right_offset<=0;m_right_a<=0;m_right_b<=0;left_top<=0;left_bot<=0;
   r_valid<=0;rsp_inside<=0;rsp_p00<=0;rsp_p10<=0;rsp_p01<=0;rsp_p11<=0;rsp_tag<=0;rsp_generation<=0;rsp_fx<=0;rsp_fy<=0;
  end else if(!fault)begin
   if(r_valid&&rsp_ready)r_valid<=0;
   if(m_complete)begin
    r_valid<=1;rsp_inside<=m_inside;rsp_tag<=m_tag;rsp_generation<=m_generation;rsp_fx<=m_fx;rsp_fy<=m_fy;m_valid<=0;
    if(!m_inside)begin rsp_p00<=0;rsp_p10<=0;rsp_p01<=0;rsp_p11<=0;end
    else if(m_boundary)begin rsp_p00<=left_top;rsp_p01<=left_bot;rsp_p10<=read_a[m_right_offset*32+:24];rsp_p11<=read_b[m_right_offset*32+:24];end
    else begin rsp_p00<=read_a[m_left_offset*32+:24];rsp_p01<=read_b[m_left_offset*32+:24];rsp_p10<=read_a[m_right_offset*32+:24];rsp_p11<=read_b[m_right_offset*32+:24];end
   end
   if(read_right)begin left_top<=read_a[m_left_offset*32+:24];left_bot<=read_b[m_left_offset*32+:24];m_phase<=1;end
   if(l_advance)begin
    l_valid<=0;m_valid<=1;m_inside<=l_inside;m_tag<=l_tag;m_generation<=l_generation;m_fx<=l_fx;m_fy<=l_fy;m_phase<=0;
    m_left_offset<=l_left_offset;m_right_offset<=l_right_offset;m_right_a<=l_right_a;m_right_b<=l_right_b;
    m_boundary<=l_boundary;
   end
   if(s_advance)begin
    s_valid<=0;l_valid<=1;l_inside<=s_inside;l_base<=s_base;l_generation<=s_generation;l_x<=s_x;l_y<=s_y;l_x1<=s_x1;l_y1<=s_y1;
    l_tag<=s_tag;l_fx<=s_fx;l_fy<=s_fy;l_left_offset<=s_x[2:0];l_right_offset<=s_x1[2:0];
    l_boundary<=s_inside&&(s_x[11:3]!=s_x1[11:3]);
    l_left_a<=left_a;l_left_b<=left_b;l_right_a<=right_a;l_right_b<=right_b;
    l_missing<=s_inside&&missing;l_relookup<=0;l_victim<=victim;l_victim_found<=victim_found;l_miss_tag<=key[missing_corner];
   end
   // A fill changes tags/ways. Recompute and register all lookup/replacement
   // results before the retained L may issue a read or request another fill.
   if(l_relookup&&fill_state==F_IDLE)begin
    l_missing<=missing;l_relookup<=0;
    l_left_a<=left_a;l_left_b<=left_b;l_right_a<=right_a;l_right_b<=right_b;
    l_victim<=victim;l_victim_found<=victim_found;l_miss_tag<=key[missing_corner];
   end
   if(s_key_change)begin frame_key<={s_generation,s_base};line_valid<=0;end
   if(req_valid&&req_ready)begin
    s_valid<=1;s_inside<=req_inside;s_nearest<=req_nearest;s_base<=req_base;s_generation<=req_generation;s_x<=req_x;s_y<=req_y;s_tag<=req_tag;s_fx<=req_fx;s_fy<=req_fy;
    s_x1<=(req_nearest||req_x==SRC_W-1)?req_x:req_x+1'b1;
    s_y1<=(req_nearest||req_y==SRC_H-1)?req_y:req_y+1'b1;
    if(req_inside&&(req_x>=SRC_W||req_y>=SRC_H||req_base[5:0]!=0||{1'b0,req_base}+SRC_W*SRC_H>29'h10000000))fault<=1;
   end
   if(fill_start)begin
    // Register replacement success as well as its index. The measured V2B
    // critical path was tags -> protected ways -> victim_found -> fill-row CE.
    // This check belongs to the following miss-only preparation stage.
    fill_way<=l_victim;fill_victim_found<=l_victim_found;fill_tag<=l_miss_tag;
    fill_row<=0;fill_state<=F_PREP;watchdog<=0;
   end
   if(fill_state==F_CMD||fill_state==F_WAIT)begin
    watchdog<=watchdog+1'b1;
    if(watchdog>=WATCHDOG_CYCLES-1)fault<=1;
   end
   case(fill_state)
    F_PREP:begin
     if(!fill_victim_found)fault<=1;
     else begin line_valid[fill_way]<=0;fill_state<=F_CMD;watchdog<=0;end
    end
    F_CMD:if(cmd_ready)begin fill_state<=F_WAIT;watchdog<=0;end
    F_WAIT:if(mem_rsp_valid)begin
     if(mem_rsp_write)fault<=1;
     else begin fill_data<=rsp_block;fill_word<=0;fill_state<=F_WRITE;watchdog<=0;end
    end
    F_WRITE:if(fill_word==7)begin
     if(fill_row==3)begin tags[fill_way]<=fill_tag[15:0];line_valid[fill_way]<=1;replace_way<=fill_way+1'b1;fill_state<=F_IDLE;l_relookup<=1;end
     else begin fill_row<=fill_row+1'b1;fill_state<=F_CMD;watchdog<=0;end
    end else fill_word<=fill_word+1'b1;
    default:begin end
   endcase
  end
 end
endmodule
`default_nettype wire
