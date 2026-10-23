function result = inspectIphonePasswordCapture()
%INSPECTIPHONEPASSWORDCAPTURE Estimate sample periods from a newly found file.
% IQ is preserved as I+jQ; conjugation changes phase convention but not AM.
labRoot=fileparts(mfilename('fullpath'));
addpath(fullfile(labRoot,'signal_processing'));
raw=fullfile(getenv('USERPROFILE'),'Desktop','연구','APMC 2026','5. 모바일','iphone6', ...
    'iphone6_비밀번호화면_LCD커넥터부분_2026년03월13일11시59분08.54초.rIs');
out=fullfile(labRoot,'results','iphone_recovery_20261023','password_diagnostic');
assert(~isfolder(out),'iphone:Exists','Refuse overwrite: %s',out);mkdir(out);
fs=25e6; % Supported by the contemporaneous LabVIEW screenshot; raw has no header.
[iq,info]=readRisIqBlock(raw,0,2^23);
diag=diagnoseIq(iq(1:2^20));
am=double(abs(iq)); am=am-mean(am);
n=numel(am); nf=2^nextpow2(2*n-1);
acf=real(ifft(abs(fft(am,nf)).^2));acf=acf(1:ceil(fs/25)+1);
acf=acf./(n-(0:numel(acf)-1).');acf=acf/max(acf(1),eps);
lineLags=(round(fs/160e3):round(fs/70e3)).';
lineCandidates=localPeaks(acf,lineLags,12);
frameLags=(round(fs/62):round(fs/58)).';
frameCandidates=localPeaks(acf,frameLags,16);
% Refine each line candidate using distant multiples to reduce sub-sample bias.
base=lineCandidates(:,1);
refined=zeros(size(base)); spread=zeros(size(base));
multiples=[8 32 64 128 256 512];
detail=cell(numel(base),1);
for j=1:numel(base)
    estimates=zeros(size(multiples));
    for k=1:numel(multiples)
        center=base(j)*multiples(k);
        half=max(3,round(0.001*center));
        lags=(round(center)-half:round(center)+half).';
        [~,ind]=max(acf(lags+1));
        estimates(k)=peakAt(acf,lags(ind))/multiples(k);
    end
    refined(j)=median(estimates(3:end));
    spread(j)=max(estimates(3:end))-min(estimates(3:end));
    detail{j}=estimates;
end
lineTable=table(base,refined,fs./refined,lineCandidates(:,2),spread, ...
    'VariableNames',{'single_peak_lag_samples','refined_line_samples','conditional_line_hz','acf','multiple_estimate_spread_samples'});
frameTable=table(frameCandidates(:,1),fs./frameCandidates(:,1),frameCandidates(:,2), ...
    'VariableNames',{'frame_samples','conditional_frame_hz','acf'});
writetable(lineTable,fullfile(out,'line_candidates.csv'));
writetable(frameTable,fullfile(out,'frame_candidates.csv'));
[p,f,meta]=estimateWelchPsd(iq(1:2^20),periodicHann(8192),4096,8192,fs,"centered");
fig=figure('Visible','off','Position',[70 70 1300 900]);
tiledlayout(fig,2,2);
nexttile;plot(f/1e6,powerDb(p));xlabel('Baseband frequency (MHz)');ylabel('PSD dB re count^2/Hz');title('Raw I+jQ, Fs=25 MS/s evidence-based hypothesis');
nexttile;plot(lineLags,acf(lineLags+1));xlabel('Lag (samples)');ylabel('AM autocorrelation');title('Line-period candidates, without raster assumptions');
nexttile;plot(frameLags,acf(frameLags+1));xlabel('Lag (samples)');ylabel('AM autocorrelation');title('Frame candidates around 58-62 Hz');
nexttile;plot((0:9999)/fs*1e6,abs(iq(1:10000)));xlabel('Time (us)');ylabel('|IQ| (counts)');title('Untouched envelope');
exportgraphics(fig,fullfile(out,'timing_diagnostic.png'),Resolution=130);close(fig);
result=struct('source',raw,'read_info',info,'fs_hz',fs,'rf_center_hz',105e6, ...
    'receiver_bandwidth_hz',NaN,'metadata_status','Fs and fc supported by March13 presentation LabVIEW screenshot; same-file identity linkage from scripts and date; no raw header.', ...
    'diagnostic',diag,'line_candidates',table2struct(lineTable), ...
    'frame_candidates',table2struct(frameTable),'line_multiples',multiples, ...
    'multiple_period_estimates',{detail},'welch',meta, ...
    'caveat','Autocorrelation also detects clutter and harmonics; validate candidate timing by raster and held-out segments.');
writeJsonFile(fullfile(out,'diagnostic.json'),result);
save(fullfile(out,'autocorrelation.mat'),'acf','lineLags','frameLags','lineTable','frameTable','-v7');
disp(lineTable);disp(frameTable(1:min(10,height(frameTable)),:));
end
function result=localPeaks(ac,lags,count)
v=ac(lags+1);
where=find(v(2:end-1)>v(1:end-2)&v(2:end-1)>=v(3:end))+1;
[~,order]=sort(v(where),'descend');where=where(order(1:min(count,numel(order))));
result=zeros(numel(where),2);
for k=1:numel(where)
    result(k,:)=[peakAt(ac,lags(where(k))),v(where(k))];
end
end
function lag=peakAt(ac,lag)
j=round(lag)+1;
den=ac(j-1)-2*ac(j)+ac(j+1);
if abs(den)>eps
    lag=round(lag)+max(-.5,min(.5,.5*(ac(j-1)-ac(j+1))/den));
end
end
