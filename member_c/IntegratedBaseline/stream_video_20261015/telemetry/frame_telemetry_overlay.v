// Independent left-sidebar telemetry. No changes to image/solver arithmetic.
// All counters originate in proc_clk. Common hard reset must reset both domains.
module frame_telemetry_overlay #(
 parameter integer PROC_CYCLES_PER_MS = 54000
)(
 input wire proc_clk,proc_rst_n,pix_clk,pix_rst_n,
 input wire scan_de,scan_start,
 input wire [11:0] x,y,
 input wire [31:0] displayed_frame_id,display_age_ms,
 input wire [31:0] admitted_frames,published_frames,rejected_frames,
 input wire [511:0] reject_reason_counts,
 input wire image_valid,
 output reg on,
 output reg [23:0] rgb
);
 // 9 values, each full unsigned 32-bit converted to ten packed decimal digits.
 // Age remains milliseconds in BCD; display selects 100ms through 100s digits.
 reg [31:0] binary [0:8];
 reg [39:0] bcd [0:8];
 reg [39:0] adjusted [0:8];
 reg [31:0] ms_cycle;
 reg [5:0] bit_count;
 reg [1:0] state;
 reg held_work;
 reg req_proc;
 (* ASYNC_REG="TRUE" *) reg [2:0] ack_sync;
 reg [360:0] mailbox;
 (* ASYNC_REG="TRUE" *) reg [2:0] req_sync;
 reg ack_pix;
 reg [360:0] shown;
 reg shown_valid;
 integer i,a,b;
 always @* begin
  for(a=0;a<9;a=a+1) begin
   adjusted[a]=bcd[a];
   for(b=0;b<10;b=b+1)
    if(bcd[a][b*4+:4]>=5) adjusted[a][b*4+:4]=bcd[a][b*4+:4]+4'd3;
  end
 end
 always @(posedge proc_clk or negedge proc_rst_n) begin
  if(!proc_rst_n) begin
   ms_cycle<=0;bit_count<=0;state<=0;req_proc<=0;ack_sync<=0;mailbox<=0;held_work<=0;
   for(i=0;i<9;i=i+1)begin binary[i]<=0;bcd[i]<=0;end
  end else begin
   ack_sync<={ack_sync[1:0],ack_pix};
   if(ms_cycle==PROC_CYCLES_PER_MS-1)ms_cycle<=0;else ms_cycle<=ms_cycle+1'b1;
   case(state)
    0: if(ms_cycle==PROC_CYCLES_PER_MS-1 && ack_sync[2]==req_proc)begin
     binary[0]<=display_age_ms>=999900?32'd999900:display_age_ms;
     binary[1]<=displayed_frame_id;binary[2]<=published_frames;binary[3]<=admitted_frames;
     binary[4]<=rejected_frames;binary[5]<=reject_reason_counts[3*32+:32];
     binary[6]<=reject_reason_counts[12*32+:32];binary[7]<=reject_reason_counts[13*32+:32];
     binary[8]<=reject_reason_counts[4*32+:32];
     for(i=0;i<9;i=i+1)bcd[i]<=0;
     held_work<=display_age_ms>=250;bit_count<=0;state<=1;
    end
    1: begin
     for(i=0;i<9;i=i+1)begin
      bcd[i]<={adjusted[i][38:0],binary[i][31]};binary[i]<={binary[i][30:0],1'b0};
     end
     if(bit_count==31)state<=2;else bit_count<=bit_count+1'b1;
    end
    2: begin
     for(i=0;i<9;i=i+1)mailbox[i*40+:40]<=bcd[i];
     mailbox[360]<=held_work;req_proc<=~req_proc;state<=0;
    end
    default:state<=0;
   endcase
  end
 end
 // Bundled mailbox is stable before request reaches 3-FF synchronizer, and
 // remains stable until receiver ACK returns through another 3-FF synchronizer.
 // ACK only after applying at a frame boundary; no torn telemetry within a frame.
 always @(posedge pix_clk or negedge pix_rst_n) begin
  if(!pix_rst_n)begin req_sync<=0;ack_pix<=0;shown<=0;shown_valid<=0;end
  else begin
   req_sync<={req_sync[1:0],req_proc};
   if(scan_start && req_sync[2]!=ack_pix)begin
    shown<=mailbox;shown_valid<=1;ack_pix<=req_sync[2];
   end
  end
 end
 // Each glyph stores seven rows, five bits left to right, MSB is top-left.
 function [34:0] font;
 input [7:0] c;
 begin
 case(c)
 "0":font=35'b01110_10001_10011_10101_11001_10001_01110;
 "1":font=35'b00100_01100_00100_00100_00100_00100_01110;
 "2":font=35'b01110_10001_00001_00010_00100_01000_11111;
 "3":font=35'b11110_00001_00001_01110_00001_00001_11110;
 "4":font=35'b00010_00110_01010_10010_11111_00010_00010;
 "5":font=35'b11111_10000_10000_11110_00001_00001_11110;
 "6":font=35'b01110_10000_10000_11110_10001_10001_01110;
 "7":font=35'b11111_00001_00010_00100_01000_01000_01000;
 "8":font=35'b01110_10001_10001_01110_10001_10001_01110;
 "9":font=35'b01110_10001_10001_01111_00001_00001_01110;
 "A":font=35'b01110_10001_10001_11111_10001_10001_10001;
 "B":font=35'b11110_10001_10001_11110_10001_10001_11110;
 "C":font=35'b01111_10000_10000_10000_10000_10000_01111;
 "D":font=35'b11110_10001_10001_10001_10001_10001_11110;
 "E":font=35'b11111_10000_10000_11110_10000_10000_11111;
 "F":font=35'b11111_10000_10000_11110_10000_10000_10000;
 "G":font=35'b01111_10000_10000_10111_10001_10001_01111;
 "H":font=35'b10001_10001_10001_11111_10001_10001_10001;
 "I":font=35'b01110_00100_00100_00100_00100_00100_01110;
 "J":font=35'b00111_00010_00010_00010_10010_10010_01100;
 "K":font=35'b10001_10010_10100_11000_10100_10010_10001;
 "L":font=35'b10000_10000_10000_10000_10000_10000_11111;
 "M":font=35'b10001_11011_10101_10101_10001_10001_10001;
 "N":font=35'b10001_11001_10101_10011_10001_10001_10001;
 "O":font=35'b01110_10001_10001_10001_10001_10001_01110;
 "P":font=35'b11110_10001_10001_11110_10000_10000_10000;
 "Q":font=35'b01110_10001_10001_10001_10101_10010_01101;
 "R":font=35'b11110_10001_10001_11110_10100_10010_10001;
 "S":font=35'b01111_10000_10000_01110_00001_00001_11110;
 "T":font=35'b11111_00100_00100_00100_00100_00100_00100;
 "U":font=35'b10001_10001_10001_10001_10001_10001_01110;
 "V":font=35'b10001_10001_10001_10001_10001_01010_00100;
 "W":font=35'b10001_10001_10001_10101_10101_10101_01010;
 "X":font=35'b10001_10001_01010_00100_01010_10001_10001;
 "Y":font=35'b10001_10001_01010_00100_00100_00100_00100;
 "Z":font=35'b11111_00001_00010_00100_01000_10000_11111;
 ".":font=35'b00000_00000_00000_00000_00000_00000_10000;
 default:font=0;
 endcase
 end
 endfunction
 function [7:0] label_char;
 input [3:0] row;
 input [4:0] col;
 reg [47:0] label_text;
 begin
 case(row)
 1:label_text="FRAME ";2:label_text="PUB   ";3:label_text="CAP   ";
 4:label_text="REJ   ";5:label_text="MARK  ";6:label_text="SHAPE ";
 7:label_text="OVER  ";8:label_text="SOLVE ";default:label_text="      ";
 endcase
 label_char=label_text[(5-col)*8+:8];
 end
 endfunction

 // Raster prefetch: prepare cell N while scanning the preceding 16 pixels.
 // x=0..15 prepares glyph at x=16; x=16..31 prepares glyph at x=32, etc.
 // The decoder is split into ordinary single-cycle register stages. No timing
 // exceptions are needed, and the output still refers to current x/y.
 wire [11:0] dx=x-12'd16,dy=y-12'd80;
 reg [4:0] fetch_col;
 reg [3:0] fetch_row;
 reg [2:0] fetch_glyph_y;
 reg fetch_line_valid;
 reg [39:0] line_value;
 reg [15:0] age_digits;
 reg fetch_held;
 reg [7:0] character;
 reg [34:0] glyph;
 reg [4:0] prefetched_row,active_row;
 reg active_line_valid;
 reg [7:0] next_character;
 reg [3:0] digit;
 always @* begin
  next_character=" ";digit=0;
  if(fetch_row==0)begin
   case(fetch_col)
    0:next_character=fetch_held?"H":"A";
    1:next_character=fetch_held?"E":"G";
    2:next_character=fetch_held?"L":"E";
    3:next_character=fetch_held?"D":" ";
    5:next_character="0"+{4'b0,age_digits[15:12]};
    6:next_character="0"+{4'b0,age_digits[11:8]};
    7:next_character="0"+{4'b0,age_digits[7:4]};
    8:next_character=".";
    9:next_character="0"+{4'b0,age_digits[3:0]};
    10:next_character="S";
    default:next_character=" ";
   endcase
  end else if(fetch_row<=8)begin
   if(fetch_col<6)next_character=label_char(fetch_row,fetch_col);
   else if(fetch_col<16)begin
    digit=line_value[(15-fetch_col)*4+:4];
    next_character="0"+{4'b0,digit};
   end
  end
 end
 always @(posedge pix_clk or negedge pix_rst_n)begin
  if(!pix_rst_n)begin
   fetch_col<=0;fetch_row<=0;fetch_glyph_y<=0;fetch_line_valid<=0;
   line_value<=0;age_digits<=0;fetch_held<=0;character<=0;glyph<=0;
   prefetched_row<=0;active_row<=0;active_line_valid<=0;
  end else begin
   case(x[3:0])
    0:begin
     fetch_col<=x[8:4];fetch_row<=dy[8:5];fetch_glyph_y<=dy[3:1];
     fetch_line_valid<=y>=80 && y<350 && !dy[4] && dy[3:1]<7;
    end
    1:begin
     case(fetch_row)
      1:line_value<=shown[79:40];2:line_value<=shown[119:80];3:line_value<=shown[159:120];
      4:line_value<=shown[199:160];5:line_value<=shown[239:200];6:line_value<=shown[279:240];
      7:line_value<=shown[319:280];8:line_value<=shown[359:320];default:line_value<=0;
     endcase
     age_digits<=shown[23:8];fetch_held<=shown[360];
    end
    2:character<=next_character;
    3:glyph<=font(character);
    4:case(fetch_glyph_y)
      0:prefetched_row<=glyph[34:30];1:prefetched_row<=glyph[29:25];
      2:prefetched_row<=glyph[24:20];3:prefetched_row<=glyph[19:15];
      4:prefetched_row<=glyph[14:10];5:prefetched_row<=glyph[9:5];
      6:prefetched_row<=glyph[4:0];default:prefetched_row<=0;
     endcase
    15:begin active_row<=prefetched_row;active_line_valid<=fetch_line_valid;end
    default:begin end
   endcase
  end
 end
 always @*begin
  rgb=shown[360]?24'hffb040:24'h40ff80;
  on=0;
  // Only a five-bit pixel mux and basic horizontal/valid gating remain here.
  // All vertical decoding, counter selection and font lookup end at registers.
  if(scan_de && image_valid && shown_valid && x>=16 && x<272 &&
     active_line_valid && dx[3:1]<5)
   on=active_row[4-dx[3:1]];
 end
endmodule
