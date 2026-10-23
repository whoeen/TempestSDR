function result = previewIphonePasswordTiming()
%PREVIEWIPHONEPASSWORDTIMING Compare timing candidates without content fitting.
labRoot=fileparts(mfilename('fullpath'));addpath(fullfile(labRoot,'signal_processing'));
root=fullfile(labRoot,'results','iphone_recovery_20261023');
prior=jsondecode(fileread(fullfile(root,'password_diagnostic','diagnostic.json')));
out=fullfile(root,'password_timing_preview');
assert(~isfolder(out),'iphone:Exists','Refuse overwrite');mkdir(out);
line=prior.line_candidates(1).refined_line_samples;
frames=8;cols=550;
rowCandidates=[1880 1881 1884];
periods=[1880*line prior.frame_candidates(1).frame_samples 1884*line];
iq=readRisIqBlock(string(prior.source),0,ceil(max(periods)*frames+10*line));
images=cell(3,1);records=struct([]);
fig=figure('Visible','off','Position',[70 40 1600 1000]);tiledlayout(fig,1,4);
for k=1:numel(rowCandidates)
    rows=rowCandidates(k);
    index=(0:rows*cols-1).';
    pos=floor(index/cols)*line+mod(index,cols)*(line/cols);
    am=zeros(rows,cols,'single');odd=am;even=am;
    for f=1:frames
        z=sampleFractionalRaster(iq,4+(f-1)*periods(k)+pos,[rows cols],"cubic");
        a=abs(z);am=am+a;
        if mod(f,2),odd=odd+a;else,even=even+a;end
        if f==1,first=a;end
    end
    am=am/frames;
    images{k}=am;
    entry=struct('rows',rows,'columns',cols,'line_samples',line,'frame_samples',periods(k), ...
        'frame_hz_conditional',prior.fs_hz/periods(k),'frames',frames, ...
        'am_odd_even_correlation',corrValue(odd,even), ...
        'row_column_removed_odd_even_correlation',corrValue(removeProfiles(odd),removeProfiles(even)));
    if isempty(records),records=entry;else,records(end+1)=entry;end %#ok<AGROW>
    nexttile;imagesc(showScale(log1p(am)));axis image off;title(sprintf('%d rows | %.5f Hz\nP8 AM, no profile removal',rows,entry.frame_hz_conditional));
    imwrite(showScale(log1p(am)),fullfile(out,sprintf('rows%d_P008_am.png',rows)));
    save(fullfile(out,sprintf('rows%d_preview.mat',rows)),'am','first','odd','even','entry','-v7');
end
nexttile;imagesc(showScale(log1p(first)));axis image off;title('P1 AM reference (1884 rows)');
colormap(fig,gray(256));
sgtitle('New iPhone 6 password capture | 105 MHz / 25 MS/s source evidence | Full uncropped raster','Interpreter','none');
exportgraphics(fig,fullfile(out,'timing_candidate_comparison.png'),Resolution=120);close(fig);
result=struct('source',prior.source,'line_samples',line,'candidates',records, ...
    'caveat','550 display columns interpolate about222 acquired samples/line; no extra measured resolution. No ground-truth image was used.');
writeJsonFile(fullfile(out,'preview_metrics.json'),result);
disp(struct2table(records));
end
function y=removeProfiles(x)
x=double(x);y=x-mean(x,1)-mean(x,2)+mean(x,'all');
end
function r=corrValue(a,b)
a=double(a(:));b=double(b(:));a=a-mean(a);b=b-mean(b);r=sum(a.*b)/max(norm(a)*norm(b),eps);
end
function y=showScale(x)
lim=sampleQuantile(x,[.01 .99]);y=min(1,max(0,(double(x)-lim(1))/max(lim(2)-lim(1),eps)));
end
