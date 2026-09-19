import os
from PIL import Image

def crop_and_pad_horizontal(img_path, target_width=1800, padding_pct=0.08):
    im = Image.open(img_path).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        return im
    cropped = im.crop(bbox)
    cw, ch = cropped.size
    
    # Calculate aspect ratio
    # We want padding around the logo so height and bottom text/curves never get cut off
    pad_y = int(ch * padding_pct)
    pad_x = int(cw * padding_pct * 0.5)
    
    total_w = cw + pad_x * 2
    total_h = ch + pad_y * 2
    
    canvas = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    canvas.paste(cropped, (pad_x, pad_y), cropped)
    
    # Scale up to high-res target width (e.g. 1800px)
    scale = target_width / total_w
    target_height = int(total_h * scale)
    
    resized = canvas.resize((target_width, target_height), Image.Resampling.LANCZOS)
    return resized

def create_square_icon(img_path, target_size=1024, safe_scale=0.82):
    im = Image.open(img_path).convert("RGBA")
    bbox = im.getbbox()
    if not bbox:
        return im
    cropped = im.crop(bbox)
    cw, ch = cropped.size
    
    # Fit into target_size * safe_scale
    max_dim = max(cw, ch)
    scale = (target_size * safe_scale) / max_dim
    new_w = int(cw * scale)
    new_h = int(ch * scale)
    
    resized = cropped.resize((new_w, new_h), Image.Resampling.LANCZOS)
    
    canvas = Image.new("RGBA", (target_size, target_size), (0, 0, 0, 0))
    pos_x = (target_size - new_w) // 2
    pos_y = (target_size - new_h) // 2
    canvas.paste(resized, (pos_x, pos_y), resized)
    return canvas

def main():
    logos_dir = "logos"
    web_assets_dir = os.path.join(logos_dir, "web_assets")
    os.makedirs(web_assets_dir, exist_ok=True)
    
    # 1. Full logos
    full_logo = crop_and_pad_horizontal(os.path.join(logos_dir, "AppNexa-03.png"))
    white_logo = crop_and_pad_horizontal(os.path.join(logos_dir, "AppNexa white-03.png"))
    black_logo = crop_and_pad_horizontal(os.path.join(logos_dir, "AppNexa black-03.png"))
    tagline_logo = crop_and_pad_horizontal(os.path.join(logos_dir, "AppNexa-01.png"))
    
    # Save master web assets
    full_logo.save(os.path.join(web_assets_dir, "appnexa-logo-full.png"), "PNG")
    white_logo.save(os.path.join(web_assets_dir, "appnexa-logo-white.png"), "PNG")
    black_logo.save(os.path.join(web_assets_dir, "appnexa-logo-black.png"), "PNG")
    tagline_logo.save(os.path.join(web_assets_dir, "appnexa-logo-tagline.png"), "PNG")
    
    # 2. Master AppNexa icons
    icon_master = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=1024, safe_scale=0.85)
    icon_white = create_square_icon(os.path.join(logos_dir, "AppNexa white-02.png"), target_size=1024, safe_scale=0.85)
    icon_black = create_square_icon(os.path.join(logos_dir, "AppNexa black-02.png"), target_size=1024, safe_scale=0.85)
    
    icon_master.save(os.path.join(web_assets_dir, "appnexa-icon.png"), "PNG")
    icon_white.save(os.path.join(web_assets_dir, "appnexa-icon-white.png"), "PNG")
    icon_black.save(os.path.join(web_assets_dir, "appnexa-icon-black.png"), "PNG")
    
    # 3. PWA Icons & Favicons
    icon_512 = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=512, safe_scale=0.85)
    icon_192 = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=192, safe_scale=0.85)
    maskable_512 = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=512, safe_scale=0.72)
    maskable_192 = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=192, safe_scale=0.72)
    apple_touch = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=180, safe_scale=0.85)
    
    fav_48 = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=48, safe_scale=0.92)
    fav_32 = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=32, safe_scale=0.92)
    fav_16 = create_square_icon(os.path.join(logos_dir, "AppNexa-02.png"), target_size=16, safe_scale=0.92)
    
    icon_512.save(os.path.join(web_assets_dir, "Icon-512.png"), "PNG")
    icon_192.save(os.path.join(web_assets_dir, "Icon-192.png"), "PNG")
    maskable_512.save(os.path.join(web_assets_dir, "Icon-maskable-512.png"), "PNG")
    maskable_192.save(os.path.join(web_assets_dir, "Icon-maskable-192.png"), "PNG")
    apple_touch.save(os.path.join(web_assets_dir, "apple-touch-icon.png"), "PNG")
    
    fav_48.save(os.path.join(web_assets_dir, "favicon-48x48.png"), "PNG")
    fav_32.save(os.path.join(web_assets_dir, "favicon-32x32.png"), "PNG")
    fav_16.save(os.path.join(web_assets_dir, "favicon-16x16.png"), "PNG")
    fav_32.save(os.path.join(web_assets_dir, "favicon.png"), "PNG")
    
    # Save .ico multi-size
    fav_32.save(os.path.join(web_assets_dir, "favicon.ico"), format="ICO", sizes=[(16, 16), (32, 32), (48, 48)])
    
    # Copy across project
    destinations = [
        "landing_page/assets/images",
        "admin_panel/assets/images",
        "review_page/assets/images",
    ]
    
    all_png_files = [
        "appnexa-logo-full.png", "appnexa-logo-white.png", "appnexa-logo-black.png", "appnexa-logo-tagline.png",
        "appnexa-icon.png", "appnexa-icon-white.png", "appnexa-icon-black.png",
        "Icon-512.png", "Icon-192.png", "Icon-maskable-512.png", "Icon-maskable-192.png", "apple-touch-icon.png",
        "favicon-48x48.png", "favicon-32x32.png", "favicon-16x16.png", "favicon.png"
    ]
    
    for dst in destinations:
        os.makedirs(dst, exist_ok=True)
        for fname in all_png_files:
            src_f = os.path.join(web_assets_dir, fname)
            dst_f = os.path.join(dst, fname)
            if os.path.exists(src_f):
                with open(src_f, 'rb') as sf, open(dst_f, 'wb') as df:
                    df.write(sf.read())
        # Copy ico
        with open(os.path.join(web_assets_dir, "favicon.ico"), 'rb') as sf, open(os.path.join(dst, "favicon.ico"), 'wb') as df:
            df.write(sf.read())

    # Root favicons
    for root_dir in ["landing_page", "review_page"]:
        for f in ["favicon.png", "favicon.ico", "apple-touch-icon.png"]:
            src_f = os.path.join(web_assets_dir, f)
            dst_f = os.path.join(root_dir, f)
            with open(src_f, 'rb') as sf, open(dst_f, 'wb') as df:
                df.write(sf.read())
                
    # admin_panel web icons
    admin_web = "admin_panel/web"
    admin_icons = "admin_panel/web/icons"
    os.makedirs(admin_icons, exist_ok=True)
    with open(os.path.join(web_assets_dir, "favicon.png"), 'rb') as sf, open(os.path.join(admin_web, "favicon.png"), 'wb') as df:
        df.write(sf.read())
    with open(os.path.join(web_assets_dir, "apple-touch-icon.png"), 'rb') as sf, open(os.path.join(admin_web, "apple-touch-icon.png"), 'wb') as df:
        df.write(sf.read())
    for f in ["Icon-512.png", "Icon-192.png", "Icon-maskable-512.png", "Icon-maskable-192.png"]:
        with open(os.path.join(web_assets_dir, f), 'rb') as sf, open(os.path.join(admin_icons, f), 'wb') as df:
            df.write(sf.read())

    print("Successfully generated all uncropped, padded logos and icons!")

if __name__ == '__main__':
    main()
