"""Physical board is off by user report; historical temperature is not current."""
from pathlib import Path
from datetime import datetime,timezone
import json
R=Path(__file__).resolve().parents[1]
hw=R/'results/hardware_20261009'
now=datetime.now(timezone.utc).isoformat()
record={'recorded_at_utc':now,'user_report':'Board center/heatsink region and two nearby black chips felt hot; exact location and measured temperature unknown. User confirmed board power off.',
    'board_power_reported_off':True,'reason':'User observed heat, cooling before more board testing',
    'current_chip_or_surface_temperature_measured':False,'current_temperature_c':None,
    'historical_adc_temperature_c':54.4,'historical_adc_temperature_date':'2026-10-09',
    'historical_adc_temperature_is_current':False,
    'working_image_before_poweroff':'release/ddr_camera_hires_rowtrain_20261013/video_correct_ddr_top.sbit',
    'new_coordinate_queue_programmed':False,'host_simulation_uses_board':False,
    'hardware_testing_on_hold':True,'software_work_continues':True,
    'status_source':'Logos2 UG040005 table3-14',
    'status_definition_url':'https://www.pangomicro.com/en/uploads/69345021_1729131793.pdf',
    'status_bit27_label':'over_temp','status_bit29_label':'prcfg_over',
    'status_effective_polarity_and_adc_threshold_verified':False,
    'wrong_family_guide_not_applicable':'UG020005 Logos bit29/27 definitions are not those of PG2L100H Logos2.',
    'scope':'No current sensor read, no power/heat measurement, no diagnosis of damage. Local hardware manual supports FPGA with2 DDR3 chips; location inferred from earlier photo.'}
(hw/'thermal_hold_20261013.json').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
for p in [R/'docs/hardware_20261009.json',hw/'rowtrain_camera_state_20261013.json']:
    state=json.loads(p.read_text(encoding='utf-8-sig'))
    state.update(board_power_reported_off=True,board_poweroff_reason='Cooling after user-reported heat',
        current_program_resident=False,hardware_testing_waiting_for_cooldown=True,current_temperature_c=None,
        historical_temperature_note='54.4°C was an ADC observation on2026-10-09; not a current thermal reading.',
        current_boot_optical_picture_verified=False,current_boot_ddr_bist_observed=False,
        latest_thermal_evidence='results/hardware_20261009/thermal_hold_20261013.json',
        pending='Continue isolated coordinate lookahead simulation/final timing on PC. Board remains powered off; further board tests await cooling and a reliable temperature/thermal check. Working release retained.')
    p.write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('User power-off/thermal hold recorded. Software-only checks continue; no board actions.')
