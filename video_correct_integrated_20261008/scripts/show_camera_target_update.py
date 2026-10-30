"""Separate real-camera optical update counter. User launches manually; Esc exits."""
from pathlib import Path
from datetime import datetime
import tkinter as tk
import time,csv
from PIL import Image,ImageTk
from camera_update_counter import make_target,R
O=R/'results/camera_update_counter_20261013'
O.mkdir(exist_ok=True)
stamp=datetime.now().strftime('%Y%m%d_%H%M%S')
log=(O/f'actual_stimulus_{stamp}.csv').open('x',newline='',encoding='utf-8')
writer=csv.writer(log)
writer.writerow(['monotonic_elapsed_seconds','pc_wall_unix_seconds','counter','gray'])
window=tk.Tk()
window.title('相机更新速度测试图（10Hz变化计数；Esc退出）')
window.configure(bg='#707070')
window.attributes('-fullscreen',True)
canvas=tk.Canvas(window,bg='#707070',highlightthickness=0)
canvas.pack(fill='both',expand=True)
started=time.monotonic()
last_value=None
photo=None
item=None
last_size=None
def render():
    global last_value,photo,item,last_size
    elapsed=time.monotonic()-started
    value=int(elapsed*10)&4095
    size=(canvas.winfo_width(),canvas.winfo_height())
    if min(size)>1 and (value!=last_value or size!=last_size):
        image=make_target(value)
        scale=min(size[0]/640,size[1]/480)
        image=image.resize((round(640*scale),round(480*scale)),Image.Resampling.NEAREST)
        photo=ImageTk.PhotoImage(image)
        if item is None:item=canvas.create_image(size[0]//2,size[1]//2,image=photo,anchor='center')
        else:
            canvas.itemconfigure(item,image=photo)
            canvas.coords(item,size[0]//2,size[1]//2)
        writer.writerow([f'{elapsed:.6f}',f'{time.time():.6f}',value,value^(value>>1)])
        if value%20==0:log.flush()
        last_value=value
        last_size=size
    window.after(35,render)
def close(event=None):
    log.flush();log.close();window.destroy()
window.bind('<Escape>',close)
window.bind('<F11>',lambda event:window.attributes('-fullscreen',not window.attributes('-fullscreen')))
window.protocol('WM_DELETE_WINDOW',close)
window.after(50,render)
window.mainloop()
