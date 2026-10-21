"""Presentation controls for the iPhone 6 P=488 reconstruction attempt."""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT=Path(__file__).resolve().parent
FOLDER=ROOT/'tf_results'/'iphone6'

def font(n,bold=False):
    return ImageFont.truetype(str(Path(r'C:\Windows\Fonts')/('arialbd.ttf' if bold else 'arial.ttf')),n)

def scale(a,lo=None,hi=None):
    if lo is None: lo,hi=np.percentile(a,[1,99])
    return np.uint8(255*np.clip((a-lo)/max(hi-lo,1e-12),0,1)),float(lo),float(hi)

raw=np.asarray(Image.open(FOLDER/'reconstruction_p488.png').convert('L'),dtype=np.float32)
shown,lo,hi=scale(raw)
median=np.asarray(Image.fromarray(shown).filter(ImageFilter.MedianFilter(3)),dtype=np.uint8)
row=raw.mean(axis=1,keepdims=True); col=raw.mean(axis=0,keepdims=True)
corrected=raw-row-col+raw.mean(); corrected_shown,_,_=scale(corrected)
corrected_median=np.asarray(Image.fromarray(corrected_shown).filter(ImageFilter.MedianFilter(3)),dtype=np.uint8)

panels=[('P=488 full-band AM',shown),('3x3 median control',median),('Row/column-template removal + median',corrected_median)]
w=340; h=int(w*raw.shape[0]/raw.shape[1]); canvas=Image.new('RGB',(40+3*(w+25),h+135),'white'); d=ImageDraw.Draw(canvas)
d.text((20,14),'iPhone 6 reconstruction attempt: 238 MHz, configured 60 MHz IQ bandwidth',font=font(25,True),fill='black')
d.text((20,50),'488 frames | fH 112805.083 Hz | 1880 x 750 output | no recognizable UI detected',font=font(18),fill='#333333')
d.text((20,78),'Independent-half: image corr 0.0244, edge corr -0.00034, column profile 0.5045, row profile 0.9035',font=font(16),fill='#333333')
for i,(label,a) in enumerate(panels):
    x=20+i*(w+25); d.text((x,108),label,font=font(17,True),fill='black')
    im=Image.fromarray(a).resize((w,h),Image.Resampling.LANCZOS); canvas.paste(im.convert('RGB'),(x,135))
canvas.save(FOLDER/'iphone6_reconstruction_attempt.png')
Image.fromarray(median).save(FOLDER/'reconstruction_p488_median3.png')
Image.fromarray(corrected_median).save(FOLDER/'reconstruction_p488_profile_removed_median3.png')
