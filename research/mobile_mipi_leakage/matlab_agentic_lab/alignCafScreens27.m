function report=alignCafScreens27(outputDirectory)
%ALIGNCAFSCREENS27 One B1-fitted coordinate map for all four CAF screen views.
arguments
    outputDirectory (1,1) string
end
labRoot=string(fileparts(mfilename('fullpath')));addpath(fullfile(labRoot,'signal_processing'));
oldDirectory=fullfile(labRoot,'results','iphone6_complex_caf_channels_20261027');
assert(~isfile(fullfile(outputDirectory,'alignment_parameters.json')),'Completed alignment already exists.');
if ~isfolder(outputDirectory),mkdir(outputDirectory);end
d=load(fullfile(oldDirectory,'complex_caf.mat'),'images','labels','rowMeta','f0');
v=load(fullfile(oldDirectory,'reconstruction_views.mat'),'whiteCaf','phaseReference','phaseReferenceValid','limits');
reference=imread(d.rowMeta.reference_path);
if size(reference,3)==3,grayReference=mean(double(reference),3)/255;else,grayReference=double(reference)/255;end
[height,width]=size(grayReference);[R,N]=size(d.images{1}.power);
alignment=estimateScreenAlignment27(d.images{1}.caf1,v.whiteCaf,grayReference,d.rowMeta.row_offset_zero_based);
assert(any(alignment.orientation==[-1 1]));
blockNames=["B1","B2","B3","B23"];
palettes={gray(256),gray(256),blueRed(256),hsv(256)};
names=["power","caf_residual","phase_projection","lag_phase"];
titles=["Power","Complex CAF residual |C-Cwhite|","Phase-reference projection","Lag-product phase (deg)"];
geometryAudit=struct([]);savedViews=struct;
for bb=1:4
    if bb<=3
        power=double(d.images{bb}.power);caf=double(d.images{bb}.caf1);normCaf=double(d.images{bb}.caf1_norm);
    else
        power=(double(d.images{2}.power)+double(d.images{3}.power))/2;
        caf=(double(d.images{2}.caf1)+double(d.images{3}.caf1))/2;
        normCaf=(double(d.images{2}.caf1_norm)+double(d.images{3}.caf1_norm))/2;
    end
    residual=caf-double(v.whiteCaf);
    projectedComplex=residual.*double(v.phaseReference);
    projectedComplex(:,~v.phaseReferenceValid)=NaN;
    for variant=["native","screen"]
        [indices,weights,mapMeta]=coordinateMap(alignment,R,N,height,width,variant);
        q=struct;
        q.power=sampleRaster(power,indices,weights);
        q.complex_residual=sampleRaster(residual,indices,weights);
        q.phase_projection=real(sampleRaster(projectedComplex,indices,weights));
        q.lag_product=sampleRaster(caf,indices,weights);
        q.lag_norm=sampleRaster(normCaf,indices,weights);
        q.rho=abs(q.lag_product)./max(q.lag_norm,realmin);
        phase=angle(q.lag_product)*180/pi;phase(q.rho<.2)=NaN;
        panels={q.power,abs(q.complex_residual),q.phase_projection,phase};
        if bb==4
            savedViews.(variant)=q;
            if isempty(geometryAudit),geometryAudit=mapMeta;else,geometryAudit(end+1)=mapMeta;end %#ok<AGROW>
        end
        for kk=1:4
            stem=variant+"_"+blockNames(bb)+"_"+names(kk);
            imwrite(mapImage(panels{kk},v.limits{kk},palettes{kk}),fullfile(outputDirectory,stem+".png"));
        end
        if bb==4
            fig=figure('Name',"Aligned four views | "+variant,'Color','w','Position',[35 35 1850 1050]);
            tl=tiledlayout(fig,1,5,'TileSpacing','compact','Padding','compact');
            ax=nexttile(tl);image(ax,[0 width-1],[0 height-1],reference);axis(ax,'image');set(ax,'YDir','reverse');
            title(ax,'Reference only');xlabel(ax,'Reference column');ylabel(ax,'Reference row');
            for kk=1:4
                ax=nexttile(tl);showPanel(ax,panels{kk},v.limits{kk},palettes{kk},0:height-1);
                title(ax,titles(kk),'Interpreter','none');
                if variant=="screen",xlabel(ax,'Aligned display column');else,xlabel(ax,'Unwrapped native bin');end
                ylabel(ax,'Aligned screen row');pbaspect(ax,[width height 1]);
            end
            title(tl,"B2/B3 mean | ONE B1 coordinate map for every panel | "+variant);
            saveFigure(fig,outputDirectory,"montage_"+variant+"_B23");
            if variant=="screen"
                zoomRows=(390:min(940,height-1))+1;
                fig=figure('Name','Aligned text region across all four views','Color','w','Position',[60 60 1450 1080]);
                tl=tiledlayout(fig,2,2,'TileSpacing','compact','Padding','compact');
                for kk=1:4
                    ax=nexttile(tl);showPanel(ax,panels{kk}(zoomRows,:),v.limits{kk},palettes{kk},zoomRows-1);
                    title(ax,titles(kk),'Interpreter','none');xlabel(ax,'Aligned display column');ylabel(ax,'Aligned screen row');
                    pbaspect(ax,[width numel(zoomRows) 1]);
                end
                title(tl,'Same text-region crop in all four views; no independent image shifts or phase rotation');
                saveFigure(fig,outputDirectory,'zoom_screen_B23');
            end
        end
    end
end
imwrite(reference,fullfile(outputDirectory,'reference.png'));
report=struct('alignment',alignment,'source_directory',oldDirectory, ...
    'source_file','complex_caf.mat','input_modified',false,'calibration_block','B1 only', ...
    'validation_blocks',[2 3],'reference_used_for','Supervised display-coordinate registration only; no reference pixel insertion into measured panels.', ...
    'geometry_audit',geometryAudit,'original_row_offset',d.rowMeta.row_offset_zero_based, ...
    'period_hz',d.f0,'native_period_bins',N,'frame_periods',R, ...
    'four_view_coordinate_map_identical',true,'per_panel_registration',false, ...
    'native_scope','Entire 1100-bin row retained; integer origin with flat-raster row carry; no sample interpolation.', ...
    'screen_scope','One inferred active time-window mapped to reference width750 using complex interpolation before phase extraction. Display calibration, not verified pixel clock.', ...
    'phase_scope','Argument of aligned lag-product, not absolute RF phase; rho<0.2 masked. No phase angle interpolation.', ...
    'phase_projection','B1 white-CAF phase reference retained before applying the same coordinate map.', ...
    'color_limits_unchanged',true,'fixed_B1_limits',{v.limits}, ...
    'data_scope','The original four native CAF reconstruction types. New frame-PCA rasters are not mixed into this coordinate system.');
save(fullfile(outputDirectory,'aligned_views_B23.mat'),'savedViews','report','alignment','-v7.3');
writeJson(fullfile(outputDirectory,'alignment_parameters.json'),report);
fprintf('Aligned all four views: x0 %.3f, active width %.3f, row %g, orientation %g, training score %.4f.\n', ...
    alignment.origin_bins,alignment.active_width_bins,alignment.row_offset_zero_based,alignment.orientation,alignment.score);
end

function [indices,weights,meta]=coordinateMap(a,R,N,H,W,variant)
rows=(a.row_offset_zero_based+(0:H-1)')*N;
if variant=="native"
    if a.orientation==1,u=rows+round(a.origin_bins)+(0:N-1)+.5;
    else,u=rows+round(a.origin_bins+a.active_width_bins)-((0:N-1)+.5);end
else
    f=((0:W-1)+.5)/W;
    if a.orientation==1,u=rows+a.origin_bins+f*a.active_width_bins;
    else,u=rows+a.origin_bins+(1-f)*a.active_width_bins;end
end
q=mod(u-.5,R*N);lower=floor(q);weights=q-lower;
indices=struct('lower',lower+1,'upper',mod(lower+1,R*N)+1);
meta=struct('variant',variant,'rows',H,'columns',size(q,2), ...
    'input_midpoint_convention','native bin n has center n+0.5', ...
    'row_carry_used',true,'interpolation_used',any(weights~=0,'all'), ...
    'unique_lower_samples',numel(unique(indices.lower(:))), ...
    'coordinate_min_unwrapped',min(u,[],'all'),'coordinate_max_unwrapped',max(u,[],'all'));
if variant=="native",assert(all(weights==0,'all'));assert(meta.unique_lower_samples==numel(u));end
end
function q=sampleRaster(x,idx,w)
f=reshape(x.',[],1);q=f(idx.lower);
sel=w~=0;q(sel)=q(sel).*(1-w(sel))+f(idx.upper(sel)).*w(sel);
end
function showPanel(ax,x,range,palette,y)
h=imagesc(ax,0:size(x,2)-1,y,x);set(h,'AlphaData',isfinite(x));
set(ax,'Color',[.7 .7 .7],'YDir','reverse');clim(ax,range);colormap(ax,palette);colorbar(ax);
end
function rgb=mapImage(x,range,palette)
y=(x-range(1))/(range(2)-range(1));valid=isfinite(y);y(~valid)=0;y=min(1,max(0,y));
index=1+round(y*(size(palette,1)-1));rgb=reshape(palette(index(:),:),size(x,1),size(x,2),3);
for c=1:3,z=rgb(:,:,c);z(~valid)=.7;rgb(:,:,c)=z;end
rgb=uint8(round(255*rgb));
end
function p=blueRed(n)
u=linspace(0,1,n)';p=[min(1,2*u),1-abs(2*u-1),min(1,2*(1-u))];
end
function saveFigure(fig,out,name)
exportgraphics(fig,fullfile(out,string(name)+".png"),'Resolution',145);
savefig(fig,fullfile(out,string(name)+".fig"));
end
function writeJson(path,value)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0);cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end
