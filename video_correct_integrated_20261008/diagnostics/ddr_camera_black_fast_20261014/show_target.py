"""Display the independent black-marker target; Esc closes, F11 toggles fullscreen."""
from pathlib import Path
import tkinter as tk
from PIL import Image, ImageTk

D = Path(__file__).resolve().parent
source = Image.open(D / "results/camera_target_1920x1080.png").convert("RGB")
window = tk.Tk()
window.title("黑色角标测试图")
window.configure(bg="#b4b4b4")
window.attributes("-fullscreen", True)
canvas = tk.Canvas(window, bg="#b4b4b4", highlightthickness=0)
canvas.pack(fill="both", expand=True)
pending = None


def render():
    global pending
    pending = None
    width, height = canvas.winfo_width(), canvas.winfo_height()
    scale = min(width/source.width, height/source.height)
    canvas.photo = ImageTk.PhotoImage(source.resize((max(1, round(source.width*scale)), max(1, round(source.height*scale))), Image.Resampling.NEAREST))
    canvas.delete("all")
    canvas.create_image(width//2, height//2, image=canvas.photo, anchor="center")


def resize(event):
    global pending
    if pending is not None:
        window.after_cancel(pending)
    pending = window.after(50, render)


canvas.bind("<Configure>", resize)
window.bind("<Escape>", lambda event: window.destroy())
window.bind("<F11>", lambda event: window.attributes("-fullscreen", not window.attributes("-fullscreen")))
window.mainloop()
