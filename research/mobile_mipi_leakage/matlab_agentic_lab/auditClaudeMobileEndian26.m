function report = auditClaudeMobileEndian26()
%AUDITCLAUDEMOBILEENDIAN26 Read-only byte-order and normalized-clock audit.
% Does not modify or run the recovered Desktop/mobile code. This isolates
% representation from timing and does not assert a newly reconstructed image.
lab=fileparts(mfilename('fullpath'));
out=fullfile(lab,'results','claude_mobile_review_20261026');
assert(~isfile(fullfile(out,'endian_audit.json')),'Refuse overwrite.');
input='C:/Users/leechanghoon/Downloads/black글_fc100MHz.rIs';
info=dir(input); assert(info.bytes==1158300000);
Fs=124082800; otherFs=124084280;
total=info.bytes/4; N=2^22;
starts=round(linspace(0,total-N-1,4));
blocks=cell(4,1);
for k=1:4
    be=readWords(input,starts(k),N,'ieee-be');
    le=readWords(input,starts(k),N,'ieee-le');
    b=be(:);l=le(:)/256;
    wrap=b < -128 | b > 127;
    c=corrcoef(b,l);
    u=mod(b,65536); swapped=256*mod(u,256)+floor(u/256);
    swapped(swapped>=32768)=swapped(swapped>=32768)-65536;
    blocks{k}=struct('first_complex_sample',starts(k),'complex_samples',N, ...
        'be_rms_i',sqrt(mean(be(1,:).^2)),'be_rms_q',sqrt(mean(be(2,:).^2)), ...
        'le_rms_i',sqrt(mean(le(1,:).^2)),'le_rms_q',sqrt(mean(le(2,:).^2)), ...
        'outside_small_word_fraction',mean(wrap), ...
        'outside_small_word_be_power_fraction',sum(b(wrap).^2)/sum(b.^2), ...
        'be_vs_le_div256_correlation',c(1,2), ...
        'le_div256_minus_be_normalized_mse',sum((l-b).^2)/sum(b.^2), ...
        'le_near_rail_fraction',mean(abs(le(:))>=32760), ...
        'exact_byteswap_max_error',max(abs(swapped-le(:))));
end
beMean=mean(cellfun(@(x)x.be_rms_i,blocks));
leMean=mean(cellfun(@(x)x.le_rms_i,blocks));
assert(abs(leMean-9770.35566685692)<1e-7,'Saved Claude survey RMS did not reproduce.');
first=24816560; n=1048624;
be=readWords(input,first,n,'ieee-be');le=readWords(input,first,n,'ieee-le');
x=complex(be(1,:).',-be(2,:).');y=complex(le(1,:).',-le(2,:).');
x=x-mean(x);y=y-mean(y);
[px,f]=pwelch(x,hann(8192,'periodic'),4096,8192,Fs,'centered');
py=pwelch(y,hann(8192,'periodic'),4096,8192,Fs,'centered');
% Normalize total power to compare spectral shape, not unrelated ADC scales.
px=px/sum(px);py=py/sum(py);
L=1100; bins=mod(first+(0:n-1)',L)+1;
foldBE=accumarray(bins,abs(x).^2,[L 1],@mean);
foldLE=accumarray(bins,abs(y).^2,[L 1],@mean);
foldBE=foldBE/mean(abs(x).^2);foldLE=foldLE/mean(abs(y).^2);
fFam=112802.5501974424;fClaude=112804.136768;
timing=struct('fam_fs_hz',Fs,'claude_fs_hz',otherFs, ...
    'fs_label_difference_ppm',(otherFs/Fs-1)*1e6, ...
    'fam_fit_hz',fFam,'claude_fit_hz',fClaude, ...
    'fam_samples_per_cycle',Fs/fFam,'claude_samples_per_cycle',otherFs/fClaude, ...
    'claude_frequency_on_fam_fs_axis_hz',fClaude*Fs/otherFs, ...
    'remaining_normalized_difference_ppm',(fClaude/otherFs/(fFam/Fs)-1)*1e6, ...
    'whole_capture_relative_cycle_slip',total*(fClaude/otherFs-fFam/Fs));
report=struct('status',"completed",'input',input,'bytes',info.bytes, ...
    'matlab_version',version,'blocks',{blocks},'be_mean_rms_i',beMean, ...
    'le_mean_rms_i',leMean,'saved_claude_csv_rms_i',9770.35566685692, ...
    'saved_csv_rms_reproduced',true,'timing',timing, ...
    'figure_first_complex_sample',first,'figure_complex_samples',n, ...
    'dc_removed_complex_rms_be',sqrt(mean(abs(x).^2)), ...
    'dc_removed_complex_rms_le',sqrt(mean(abs(y).^2)), ...
    'scope',"Representation A/B using identical bytes; no reconstructed image or proven physical packet identity.", ...
    'format_evidence',"Existing documented headerless BE acquisition convention plus exact LE code/CSV reproduction. The acquisition VI was not inspected in this audit.");
fig=figure('Visible','off','Color','w','Position',[50 50 1450 900]);
tiledlayout(2,2,'TileSpacing','compact');
nexttile;idx=1:1200;plot((idx-1)/Fs*1e6,be(1,idx));hold on
plot((idx-1)/Fs*1e6,le(1,idx)/256);grid on
xlabel('Time from block start (microseconds)');ylabel('I counts');
legend('BE','LE / 256','Location','best');title('Same bytes: scaling alone cannot undo byte swap');
nexttile;idx=1:101:n;scatter(be(1,idx),le(1,idx)/256,3,'.');grid on
xlabel('BE I counts');ylabel('LE I counts / 256');title('Nonlinear wrapping at byte boundaries');
nexttile;plot((100e6+f)/1e6,10*log10(px));hold on
plot((100e6+f)/1e6,10*log10(py));grid on
xlabel('Nominal RF (MHz), I-jQ convention');ylabel('PSD / sum(PSD) (dB)');
legend('BE','LE','Location','best');title('Equal total-power normalization; different spectrum shapes');
nexttile;plot((0:L-1)/Fs*1e6,foldBE);hold on
plot((0:L-1)/Fs*1e6,foldLE);grid on
xlabel('Phase within 1100 original samples (microseconds)');ylabel('Folded power / mean power');
legend('BE','LE','Location','best');title('Period can remain while waveform changes');
sgtitle('iPhone6 fc100MHz: read-only byte-order control, no timing adjustment');
exportgraphics(fig,fullfile(out,'endian_comparison.png'),'Resolution',140);close(fig);
save(fullfile(out,'endian_audit.mat'),'report','f','px','py','foldBE','foldLE','-v7.3');
fid=fopen(fullfile(out,'endian_audit.json'),'w','n','UTF-8');assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));
fprintf('BE mean I RMS %.9f, LE %.9f; saved CSV reproduced.\n',beMean,leMean);
fprintf('Normalized cycle slip %.6f over full capture.\n',timing.whole_capture_relative_cycle_slip);
end

function data=readWords(path,first,count,order)
fid=fopen(path,'r',order);assert(fid>=0);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
assert(fseek(fid,4*first,'bof')==0);
[data,got]=fread(fid,[2 count],'int16=>double');assert(got==2*count);
end
