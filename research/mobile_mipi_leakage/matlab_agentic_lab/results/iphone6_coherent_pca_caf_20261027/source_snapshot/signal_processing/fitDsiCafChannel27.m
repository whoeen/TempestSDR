function fit = fitDsiCafChannel27(B, target, weights, options)
%FITDSICAFCHANNEL27 Fit a shared three-lane channel to complex CAF features.
%   FIT = fitDsiCafChannel27(B,TARGET,WEIGHTS,OPTIONS) fits H=h*h' with
%   rank-one PSD structure. B is the nine-real-parameter Hermitian design
%   returned by dsiCafBasis27, possibly rowwise delayed and stacked over row
%   classes. WEIGHTS are nonnegative precision weights:
%       sum(weights .* abs(prediction-target).^2).
%   They are NOT square-root weights; sqrt is applied internally.
%
%   OPTIONS fields (all optional): optimize=true, maxIterations=400,
%   maxStarts=5, ridgeRelative=1e-8. optimize=false is a cheap coarse scan:
%   relaxed Hermitian LS -> rank-one eigen initialization plus fixed seeds.
%   optimize=true runs base-MATLAB fminsearch in five real dimensions,
%   fixing one lane's global phase per start. No Optimization Toolbox needed.
%
%   A single channel should be shared between physically comparable classes.
%   No arbitrary complex phase rotation of the CAF prediction is allowed.
%   h is reported with its strongest lane at phase zero. Absolute RF phase
%   is not identifiable from nonconjugate second-order statistics.
%
%   Channel units follow the arbitrary forward model; physical calibration
%   and frequency-flat-lane identifiability are not established by this fit.

arguments
    B {mustBeNumeric, mustBeFinite}
    target (:,1) {mustBeNumeric, mustBeFinite}
    weights (:,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBeNonnegative}
    options (1,1) struct = struct()
end
assert(ismatrix(B)&&size(B,2)==9,'B must have nine Hermitian columns.');
assert(size(B,1)==numel(target)&&numel(target)==numel(weights), ...
    'B, target and weights must share the feature count.');
assert(any(weights>0),'At least one positive feature weight is required.');
B=double(B);target=double(target);weights=double(weights);
settings=struct('optimize',true,'maxIterations',400,'maxStarts',5,'ridgeRelative',1e-8);
names=fieldnames(options);
for ii=1:numel(names)
    assert(isfield(settings,names{ii}),'Unknown fit option: %s',names{ii});
    settings.(names{ii})=options.(names{ii});
end
validateattributes(settings.optimize,{'logical','numeric'},{'scalar','real','finite'});
validateattributes(settings.maxIterations,{'numeric'},{'scalar','real','integer','positive'});
validateattributes(settings.maxStarts,{'numeric'},{'scalar','real','integer','positive','<=',5});
validateattributes(settings.ridgeRelative,{'numeric'},{'scalar','real','finite','nonnegative'});
rootWeight=sqrt(weights);
weightedB=B.*rootWeight;
weightedTarget=target.*rootWeight;
targetNorm=norm(weightedTarget);
assert(targetNorm>0,'The weighted CAF target is identically zero.');
bScale=norm(weightedB,'fro')/sqrt(max(1,numel(B)));
yScale=targetNorm/sqrt(numel(target));
assert(bScale>0,'The weighted model design is identically zero.');
Bs=B/bScale;ys=target/yScale;
Bw=Bs.*rootWeight;yw=ys.*rootWeight;
A=[real(Bw);imag(Bw)];rhs=[real(yw);imag(yw)];
singularValues=svd(A,'econ');
[designRank,designCondition]=rankCondition(singularValues,size(A));
gram=A.'*A;
ridge=settings.ridgeRelative*max(trace(gram)/9,eps);
thetaRelaxed=(gram+ridge*eye(9))\(A.'*rhs);
HRelaxed=thetaToMatrix(thetaRelaxed);
HRelaxed=(HRelaxed+HRelaxed')/2;
[eigenvectors,eigenvalueMatrix]=eig(HRelaxed);
eigenvalues=real(diag(eigenvalueMatrix));
[maxEigenvalue,maxIndex]=max(eigenvalues);
if maxEigenvalue>0
    eigenDirection=eigenvectors(:,maxIndex);
else
    eigenDirection=ones(3,1)/sqrt(3);
end
directions=[eigenDirection,ones(3,1)/sqrt(3),eye(3)];
numberStarts=settings.maxStarts;
startLoss=zeros(numberStarts,1);finalLoss=zeros(numberStarts,1);
exitFlags=zeros(numberStarts,1);iterationCounts=zeros(numberStarts,1);
bestH=zeros(3,1);bestLoss=1;
normalizer=sum(abs(yw).^2);
optimSettings=optimset('Display','off','MaxIter',settings.maxIterations, ...
    'MaxFunEvals',max(1500,8*settings.maxIterations),'TolX',1e-7,'TolFun',1e-9);
for ss=1:numberStarts
    direction=directions(:,ss);
    direction=direction/max(norm(direction),realmin);
    directionPrediction=Bw*matrixToTheta(direction*direction');
    gain=max(0,real(directionPrediction'*yw)/ ...
        max(sum(abs(directionPrediction).^2),realmin));
    floorGain=1e-4*norm(yw)/max(norm(directionPrediction),realmin);
    seed=direction*sqrt(max(gain,floorGain));
    [~,referenceLane]=max(abs(seed));
    seed=fixPhase(seed,referenceLane);
    parameter=packChannel(seed,referenceLane);
    objective=@(v) channelLoss(v,referenceLane,Bw,yw,normalizer);
    startLoss(ss)=objective(parameter);
    if settings.optimize
        [parameter,loss,exitFlag,output]=fminsearch(objective,parameter,optimSettings);
        iterationCounts(ss)=output.iterations;
        exitFlags(ss)=exitFlag;
    else
        loss=startLoss(ss);
    end
    finalLoss(ss)=loss;
    if loss<bestLoss
        bestLoss=loss;
        bestH=unpackChannel(parameter,referenceLane);
    end
end
[~,referenceLane]=max(abs(bestH));
bestH=fixPhase(bestH,referenceLane);
physicalScale=sqrt(yScale/bScale);
h=bestH*physicalScale;
H=h*h';
prediction=B*matrixToTheta(H);
denWeighted=norm(weightedTarget)*norm(prediction.*rootWeight);
coherenceWeighted=(weightedTarget'*(prediction.*rootWeight))/max(denWeighted,realmin);
denRaw=norm(target)*norm(prediction);
coherenceRaw=(target'*prediction)/max(denRaw,realmin);
weightedNmse=sum(weights.*abs(prediction-target).^2)/sum(weights.*abs(target).^2);
unweightedNmse=sum(abs(prediction-target).^2)/sum(abs(target).^2);
% Local fixed-candidate identifiability: derivative wrt the five gauge-fixed
% real channel coordinates. Timing, bitrate and model errors are not in J.
derivativeDirections=parameterDirections(referenceLane);
J=complex(zeros(size(B,1),5));
for ii=1:5
    dh=derivativeDirections(:,ii);
    dH=dh*bestH'+bestH*dh';
    J(:,ii)=Bw*matrixToTheta(dH);
end
realJacobian=[real(J);imag(J)];
jacobianSingularValues=svd(realJacobian,'econ');
[jacobianRank,jacobianCondition]=rankCondition(jacobianSingularValues,size(realJacobian));
relativeChannel=h/max(abs(h(referenceLane)),realmin);
fit=struct('h',h,'H',H,'prediction',prediction, ...
    'relativeChannel',relativeChannel,'relativeAmplitude',abs(relativeChannel), ...
    'relativePhaseRad',angle(relativeChannel),'relativePhaseDeg',angle(relativeChannel)*180/pi, ...
    'referenceLaneZeroBased',referenceLane-1,'globalPhaseIdentifiable',false, ...
    'corrComplex',abs(coherenceWeighted),'realCoherence',real(coherenceWeighted), ...
    'coherencePhaseRad',angle(coherenceWeighted),'corrComplexUnweighted',abs(coherenceRaw), ...
    'complexResidualNmse',weightedNmse,'unweightedNmse',unweightedNmse, ...
    'phaseRotatedPredictionUsed',false, ...
    'relaxedHermitianEigenvaluesScaled',eigenvalues, ...
    'relaxedHermitianNmse',sum(abs(A*thetaRelaxed-rhs).^2)/sum(abs(rhs).^2), ...
    'rankOneProjectionInitialLoss',startLoss(1),'optimized',logical(settings.optimize), ...
    'startLoss',startLoss,'finalLoss',finalLoss,'exitFlags',exitFlags,'iterations',iterationCounts, ...
    'designSingularValues',singularValues,'designRank',designRank,'designCondition',designCondition, ...
    'channelJacobianSingularValues',jacobianSingularValues, ...
    'channelJacobianRank',jacobianRank,'channelJacobianCondition',jacobianCondition, ...
    'physicalChannelIdentified',false,'settings',settings, ...
    'weightMeaning',"Precision weights, not square-root weights", ...
    'scale',struct('basis',bScale,'target',yScale), ...
    'scope',"Conditional frequency-flat three-lane channel fit; gauge, model mismatch and rank must be audited.");
end

function H=thetaToMatrix(theta)
H=diag(theta(1:3));
H(1,2)=theta(4)+1i*theta(5);H(2,1)=conj(H(1,2));
H(1,3)=theta(6)+1i*theta(7);H(3,1)=conj(H(1,3));
H(2,3)=theta(8)+1i*theta(9);H(3,2)=conj(H(2,3));
end

function theta=matrixToTheta(H)
theta=[real(H(1,1));real(H(2,2));real(H(3,3)); ...
    real(H(1,2));imag(H(1,2));real(H(1,3));imag(H(1,3)); ...
    real(H(2,3));imag(H(2,3))];
end

function h=fixPhase(h,referenceLane)
if abs(h(referenceLane))>0,h=h*exp(-1i*angle(h(referenceLane)));end
h(referenceLane)=real(h(referenceLane));
end

function value=packChannel(h,referenceLane)
other=setdiff(1:3,referenceLane,'stable');
value=[real(h(referenceLane));real(h(other(1)));imag(h(other(1))); ...
    real(h(other(2)));imag(h(other(2)))];
end

function h=unpackChannel(value,referenceLane)
other=setdiff(1:3,referenceLane,'stable');
h=complex(zeros(3,1));
h(referenceLane)=value(1);
h(other(1))=value(2)+1i*value(3);
h(other(2))=value(4)+1i*value(5);
end

function directions=parameterDirections(referenceLane)
other=setdiff(1:3,referenceLane,'stable');
directions=complex(zeros(3,5));
directions(referenceLane,1)=1;
directions(other(1),2)=1;directions(other(1),3)=1i;
directions(other(2),4)=1;directions(other(2),5)=1i;
end

function loss=channelLoss(parameter,referenceLane,B,y,normalizer)
if any(~isfinite(parameter)),loss=realmax('double')/100;return;end
h=unpackChannel(parameter,referenceLane);
prediction=B*matrixToTheta(h*h');
loss=sum(abs(prediction-y).^2)/normalizer;
if ~isfinite(loss),loss=realmax('double')/100;end
end

function [rankValue,conditionValue]=rankCondition(s,dimensions)
if isempty(s)||s(1)==0,rankValue=0;conditionValue=Inf;return;end
tolerance=max(dimensions)*eps(s(1));
rankValue=sum(s>tolerance);
if rankValue<dimensions(2),conditionValue=Inf;else,conditionValue=s(1)/s(end);end
end
