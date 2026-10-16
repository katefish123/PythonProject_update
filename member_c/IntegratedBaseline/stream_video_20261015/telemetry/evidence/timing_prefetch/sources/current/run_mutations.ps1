$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$source=Get-Content "$here/frame_telemetry_overlay.v" -Raw
$mutants=@(
 @{Name='glyphoffset';Text=$source.Replace('on=active_row[4-dx[3:1]]','on=active_row[4-((dx[3:1]+1''b1)&3''h7)]');Expected='full raster mismatch';Top='tb_frame_telemetry_raster'},
 @{Name='midframe';Text=$source.Replace('if(scan_start && req_sync[2]!=ack_pix)','if(req_sync[2]!=ack_pix)');Expected='snapshot applied mid-frame'},
 @{Name='noack';Text=$source.Replace(' && ack_sync[2]==req_proc','');Expected='mailbox changed without ACK'}
)
foreach($m in $mutants){
 $top=if($m.Top){$m.Top}else{'tb_frame_telemetry'}
 $out="D:/FPGA/output/c_frame_telemetry_20261015_mutant_$($m.Name)"
 New-Item -ItemType Directory -Force $out | Out-Null
 [IO.File]::WriteAllText("$out/frame_telemetry_overlay.v",$m.Text)
 Push-Location $out
 try {
 if(-not (Test-Path work)){& 'D:/softwares/modelsim/win64/vlib.exe' work}
 & 'D:/softwares/modelsim/win64/vlog.exe' -sv "$out/frame_telemetry_overlay.v" "$here/$top.sv" | Tee-Object compile.log
 if($LASTEXITCODE -ne 0){throw 'mutation compile failure'}
 & 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' "work.$top" | Tee-Object simulation.log
 if(-not (Select-String simulation.log -Pattern $m.Expected -Quiet)){throw "mutation was not caught for intended reason: $($m.Name)"}
 "PASS negative mutation caught: $($m.Name)" | Tee-Object mutation_result.txt
 }finally{Pop-Location}
}
