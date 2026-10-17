`timescale 1ns/1ps
module tb_region_sample;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,iv=0,ordy=0,scene=1,markers=1,bank=1,pvalid=1;
 reg[1:0]route=2;reg[11:0]x=3,y=4,u=2,v=3;
 reg[23:0]rgb=24'h102030,bg=24'hd0e0f0;reg[31:0]tag=1,fid=7,ver=9;
 reg[511:0]params=0;reg[575:0]h=0;reg[31:0]pv=9,pf=7;reg[12:0]width=16,height=12;
 wire ready,ov,os,oe,ob,busy;wire[23:0]orgb;wire[31:0]ot,ofid,over;wire[11:0]ox,oy;
 wire qv;reg qr=0;wire[11:0]x0,y0,x1,y1;wire[31:0]qt,qf,qver;wire qb;
 reg rv=0;wire rr;reg[95:0]pixels;reg[31:0]rt,rf,rver,mf,mver;reg rb,mvalid=1;reg[3:0]hits=0;
 region_sample dut(.clk(clk),.rst_n(rst_n),.in_valid(iv),.in_ready(ready),.in_route(route),.in_scene_valid(scene),
 .in_markers_enabled(markers),.in_bank(bank),.in_x(x),.in_y(y),.in_u(u),.in_v(v),.in_rgb(rgb),.in_background(bg),
 .in_tag(tag),.in_frame_id(fid),.in_version(ver),.profile_valid(pvalid),.profile_params(params),.profile_h(h),
 .profile_version(pv),.profile_frame_id(pf),.width(width),.height(height),.busy(busy),
 .q_valid(qv),.q_ready(qr),.q_x0(x0),.q_y0(y0),.q_x1(x1),.q_y1(y1),.q_tag(qt),.q_frame_id(qf),.q_version(qver),.q_bank(qb),
 .r_valid(rv),.r_ready(rr),.r_pixels(pixels),.r_tag(rt),.r_frame_id(rf),.r_version(rver),.r_bank(rb),
 .r_mask_valid(mvalid),.r_mask_frame_id(mf),.r_mask_version(mver),.r_marker_hit(hits),
 .out_valid(ov),.out_ready(ordy),.out_rgb(orgb),.out_scene_valid(os),.out_error(oe),.out_bank(ob),
 .out_x(ox),.out_y(oy),.out_tag(ot),.out_frame_id(ofid),.out_version(over));
 task tick;begin @(posedge clk);#1;end endtask
 task submit;begin @(negedge clk);iv=1;while(!ready)@(negedge clk);tick();@(negedge clk);iv=0;end endtask
 task expect_output(input[23:0]color,input good,bad);
 reg[144:0]saved;integer n;
 begin
 n=0;while(!ov)begin tick();n=n+1;if(n>2000)$fatal(1,"OUTPUT_TIMEOUT");end
 if(orgb!==color||os!==good||oe!==bad||ot!==tag||ofid!==fid||over!==ver||ob!==bank||ox!==x||oy!==y)$fatal(1,"OUTPUT_MISMATCH tag=%d rgb=%h expected=%h good=%b error=%b",tag,orgb,color,os,oe);
 saved={orgb,os,oe,ob,ox,oy,ot};repeat(5)begin tick();if(!ov||{orgb,os,oe,ob,ox,oy,ot}!==saved||!busy||ready)$fatal(1,"OUTPUT_BACKPRESSURE");end
 @(negedge clk);ordy=1;tick();@(negedge clk);ordy=0;tag=tag+1;tick();if(busy)$fatal(1,"NOT_IDLE");
 end endtask
 task await_request(input integer ax,ay,bx,by);
 reg[144:0]saved;integer n;
 begin
 n=0;while(!qv)begin tick();n=n+1;if(n>1800)$fatal(1,"MAP_TIMEOUT");end
 if(x0!==ax||y0!==ay||x1!==bx||y1!==by||qt!==tag||qf!==fid||qver!==ver||qb!==bank)$fatal(1,"ADDRESS_ASSOCIATION %d %d %d %d",x0,y0,x1,y1);
 saved={x0,y0,x1,y1,qt,qf,qver,qb};repeat(4)begin tick();if(!qv||{x0,y0,x1,y1,qt,qf,qver,qb}!==saved)$fatal(1,"REQUEST_BACKPRESSURE");end
 @(negedge clk);qr=1;tick();@(negedge clk);qr=0;
 rt=tag;rf=fid;rver=ver;rb=bank;mf=fid;mver=ver;
 end endtask
 task respond;begin repeat(3)tick();@(negedge clk);rv=1;while(!rr)@(negedge clk);tick();@(negedge clk);rv=0;end endtask
 function[23:0]oracle(input[95:0]p,input[3:0]mask,input integer fx,fy);
 integer c,a,b,d,e,t,z;reg[23:0]result;
 begin result=0;for(c=0;c<3;c=c+1)begin
 a=mask[0]?bg[c*8+:8]:p[c*8+:8];b=mask[1]?bg[c*8+:8]:p[24+c*8+:8];
 d=mask[2]?bg[c*8+:8]:p[48+c*8+:8];e=mask[3]?bg[c*8+:8]:p[72+c*8+:8];
 t=a*(256-fx)+b*fx;z=d*(256-fx)+e*fx;result[c*8+:8]=(t*(256-fy)+z*fy)>>16;
 end oracle=result;end endfunction
 function[23:0]pattern(input integer a,b);
 reg[7:0]r,g,z;begin r=(a*3+b*7)%256;g=(a*11+b*5)%256;z=(a*17+b*13)%256;pattern={r,g,z};end endfunction
 reg[923:0]vectors[0:1023];reg[1523:0]composed[0:1023];reg[23:0]reference_pixels[0:1023];
 integer i,requests=0,interpolations=0,expected_requests=0,xx,yy,xx1,yy1,vector_pixels=0;reg[23:0]expected;
 always @(posedge clk)if(rst_n&&qv&&qr)requests=requests+1;
 always @(posedge clk)if(rst_n&&dut.original_b.in_valid)interpolations=interpolations+1;
 initial begin
 $readmemh("vectors.hex",vectors);$readmemh("composed_vectors.hex",composed);$readmemh("expected_pixels.hex",reference_pixels);
 params[0*64+:64]=64'sd17179869184;params[1*64+:64]=64'sd12884901888;
 h[0*64+:64]=64'sd1073741824;h[4*64+:64]=64'sd1073741824;h[8*64+:64]=64'sd1073741824;
 pixels={24'hf0d0b0,24'h907050,24'h604020,24'h103050};
 repeat(3)tick();rst_n=1;tick();
 route=0;submit();expect_output(rgb,1,0);route=1;submit();expect_output(bg,1,0);
 scene=0;route=2;submit();expect_output(rgb,0,0);scene=1;
 pv=10;submit();expect_output(bg,0,1);pv=9;
 pvalid=0;submit();expect_output(bg,0,1);pvalid=1;
 width=1;submit();expect_output(bg,0,1);width=16;
 if(requests!=0)$fatal(1,"BYPASS_MEMORY_REQUEST");
 // Translation gives x=2.25,y=3.5, with all exact neighbor masks.
 h[2*64+:64]=64'sd268435456;h[5*64+:64]=64'sd536870912;
 for(i=0;i<16;i=i+1)begin
 hits=i;submit();await_request(2,3,3,4);expected=oracle(pixels,hits,64,128);respond();expect_output(expected,1,0);
 end
 // Disabled markers ignore an absent mask and even asserted hit flags.
 markers=0;mvalid=0;hits=15;submit();await_request(2,3,3,4);respond();expect_output(oracle(pixels,0,64,128),1,0);markers=1;mvalid=1;
 // Each wrong association independently fails closed.
 for(i=0;i<7;i=i+1)begin
 submit();await_request(2,3,3,4);
 case(i)0:rt=rt+1;1:rf=rf+1;2:rver=rver+1;3:rb=!rb;4:mf=mf+1;5:mver=mver+1;6:mvalid=0;endcase
 respond();expect_output(bg,0,1);mvalid=1;
 end
 // Profile changes while request is computing cannot change captured map.
 hits=0;submit();h[2*64+:64]=64'sd1073741824;pv=123;await_request(2,3,3,4);respond();expect_output(oracle(pixels,0,64,128),1,0);pv=9;
 h[2*64+:64]=0;h[5*64+:64]=0;u=15;v=11;
 submit();await_request(15,11,15,11);respond();expect_output(pixels[23:0],1,0);
 u=16;submit();expect_output(bg,1,0); // outside valid source fills background
 h[8*64+:64]=0;u=2;submit();expect_output(bg,0,1);h[8*64+:64]=64'sd1073741824;
 // Coordinated reset cancels a held request; test memory has no accepted transaction.
 submit();while(!qv)tick();rst_n=0;tick();if(ov||qv||busy)$fatal(1,"RESET_INFLIGHT");rst_n=1;tick();
 route=0;submit();expect_output(rgb,1,0);
 if(requests!=26||interpolations!=19)$fatal(1,"INITIAL_SINGLE_SAMPLE_COUNTS %d %d",requests,interpolations);
 // Largest supported canvas: coordinate4095 must not wrap when clamping +1.
 route=2;width=4096;height=4096;u=4095;v=4095;
 params[0*64+:64]=64'sd4398046511104;params[1*64+:64]=64'sd4398046511104;
 submit();await_request(4095,4095,4095,4095);respond();expect_output(pixels[23:0],1,0);
 // Accepted memory transaction is explicitly cancelled by this test producer
 // while reset is asserted. No response may survive the coordinated reset.
 submit();await_request(4095,4095,4095,4095);rst_n=0;rv=0;tick();rst_n=1;
 repeat(350)begin tick();if(ov||qv||busy)$fatal(1,"COORDINATED_RESET_ACCEPTED_REQUEST");end
 if(requests!=28||interpolations!=20)$fatal(1,"BOUNDARY_RESET_COUNTS");
 expected_requests=requests;route=2;markers=0;hits=0;x=0;y=0;
 for(i=0;i<1024;i=i+1)begin
 params=vectors[i][412+:512];h=composed[i][924+:576];width=vectors[i][386+:13];height=vectors[i][399+:13];
 pv=vectors[i][322+:32];pf=vectors[i][354+:32];fid=vectors[i][290+:32];ver=pv;tag=vectors[i][258+:32];
 u=composed[i][1500+:12];v=composed[i][1512+:12];submit();
 if(vectors[i][129])expect_output(bg,0,1);
 else if(!vectors[i][128])expect_output(bg,1,0);
 else begin
 xx=$signed(vectors[i][0+:64])>>>30;yy=$signed(vectors[i][64+:64])>>>30;
 xx1=xx+1>=width?width-1:xx+1;yy1=yy+1>=height?height-1:yy+1;
 await_request(xx,yy,xx1,yy1);pixels={pattern(xx1,yy1),pattern(xx,yy1),pattern(xx1,yy),pattern(xx,yy)};
 expected=reference_pixels[i];respond();expect_output(expected,1,0);expected_requests=expected_requests+1;vector_pixels=vector_pixels+1;
 end
 end
 if(requests!=expected_requests)$fatal(1,"DUPLICATE_MEMORY_REQUEST %d %d",requests,expected_requests);
 if(interpolations!=20+vector_pixels)$fatal(1,"DUPLICATE_INTERPOLATION %d",interpolations);
 $display("PASS REGION_SAMPLE original-B single interpolation,16 masks,1024 independent composed vectors,sampled_pixels=%0d,profile snapshot,stale rejection,bypass,edges,backpressure,reset requests=%0d interpolations=%0d",vector_pixels,requests,interpolations);$finish;
 end
 initial begin #10000000;$fatal(1,"WATCHDOG");end
endmodule
