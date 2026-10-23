function summary = finalizeIphoneRecovery(refinedOnly)
%FINALIZEIPHONERECOVERY Export reversible display crops and column controls.
% No crop or display filtering is used to calculate the reported AM metrics.
arguments
    refinedOnly (1,1) logical = false
end
labRoot=fileparts(mfilename('fullpath'));addpath(fullfile(labRoot,'signal_processing'));
root=fullfile(labRoot,'results','iphone_recovery_20261023');
imageFolder='presentation_v2';
if refinedOnly,imageFolder='presentation_refined';end
out=fullfile(root,imageFolder);assert(~isfolder(out),'iphone:Exists','Refuse overwrite');mkdir(out);
old=jsondecode(fileread(fullfile(root,'archive_P008','survey.json')));
folders=string(fullfile(root,'archive_P008',string({old.key})));
keys=string({old.key});
folders=[folders fullfile(root,'bottom_middle_238_P032_v2') fullfile(root,'response_308_P032_v2') fullfile(root,'iphone6s_P032') fullfile(root,'password_105_P064')];
keys=[keys "bottom_middle_238_P032" "response_308_P032" "iphone6s_P032" "password_105_P064"];
if refinedOnly
    folders=string(fullfile(root,'password_105_P064_refined'));
    keys="password_105_P064_refined";
end
summary=struct([]);
for k=1:numel(folders)
    s=load(fullfile(folders(k),'raster_final.mat'));
    a=double(s.am);nr=size(a,1);nc=size(a,2);
    if keys(k)=="iphone6s_P032"
        rr=s.activeRows;cc=s.activeCols;cropMethod="Existing iPhone6s active crop from prior benchmark";
    else
        h=min(1334,nr);w=min(750,nc);
        rowScore=mean(log1p(a),2);rs=bestCircularWindow(rowScore,h);
        rr=mod(rs-1+(0:h-1),nr)+1;
        active=log1p(a(rr,:));
        smooth=movmean(active,9,1);
        colScore=mean(abs(diff(smooth,1,1)),1);
        cs=bestCircularWindow(colScore(:),w);
        cs=mod(cs-1-floor((nc-w)/2),nc)+1;
        cc=mod(cs-1+(0:nc-1),nc)+1;
        cropMethod="Assumed1334-row window; all raster columns retained and cyclically reordered; full raster retained";
    end
    raw=log1p(a(rr,cc));
    rawDisplay=scaled(raw);
    cleaned=raw-mean(raw,1);
    cleanedDisplay=scaled(cleaned);
    % Use global phase alignment as a separate, interpretable control.
    z=s.globalCoherent(rr,cc);
    consistency=min(1,double(abs(z))./max(a(rr,cc),eps));
    phaseReference=angle(sum(double(z),'all'));
    hue=mod((double(angle(z))-phaseReference+pi)/(2*pi),1);
    reliable=(a(rr,cc)>=sampleQuantile(a(rr,cc),.15)) & consistency>=.20;
    hsv=hsv2rgb(cat(3,hue,consistency.*reliable,rawDisplay));
    stem=keys(k);
    imwrite(rawDisplay,fullfile(out,stem+"_am.png"));
    imwrite(cleanedDisplay,fullfile(out,stem+"_column_removed.png"));
    imwrite(hsv,fullfile(out,stem+"_phase_hsv.png"));
    fig=figure('Visible','off','Position',[70 50 1280 900]);
    tiledlayout(fig,1,3);
    nexttile;imagesc(rawDisplay);axis image off;title('AM average / log display');
    nexttile;imagesc(cleanedDisplay);axis image off;title('Column-profile removal control');
    nexttile;image(hsv);axis image off;title('Relative phase HSV / masked');
    colormap(fig,gray(256));
    prog=readtable(fullfile(folders(k),'frame_progression.csv'));
    n=prog.frames(end);
    sgtitle(sprintf('%s | %d stored frames | display crop only',s.device.title,n),'Interpreter','none');
    exportgraphics(fig,fullfile(out,stem+"_comparison.png"),Resolution=130);close(fig);
    if k<=numel(old) && ~refinedOnly
        source=string(old(k).source);
    elseif startsWith(keys(k),"password_105")
        pd=jsondecode(fileread(fullfile(root,'password_diagnostic','diagnostic.json')));source=string(pd.source);
    else
        source=fullfile(getenv('USERPROFILE'),'Desktop','mobile','0625',s.device.filename);
    end
    entry=struct('key',stem,'title',string(s.device.title),'source',source, ...
        'fs_hz',s.device.fs_hz,'fc_hz',s.device.rf_center_hz,'bandwidth_hz',s.device.receiver_bandwidth_hz, ...
        'frames',n,'am_odd_even_correlation',prog.am_odd_even_correlation(end), ...
        'coherent_over_am',prog.mean_coherent_over_incoherent(end), ...
        'line_samples',s.device.fs_hz/s.device.prior_line_hz,'frame_samples',s.device.prior_frame_samples, ...
        'samples_per_output_raster_cell',(s.device.fs_hz/s.device.prior_line_hz)/nc, ...
        'crop_method',cropMethod,'crop_row_start',rr(1),'crop_column_start',cc(1), ...
        'crop_rows',numel(rr),'crop_columns',numel(cc), ...
        'preview',string(imageFolder)+"/"+stem+"_comparison.png",'am',string(imageFolder)+"/"+stem+"_am.png", ...
        'cleaned',string(imageFolder)+"/"+stem+"_column_removed.png",'phase',string(imageFolder)+"/"+stem+"_phase_hsv.png", ...
        'phase_reference_rad',phaseReference,'phase_consistency_threshold',.20, ...
        'full_output_folder',folders(k), ...
        'display_filter_caveat','Column mean removal can erase true vertical image structure. HSV encodes relative RF phase, not display RGB. Crop size is a display hypothesis.');
    if isempty(summary),summary=entry;else,summary(end+1)=entry;end %#ok<AGROW>
end
if refinedOnly
    preceding=jsondecode(fileread(fullfile(root,'presentation_summary.json')));
    summary=[preceding(:);summary(:)];
end
writeJsonFile(fullfile(root,'presentation_summary.json'),summary);
end
function start=bestCircularWindow(x,n)
x=double(x(:));h=numel(x);s=conv([x;x],ones(n,1),'valid');[~,start]=max(s(1:h));
end
function y=scaled(x)
lim=sampleQuantile(x,[.01 .99]);y=min(1,max(0,(double(x)-lim(1))/max(lim(2)-lim(1),eps)));
end
