`default_nettype none
// Byte-address layout. MEMORY_BYTES must be set to the board's usable capacity
// by the integrator; its default describes only the command address window.
module ddr_memory_layout #(
 parameter integer SRC_W=1920,SRC_H=1080,OUT_W=640,OUT_H=904,
 parameter integer MEMORY_BYTES=1073741824
)(output wire [31:0] source_base0_byte,source_base1_byte,source_base2_byte,
 result_base0_byte,result_base1_byte,source_bytes,result_bytes,output wire layout_valid);
 localparam [63:0] SRC_BYTES=64'd4*SRC_W*SRC_H;
 localparam [63:0] OUT_BYTES=64'd4*OUT_W*OUT_H;
 localparam [63:0] SRC_STRIDE=((SRC_BYTES+31)/32)*32;
 localparam [63:0] OUT_STRIDE=((OUT_BYTES+31)/32)*32;
 localparam [63:0] RESULT0=3*SRC_STRIDE;
 localparam [63:0] RESULT1=RESULT0+OUT_STRIDE;
 localparam [63:0] END_BYTE=RESULT1+OUT_STRIDE;
 assign source_base0_byte=0;
 assign source_base1_byte=SRC_STRIDE[31:0];
 assign source_base2_byte=2*SRC_STRIDE[31:0];
 assign result_base0_byte=RESULT0[31:0];assign result_base1_byte=RESULT1[31:0];
 assign source_bytes=SRC_BYTES[31:0];assign result_bytes=OUT_BYTES[31:0];
 assign layout_valid=(SRC_W>0&&SRC_H>0&&OUT_W>0&&OUT_H>0&&MEMORY_BYTES>0)&&
  SRC_STRIDE<=64'd1073741824&&OUT_STRIDE<=64'd1073741824&&
  END_BYTE<=64'd1073741824&&END_BYTE<=MEMORY_BYTES;
endmodule
`default_nettype wire
