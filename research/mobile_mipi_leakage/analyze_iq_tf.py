"""Row-aligned and within-line STFT views for three smartphone IQ captures.

The row-scale map uses one complete raster line per FFT.  The column-scale
map uses a 64-raster-cell Hann window, 8-cell hop, and averages power across
rows and frames.  A single cell has only about one stored complex sample and
cannot support a frequency-resolved STFT.
"""
from __future__ import annotations
import csv, json, math, os, sys
from dataclasses import dataclass
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'coherent_results'/'tf_big_endian'
DATA=Path(os.environ.get('TEMPEST_DATA_ROOT', ROOT/'data')).expanduser()

@dataclass(frozen=True)
class Capture:
    key:str; title:str; file:Path; fc:float; bandwidth:float; fs:float
    fh:float; rows:int; cols:int; image:Path

CAPTURES=(
    Capture('iphone6','iPhone 6',DATA/'238M_60M_124.08571M_topleft_iphone6.rIs',238e6,60e6,124.085710e6,112805.083,1880,1100,ROOT/'coherent_results'/'three_devices_big_endian'/'iphone6'/'final_arrays.npz'),
    Capture('lgx2','LG X2 (2019)',DATA/'LGX22019_344.8M_60M_136.56551M.rIs',344.8e6,60e6,136.565510e6,88679.652541,1478,1022,ROOT/'coherent_results'/'three_devices_big_endian'/'lgx2'/'final_arrays.npz'),
    Capture('galaxy_s4_lte','Galaxy S4 LTE',Path(os.environ.get('TEMPEST_GALAXY_171_FILE',DATA/'171.5mhz_20m_55.81679m_galaxS4lte.rIs')).expanduser(),171.5e6,20e6,55.816790e6,116153.4254,1936,1080,ROOT/'coherent_results'/'three_devices_big_endian'/'galaxy_s4_lte'/'final_arrays.npz'),
)

def font(size=20,bold=False):
    candidates=[Path(r'C:\Windows\Fonts')/('arialbd.ttf' if bold else 'arial.ttf'),Path('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' if bold else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')]
    for p in candidates:
        if p.is_file(): return ImageFont.truetype(str(p),size)
    return ImageFont.load_default()

def nextpow2(n): return 1 << max(0,int(n-1)).bit_length()

def read_iq(path,start,count):
    with path.open('rb') as f:
        f.seek(4*start); raw=np.fromfile(f,dtype='>i2',count=2*count)
    if raw.size!=2*count: raise RuntimeError(f'short read: {path} {raw.size//2}/{count}')
    z=raw.reshape(-1,2)
    return z[:,0].astype(np.float32)+1j*z[:,1].astype(np.float32)

def turbo(x):
    # Compact polynomial-free blue/cyan/yellow/red map.
    stops=np.array([[10,20,70],[20,85,170],[15,165,190],[80,205,120],[235,215,45],[240,95,20],[120,5,15]],dtype=float)
    u=np.clip(x,0,1)*(len(stops)-1); k=np.minimum(u.astype(int),len(stops)-2); a=(u-k)[...,None]
    return np.uint8((1-a)*stops[k]+a*stops[k+1])

def db_scale(p,span=45):
    d=10*np.log10(np.maximum(p,np.finfo(float).tiny)); top=np.percentile(d,99.5)
    return np.clip((d-(top-span))/span,0,1),float(top-span),float(top)

def crop_band(power,freq,cap):
    mask=np.abs(freq)<=cap.bandwidth/2
    return power[...,mask],freq[mask]

def row_stft(cap,frames=6):
    spl=cap.fs/cap.fh; nwin=max(16,int(round(spl))); nfft=nextpow2(nwin)
    window=np.hanning(nwin).astype(np.float32); acc=np.zeros((cap.rows,nfft),dtype=np.float64)
    frame_samples=int(math.ceil(cap.rows*spl))+nwin+4
    for frame in range(frames):
        start=int(round(frame*cap.rows*spl)); iq=read_iq(cap.file,start,frame_samples)
        iq-=iq.mean(dtype=np.complex128)
        starts=np.floor(np.arange(cap.rows)*spl).astype(int)
        for first in range(0,cap.rows,128):
            s=starts[first:first+128,None]+np.arange(nwin)[None,:]
            z=iq[s]*window
            acc[first:first+len(s)]+=np.abs(np.fft.fftshift(np.fft.fft(z,nfft,axis=1),axes=1))**2
    freq=np.fft.fftshift(np.fft.fftfreq(nfft,1/cap.fs))
    power,freq=crop_band(acc/frames,freq,cap)
    return power,freq,{'window_samples':nwin,'nfft':nfft,'true_resolution_hz':cap.fs/nwin,'fft_bin_spacing_hz':cap.fs/nfft,'frames_averaged':frames}

def column_stft(cap,frames=4,row_stride=4,cells=64,hop_cells=8):
    spl=cap.fs/cap.fh; sample_per_cell=spl/cap.cols
    nwin=max(16,int(round(cells*sample_per_cell))); hop=max(1,int(round(hop_cells*sample_per_cell))); nfft=nextpow2(nwin)
    window=np.hanning(nwin).astype(np.float32); centres=np.arange(nwin//2,int(math.floor(spl))-nwin//2+1,hop)
    acc=np.zeros((len(centres),nfft),dtype=np.float64); count=0
    frame_samples=int(math.ceil(cap.rows*spl))+nwin+4
    for frame in range(frames):
        start=int(round(frame*cap.rows*spl)); iq=read_iq(cap.file,start,frame_samples)
        iq-=iq.mean(dtype=np.complex128)
        for row in range(0,cap.rows,row_stride):
            line=int(math.floor(row*spl)); begins=line+centres-nwin//2
            index=begins[:,None]+np.arange(nwin)[None,:]
            z=iq[index]*window
            acc+=np.abs(np.fft.fftshift(np.fft.fft(z,nfft,axis=1),axes=1))**2; count+=1
    freq=np.fft.fftshift(np.fft.fftfreq(nfft,1/cap.fs))
    power,freq=crop_band(acc/max(count,1),freq,cap)
    position=centres/spl*cap.cols
    return power,freq,position,{'window_cells':cells,'hop_cells':hop_cells,'window_samples':nwin,'hop_samples':hop,'nfft':nfft,
        'true_resolution_hz':cap.fs/nwin,'fft_bin_spacing_hz':cap.fs/nfft,'frames_averaged':frames,'row_stride':row_stride,'line_spectra_averaged':count}

def heatmap(power,freq,xvalues,width,height,xlabel,title,fc):
    scaled,low,high=db_scale(power)
    img=Image.fromarray(turbo(scaled.T[::-1])).resize((width,height),Image.Resampling.BILINEAR)
    left,top,right,bottom=92,74,28,70
    canvas=Image.new('RGB',(left+width+right,top+height+bottom),'white'); canvas.paste(img,(left,top)); d=ImageDraw.Draw(canvas)
    d.text((18,15),title,font=font(23,True),fill='black')
    d.rectangle((left,top,left+width,top+height),outline='black',width=1)
    for j in range(5):
        y=top+height*j/4; f=(fc+freq[-1]-(freq[-1]-freq[0])*j/4)/1e6
        d.line((left-5,y,left,y),fill='black'); d.text((4,int(y-9)),f'{f:.1f}',font=font(14),fill='black')
    for j in range(5):
        x=left+width*j/4; value=xvalues[0]+(xvalues[-1]-xvalues[0])*j/4
        d.line((x,top+height,x,top+height+5),fill='black'); label=f'{value:.0f}'
        d.text((int(x-15),top+height+9),label,font=font(14),fill='black')
    d.text((left+width//2-75,top+height+40),xlabel,font=font(16),fill='black')
    d.text((4,top+height+42),f'{low:.1f}..{high:.1f} dB',font=font(13),fill='#444444')
    return canvas

def fit_image(path,height=590,width=390):
    if path.suffix.lower()=='.npz':
        with np.load(path) as data:
            amplitude=np.asarray(data['amplitude'])
            rows=np.asarray(data['active_rows'],dtype=int)
            cols=np.asarray(data['active_cols'],dtype=int)
        a=np.log1p(amplitude[np.ix_(rows,cols)]).astype(float)
        lo,hi=np.percentile(a,[1,99])
    else:
        im=Image.open(path).convert('L'); a=np.asarray(im,dtype=float); lo,hi=np.percentile(a,[1,99])
    a=np.uint8(255*np.clip((a-lo)/max(hi-lo,1),0,1)); im=Image.fromarray(a)
    im.thumbnail((width,height),Image.Resampling.LANCZOS)
    canvas=Image.new('RGB',(width,height),'white'); canvas.paste(im.convert('RGB'),((width-im.width)//2,(height-im.height)//2)); return canvas

def montage(cap,row_png,col_png):
    recon=fit_image(cap.image,590,390); row=Image.open(row_png).convert('RGB'); col=Image.open(col_png).convert('RGB')
    row.thumbnail((650,590),Image.Resampling.LANCZOS); col.thumbnail((650,590),Image.Resampling.LANCZOS)
    w=50+390+25+row.width+25+col.width+30; h=700
    out=Image.new('RGB',(w,h),'white'); d=ImageDraw.Draw(out)
    d.text((25,13),f'{cap.title}: reconstructed image and raw-IQ time-frequency views',font=font(27,True),fill='black')
    row_us=1e6/cap.fh; cell_ns=1e9/(cap.fh*cap.cols)
    d.text((25,51),f'Configured IQ BW {cap.bandwidth/1e6:.1f} MHz | stored {cap.fs/1e6:.6f} MS/s | row {row_us:.4f} us | raster cell {cell_ns:.3f} ns',font=font(17),fill='#333333')
    y=100; out.paste(recon,(25,y)); out.paste(row,(440,y)); out.paste(col,(465+row.width,y))
    d.text((25,80),'P=24 fractional-resampled big-endian AM average',font=font(17,True),fill='black')
    out.save(OUT/cap.key/'tf_montage.png')

def analyze(cap):
    folder=OUT/cap.key; folder.mkdir(parents=True,exist_ok=True)
    rp,rf,ri=row_stft(cap); cp,cf,pos,ci=column_stft(cap)
    row_img=heatmap(rp,rf,np.arange(cap.rows),600,510,'Raster row index','One-row STFT, power averaged over 6 frames',cap.fc)
    col_img=heatmap(cp,cf,pos,600,510,'Raster column position','64-cell STFT, power averaged over rows and 4 frames',cap.fc)
    row_path=folder/'row_scale_stft.png'; col_path=folder/'column_scale_stft.png'; row_img.save(row_path); col_img.save(col_path)
    row_time=1/cap.fh; cell_time=row_time/cap.cols
    def modulation(power,freq):
        db=10*np.log10(np.maximum(power,np.finfo(float).tiny))
        band=10*np.log10(np.maximum(power.sum(axis=1),np.finfo(float).tiny))
        spread=np.percentile(db,95,axis=0)-np.percentile(db,5,axis=0)
        indices=np.argsort(spread)[-5:][::-1]
        return {'band_power_position_p95_minus_p05_db':float(np.percentile(band,95)-np.percentile(band,5)),
                'largest_frequency_local_position_spreads':[{'baseband_hz':float(freq[i]),'rf_hz':float(cap.fc+freq[i]),'p95_minus_p05_db':float(spread[i])} for i in indices]}
    meta={'device':cap.title,'raw_file':str(cap.file),'center_frequency_hz':cap.fc,'configured_complex_bandwidth_hz':cap.bandwidth,
          'stored_complex_sample_rate_sps':cap.fs,'raster_rows':cap.rows,'raster_columns':cap.cols,'row_time_s':row_time,'raster_cell_time_s':cell_time,
          'stored_samples_per_row':cap.fs*row_time,'stored_samples_per_raster_cell':cap.fs*cell_time,
          'row_stft':{**ri,'modulation':modulation(rp,rf)},'column_stft':{**ci,'modulation':modulation(cp,cf)},
          'interpretation':'Column position is equivalent line phase. A physical screen column recurs once per row and is not one contiguous frame-time interval.',
          'iq_format':'interleaved big-endian signed int16 I,Q, headerless',
          'bandwidth_note':'Configured receive bandwidth comes from capture metadata. Stored sample rate is not asserted as usable analog bandwidth.'}
    (folder/'tf_metadata.json').write_text(json.dumps(meta,indent=2),encoding='utf-8')
    np.savez_compressed(folder/'tf_arrays.npz',row_power=rp.astype(np.float32),row_frequency_hz=rf.astype(np.float64),column_power=cp.astype(np.float32),column_frequency_hz=cf.astype(np.float64),column_position=pos.astype(np.float64))
    montage(cap,row_path,col_path); print(cap.key,meta,flush=True); return meta

def main():
    OUT.mkdir(exist_ok=True); summaries=[analyze(c) for c in CAPTURES]
    with (OUT/'bandwidth_timing.csv').open('w',newline='',encoding='utf-8-sig') as f:
        keys=['device','center_frequency_hz','configured_complex_bandwidth_hz','stored_complex_sample_rate_sps','raster_rows','raster_columns','row_time_s','raster_cell_time_s','stored_samples_per_row','stored_samples_per_raster_cell']
        w=csv.DictWriter(f,fieldnames=keys); w.writeheader(); w.writerows([{k:d[k] for k in keys} for d in summaries])
    (OUT/'summary.json').write_text(json.dumps(summaries,indent=2),encoding='utf-8')

if __name__=='__main__': main()
