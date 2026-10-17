`timescale 1ns/1ps
module tb_lens_profile_bank;
 reg clk=0,rst_n=0;always #5 clk=~clk;
 reg cfg_begin=0,cfg_write=0,cfg_seal=0,frame_start=0;
 reg[4:0]cfg_index=0;reg[63:0]cfg_data=0;
 wire cfg_error,pending_valid,active_valid;wire[1471:0]active_words;
 reg[12:0]expected_width=1920,expected_height=1080;reg[31:0]expected_mode=7;
 lens_profile_bank dut(.*);
 reg[63:0]words[0:22];integer errors=0,cases=0;
 always @(posedge clk)if(cfg_error)errors++;
 task defaults(input integer version);
 begin
 for(integer i=0;i<23;i++)words[i]=0;
 words[0]=913*64'd1073741824;words[1]=901*64'd1073741824;
 words[2]=960*64'd1073741824;words[3]=539*64'd1073741824;
 words[8]=1073741824;words[12]=1073741824;words[16]=1073741824;
 words[17]=1920;words[18]=1080;words[19]=version;words[20]=version+100;words[21]=7;words[22]=1;
 end endtask
 task pulse_begin;begin @(negedge clk);cfg_begin=1;@(negedge clk);cfg_begin=0;end endtask
 task write_all(input integer count);
 begin pulse_begin();for(integer i=0;i<count;i++)begin @(negedge clk);cfg_index=i;cfg_data=words[i];cfg_write=1;end
 @(negedge clk);cfg_write=0;end endtask
 task seal;begin @(negedge clk);cfg_seal=1;@(negedge clk);cfg_seal=0;end endtask
 task boundary;begin @(negedge clk);frame_start=1;@(negedge clk);frame_start=0;end endtask
 task invalid_case(input integer index,input[63:0]bad);
 integer e;begin defaults(2);words[index]=bad;e=errors;write_all(23);seal();repeat(2)@(negedge clk);
 if(pending_valid||errors==e||active_words[19*64+:64]!=1)$fatal(1,"invalid profile accepted index%0d",index);cases++;
 end endtask
 initial begin
 repeat(3)@(negedge clk);rst_n=1;defaults(1);
 write_all(22);seal();if(pending_valid||active_valid)$fatal(1,"partial profile accepted");
 write_all(23);seal();if(!pending_valid||active_valid)$fatal(1,"seal must not commit midframe");
 @(negedge clk);cfg_write=1;cfg_index=19;cfg_data=999;@(negedge clk);cfg_write=0;
 boundary();if(!active_valid||active_words[19*64+:64]!=1)$fatal(1,"pending bank mutated");
 invalid_case(0,0);invalid_case(1,65537*64'd1073741824);
 invalid_case(2,-64'sd1);invalid_case(3,1080*64'd1073741824);
 invalid_case(4,1073741825);invalid_case(5,-64'sd1073741825);
 invalid_case(6,268435457);invalid_case(7,-64'sd268435457);
 invalid_case(8,65537*64'd1073741824);
 invalid_case(17,1280);invalid_case(18,720);invalid_case(19,0);
 invalid_case(20,64'h100000001);invalid_case(21,8);invalid_case(22,2);
 defaults(2);write_all(23);
 @(negedge clk);cfg_seal=1;frame_start=1;@(negedge clk);cfg_seal=0;frame_start=0;
 if(active_words[19*64+:64]!=1||!pending_valid)$fatal(1,"same-edge seal committed too early");
 boundary();if(active_words[19*64+:64]!=2||pending_valid)$fatal(1,"complete frame bundle not committed");
 defaults(3);write_all(23);seal();expected_mode=8;#1;
 if(active_valid)$fatal(1,"ACTIVE_PROFILE_MODE_CHANGED_BUT_STILL_VALID");
 boundary();if(pending_valid||active_words[19*64+:64]!=2||active_valid)$fatal(1,"PENDING_MODE_CHANGED_AFTER_SEAL_WAS_COMMITTED");
 expected_mode=7;expected_width=1280;#1;if(active_valid)$fatal(1,"active profile dimension mismatch ignored");
 expected_width=1920;#1;if(!active_valid)$fatal(1,"same known mode not reusable");
 defaults(3);write_all(23);seal();@(negedge clk);rst_n=0;@(negedge clk);rst_n=1;
 boundary();if(active_valid||pending_valid)$fatal(1,"reset retained stale profile");
 $display("PASS LENS_PROFILE_BANK 15 invalid profiles,partial,pending immutability,atomic boundary,seal collision,reset");$finish;
 end
 initial begin #100000;$fatal(1,"profile timeout");end
endmodule
