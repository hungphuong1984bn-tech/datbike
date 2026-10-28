import sys
import os
import shutil
import numpy as np
from PIL import Image

def apply_icon_option(opt):
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    target_dir = os.path.join(base_dir, "assets", "icon")
    
    file_map = {
        "1": "white_option1_bike.png",
        "2": "white_option2_glyph.png",
        "3": "white_option3_solid.png"
    }
    
    filename = file_map.get(str(opt), "white_option2_glyph.png")
    src_path = os.path.join(target_dir, filename)
    if not os.path.exists(src_path):
        return
        
    src_img = Image.open(src_path).convert("RGBA")
    src_img.convert("RGB").save(os.path.join(target_dir, "icon.png"), quality=95)
    
    arr = np.array(src_img)
    is_bg = (arr[:, :, 0] > 245) & (arr[:, :, 1] > 245) & (arr[:, :, 2] > 245)
    arr[:, :, 3] = np.where(is_bg, 0, 255).astype(np.uint8)
    
    fg_trans = Image.fromarray(arr)
    fg_canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    inner = int(1024 * 0.70)
    scaled_fg = fg_trans.resize((inner, inner), Image.LANCZOS)
    fg_canvas.alpha_composite(scaled_fg, ((1024 - inner)//2, (1024 - inner)//2))
    fg_canvas.save(os.path.join(target_dir, "icon_foreground.png"))

if __name__ == "__main__":
    choice = sys.argv[1] if len(sys.argv) > 1 else "2"
    apply_icon_option(choice)
