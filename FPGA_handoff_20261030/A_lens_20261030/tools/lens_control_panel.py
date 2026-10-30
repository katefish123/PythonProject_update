"""Local host control panel. Nothing opens or connects when this module is imported."""
from pathlib import Path
import datetime,json,math,queue,re,subprocess,sys,threading

ROOT=Path(__file__).resolve().parents[1]

def command_for(angle,zoom,port,output,offline):
    angle=float(angle);zoom=float(zoom)
    if not math.isfinite(angle) or not -180<=angle<=180:raise ValueError('角度应在-180到180度之间')
    if not math.isfinite(zoom) or not 1<=zoom<=4:raise ValueError('放大倍数应在1到4之间')
    if not offline and not re.fullmatch(r'COM[1-9][0-9]*',port.strip(),re.IGNORECASE):raise ValueError('请先选择板卡串口')
    argv=[sys.executable,str(ROOT/'tools/send_lens_angle.py'),'--angle-deg',str(angle),'--zoom',str(zoom),
          '--sequence',str(int(datetime.datetime.now().timestamp()*1000)&65535),'--output',str(output)]
    if offline:argv+=['--dry-run']
    else:argv+=['--port',port.strip().upper()]
    return argv

def main():
    import tkinter as tk
    from tkinter import ttk
    window=tk.Tk();window.title('FPGA镜头矫正 · 角度控制');window.geometry('570x405');window.minsize(530,390)
    style=ttk.Style();style.configure('TLabel',font=('Microsoft YaHei UI',10));style.configure('TButton',font=('Microsoft YaHei UI',10))
    box=ttk.Frame(window,padding=22);box.pack(fill='both',expand=True)
    ttk.Label(box,text='镜头矫正与角度控制',font=('Microsoft YaHei UI',16,'bold')).grid(row=0,column=0,columnspan=3,sticky='w',pady=(0,12))
    ttk.Label(box,text='下载匹配工程后，打开相机实时输出，再应用角度。',wraplength=500).grid(row=1,column=0,columnspan=3,sticky='w',pady=(0,14))
    port=tk.StringVar();angle=tk.StringVar(value='0');zoom=tk.StringVar(value='1')
    ttk.Label(box,text='板卡串口').grid(row=2,column=0,sticky='w')
    ports=ttk.Combobox(box,textvariable=port,width=23,state='readonly');ports.grid(row=2,column=1,sticky='ew',padx=10)
    def refresh_ports():
        try:
            deps='C:/D/FPGA/A_software_20261024/deps'
            if deps not in sys.path:sys.path.insert(0,deps)
            from serial.tools.list_ports import comports
            devices=list(comports());values=[d.device for d in devices]
            ports['values']=values
            preferred=next((d.device for d in devices if 'CP210' in (d.description or '').upper()),None)
            if port.get() not in values:port.set(preferred or (values[0] if values else ''))
            status.set('请选择板卡串口。' if values else '未找到串口，请检查板卡USB连接。')
        except Exception as e:status.set('串口列表读取失败：'+str(e))
    refresh=ttk.Button(box,text='刷新',command=refresh_ports);refresh.grid(row=2,column=2)
    ttk.Label(box,text='旋转角度').grid(row=3,column=0,sticky='w',pady=12)
    spin=ttk.Spinbox(box,from_=-180,to=180,increment=1,textvariable=angle,width=15);spin.grid(row=3,column=1,sticky='w',padx=10)
    ttk.Label(box,text='正数顺时针').grid(row=3,column=2,sticky='w')
    quick=ttk.Frame(box);quick.grid(row=4,column=1,columnspan=2,sticky='w',padx=10)
    quick_buttons=[]
    for value in [0,-12,12,90]:
        b=ttk.Button(quick,text=f'{value}°',width=6,command=lambda v=value:angle.set(str(v)));b.pack(side='left',padx=(0,6));quick_buttons.append(b)
    ttk.Label(box,text='放大倍数').grid(row=5,column=0,sticky='w',pady=12)
    scale=ttk.Spinbox(box,from_=1,to=4,increment=.1,textvariable=zoom,width=15);scale.grid(row=5,column=1,sticky='w',padx=10)
    ttk.Label(box,text='自动裁剪会适当缩小视野，角度切换在新帧开始时生效。',wraplength=500).grid(row=6,column=0,columnspan=3,sticky='w',pady=(0,12))
    status=tk.StringVar(value='尚未连接；角度参数未发送。');events=queue.Queue();busy=False
    def set_busy(value):
        nonlocal busy
        busy=value
        for control in [apply,preview,refresh,spin,scale,*quick_buttons]:control.configure(state='disabled' if value else 'normal')
        ports.configure(state='disabled' if value else 'readonly')
    def launch(offline):
        if busy:return
        folder=ROOT/'host_sessions';folder.mkdir(exist_ok=True)
        output=folder/('angle_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'.json')
        try:argv=command_for(angle.get(),zoom.get(),port.get(),output,offline)
        except (ValueError,TypeError) as e:status.set(str(e));return
        set_busy(True);status.set('正在离线检查参数…' if offline else '正在发送，等待新帧确认…')
        def work():
            env=dict(__import__('os').environ);env['PYTHONIOENCODING']='utf-8'
            try:
                p=subprocess.run(argv,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf-8',errors='replace',creationflags=subprocess.CREATE_NO_WINDOW,timeout=45)
                output.with_suffix('.log').write_text(p.stdout,encoding='utf-8')
                if p.returncode:events.put(('error','未完成：'+p.stdout.strip().splitlines()[-1]));return
                result=json.loads(output.read_text(encoding='utf-8'));factor=result['applied_zoom']
                events.put(('ok',('离线检查通过' if offline else '新帧已锁定参数')+f'；角度{result["angle_deg_clockwise_display"]:g}°，实际放大{factor:.3f}倍。'))
            except Exception as e:events.put(('error','未完成：'+str(e)))
        threading.Thread(target=work,daemon=True).start()
    actions=ttk.Frame(box);actions.grid(row=7,column=0,columnspan=3,sticky='w')
    apply=ttk.Button(actions,text='应用到板卡',command=lambda:launch(False));apply.pack(side='left',padx=(0,10))
    preview=ttk.Button(actions,text='仅做离线检查',command=lambda:launch(True));preview.pack(side='left')
    ttk.Label(box,textvariable=status,wraplength=500).grid(row=8,column=0,columnspan=3,sticky='w',pady=(14,0))
    def poll():
        try:
            while True:
                _,message=events.get_nowait();status.set(message);set_busy(False)
        except queue.Empty:pass
        window.after(100,poll)
    box.columnconfigure(1,weight=1);poll();window.mainloop()

if __name__=='__main__':
    if '--self-check' in sys.argv:
        dry=command_for('12','1','',ROOT/'verification/panel_dry.json',True)
        live=command_for('-12','1.2','COM15',ROOT/'verification/panel_live.json',False)
        assert '--dry-run' in dry and '--port' not in dry and '--port' in live and '--dry-run' not in live
        for args in [('nan',1,'COM1'),(181,1,'COM1'),(0,0,'COM1'),(0,1,'')]:
            try:command_for(*args,ROOT/'unused.json',False)
            except ValueError:pass
            else:raise AssertionError('Invalid UI command accepted')
        print('HOST_PANEL_SELF_CHECK_PASS no_window_opened=1 no_serial_accessed=1')
    else:main()
