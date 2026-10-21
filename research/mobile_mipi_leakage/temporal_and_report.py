"""Independent temporal rank-one matched subspace control and result report."""
import sys
sys.dont_write_bytecode=True
from pathlib import Path
import json, html, hashlib
import numpy as np
from PIL import Image, ImageDraw
import run_separation as s

def temporal_fit(frames, indices):
    # Learn weights at sparse pixel positions, evaluate held-out pixels separately.
    # R is total covariance: signal variance * 11.T does not change ideal MVDR
    # weights under the response constraint 1.T w = 1. Finite-sample cross terms
    # can still bias adaptive weights; 10% diagonal loading limits this.
    x=np.stack([frames[i,::4,::4].ravel() for i in indices]).astype(np.float64)
    x-=x.mean(axis=1,keepdims=True)
    r=x@x.T/max(x.shape[1]-1,1)
    r=.9*r+.1*np.trace(r)/len(indices)*np.eye(len(indices))
    one=np.ones(len(indices)); w=np.linalg.solve(r,one); w/=one@w
    out=np.zeros(frames.shape[1:],dtype=np.float64)
    for weight,i in zip(w,indices): out+=weight*frames[i]
    return out.astype(np.float32),w,{'weight_sum':float(w.sum()),'min_weight':float(w.min()),
        'max_weight':float(w.max()),'white_noise_equivalent_frames':float(1/(w@w)),
        'constraint_error':float(abs(w.sum()-1)),'covariance_condition':float(np.linalg.cond(r))}

def process(directory):
    summary=json.loads((directory/'summary.json').read_text(encoding='utf-8'))
    splits=json.loads((directory/'split.json').read_text(encoding='utf-8'))
    f=np.load(directory/'logam_frames.npy',mmap_mode='r')
    full=np.load(directory/'baseline_logam.npy')
    val=np.asarray(splits['validation_1based'])-1; test=np.asarray(splits['test_1based'])-1
    valraw=s.mean_frames(f,val); testraw=s.mean_frames(f,test)
    out,w,info=temporal_fit(f,np.arange(40)); vout,vw,vinfo=temporal_fit(f,val)
    limits=splits['display_limits']
    row={'device':summary['device'],'method':'temporal_matched_rank1','rank':1,
         **s.metrics(out,full,vout,testraw,valraw,limits)}
    # Pixel grid used for covariance is excluded here; no resmoothing or resizing.
    mask=np.ones(full.shape,dtype=bool); mask[::4,::4]=False
    reference_mse=np.mean((valraw[mask]-testraw[mask])**2,dtype=np.float64)
    output_mse=np.mean((vout[mask]-testraw[mask])**2,dtype=np.float64)
    info['excluded_covariance_grid_raw_mse_reduction_pct']=float(100*(1-output_mse/reference_mse))
    summary['metrics']=[r for r in summary['metrics'] if r['method']!='temporal_matched_rank1']+[row]
    summary['temporal_matched']={'full':info,'validation':vinfo,'signature':'ones(P), same normalized log-AM image on every frame',
        'covariance':'total spatial sample covariance at [::4,::4] with 10% diagonal loading',
        'limitation':'Any frame-invariant artifact has the same signature and passes with unit response.'}
    s.dump(directory/'summary.json',summary); s.csvwrite(directory/'metrics.csv',summary['metrics'])
    s.csvwrite(directory/'temporal_weights.csv',[{'frame':i+1,'weight':float(z)} for i,z in enumerate(w)])
    np.save(directory/'temporal_matched_rank1.npy',out)
    s.gray(out,limits).save(directory/'temporal_matched_rank1.png')
    s.save_signed(directory/'temporal_matched_removed.png',full-out,(limits[1]-limits[0])/2)
    with np.load(directory/'components.npz') as comp:
        rpca=comp['rpca_lambda1']; spatial=comp[f'matched_r{summary["matched_selected_rank"]}']
        s.comparison(directory/'comparison_all.png',summary['title']+' | 40 frames',
                     [('Original',full),('RPCA: spatial low rank',rpca),('Matched: spatial',spatial),('Matched: repeated frame',out)],limits,width=310)
        s.lineplot(directory/'column_profiles_all.png',summary['title']+' | narrow-column profiles',
                   [('Original',s.stripe_profile(full),'#222222'),('RPCA',s.stripe_profile(rpca),'#1664c0'),('Temporal matched',s.stripe_profile(out),'#d23b35')])
    # Fixed viewports emphasize existing glyphs; crop positions are not tuned by method.
    h,ww=full.shape
    crop=(slice(int(.4*h),int(.7*h)),slice(int(.1*ww),int(.9*ww)))
    s.comparison(directory/'detail_crop.png',summary['title']+' | identical middle-screen crop',
                 [('Original',full[crop]),('RPCA',rpca[crop]),('Spatial matched',spatial[crop]),('Temporal matched',out[crop])],limits,width=400)
    print(summary['device'],'temporal',row['stripe_reduction_pct'],info,flush=True)
    return summary

def write_reports(summaries):
    main_order=['lgx2','galaxy_s4_lte_171p5M','iphone6s']
    by_key={x['device']:x for x in summaries}
    main=[by_key[k] for k in main_order if k in by_key]
    rows=[]
    for d in main:
        sel=f'matched_r{d["matched_selected_rank"]}'
        for r in d['metrics']:
            if r['method'] in ['baseline','rpca_lambda1',sel,'temporal_matched_rank1']: rows.append(r)
    s.csvwrite(s.OUT/'primary_metrics.csv',rows)
    s.csvwrite(s.OUT/'all_metrics.csv',[r for d in summaries for r in d['metrics']])
    lines=['# 3기종 RPCA / matched subspace 실험', '',
           '실행일: 2026-09-21. LG X2(2019), Galaxy S4 LTE, iPhone 6s. 원본 .rIs는 읽기 전용으로 사용했다.', '',
           '## 관찰 결과', '',
           '이번에 적용한 공간 RPCA와 데이터에서 학습한 spatial matched subspace는 화면 의존 공통모드 방사만 선택적으로 분리하지 못했다. LG X2에서 고정 세로선은 대부분 남고 키패드/글자가 약해졌다. iPhone에서는 큰 버튼은 남지만 작은 글자와 경계가 손실됐다. 이는 이 데이터와 아래 가정에서 얻은 결과이며, 알려진 순수 공통모드 기준 신호를 사용하는 matched subspace 전체의 실패를 뜻하지 않는다.', '',
           'Temporal matched는 반복되는 정적 화면에 대한 응답을 1로 고정하므로 세부 내용을 더 보존하지만, 같은 방식으로 반복되는 세로선도 통과시킨다. 간섭의 물리적 발생원이 column driver라는 가설이나 추출 성분이 DSI common-mode라는 사실을 이 영상만으로 입증하지 않았다.', '',
           '## 주요 지표', '',
           '세로선 지표 = column 평균에서 61-column 이동평균을 뺀 값의 RMS. 감소율은 nuisance-only 제거율이 아니다. 화면의 세로 구조도 포함할 수 있다. 음수는 증가다.', '',
           '| 기종 | 방법 | rank | 세로선 RMS 감소 | 독립 raw 기준 MSE 감소 |',
           '|---|---|---:|---:|---:|']
    for d in main:
        for r in rows:
            if r['device']==d['device'] and r['method']!='baseline':
                lines.append(f'| {d["title"]} | {r["method"]} | {r["rank"]} | {r["stripe_reduction_pct"]:.2f}% | {r["heldout_raw_mse_reduction_pct"]:.2f}% |')
    lines += ['', 'Raw 기준 MSE 감소는 잡음 평활화 또는 반복 간섭 보존만으로도 좋아질 수 있다. 실제 화면 ground truth가 없으므로 SNR 개선, 해상도 개선, 문자 복원 성공으로 해석하지 않는다. y-edge 상관도 원본의 잡음을 포함하므로 단독으로 화면 보존율로 해석하지 않는다.', '',
      '## 입력과 정렬', '',
      '각 측정본의 첫 40 frame. 기존 복원 코드의 line/frame period와 circular crop을 사용하고, complex IQ DC 제거 → complex 선형보간 raster → content-profile 수평 정렬 → AM → 프레임 median으로 정규화 → log-AM 순서로 처리했다. 수치 분석은 native raster, PNG montage만 축소한다. Median filtering, TV, 생성형 복원은 사용하지 않았다.', '',
      'Galaxy 111.9 MHz는 기존 3기종 benchmark에 있던 측정본으로 별도 대조 결과도 보존했다. 기록에 키패드가 더 잘 보이는 것으로 명시된 171.5 MHz 측정본을 주 비교 대상으로 추가했다. 171.5 MHz는 기존 timing/crop을 사용하되 이 실험에서 수평 profile registration을 다시 추정했다. 과거 MATLAB offset trace를 그대로 복사한 결과는 아니다.', '']
    for d in summaries:
        acq=json.loads((s.OUT/d['device']/'acquisition.json').read_text(encoding='utf-8'))
        lines.append(f'- {d["title"]}: `{acq["raw_file"]}`, active {d["native_shape"]}, fs={acq["fs"]:g} Hz, fH={acq["f_h"]:.6f} Hz.')
    lines += ['', '## RPCA: penalized stable PCP', '',
      r'$$Y=L+S+N,\qquad \min_{L,S}\frac12\|Y-L-S\|_F^2+\tau\|L\|_*+\tau\lambda\|S\|_1.$$', '',
      '행렬은 H×W 평균 log-AM 이미지다. 전체 scalar mean만 분리했다가 복원한다. tau = sigma_mean (sqrt(H)+sqrt(W)), lambda = multiplier / sqrt(max(H,W)); multiplier=0.5, 1, 2를 모두 저장하고 기본값은 사전 지정한 1이다. sigma_mean은 별개 frame half 평균의 차/2에 대한 MAD 추정이다. 간섭이 유색이고 frame 상관이 있을 수 있으므로 이 tau는 실용적 규제 강도이며 최적 잡음 경계 보장이 아니다.', '',
      '각 반복에서 full exact SVD thresholding과 entrywise soft thresholding을 교대한다. 최대 160회, 상대 변화 2e-5까지 실행하며 수렴 여부·목적함수·fixed-point 오차를 저장했다. High rank만으로 sparse 성분 가정이 충족되지 않는다.', '',
      '## Spatial matched subspace', '',
      r'$$\widehat y=H(H^T R^{-1}H)^{-1}H^T R^{-1}y.$$', '',
      '각 raster row를 W차원 관측으로 본다. H는 학습 20 frame 평균의 RPCA(lambda=1) 결과에서 학습한 right singular vector다. R은 학습 frame의 평균을 뺀 temporal residual에서 추정하고 10% diagonal loading한다. 따라서 R은 시간 변화 간섭을 모델링하며 고정 세로선은 제거되지 않는다. 이 H는 검증된 common-mode 기준 패턴이 아닌 데이터 유래 후보 공간이다.', '',
      '학습: 1,3,...,39번. 검증: 2,6,...,38번. 시험: 4,8,...,40번. 검증 10장을 다시 5+5장으로 나눠 ranks={2,4,8,16,32,64} 중 학습 RPCA rank 이하에서 raw-reference MSE를 최소화한다. 시험 frame은 rank 선택에 사용하지 않는다. 추가 unweighted subspace control도 저장했다.', '',
      '시험 지표는 검증 10장에 적용한 결과와 처리하지 않은 시험 10장 평균 사이의 MSE/SSIM이다. 동일한 저랭크 필터를 양쪽에 적용해서 생기는 인위적인 repeatability 상승을 피했다. 전체 40장 출력은 시각화·최종 후보용이며 독립 시험 추정치로 취급하지 않는다.', '',
      '## Temporal matched subspace', '',
      r'$$x_p=a s_p+n_p,\quad a=\mathbf 1,\quad w=R^{-1}a/(a^T R^{-1}a),\quad \widehat s_p=w^Tx_p.$$', '',
      'Frame×pixel 행렬에서 반복되는 화면 성분의 temporal signature a=ones를 명시했다. 시간 방향 rank=1은 이미지의 공간 rank=1을 뜻하지 않는다. 전체 공분산을 픽셀 [::4,::4]에서 추정하고 10% diagonal loading했다. 이상적으로 신호의 aa^T 항은 unity-response 제약 아래 가중치에 영향을 주지 않는다. 유한 표본에서는 신호-잡음 교차항 영향이 남는다. 공분산 추정 격자를 제외한 픽셀의 raw-reference MSE도 별도로 기록했다.', '',
      '동일한 정적 간섭 역시 a=ones이므로 보존된다. 별도의 interference-only 측정이나 source-specific signature 없이는 화면과 구별할 수 없다.', '',
      '## 랭크 해석', '',
      '이전 LG X2의 effective rank 108.64는 frame 평균을 제거한 (frame·row)×candidate-column 행렬 값이었다. 이번 H×W 평균 이미지의 rank와 직접 비교할 수 없다. 고정 세로 무늬 b(x)가 모든 row에 같다면 I=1_H b^T이므로 세로선 개수와 상관없이 spatial rank=1이다. 그런 세로선은 low-rank L에 들어갈 수 있다. 또한 일정 화면과 고정 간섭은 frame×pixel 표현에서 모두 시간 방향 rank=1이다.', '',
      'AM/log-AM은 비선형 변환이다. IQ에서 z=s+i인 경우 abs(z) 또는 log(abs(z))는 두 물리 신호의 합으로 분해되지 않는다. 이 실험의 L/S는 통계적 영상 성분이며 독립된 물리 방사 전류가 아니다.', '',
      '## 다음 측정에 필요한 구별 정보', '',
      '동일 수신 설정에서 알려진 테스트 패턴을 바꾼 측정, 신호원이 분리된 probe/reference 채널, 또는 DSI lane/packet 관련 기준 주기와 위상 정보를 확보하면 H를 화면 관련 성분으로 정의할 근거가 생긴다. 화면 off는 clock/driver 동작까지 바꿀 수 있어 자동으로 동일 간섭 기준이 되지 않는다. 실제 common-mode 전류의 전기적 확인도 별도 측정이 필요하다.', '',
      '## 재현과 검증', '',
      '`run_separation.py --selftest` 후 `run_separation.py --device all`, 이어서 `temporal_and_report.py`를 실행한다. NumPy/Pillow만 필요하다. 원본 capture 경로와 parameter는 코드에 명시돼 있다. results/provenance.json, acquisition.json, split.json으로 입력·구현·평가 구분을 추적한다.', '',
      '합성 저랭크+sparse+Gaussian 데이터의 RPCA truth 상대오차는 results/numerical_selftest.json에 기록됐다. Matched estimator의 subspace unity-response와 covariance-weighted noise variance도 수치 검증했다. 실측 모든 RPCA의 수렴 상태는 각 summary.json에 있다.', '',
      '- [Stable Principal Component Pursuit](https://arxiv.org/abs/1001.2363)',
      '- [Matched Subspace Detectors](https://www.mssc.mu.edu/~daniel/mscs6960/spring2010/ScharfFriedlanderTSP94.pdf)', '',
      '## 결과 파일', '',
      'results/index.html: 기종별 모든 비교 이미지. 각 폴더의 components.npz: baseline, RPCA L/S/N, 공간 matched 결과와 H/R/weights. temporal_matched_rank1.npy: 시간 matched 결과. metrics.csv와 각 convergence.csv: 수치 지표. logam_frames.npy: 정렬 40-frame cache.']
    (s.ROOT/'REPORT_KR.md').write_text('\n'.join(lines),encoding='utf-8')
    # Read-only local viewer: a compact report plus native comparisons and zooms.
    cards=[]
    for d in main+[d for d in summaries if d['device'] not in main_order]:
        key=d['device']; table=[]
        chosen=['baseline','rpca_lambda1',f'matched_r{d["matched_selected_rank"]}','temporal_matched_rank1']
        for r in d['metrics']:
            if r['method'] in chosen:
                table.append(f'<tr><td>{html.escape(r["method"])}</td><td>{r["rank"]}</td><td>{r["stripe_reduction_pct"]:.2f}%</td><td>{r["heldout_raw_mse_reduction_pct"]:.2f}%</td></tr>')
        cards.append(f'''<section id="{key}"><h2>{html.escape(d['title'])}</h2>
<p>40 frames · native {d['native_shape'][0]} × {d['native_shape'][1]} · 동일 밝기 범위</p>
<a href="{key}/comparison_all.png"><img src="{key}/comparison_all.png" alt="original, RPCA, spatial matched and temporal matched comparison"></a>
<table><thead><tr><th>방법</th><th>rank</th><th>세로선 RMS 감소</th><th>독립 raw MSE 감소</th></tr></thead><tbody>{''.join(table)}</tbody></table>
<details><summary>글자 확대 비교</summary><img src="{key}/detail_crop.png"></details>
<details><summary>제거된 성분</summary><img src="{key}/removed_components.png"></details>
<details><summary>RPCA λ 민감도</summary><img src="{key}/rpca_sensitivity.png"></details>
<details><summary>Spatial matched rank 민감도</summary><img src="{key}/matched_sensitivity.png"></details>
<p><a href="{key}/metrics.csv">Metrics CSV</a> · <a href="{key}/column_profiles_all.png">Column profiles</a> · <a href="{key}/summary.json">Parameters and convergence</a></p></section>''')
    page='''<!doctype html><html lang="ko"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>3기종 RPCA / matched subspace</title>
<style>body{margin:0;background:#f3f5f8;color:#172333;font:16px/1.65 "Malgun Gothic",sans-serif}main{max-width:1450px;margin:auto;padding:36px}h1{margin:0;font-size:30px}h2{font-size:24px}section{margin-top:28px;padding:26px;background:white;border:1px solid #dce2ea;border-radius:12px}img{max-width:100%;height:auto}a{color:#165eb7}table{border-collapse:collapse;width:100%;font-size:14px}th,td{text-align:left;padding:9px;border-bottom:1px solid #dce2ea}details{border-top:1px solid #e3e7eb;margin-top:14px;padding-top:10px}summary{cursor:pointer}.note{background:#fff7e6;border-left:4px solid #bc7e19;padding:15px 20px}.nav{display:flex;gap:20px;flex-wrap:wrap}</style>
<main><h1>3기종 RPCA / matched subspace 비교</h1><p>2026-09-21 · LG X2 · Galaxy S4 LTE · iPhone 6s</p>
<div class="note"><b>공통모드 성분만의 분리는 확인되지 않았습니다.</b> 공간 저랭크 처리는 고정 세로선도 보존하고 일부 글자를 제거했습니다. 시간 matched 방식은 반복 화면과 고정 간섭을 함께 보존합니다. 표시된 rank는 처리 행렬의 통계적 rank이며 물리 신호원 개수가 아닙니다.</div>
<p>세로선 감소는 화면 구조 손실을 포함할 수 있고, raw MSE 개선은 잡음 평활화만으로도 생깁니다. 실제 화면 정답과 비교한 복원 정확도가 아닙니다. 각 이미지를 누르면 큰 그림을 볼 수 있습니다.</p><nav class="nav">'''+''.join(f'<a href="#{d["device"]}">{html.escape(d["title"])}</a>' for d in main)+'''<a href="../REPORT_KR.md">실험 기록</a><a href="primary_metrics.csv">주요 CSV</a></nav>'''+''.join(cards)+'</main></html>'
    (s.OUT/'index.html').write_text(page,encoding='utf-8')
    s.dump(s.OUT/'final_provenance.json',{'run_separation_sha256':hashlib.sha256((s.ROOT/'run_separation.py').read_bytes()).hexdigest(),
          'temporal_report_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
          'legacy_sha256':hashlib.sha256((s.ROOT/'vendor/legacy_benchmark.py').read_bytes()).hexdigest(),
          'python':sys.version,'numpy':np.__version__,'devices':[d['device'] for d in summaries]})

if __name__=='__main__':
    summaries=[process(p.parent) for p in sorted(s.OUT.glob('*/summary.json'))]
    write_reports(summaries)
