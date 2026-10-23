from PIL import Image,ImageDraw
from pathlib import Path
p=Path("C:/Users/leechanghoon/Documents/Codex/2026-09-21/snr-svd/tempestsdr-cloud/research/mobile_mipi_leakage/matlab_agentic_lab/results/iphone_recovery_20261023/archive_P008")
keys=['book34_238','bottom_middle_238','topleft_238','book93_238','response_308','response_312']
a=Image.new('RGB',(900,1060),'white');d=ImageDraw.Draw(a)
for i,k in enumerate(keys):
 im=Image.open(p/k/'P008_am.png').convert('RGB');im.thumbnail((280,480))
 x=(i%3)*300+10;y=(i//3)*525+35;a.paste(im,(x,y));d.text((x,y-22),k+' / AM P8',fill='black')
a.save(p/'archive_survey_am.png')
