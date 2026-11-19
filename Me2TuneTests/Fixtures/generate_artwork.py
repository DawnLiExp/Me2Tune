"""Regenerate the small cover-import fixtures on macOS with Pillow and ffmpeg."""
from pathlib import Path
import subprocess

from PIL import Image

root = Path(__file__).parent
artwork = root / "Artwork"
artwork.mkdir(exist_ok=True)
first = Image.new("RGB", (48, 32), (220, 40, 24))
first.paste((24, 190, 40), (0, 0, 12, 32))
second = Image.new("RGB", first.size, (24, 40, 220))
first.save(artwork / "still.bmp")
first.save(artwork / "still.avif")
subprocess.run(["sips", "-s", "format", "heic", artwork / "still.bmp", "--out", artwork / "still.heic"], check=True)

transparent = first.convert("RGBA")
transparent.paste((0, 0, 0, 0), (0, 0, 12, 32))
transparent.save(artwork / "transparent.webp", lossless=True)
animation = dict(save_all=True, append_images=[second], duration=200, loop=0)
first.save(artwork / "animated.gif", **animation)
first.save(artwork / "animated.webp", lossless=True, **animation)
first.save(artwork / "animated.apng", format="PNG", **animation)
first.save(artwork / "pages.tiff", save_all=True, append_images=[second], tiffinfo={274: 6}, compression="tiff_lzw")

subprocess.run([
    "ffmpeg", "-v", "error", "-y", "-i", root / "Tags/id3v4.mp3", "-ignore_loop", "1",
    "-i", artwork / "animated.gif", "-map", "0:a:0", "-map", "1:v:0", "-c", "copy",
    "-frames:v", "1", "-disposition:v", "attached_pic", "-metadata:s:v", "comment=Cover (front)",
    root / "Tags/legacy-gif.mp3"
], check=True)
