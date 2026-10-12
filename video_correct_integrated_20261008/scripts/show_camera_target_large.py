"""Local static target viewer for the real camera; no browser, server, or capture."""
from pathlib import Path
import tkinter as tk
from PIL import Image, ImageTk

root_path=Path(__file__).resolve().parents[1]
source=Image.open(root_path/'results/camera_target_large_20261011/source_large_markers_640x480.png').convert('RGB')
window=tk.Tk()
window.title('相机测试图片（大角标、静态）')
window.configure(bg='#707070')
window.attributes('-fullscreen',True)
canvas=tk.Canvas(window,bg='#707070',highlightthickness=0)
canvas.pack(fill='both',expand=True)
pending=None

def render():
    global pending
    pending=None
    width,height=canvas.winfo_width(),canvas.winfo_height()
    scale=min(width/source.width,height/source.height)
    size=(max(1,round(source.width*scale)),max(1,round(source.height*scale)))
    # Rendering scale only; the original test asset is never written.
    canvas.photo=ImageTk.PhotoImage(source.resize(size,Image.Resampling.NEAREST))
    canvas.delete('all')
    canvas.create_image(width//2,height//2,image=canvas.photo,anchor='center')

def resize(event):
    global pending
    if pending is not None:window.after_cancel(pending)
    pending=window.after(50,render)

canvas.bind('<Configure>',resize)
window.bind('<Escape>',lambda event:window.destroy())
window.bind('<F11>',lambda event:window.attributes('-fullscreen',not window.attributes('-fullscreen')))
window.mainloop()
