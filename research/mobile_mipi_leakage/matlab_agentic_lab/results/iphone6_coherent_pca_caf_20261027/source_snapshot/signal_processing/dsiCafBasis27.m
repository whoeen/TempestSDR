function [B, meta] = dsiCafBasis27(model, emissionIndex, fsHz, fcHz, lagSamples, harmonicOrders)
%DSICAFBASIS27 Exact symmetric nonconjugate CAF basis for three RF lanes.
%   [B,META] = dsiCafBasis27(MODEL,E,FS,FC,LAGS,ORDERS) uses Fourier
%   coefficients from dsi3LanePowerModel27. The model coefficients describe
%   positive RF; this function includes the -FC downconversion lag phase.
%
%   Measurement convention:
%     z[n+d]*conj(z[n])*exp(-1i*2*pi*alpha*(n+d/2)/FS).
%   Rows have harmonic order fastest, then lag. For y=sum_l h_l*s_l,
%   R_y = B*theta(H), H=h*h', with nine REAL Hermitian parameters:
%     H11 H22 H33 real(H12) imag(H12) real(H13) imag(H13)
%     real(H23) imag(H23).
%   Global h phase is unobservable. A delay t0 applied to all lane waveforms
%   multiplies each row by exp(-1i*2*pi*alpha*t0). Residual CFO nu multiplies
%   each row by exp(1i*2*pi*nu*lag/FS). Neither is fitted here.
%
%   This is an ideal periodic, frequency-flat per-lane channel hypothesis.
%   Unknown HS timing, clock radiation and state mixing remain model errors.

arguments
    model (1,1) struct
    emissionIndex (1,1) {mustBeNumeric, mustBeReal, mustBeInteger, mustBePositive}
    fsHz (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
    fcHz (1,1) {mustBeNumeric, mustBeReal, mustBeFinite}
    lagSamples (:,1) {mustBeNumeric, mustBeReal, mustBeFinite}
    harmonicOrders (:,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBeInteger}
end
fsHz=double(fsHz);fcHz=double(fcHz);
lagSamples=double(lagSamples);harmonicOrders=double(harmonicOrders);
assert(isfield(model,'coefficients') && isfield(model,'harmonics') && ...
    isfield(model,'f0Hz'),'Incomplete Fourier model.');
assert(emissionIndex <= numel(model.coefficients),'Invalid emission index.');
coefficient=model.coefficients{emissionIndex};
carrierOrders=model.harmonics(:);
assert(size(coefficient,2)==3 && size(coefficient,1)==numel(carrierOrders), ...
    'Expected one Fourier coefficient column per lane.');
assert(all(diff(carrierOrders)==1),'Model harmonics must be consecutive.');
assert(~isempty(lagSamples)&&~isempty(harmonicOrders),'Empty CAF coordinate list.');
numberHarmonics=numel(harmonicOrders);
numberLags=numel(lagSamples);
B=complex(zeros(numberHarmonics*numberLags,9));
pairMatrices=complex(zeros(3,3,numberHarmonics*numberLags));
n=numel(carrierOrders);
for lagIndex=1:numberLags
    tau=lagSamples(lagIndex)/fsHz;
    for orderIndex=1:numberHarmonics
        order=harmonicOrders(orderIndex);
        row=orderIndex+(lagIndex-1)*numberHarmonics;
        first=max(1,1-order);
        last=min(n,n-order);
        if first>last,continue;end
        lowerIndex=(first:last).';
        upperIndex=lowerIndex+order;
        averageRfHz=(carrierOrders(lowerIndex)+order/2)*model.f0Hz;
        lagPhasor=exp(1i*2*pi*(averageRfHz-fcHz)*tau);
        % Nonconjugating transpose is intentional: A_lm is c_l[k+h]*c_m[k]^*.
        A=coefficient(upperIndex,:).'*(conj(coefficient(lowerIndex,:)).*lagPhasor);
        pairMatrices(:,:,row)=A;
        B(row,:)=[A(1,1),A(2,2),A(3,3), ...
            A(1,2)+A(2,1),1i*(A(1,2)-A(2,1)), ...
            A(1,3)+A(3,1),1i*(A(1,3)-A(3,1)), ...
            A(2,3)+A(3,2),1i*(A(2,3)-A(3,2))];
    end
end
realDesign=[real(B);imag(B)];
singularValues=svd(realDesign,'econ');
[effectiveRank,conditionNumber]=rankCondition(singularValues,size(realDesign));
meta=struct('harmonicOrders',harmonicOrders,'lagSamples',lagSamples, ...
    'alphaHz',repmat(harmonicOrders*model.f0Hz,numberLags,1), ...
    'tauSeconds',repelem(lagSamples/fsHz,numberHarmonics), ...
    'rowOrder',"harmonic fastest, then lag", ...
    'parameterOrder',["H11","H22","H33","realH12","imagH12", ...
        "realH13","imagH13","realH23","imagH23"], ...
    'fsHz',fsHz,'fcHz',fcHz,'f0Hz',model.f0Hz, ...
    'lagConvention',"z[n+d] conj(z[n]); central time (n+d/2)/Fs", ...
    'downconversionIncluded',true,'pairMatrices',pairMatrices, ...
    'realDesignSingularValues',singularValues, ...
    'realDesignEffectiveRank',effectiveRank, ...
    'realDesignConditionNumber',conditionNumber, ...
    'source',"Spooner CAF Eq.4,8: https://cyclostationary.blog/2015/09/28/the-cyclic-autocorrelation/");
end

function [rankValue,conditionValue]=rankCondition(s,dimensions)
if isempty(s)||s(1)==0,rankValue=0;conditionValue=Inf;return;end
tolerance=max(dimensions)*eps(s(1));
rankValue=sum(s>tolerance);
if rankValue<dimensions(2),conditionValue=Inf;else,conditionValue=s(1)/s(end);end
end
