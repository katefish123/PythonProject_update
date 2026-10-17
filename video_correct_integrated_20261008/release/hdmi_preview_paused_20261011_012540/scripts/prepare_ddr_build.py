"""Generate a DDR board build from reviewed video IO and generated PHY rules."""
from pathlib import Path
import re,sys,xml.etree.ElementTree as ET
R=Path(__file__).resolve().parents[1]
CHECK_ONLY='--check' in sys.argv
DDR_TOP_FILES=('frame_processor.v','frame_session.v','video_correct_ddr_core.v','video_correct_ddr_top.v')
HDMI_FILES=('hdmi_config.v','iic_dri.v','ms7200_ctl.v','ms7210_ctl.v')
DIAGNOSTIC_TOP_PREFIXES=('hdmi_link_probe','hdmi_link_i2c_probe','video_correct_ddr_status')
I=R/'rtl/memory/ddr3_ip'
base=(R/'constr/board_bram.fdc').read_text(encoding='utf-8')
# Retain the already verified video pins and video IO delays, but combine DDR
# clock domains in a single group with their own generated PHY timing rules.
base='\n'.join(s for s in base.splitlines() if not s.startswith('set_clock_groups'))
example=(I/'pnr/ddr_test.fdc').read_text(encoding='utf-8-sig')
# Include every bank used by DQ OR CA. CA also uses its quarter-rate divider.
# Pango derives bank indices in CA-first order; validate that relationship.
idf=ET.parse(I/'ddr3_ip.idf')
params={n.findtext('name'):n.findtext('value') for n in idf.iter('param')}
if not params:
    params={n.attrib.get('name'):n.findtext('value') for n in idf.iter() if n.attrib.get('name') and n.find('value') is not None}
active_dq_banks={int(params[f'DQ{i}_BANK_NUM']) for i in range(9) if params.get(f'DQ{i}_EN')=='true'}
if not active_dq_banks:raise RuntimeError('No enabled DDR DQ banks found in IDF')
if params['BANK0']!=params['BANK_CA']:raise RuntimeError('DDR bank order must match the Pango CA-first derivation')
for i in range(9):
    if params.get(f'DQ{i}_EN')=='true' and params[f'BANK{params[f"DQ{i}_BANK_NUM"]}']!=params[f'BANK_DQG_{i}']:
        raise RuntimeError(f'DDR DQ{i} bank index does not match its physical bank')
active_phy_banks=active_dq_banks|{0}
phy=[];pins=set()
for line in example.splitlines():
    used_clocks=re.findall(r'phy_dq_sysclk_(\d+)',line)
    if any(int(index) not in active_phy_banks for index in used_clocks):continue
    gates=re.findall(r'ddrphy_ioclk_gate\[(\d+)\]',line)
    if any(int(index) not in active_phy_banks for index in gates):continue
    if line.startswith('define_attribute {p:mem_'):
        if 'PAP_IO_UNUSED' not in line:
            phy.append(line)
            m=re.match(r'define_attribute \{p:(.+?)\} \{PAP_IO_LOC\} \{(.+?)\}',line)
            if m:pins.add((m[1],m[2]))
    elif line.startswith('define_attribute {i:') or line.startswith(('create_generated_clock','set_multicycle_path','set_clock_uncertainty')):
        phy.append(line.replace('I_ips_ddr_top','memory_ip').replace('ref_clk_p','ddr_ref_clk_p'))
if len(pins)!=71:raise RuntimeError(f'DDR pin count {len(pins)}')
ref=['create_clock -name ref_clk -period 8.000 [get_ports {ddr_ref_clk_p}]']
for port,pin in [('ddr_ref_clk_p','N3'),('ddr_ref_clk_n','N2')]:
    for attr,value in [('PAP_IO_DIRECTION','INPUT'),('PAP_IO_LOC',pin),('PAP_IO_VCCIO','1.5'),('PAP_IO_STANDARD','SSTL15D_I')]:
        ref.append(f'define_attribute {{p:{port}}} {{{attr}}} {{{value}}}')
# Preserve the vendor's calibration/reference/serial-PHY clock isolation. The
# data-path quarter clocks remain RELATED to the controller clock, with the
# vendor's generated-edge, 2-cycle and 0.4ns uncertainty rules above.
data_clocks=['ddrphy_sysclk']+[f'phy_dq_sysclk_{n}' for n in sorted(active_phy_banks)]
groups=['# Clock isolation follows the generated Pango HMIC_S example.',
 'set_clock_groups -asynchronous -group [get_clocks {sys_clk_27m}] -group [get_clocks {rx_pixel}] -group [get_clocks {cfg_clock}] -group [get_clocks {pixel_clock tx_pixel}] -group [get_clocks {ref_clk}] -group [get_clocks {rst_clk}] -group [get_clocks {phy_dq_clk_0}] -group [get_clocks {phy_dq_clk_1}] -group [get_clocks {'+' '.join(data_clocks)+'}]']
fdc='\n'.join([base,'# DDR pins: verified board LOC, active IO; no example unused ports.',*ref,*phy,*groups])+'\n'
if not CHECK_ONLY:(R/'constr/board_ddr.fdc').write_text(fdc,encoding='utf-8')
sources=[p for p in sorted((R/'vendor/b/rtl').glob('*.v')) if p.name!='marker_detector.v']+[R/'rtl/algo/marker_detector.v']
for directory in ['common','video','memory']:
    sources+=sorted((R/f'rtl/{directory}').glob('*.v'))
sources += [R/'rtl/hdmi'/name for name in HDMI_FILES]
sources += [R/'rtl/top'/name for name in DDR_TOP_FILES]
sources += [R/'vendor/c_current/01_design_code/video_timing_vtc.v',R/'vendor/c_current/01_design_code/hdmi_vs_recover.v']
sources += [R/f'vendor/c_current/01_design_code/ip/{n}/{n}.v' for n in ['video_pll_27m_148m5','config_pll_27m_10m']]
sources += [I/'ddr3_ip.v',I/'ddr3_ip_ddrphy_top.v']
sources += sorted(p for p in (I/'rtl').rglob('*') if p.suffix in ['.v','.vp'])
flow=['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
flow += [f'add_design {{{p.as_posix()}}}' for p in sources]
flow += [f'add_constraint -logic -fdc {{{(R/"constr/board_ddr.fdc").as_posix()}}}',
 'compile -top_module video_correct_ddr_top','synthesize -ads','dev_map','pnr','report_timing','gen_bit_stream']
if CHECK_ONLY:
    missing=[p for p in sources if not p.is_file()]
    if missing:raise FileNotFoundError(missing[0])
    if any(p.name.startswith(DIAGNOSTIC_TOP_PREFIXES) for p in sources):raise RuntimeError('Diagnostic top leaked into the DDR release source list')
    for name in DDR_TOP_FILES:
        if name not in [p.name for p in sources]:raise RuntimeError(f'Missing required DDR source {name}')
    pds_file=R/'pds/build_board_ddr.tcl'
    if not pds_file.is_file():raise FileNotFoundError(pds_file)
    pds_text=pds_file.read_text(encoding='utf-8')
    if 'compile -top_module video_correct_ddr_top' not in pds_text or 'rtl/top/video_correct_ddr_top.v' not in pds_text or 'rtl/top/video_correct_ddr_core.v' not in pds_text:
        raise RuntimeError('Existing DDR PDS flow does not retain the main DDR top/core')
    if 'hdmi_link_probe_top.v' in pds_text or 'hdmi_link_i2c_probe_top.v' in pds_text or 'rtl/hdmi/diag/' in pds_text:
        raise RuntimeError('Existing DDR PDS flow contains a diagnostic-only dependency')
    print(f'DDR source check PASS: {len(sources)} files, explicit top/HDMI allowlists, main top/core/BIST/DDR retained; no generated outputs changed')
else:
    (R/'pds/build_board_ddr.tcl').write_text('\n'.join(flow)+'\n',encoding='utf-8')
print(f'DDR build: {len(sources)} HDL files, 71 DDR pins + N3/N2 reference, no UNUSED DDR ports')
