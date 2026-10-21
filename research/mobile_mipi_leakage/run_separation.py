"""Three-device image-domain RPCA and covariance-weighted matched subspace.

Raw captures are opened read-only. Reuses the established raster acquisition.
Outputs are statistical screen candidates, not identified MIPI common-mode.
"""
from __future__ import annotations
import os
os.environ.setdefault('OPENBLAS_NUM_THREADS', '4')
os.environ.setdefault('OMP_NUM_THREADS', '4')
import sys
sys.dont_write_bytecode = True
import argparse, csv, hashlib, json, math, time
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from vendor import legacy_benchmark as bench

ROOT = Path(__file__).resolve().parent
DATA = Path(os.environ.get('TEMPEST_DATA_ROOT', ROOT/'data')).expanduser()
bench.ROOT = DATA
OUT = ROOT / 'results'
EPS = 1e-12
LAMBDAS = (0.5, 1.0, 2.0)
RANKS = (2, 4, 8, 16, 32, 64)

def devices():
    base=bench.make_devices()
    galaxy=bench.Device(
        key='galaxy_s4_lte_171p5M', title='Galaxy S4 LTE (171.5 MHz)',
        file=Path(os.environ.get('TEMPEST_GALAXY_171_FILE', DATA/'171.5mhz_20m_55.81679m_galaxS4lte.rIs')).expanduser(),
        fs=55.816790e6, f_h=116153.4254, rows=1936, cols=1080,
        frame_period=1936*55.816790e6/116153.4254, origin_columns=0.,
        active_rows=bench.circular_indices([(61,1936),(1,36)]),
        active_cols=bench.circular_indices([(877,1080),(1,719)]))
    return base+[galaxy]

def dump(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False), encoding='utf-8')

def csvwrite(path, rows):
    if not rows: return
    with Path(path).open('w', newline='', encoding='utf-8-sig') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

def font(size=24, bold=False):
    return ImageFont.truetype(str(Path(r'C:\Windows\Fonts') / ('arialbd.ttf' if bold else 'arial.ttf')), size)

def norm(x):
    return float(np.linalg.norm(x))

def corr(a, b):
    a = np.asarray(a, dtype=np.float64).ravel().copy(); b = np.asarray(b, dtype=np.float64).ravel().copy()
    a -= a.mean(); b -= b.mean()
    return float(a @ b / max(norm(a) * norm(b), EPS))

def mad(x):
    a = np.asarray(x).ravel(); med = np.median(a)
    return float(1.4826 * np.median(np.abs(a - med)))

def moving(x, width=61):
    return np.convolve(np.pad(x, width//2, mode='reflect'), np.ones(width)/width, mode='valid')

def stripe_profile(x):
    p = np.mean(x, axis=0, dtype=np.float64)
    return p - moving(p)

def stripe_rms(x):
    return float(np.sqrt(np.mean(stripe_profile(x)**2)))

def bounds(x):
    a,b = np.percentile(x, [1,99]); return float(a), float(max(b, a+EPS))

def gray(x, limits):
    lo,hi = limits
    return Image.fromarray(np.uint8(np.clip((x-lo)/(hi-lo),0,1)*255))

def save_signed(path, x, limit):
    gray(x, (-limit,limit)).save(path)

def get_frames(device, directory, count=40):
    cached = directory/'logam_frames.npy'
    manifest = directory/'acquisition.json'
    meta = {'key':device.key, 'raw_file':str(device.file), 'raw_bytes':device.file.stat().st_size,
            'raw_mtime_ns':device.file.stat().st_mtime_ns, 'fs':device.fs, 'f_h':device.f_h,
            'full_raster':[device.rows,device.cols], 'active_shape':[device.active_rows.size,device.active_cols.size],
            'frame_period_samples':device.frame_period, 'origin_columns':device.origin_columns, 'frames':count,
            'domain':'log(abs(complex-linear-interpolated-IQ)/frame-median-AM)',
            'interpolation':'established complex linear raster interpolation, no additional image resizing',
            'frame_dc_iq_removal':True, 'active_rows_zero_based':device.active_rows.tolist(),
            'active_cols_zero_based':device.active_cols.tolist()}
    if cached.exists() and manifest.exists() and json.loads(manifest.read_text(encoding='utf-8')) == meta:
        print(device.key, 'using cached frames', flush=True)
        return np.load(cached, mmap_mode='r')
    f = np.lib.format.open_memmap(cached, mode='w+', dtype=np.float32, shape=(count,*meta['active_shape']))
    spl = device.fs/device.f_h; cell = spl/device.cols; margin = 36*cell
    ref = None; rows=[]
    with device.file.open('rb') as h:
        for k in range(count):
            start = k*device.frame_period + device.origin_columns*cell
            first=max(0,math.floor(start-margin)-2); last=math.ceil(start+device.rows*spl+margin)+2
            iq=bench.read_iq_range(h,first,last-first+1)
            iq-=np.complex64(iq.mean(dtype=np.complex128))
            raw=bench.sample_raster(iq,first,start,device.rows,device.cols,spl)
            profile=bench.column_profile(np.abs(raw))
            shift,score=(0.,1.) if ref is None else bench.estimate_applied_column_shift(profile,ref,32)
            if abs(shift)>1e-9: raw=bench.sample_raster(iq,first,start-shift*cell,device.rows,device.cols,spl)
            if ref is None: ref=bench.column_profile(np.abs(raw))
            am=bench.crop(np.abs(raw),device)
            positive=am[am>0]; scale=float(np.median(positive)); floor=float(np.percentile(positive,.1))
            f[k]=np.log(np.maximum(am,floor)/max(scale,EPS))
            rows.append({'frame':k+1,'nominal_start':start,'aligned_start':start-shift*cell,'shift_columns':shift,'alignment_score':score,'am_scale':scale,'am_floor':floor})
            if (k+1)%5==0: print(device.key, f'acquisition {k+1}/{count}', flush=True)
    f.flush(); dump(manifest,meta); csvwrite(directory/'alignment.csv',rows)
    return np.load(cached,mmap_mode='r')

def mean_frames(frames, indices):
    out=np.zeros(frames.shape[1:],dtype=np.float64)
    for i in indices: out+=frames[i]
    return (out/len(indices)).astype(np.float32)

def sigma_mean(frames, indices):
    a=mean_frames(frames,indices[::2]); b=mean_frames(frames,indices[1::2])
    # Half-sum and half-difference have equal noise variance for independent halves.
    return mad((a-b)*.5)

def stable_rpca(y, sigma, multiplier=1., tag='', maxiter=160, tol=2e-5):
    """Convex penalized stable PCP, exact block proximal updates.
    min .5||Y-L-S||F^2 + tau||L||* + tau*lambda||S||1.
    Exact SVD (no random truncation); scalar DC is restored separately.
    """
    center=float(np.mean(y)); x=np.asarray(y-center,dtype=np.float32)
    tau=float(sigma*(math.sqrt(x.shape[0])+math.sqrt(x.shape[1])))
    lam=float(multiplier/math.sqrt(max(x.shape))); threshold=tau*lam
    sparse=np.zeros_like(x); low=np.zeros_like(x); records=[]; converged=False
    scale=max(norm(x),EPS); start=time.time()
    for k in range(1,maxiter+1):
        prev_low=low; prev_sparse=sparse
        u,s,vt=np.linalg.svd(x-sparse,full_matrices=False)
        shrunk=np.maximum(s-tau,0); rank=int(np.count_nonzero(shrunk))
        low=(u[:,:rank]*shrunk[:rank])@vt[:rank]
        residual=x-low
        sparse=np.sign(residual)*np.maximum(np.abs(residual)-threshold,0)
        change=(norm(low-prev_low)+norm(sparse-prev_sparse))/scale
        error=x-low-sparse
        objective=.5*norm(error)**2+tau*float(shrunk.sum())+threshold*float(np.abs(sparse).sum(dtype=np.float64))
        records.append({'iteration':k,'rank':rank,'objective':objective,'relative_change':change})
        if k%25==0: print(f'{tag} RPCA iter={k} rank={rank} change={change:.3g}',flush=True)
        if change<tol: converged=True; break
    # Fixed-point residual verifies the final pair, beyond objective decrease.
    uu,ss,vv=np.linalg.svd(x-sparse,full_matrices=False)
    st=np.maximum(ss-tau,0); rr=np.count_nonzero(st)
    check=(uu[:,:rr]*st[:rr])@vv[:rr]
    fixed_point=norm(check-low)/scale
    info={'lambda_multiplier':multiplier,'lambda':lam,'tau':tau,'sparse_threshold':threshold,'noise_sigma_mean':sigma,
          'iterations':k,'converged':converged,'relative_change':change,'fixed_point_relative':fixed_point,
          'low_rank':rank,'sparse_fraction':float(np.mean(sparse!=0)), 'dense_residual_rms':float(np.sqrt(np.mean(error**2))),
          'objective_start':records[0]['objective'],'objective_end':objective,
          'objective_nonincreasing':bool(np.all(np.diff([r['objective'] for r in records])<=1e-4*max(objective,EPS))),
          'seconds':time.time()-start,'center':center}
    return (low+center).astype(np.float32),sparse.astype(np.float32),error.astype(np.float32),info,records

def covariance(frames, indices, mean, stride=4):
    width=frames.shape[2]; r=np.zeros((width,width),dtype=np.float64); n=0
    for i in indices:
        d=(frames[i,::stride,:]-mean[::stride,:]).astype(np.float64)
        r+=d.T@d; n+=d.shape[0]
    r/=max(n-mean[::stride].shape[0],1)
    # Fixed 10% diagonal loading; captures dense, colored temporal variability.
    level=float(np.trace(r)/width)
    return .9*r+.1*level*np.eye(width),level

def matched_operator(basis, covariance_matrix):
    """BLUE / matched subspace estimator for row y = H a + noise.
    y_hat = y R^-1 H (H.T R^-1 H)^-1 H.T.
    Returns W where y_hat=(y@W)@H.T, with exact unit response on H.
    """
    z=np.linalg.solve(covariance_matrix,basis)
    gram=basis.T@z
    weights=np.linalg.solve(gram,z.T).T
    err=norm(basis.T@weights-np.eye(basis.shape[1]))
    return weights, {'gram_condition':float(np.linalg.cond(gram)), 'unit_response_error':err}

def apply_matched(y,basis,weights,center):
    return (((y-center)@weights)@basis.T+center).astype(np.float32)

def spectrum(y):
    s=np.linalg.svd(y-np.mean(y),compute_uv=False)
    p=s*s/max(float(s@s),EPS); nz=p>0
    return s, {'effective_rank':float(np.exp(-np.sum(p[nz]*np.log(p[nz])))),
               'rank90':int(np.searchsorted(np.cumsum(p),.9)+1),'rank95':int(np.searchsorted(np.cumsum(p),.95)+1)}

def metrics(candidate,baseline,validation_output,test_raw,validation_raw,limits):
    lo,hi=limits
    a=np.clip((validation_output[::2,::2]-lo)/(hi-lo),0,1)
    b=np.clip((test_raw[::2,::2]-lo)/(hi-lo),0,1)
    base_mse=float(np.mean((validation_raw-test_raw)**2,dtype=np.float64))
    mse=float(np.mean((validation_output-test_raw)**2,dtype=np.float64))
    dy=np.diff(baseline,axis=0); cy=np.diff(candidate,axis=0)
    return {'stripe_rms':stripe_rms(candidate),'stripe_reduction_pct':100*(1-stripe_rms(candidate)/max(stripe_rms(baseline),EPS)),
            'image_correlation_to_baseline':corr(candidate,baseline),'y_edge_correlation_to_baseline':corr(cy,dy),
            'y_edge_rms_ratio':norm(cy)/max(norm(dy),EPS),
            'removed_y_edge_rms_ratio':norm(dy-cy)/max(norm(dy),EPS),
            'heldout_raw_mse':mse,'heldout_raw_mse_reduction_pct':100*(1-mse/max(base_mse,EPS)),
            'heldout_raw_ssim':float(bench.ssim_channel(a,b)),
            'output_variance_ratio':float(np.var(candidate)/max(float(np.var(baseline)),EPS))}

def comparison(path,title,panels,limits,width=340):
    h=int(width*panels[0][1].shape[0]/panels[0][1].shape[1]); top=100
    canvas=Image.new('RGB',(30+len(panels)*(width+20),h+top+45),'white'); d=ImageDraw.Draw(canvas)
    d.text((20,12),title,font=font(26,True),fill='black')
    d.text((20,48),'Same baseline intensity scale; native arrays also saved. Candidates are not source-identified.',font=font(16),fill='#444444')
    for k,(label,a) in enumerate(panels):
        x=20+k*(width+20); d.text((x,77),label,font=font(19,True),fill='black')
        canvas.paste(gray(a,limits).resize((width,h),Image.Resampling.LANCZOS).convert('RGB'),(x,top))
    canvas.save(path)

def lineplot(path,title,series,xlabel='Column',ylabel='Narrow-column profile'):
    w,h=1160,460; x0,y0,x1,y1=90,65,1120,385
    canvas=Image.new('RGB',(w,h),'white'); d=ImageDraw.Draw(canvas)
    d.text((25,15),title,font=font(24,True),fill='black')
    mn=min(float(np.min(s)) for _,s,_ in series); mx=max(float(np.max(s)) for _,s,_ in series)
    for t in range(5):
        y=y0+(y1-y0)*t/4; val=mx-(mx-mn)*t/4
        d.line((x0,y,x1,y),fill='#dddddd'); d.text((8,y-9),f'{val:.3g}',font=font(15),fill='black')
    for j,(label,s,color) in enumerate(series):
        pts=[(x0+i*(x1-x0)/max(len(s)-1,1),y1-(float(v)-mn)*(y1-y0)/max(mx-mn,EPS)) for i,v in enumerate(s)]
        d.line(pts,fill=color,width=2); d.text((x0+j*310,410),label,font=font(17),fill=color)
    canvas.save(path)

def analyze(device):
    directory=OUT/device.key; directory.mkdir(parents=True,exist_ok=True)
    frames=get_frames(device,directory)
    # Interleaved disjoint splits distribute slow capture drift across the groups.
    train=np.arange(0,40,2); val=np.arange(1,40,4); test=np.arange(3,40,4)
    va=val[::2]; vb=val[1::2]
    full=mean_frames(frames,np.arange(40)); train_mean=mean_frames(frames,train)
    val_mean=mean_frames(frames,val); test_mean=mean_frames(frames,test)
    va_mean=mean_frames(frames,va); vb_mean=mean_frames(frames,vb)
    limits=bounds(full)
    np.save(directory/'baseline_logam.npy',full); gray(full,limits).save(directory/'baseline.png')
    dump(directory/'split.json',{'train_1based':(train+1).tolist(),'validation_1based':(val+1).tolist(),
         'test_1based':(test+1).tolist(),'validation_rank_fit_1based':(va+1).tolist(),
         'validation_rank_reference_1based':(vb+1).tolist(),'display_limits':limits,
         'note':'Test frames never select rank/lambda. Test raw image remains unfiltered for evaluation.'})
    noise_full=sigma_mean(frames,np.arange(40)); noise_train=sigma_mean(frames,train); noise_val=sigma_mean(frames,val)
    all_metrics=[{'device':device.key,'method':'baseline','rank':-1,**metrics(full,full,val_mean,test_mean,val_mean,limits)}]
    outputs={'baseline':full}; info_all={}; native={'baseline':full,'validation_raw':val_mean,'test_raw':test_mean}
    # Prespecified default lambda=1. Sensitivity variants never relabeled as success.
    for mult in LAMBDAS:
        label=f'rpca_lambda{mult:g}'; print(device.key,label,flush=True)
        low,sparse,residual,info,history=stable_rpca(full,noise_full,mult,device.key+' full '+label)
        vlow,_,_,vinfo,_=stable_rpca(val_mean,noise_val,mult,device.key+' validation '+label)
        outputs[label]=low; native[label]=low; native[label+'_sparse']=sparse; native[label+'_dense_residual']=residual
        gray(low,limits).save(directory/(label+'.png'))
        save_signed(directory/(label+'_removed.png'),full-low,(limits[1]-limits[0])/2)
        save_signed(directory/(label+'_sparse.png'),sparse,(limits[1]-limits[0])/2)
        info_all[label]={'full':info,'validation':vinfo}; csvwrite(directory/(label+'_convergence.csv'),history)
        all_metrics.append({'device':device.key,'method':label,'rank':info['low_rank'],**metrics(low,full,vlow,test_mean,val_mean,limits)})
    training_low,_,_,training_info,_=stable_rpca(train_mean,noise_train,1.,device.key+' training basis')
    center=float(np.mean(training_low))
    _,sing,vt=np.linalg.svd(training_low-center,full_matrices=False)
    candidate_rank=min(training_info['low_rank'],int(np.count_nonzero(sing>max(float(sing[0])*1e-5,EPS))))
    cov,noise_level=covariance(frames,train,train_mean)
    ranks=sorted(set(min(r,candidate_rank) for r in RANKS if candidate_rank>0))
    if not ranks: raise RuntimeError('Training RPCA retained no signal subspace')
    selection=[]; operators={}; operator_infos={}
    for r in ranks:
        basis=vt[:r].T.astype(np.float64)
        weights,minfo=matched_operator(basis,cov)
        pred=apply_matched(va_mean,basis,weights,center)
        mse=float(np.mean((pred-vb_mean)**2,dtype=np.float64))
        selection.append({'rank':r,'validation_raw_mse':mse,**minfo})
        operators[r]=(basis,weights); operator_infos[r]=minfo
    selected=min(selection,key=lambda row:row['validation_raw_mse'])['rank']
    for r in ranks:
        basis,weights=operators[r]
        result=apply_matched(full,basis,weights,center)
        validation=apply_matched(val_mean,basis,weights,center)
        label=f'matched_r{r}'; outputs[label]=result; native[label]=result
        gray(result,limits).save(directory/(label+'.png'))
        save_signed(directory/(label+'_removed.png'),full-result,(limits[1]-limits[0])/2)
        all_metrics.append({'device':device.key,'method':label,'rank':r,**metrics(result,full,validation,test_mean,val_mean,limits)})
    selected_name=f'matched_r{selected}'
    matched=outputs[selected_name]; rpca=outputs['rpca_lambda1']
    # Ordinary SVD with the same rank isolates the effect of covariance weighting.
    basis,_=operators[selected]
    ordinary=((full-center)@basis)@basis.T+center
    ordinary_val=((val_mean-center)@basis)@basis.T+center
    native['unweighted_subspace_control']=ordinary.astype(np.float32)
    gray(ordinary,limits).save(directory/'unweighted_subspace_control.png')
    all_metrics.append({'device':device.key,'method':'unweighted_subspace_control','rank':selected,**metrics(ordinary,full,ordinary_val,test_mean,val_mean,limits)})
    csvwrite(directory/'metrics.csv',all_metrics); csvwrite(directory/'matched_rank_selection.csv',selection)
    s,sp=spectrum(full); sl,spl=spectrum(rpca); sr,spr=spectrum(full-rpca)
    csvwrite(directory/'spatial_singular_values.csv',[{'index':i+1,'baseline':float(s[i]),'rpca':float(sl[i]),'removed':float(sr[i])} for i in range(len(s))])
    summary={'device':device.key,'title':device.title,'native_shape':list(full.shape),'frame_count':40,
             'noise_sigma_mean':{'full':noise_full,'train':noise_train,'validation':noise_val},'rpca':info_all,
             'training_rpca':training_info,'matched_selected_rank':selected,'matched_rank_selection':selection,
             'covariance_diagonal_loading':.1,'covariance_mean_variance':noise_level,
             'baseline_spatial_spectrum':sp,'rpca_spatial_spectrum':spl,'removed_spatial_spectrum':spr,
             'primary_methods':['rpca_lambda1',selected_name],'metrics':all_metrics}
    dump(directory/'summary.json',summary)
    np.savez_compressed(directory/'components.npz',**native,training_low=training_low,signal_basis=operators[selected][0],matched_weights=operators[selected][1],noise_covariance=cov)
    comparison(directory/'comparison.png',device.title+' | P=40 | log-AM', [('Original',full),('Stable RPCA (lambda=1)',rpca),(f'Matched subspace (r={selected})',matched)],limits)
    comparison(directory/'rpca_sensitivity.png',device.title+' | RPCA sensitivity',[(f'lambda x {m:g}',outputs[f'rpca_lambda{m:g}']) for m in LAMBDAS],limits)
    comparison(directory/'matched_sensitivity.png',device.title+' | Matched subspace sensitivity',[(f'rank {r}',outputs[f'matched_r{r}']) for r in ranks],limits,width=240)
    removed_limit=(limits[1]-limits[0])/2
    comparison(directory/'removed_components.png',device.title+' | Removed components', [('Original - RPCA',full-rpca),('Original - matched',full-matched)],(-removed_limit,removed_limit))
    lineplot(directory/'column_profiles.png',device.title+' | narrow-column profiles', [('Original',stripe_profile(full),'#222222'),('RPCA',stripe_profile(rpca),'#1664c0'),('Matched',stripe_profile(matched),'#d23b35')])
    print('DONE',device.key,'selected_rank',selected,flush=True)
    return summary

def selftest():
    rng=np.random.default_rng(123)
    m,n,r=140,100,3
    a=np.linalg.qr(rng.normal(size=(m,r)))[0]; b=np.linalg.qr(rng.normal(size=(n,r)))[0]
    truth=(a*np.array([30.,25.,20.]))@b.T
    sparse=np.zeros((m,n)); mask=rng.random((m,n))<.04; sparse[mask]=rng.normal(0,2,mask.sum())
    y=truth+sparse+rng.normal(0,.015,(m,n))
    low,sp,res,info,_=stable_rpca(y,.015,1.,'synthetic',maxiter=250,tol=1e-6)
    relative=norm(low-truth)/norm(truth)
    assert relative<.08, relative
    assert norm(y-low-sp-res)/norm(y)<1e-6
    assert info['objective_nonincreasing']
    h=np.linalg.qr(rng.normal(size=(15,4)))[0]; z=rng.normal(size=(15,15)); cov=z@z.T+np.eye(15)
    w,wi=matched_operator(h,cov)
    clean=rng.normal(size=(25,4))@h.T
    assert norm(clean@w@h.T-clean)/norm(clean)<1e-10
    # BLUE has no higher total noise variance than the unweighted projection.
    assert np.trace(w.T@cov@w)<=np.trace(h.T@cov@h)+1e-10
    d={'rpca_relative_error_to_known_truth':relative,'rpca_converged':info['converged'],
       'rpca_objective_nonincreasing':info['objective_nonincreasing'],'matched_unit_response_error':wi['unit_response_error']}
    dump(OUT/'numerical_selftest.json',d); print('NUMERICAL SELFTEST',d,flush=True)

def main():
    p=argparse.ArgumentParser(); p.add_argument('--device',default='all'); p.add_argument('--selftest',action='store_true'); args=p.parse_args()
    OUT.mkdir(exist_ok=True)
    if args.selftest: selftest(); return
    for d in devices():
        if args.device=='all' or d.key==args.device: analyze(d)
    all_summaries=[json.loads(p.read_text(encoding='utf-8')) for p in OUT.glob('*/summary.json')]
    csvwrite(OUT/'all_metrics.csv',[r for s in all_summaries for r in s['metrics']])
    dump(OUT/'provenance.json',{'analysis_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'legacy_sha256':hashlib.sha256((ROOT/'vendor/legacy_benchmark.py').read_bytes()).hexdigest(),
          'numpy_version':np.__version__,'python_version':sys.version,'seed_synthetic':123,
          'source_legacy_file':str(DATA/'benchmark_three_device_gatefree_median_v1.py'),
          'references':['https://arxiv.org/abs/1001.2363','https://www.mssc.mu.edu/~daniel/mscs6960/spring2010/ScharfFriedlanderTSP94.pdf']})

if __name__=='__main__': main()
