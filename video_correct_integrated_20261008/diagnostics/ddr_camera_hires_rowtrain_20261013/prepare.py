"""Independent display row train clone of the sealed prefetch image."""
from pathlib import Path
import hashlib,json,shutil,re
D=Path(__file__).resolve().parent
R=D.parents[1]
O=D/'results'
O.mkdir(exist_ok=True)
base=R/'release/ddr_camera_hires_prefetch_20261012'
old=R/'diagnostics/ddr_camera_hires_prefetch_20261012'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
q=json.loads((base/'build_qualification.json').read_text(encoding='utf-8-sig'))
assert q['simulations_passed'] and q['timing_passed']
manifest=json.loads((base/'source_hashes.json').read_text(encoding='utf-8-sig'))
for p,h in manifest.items():assert sha(Path(p))==h,p
flow=(old/'results/build.tcl').read_text(encoding='utf-8-sig')
for name in ['video_correct_ddr_top.v','ddr_word_engine.v','ddr_result_display.v']:
    source=next(Path(p) for p in manifest if Path(p).name==name)
    shutil.copyfile(source,O/name)
    before='add_design {'+source.as_posix()+'}'
    assert flow.count(before)==1
    flow=flow.replace(before,'add_design {'+(O/name).as_posix()+'}')
display=(O/'ddr_result_display.v').read_text(encoding='utf-8-sig')
start=display.index('                UI_IDLE: begin')
end=display.index('                default: ui_state<=UI_IDLE;',start)
display=display[:start]+'''                UI_IDLE: begin
                    cmd_valid_r<=0;
                    if(req_sync_ui[2]!=ui_req_seen) begin
                        ui_req_seen<=req_sync_ui[2];
                        ui_line_gen<=req_gen;
                        ui_line_row<=req_row;
                        active_base<=req_bank?BASE1:BASE0;
                        burst_index<=0;
                        cmd_addr_r<=(req_bank?BASE1:BASE0) + req_row*OUT_W;
                        cmd_valid_r<=1;
                        ui_state<=UI_CMD;
                    end
                end
                UI_CMD: begin
                    // Stable request until accepted; never overlap responses.
                    if(cmd_valid_r && cmd_ready) begin
                        cmd_valid_r<=0;
                        ui_state<=UI_RSP;
                    end
                end
                UI_RSP: begin
                    if(rsp_valid) begin
                        if(!scan_active_ui[2] || ui_line_row[0]!=scan_row_ui2[0]) begin
                            // Store the response and advertise the next read on
                            // this edge. When the arbiter retires this response,
                            // the next row beat is already requesting priority.
                            if(ui_line_row[0]) line_mem1[burst_index]<=rsp_rdata;
                            else               line_mem0[burst_index]<=rsp_rdata;
                            if(burst_index==BURSTS_PER_ROW-1) begin
                                ui_ack_toggle<=ui_req_seen;ui_state<=UI_IDLE;
                            end else begin
                                burst_index<=burst_index+1'b1;
                                cmd_addr_r<=cmd_addr_r+28'd8;
                                cmd_valid_r<=1;ui_state<=UI_CMD;
                            end
                        end else begin
                            // Retain a late beat until this parity buffer is
                            // released by scanout; no partial row acknowledgement.
                            beat_data<=rsp_rdata;ui_state<=UI_WRITE;
                        end
                    end
                end
                UI_WRITE: begin
                    if(!scan_active_ui[2] || ui_line_row[0]!=scan_row_ui2[0]) begin
                        if(ui_line_row[0]) line_mem1[burst_index]<=beat_data;
                        else               line_mem0[burst_index]<=beat_data;
                        if(burst_index==BURSTS_PER_ROW-1) begin
                            ui_ack_toggle<=ui_req_seen;ui_state<=UI_IDLE;
                        end else begin
                            burst_index<=burst_index+1'b1;
                            cmd_addr_r<=cmd_addr_r+28'd8;
                            cmd_valid_r<=1;ui_state<=UI_CMD;
                        end
                    end
                end
'''+display[end:]
(O/'ddr_result_display.v').write_text(display,encoding='utf-8')
(O/'build.tcl').write_text(flow,encoding='utf-8')
paths=[Path(m[1]) for line in flow.splitlines() if (m:=re.fullmatch(r'add_design \{(.+)\}',line))]
paths+=[R/'constr/board_ddr.fdc']
(O/'source_hashes.json').write_text(json.dumps({str(p):sha(p) for p in paths},indent=2)+'\n',encoding='utf-8')
config=json.loads((old/'results/configuration.json').read_text(encoding='utf-8-sig'))
config.update(base_release='release/ddr_camera_hires_prefetch_20261012',display_row_train=True,
    note='Only display reader transaction scheduling changed. Immediate response store/next command retains row priority; late parity collision retains its beat. Physical acceptance pending.')
(O/'configuration.json').write_text(json.dumps(config,indent=2)+'\n',encoding='utf-8')
for p in list((old/'results').glob('*.hex'))+[old/'results/fixture.json']:
    shutil.copyfile(p,O/p.name)
for p in old.glob('*.sv'):shutil.copyfile(p,D/p.name)
for p in list((old/'results').glob('tb*.sv'))+list((old/'results').glob('tb*.do')):
    content=p.read_text(encoding='utf-8-sig').replace(old.as_posix(),D.as_posix())
    (O/p.name).write_text(content,encoding='utf-8')
shutil.copyfile(old/'results/simulation_cases.json',O/'simulation_cases.json')
print('Independent row train clone prepared; sealed prefetch and baseline unchanged.')
