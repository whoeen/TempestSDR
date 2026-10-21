"""Frame stripe diagnostics and explicitly conditional chamber candidates."""
from pathlib import Path
import json, csv, math
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'chamber_plan'; OUT.mkdir(exist_ok=True)
DATA=[('lgx2','LG X2 (2019)',720,1440,88679.652541,90.6306,344.8,60,136.565510),
      ('galaxy_s4_lte_171p5M','Galaxy S4 LTE',1080,1920,116153.4254,139.53,171.5,20,55.816790),
      ('iphone6s','iPhone 6s',750,1334,112613.234,112613.234*750/1e6,311,20,55.054870)]

def save_csv(name,rows):
    with (OUT/name).open('w',encoding='utf-8-sig',newline='') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

def corr(a,b):
    a=a-a.mean(); b=b-b.mean(); return float(a@b/max(np.linalg.norm(a)*np.linalg.norm(b),1e-12))

def font(n,bold=False):
    return ImageFont.truetype(str(Path(r'C:\Windows\Fonts')/('arialbd.ttf' if bold else 'arial.ttf')),n)

def stripes(key,title):
    frames=np.load(ROOT/'results'/key/'logam_frames.npy',mmap_mode='r')
    profile=np.asarray([np.mean(f,axis=0,dtype=np.float64) for f in frames])
    hp=np.array([p-np.convolve(np.pad(p,30,mode='reflect'),np.ones(61)/61,mode='valid') for p in profile])
    mean=hp.mean(axis=0); residual=hp-mean
    cs=np.array([corr(p,mean) for p in hp])
    shifts=np.array([np.arange(-6,7)[np.argmax([corr(np.roll(p,s),mean) for s in range(-6,7)])] for p in hp])
    order=np.argsort(np.abs(mean))[::-1]; peaks=[]
    for p in order:
        if all(abs(int(p)-q)>5 for q in peaks): peaks.append(int(p))
        if len(peaks)==12: break
    peak_rows=[]
    for p in sorted(peaks):
        sign=np.sign(mean[p]); vals=hp[:,p]*sign
        peak_rows.append({'column_0based':p,'mean_signed_amplitude':float(mean[p]),
                          'std_amplitude':float(np.std(hp[:,p])),
                          'fraction_same_sign':float(np.mean(vals>0)),
                          'fraction_above_half_mean_amplitude':float(np.mean(vals>.5*abs(mean[p]))),
                          'min_amplitude_in_mean_sign':float(vals.min()),'max_amplitude_in_mean_sign':float(vals.max())})
    # This is profile decomposition energy, NOT an identified physical driver fraction.
    summary={'device':key,'frames':len(frames),'mean_profile_correlation_min':float(cs.min()),
             'mean_profile_correlation_median':float(np.median(cs)),
             'profile_static_energy_fraction':float(np.sum(mean**2)/np.mean(np.sum(hp**2,axis=1))),
             'residual_profile_rms_over_mean_profile_rms':float(np.sqrt(np.mean(residual**2)/np.mean(mean**2))),
             'best_integer_alignment_shift_histogram':{str(int(s)):int(np.sum(shifts==s)) for s in np.unique(shifts)},
             'strong_peak_min_same_sign_fraction':min(p['fraction_same_sign'] for p in peak_rows),
             'strong_peak_min_half_mean_fraction':min(p['fraction_above_half_mean_amplitude'] for p in peak_rows),
             'caveat':'All statistics use row-averaged normalized log-AM; locations are after existing raster registration. Fixed screen column structure can contribute.'}
    save_csv(key+'_peaks.csv',peak_rows)
    save_csv(key+'_frame_profile_metrics.csv',[{'frame':i+1,'correlation_to_mean':float(cs[i]),'best_shift_columns':int(shifts[i]),
                                            'profile_rms':float(np.sqrt(np.mean(hp[i]**2)))} for i in range(40)])
    lim=float(np.percentile(np.abs(hp),99)); rlim=float(np.percentile(np.abs(residual),99))
    def heat(a,scale):
        z=np.clip(a/scale,-1,1); rgb=np.empty((*a.shape,3),dtype=np.uint8)
        rgb[:,:,0]=255*(1-np.maximum(-z,0)); rgb[:,:,1]=255*(1-np.abs(z)); rgb[:,:,2]=255*(1-np.maximum(z,0))
        return Image.fromarray(rgb).resize((1100,280),Image.Resampling.NEAREST)
    canvas=Image.new('RGB',(1210,765),'white'); d=ImageDraw.Draw(canvas)
    d.text((30,14),title+' | vertical-stripe positions across 40 frames',font=font(25,True),fill='black')
    d.text((30,53),'Each row = one frame, each column = one raster column. Red/blue = positive/negative profile.',font=font(17),fill='black')
    d.text((85,85),'A. Narrow-column profile (row-averaged image)',font=font(20,True),fill='black')
    canvas.paste(heat(hp,lim),(85,118));d.text((20,120),'F1',font=font(16),fill='black');d.text((14,375),'F40',font=font(16),fill='black')
    d.text((85,420),'B. Same profiles minus their 40-frame mean (separate, amplified scale)',font=font(20,True),fill='black')
    canvas.paste(heat(residual,rlim),(85,454));d.text((20,456),'F1',font=font(16),fill='black');d.text((14,710),'F40',font=font(16),fill='black')
    canvas.save(OUT/(key+'_frame_stripes.png'))
    np.savez_compressed(OUT/(key+'_profiles.npz'),profile=hp,mean_profile=mean,variation=residual)
    return summary

def main():
    summaries=[]; bitrate=[]; windows=[]; bandwidth=[]; geometry=[]
    for key,title,w,h,fh,fp,fc,bw,fs in DATA:
        summaries.append(stripes(key,title))
        payload=w*h*60*24/1e9
        bitrate.append({'device':title,'width':w,'height':h,'refresh_assumed_Hz':60,'bpp_assumed':24,
            'active_pixel_rate_Mpix_s':w*h*60/1e6,'aggregate_active_payload_Gbps':payload,
            'min_lane_rate_4lanes_Mbps':payload*1000/4,'min_DDR_clock_4lanes_MHz':payload*1000/8,
            'min_lane_rate_2lanes_Mbps':payload*1000/2,'min_DDR_clock_2lanes_MHz':payload*1000/4,
            'prior_RF_center_MHz':fc,'prior_nominal_file_BW_MHz':bw,'saved_IQ_rate_MSps':fs,
            'measured_raster_line_Hz':fh})
        for lanes in [4,2]:
            low=payload*1000/(2*lanes); high=low*1.5
            for harmonic in [1,2,3,4,5]:
                windows.append({'device':title,'assumed_lanes':lanes,'assumed_alpha_min':1.,'assumed_alpha_max':1.5,
                   'harmonic_index':harmonic,'search_start_MHz':low*harmonic,'search_end_MHz':high*harmonic,
                   'status':'conditional planning scenario, not measured clock or guaranteed emission',
                   'within_USRP2940_part_of_window':bool(low*harmonic<2200)})
        geometry.append({'device':title,'apparent_pixel_timing_Mpix_s':fp,
             'assumed_4lane_RGB888_serial_Mbps':6*fp,'assumed_DDR_clock_MHz':3*fp,
             'third_harmonic_MHz':9*fp,'fifth_harmonic_MHz':15*fp,
             'status':'strong additional assumptions: raster timing equals packet serialization pixel timing; not measured lane rate'})
        for B in [5,10,20,40,60,80,100]:
            bandwidth.append({'device':title,'total_centered_RF_BW_MHz':B,'one_sided_envelope_band_MHz':B/2,
              'apparent_pixel_rate_Mpix_s':fp,'finest_sinusoid_period_pixels_linear_AM_model':2*fp/B,
              'sinusoid_half_period_pixels':fp/B,
              'caveat':'Centered double-sideband linear-envelope approximation; filter transition band and SNR worsen this scale; no hard universal image resolution claim'})
    save_csv('bitrate_and_prior_capture.csv',bitrate);save_csv('conditional_clock_search_windows.csv',windows)
    save_csv('conditional_geometry_clock.csv',geometry);save_csv('bandwidth_detail_scale.csv',bandwidth)
    hardware_windows=[]
    for row in windows:
        start=max(700.,row['search_start_MHz']); stop=min(2200.,row['search_end_MHz'])
        if start < stop:
            hardware_windows.append({**row,'RF_window_clipped_start_MHz':start,
                'RF_window_clipped_end_MHz':stop,
                'hardware_assumption':'Confirmed HyperLOG 7060; USRP-2940 receiver is conditional; LNA/BPF coverage not independently verified'})
    save_csv('hardware_aware_candidates.csv',hardware_windows)
    center_limits=[{'full_RF_BW_MHz':B,'min_center_MHz':700+B/2,'max_center_MHz':2200-B/2,
                    'condition':'HyperLOG 7060 plus USRP-2940; receiver must support this instantaneous BW; extra filter transition margin may be needed'}
                   for B in [20,40,60,80,100]]
    save_csv('receiver_center_limits.csv',center_limits)
    edge=[{'t20_80_ps':tr,'linear_t0_100_ps':tr/.6,'envelope_asymptote_corner_GHz':.6/(math.pi*tr*1e-12)/1e9} for tr in [50,100,200,300]]
    save_csv('edge_corner_examples.csv',edge)
    result={'stripe_diagnostics':summaries,'bitrate':bitrate,'conditional_geometry_clock':geometry,'edge_examples':edge,
            'equipment':{'antenna':'Aaronia HyperLOG 7060','antenna_rated_MHz':[700,6000],
                         'LNA':'Aaronia preamp, exact model unknown',
                         'BPF':'User reports tunable BPF units for three frequency bands; passband and loss unmeasured',
                         'receiver_assumption':'USRP-2940 from prior project record; not confirmed for today',
                         'conditional_RF_intersection_MHz':[700,2200]},
            'hardware_aware_candidates':hardware_windows,'receiver_center_limits':center_limits,
            'ES_filter':{'code':'external/es-coursework/make_bandwidth_sweep.py',
                         'label_5MHz_one_sided_stop_MHz':5,'flat_passband_one_sided_MHz':3,'total_zero_to_zero_support_MHz':10,
                         'total_flat_passband_MHz':6,'pixel_rate_MHz':148.4999704174879,
                         'pixel_period_at_3MHz':148.4999704174879/3,'pixel_period_at_5MHz':148.4999704174879/5}}
    (OUT/'calculations.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(result,ensure_ascii=False,indent=2))

if __name__=='__main__':main()
