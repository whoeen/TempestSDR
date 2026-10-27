# iPhone 6 CAF 행 상태: 참조 화면과 학습 정합 검토
2026-10-27 · 담당 row_state_reference · MATLAB 실행은 root 소유

## 참조 화면에서 직접 측정한 값
입력: C:/Users/leechanghoon/Downloads/5D0ED11B-F431-49D4-84C4-E25AD8746E2C.png.
Pillow/NumPy로 PNG pixel을 읽었다. 크기750×1334, 전체 grayscale이다.

행 번호는 모두0-based:
- 정확한 all-black: 0–385, 948–1333. 총772행.
- 정확한 all-white: 386–431, 453–481, 503–531, 553–581, 603–631, 653–681, 703–731, 753–781, 803–831, 853–881, 903–947. 총352행.
- 문자/혼합: 432–452 +50j, j=0,…,9. 총210행.
- Gray pixel44299개, 정확한 black/white fraction0.9557231384307846.
- 첫 문자줄bitmap은 나머지9줄과 일부antialias/배치가 다르다. 두 번째부터 열 번째까지의21×750graybitmap은 모두 동일하다. 첫줄과 나머지의binary threshold128bitmap 일치율은0.982984126984127이다.
- 문자줄의맨위/맨아래행은gray-only일수있다. 이를정확한흑백packet로만근사하면white행과같아질수있으므로경계제외가유용하다.

이label은참조화면의정답class이며,RF에서흰색/검정을blind복호화했다는주장이아니다.

## 학습 구간에서의 row mapping
root가 B1 native raster에서 내보낸
results/caf_row_features_training_20261027.csv만 사용했다.
B2/B3는 mapping선택에 사용하지 않았다.

Measured1881-row좌표와source1334-row좌표의관계:
capture_row = mod(offset + scale × source_row,1881).

기준text mask는source432–452+50j이다. 측정feature에서101-rowcircular medianbaseline을제거하고5-tapbinomial[1,4,6,4,1]/16평활화,1/99percentileclipping,zero-mean/unitnorm을적용했다. 아래수치는Python독립계산이며MATLAB본실행결과는root의row_label_metadata.json을최종근거로한다.

- Row mean만: bestoffset562, correlation≈0.88535.
- Row absolute column-residual만: offset562, ≈0.85699.
- 고정columnbaseline하위70%열의row std: offset561, ≈0.75716.
- 위세정규화feature를평균한합성feature: **scale1,offset562,score0.85363558**.
- offset−50=512score0.77106544, offset+50=612score0.76684903. ±50aliasmargin≈0.08257.
- scale0.98:0.002:1.02검색상최고는scale0.998,offset563,score0.85607057. scale1대비gain0.002435에불과하다.
- 사전명시된절대scoregain0.01를넘지않으면scale1을유지하는보수적규칙을구현했다. 이는confidence interval이나유의확률이아니다.

이mapping이면sourcetextrows는capture994–1014+50j에놓인다. 1881−1334=547행은영상blackbar와합치면안된다. 해당시간은unassigned/transport-blanking후보이며LP나HSoff가확인된것이아니다.

## Boundary exclusion
각class변경점과active/unassigned경계의±2capture rows를label0으로제외한다.
scale1,offset562이면예상counts:
- black764
- white308
- text170
- unassigned/boundary639

검증IQ에서는동일labelmap을고정해야한다. residualphase/CFO분석의lag가rowboundary를넘는sample은별도pairmask로제외한다. 이labelmargin은그pairmask를대체하지않는다.

## MATLAB 구현
signal_processing/buildIphoneRowLabelsCaf27.m

[labels,metadata,features] = buildIphoneRowLabelsCaf27(double(trainingRaster),outputDirectory)

- labels:1881×1uint8,0unassigned/boundary,1black,2white,3text.
- metadata:reference사용범위,offset/scale,score,50rowaliases,counts.
- features:trainingfeature,rawlabel,referencecoordinate,Gcurve,scalegrid.
- MATLABbase기능만사용한다. 반환label은known-reference를이용한supervisedrow-positioncalibration이다.
- optionaloutput은row_label_metadata.json,row_labels.csv,row_labels.mat을저장한다.
- 실제MATLAB실행/정적검사는root가수행한다.

## 해석과 사용상 제한
흰색·검정의물리적구분은현재수신power하나로새로학습된것이아니라,문자반복의위치에참조화면을정렬해부여했다. 따라서state별CAF와3lanechannel추정은이정렬가설에조건부이다. 원본스크린샷을복원결과pixel에복사하거나,참조화면으로채운이미지를RF복원화면이라고표시하면안된다.

텍스트가50행간격으로동일반복되므로50행shift는실제모호성이다. 첫/마지막문자줄과흰영역전체경계를함께보아정렬하고위alias점수를기록한다. 더나은screenpattern은각줄의내용이나위치가서로다른knowntrainingpattern이다. 현재사용자입력화면을변경했다고가정하지않는다.
