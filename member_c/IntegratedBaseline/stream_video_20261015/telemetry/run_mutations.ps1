$ErrorActionPreference='Stop'
$here=$PSScriptRoot
$source=Get-Content "$here/frame_telemetry_overlay.v" -Raw
$mutants=@(
 @{Name='midframe';Text=$source.Replace('if(scan_start && req_sync[2]!=ack_pix)','if(req_sync[2]!=ack_pix)');Expected='snapshot applied mid-frame'},
 @{Name='noack';Text=$source.Replace(' && ack_sync[2]==req_proc','');Expected='mailbox changed without ACK'}
)
foreach($m in $mutants){
 $out="D:/FPGA/output/c_frame_telemetry_20261015_mutant_$($m.Name)"
 New-Item -ItemType Directory -Force $out | Out-Null
 [IO.File]::WriteAllText("$out/frame_telemetry_overlay.v",$m.Text)
 Push-Location $out
 try {
 & 'D:/softwares/modelsim/win64/vlib.exe' work
 & 'D:/softwares/modelsim/win64/vlog.exe' -sv "$out/frame_telemetry_overlay.v" "$here/tb_frame_telemetry.sv" | Tee-Object compile.log
 if($LASTEXITCODE -ne 0){throw 'mutation compile failure'}
 & 'D:/softwares/modelsim/win64/vsim.exe' -c -do 'run -all; quit -code 0' work.tb_frame_telemetry | Tee-Object simulation.log
 if(-not (Select-String simulation.log -Pattern $m.Expected -Quiet)){throw "mutation was not caught for intended reason: $($m.Name)"}
 "PASS negative mutation caught: $($m.Name)" | Tee-Object mutation_result.txt
 }finally{Pop-Location}
}
