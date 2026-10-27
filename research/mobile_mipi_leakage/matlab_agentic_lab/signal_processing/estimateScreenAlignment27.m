function alignment=estimateScreenAlignment27(caf,whiteCaf,reference,rowOffset)
%ESTIMATESCREENALIGNMENT27 B1-only global display registration to known screen.
% This fits display geometry only. It never substitutes reference pixels.
% x0 is the left boundary of the ACTIVE TIME WINDOW in zero-based bin units.
% For source row r and column c, pixel-center time is
%   u=(rowOffset+r)*N+x0+width*(c+.5)/W              (orientation +1)
%   u=(rowOffset+r)*N+x0+width*(1-(c+.5)/W)          (orientation -1).
% Measured CAF centers occur at .5,1.5,...; interpolation uses flat raster
% coordinates with row carry, including the periodic frame boundary.
arguments
    caf (:,:) {mustBeNumeric}
    whiteCaf (1,:) {mustBeNumeric}
    reference (:,:) {mustBeNumeric,mustBeReal}
    rowOffset (1,1) double {mustBeInteger}=562
end
[R,N]=size(caf);[H,W]=size(reference);
assert(numel(whiteCaf)==N&&N>=500&&H>20&&W>20,'Unexpected geometry.');
assert(all(isfinite(caf),'all')&&all(isfinite(whiteCaf),'all'),'CAF must be finite.');
ref=double(reference);assert(all(isfinite(ref),'all'),'Reference must be finite.');
if max(ref,[],'all')>1,ref=ref/255;end
assert(min(ref,[],'all')>=0&&max(ref,[],'all')<=1,'Use grayscale [0,1] or uint8 scale.');
ink=1-ref;rowVariation=std(ink,0,2);
eligible=find(rowVariation>max(.01,.15*max(rowVariation)))-1;
assert(numel(eligible)>=8,'Reference has too few nonuniform rows.');
ys=eligible(unique(round(linspace(1,numel(eligible),min(96,numel(eligible))))));
residual=double(caf)-double(whiteCaf);
A=abs(residual(mod(rowOffset+ys,R)+1,:));A=centerBoth(A);
FA=fft(A,[],2);normA=norm(A,'fro');
assert(normA>0,'No measured variation after row/column DC removal.');
% Coarse cyclic correlation is an efficient seed only. Final fitting below
% uses the continuous flat-raster map, so wrapped text keeps the row carry.
widths=500:5:min(1100,N);coarse=zeros(numel(widths)*2*3,6);count=0;
for width=widths
    centers=((0:width-1)+.5)*W/width-.5;
    pattern=interp1(0:W-1,ink(ys+1,:).',centers,'linear',0).';
    for orientation=[1 -1]
        T=zeros(numel(ys),N);
        if orientation==1,T(:,1:width)=pattern;else,T(:,1:width)=fliplr(pattern);end
        T=centerBoth(T);denom=normA*norm(T,'fro');
        if denom<=eps,continue;end
        signed=real(ifft(sum(conj(fft(T,[],2)).*FA,1)))/denom;
        objective=abs(signed);
        for peak=1:3
            [value,index]=max(objective);if ~isfinite(value),break;end
            count=count+1;coarse(count,:)=[index-1,width,rowOffset,orientation,value,signed(index)];
            distance=abs(mod((0:N-1)-(index-1)+N/2,N)-N/2);
            objective(distance<=20)=-Inf;
        end
    end
end
coarse=coarse(1:count,:);assert(~isempty(coarse),'No alignment candidates.');
coarse=sortrows(coarse,-5);
% Retain six separated seeds per orientation, rather than only one basin.
seeds=zeros(0,6);
for orientation=[1 -1]
    pool=coarse(coarse(:,4)==orientation,:);local=zeros(0,6);
    for i=1:size(pool,1)
        x=pool(i,:);
        if isempty(local)||all(circularDistance(local(:,1),x(1),N)>12|abs(local(:,2)-x(2))>15)
            local(end+1,:)=x; %#ok<AGROW>
        end
        if size(local,1)>=6,break;end
    end
    seeds=[seeds;local]; %#ok<AGROW>
end
flat=reshape(residual.',[],1);M=numel(flat);
columns=linspace(0,W-1,min(192,W));
Tref=interp1(0:W-1,ink(ys+1,:).',columns,'linear').';
Tref=centerBoth(Tref);refNorm=norm(Tref,'fro');
assert(refNorm>0,'Reference variation disappeared after DC removal.');
trials=zeros(size(seeds,1)*5*11*9+600,6);nTrial=0;
for k=1:size(seeds,1)
    seed=seeds(k,:);
    for row=rowOffset+(-2:2)
        for width=max(500,seed(2)-10):2:min(min(1100,N),seed(2)+10)
            for x=seed(1)+(-8:2:8)
                [score,signed]=scoreMap(flat,M,N,ys,columns,W,Tref,refNorm,x,width,row,seed(4));
                nTrial=nTrial+1;trials(nTrial,:)=[mod(x,N),width,row+floor(x/N),seed(4),score,signed];
            end
        end
    end
end
trials=trials(1:nTrial,:);trials=sortrows(trials,-5);best=trials(1,:);
for row=max(rowOffset-3,best(3)-1):min(rowOffset+3,best(3)+1)
    for width=max(500,best(2)-2):.5:min(min(1100,N),best(2)+2)
        for x=best(1)+(-2:.25:2)
            [score,signed]=scoreMap(flat,M,N,ys,columns,W,Tref,refNorm,x,width,row,best(4));
            trials(end+1,:)=[mod(x,N),width,row+floor(x/N),best(4),score,signed]; %#ok<AGROW>
        end
    end
end
trials=sortrows(trials,-5);best=trials(1,:);
% Independent coordinate-density audit: same fitted transform, all columns.
fullColumns=0:W-1;Tfull=centerBoth(ink(ys+1,:));
[fullScore,fullSigned]=scoreMap(flat,M,N,ys,fullColumns,W,Tfull,norm(Tfull,'fro'), ...
    best(1),best(2),best(3),best(4));
outside=circularDistance(trials(:,1),best(1),N)>5|abs(trials(:,2)-best(2))>10| ...
    abs(trials(:,3)-best(3))>1|trials(:,4)~=best(4);
if any(outside),alternative=trials(find(outside,1),:);margin=best(5)-alternative(5);
else,alternative=nan(1,6);margin=NaN;end
orientationScores=[max(trials(trials(:,4)==1,5)),max(trials(trials(:,4)==-1,5))];
alignment=struct('origin_bins',best(1),'active_width_bins',best(2), ...
    'row_offset_zero_based',best(3),'orientation',best(4),'score',best(5));
alignment.audit=struct('scope','Supervised B1-only global display registration; not decoding or a fidelity estimate.', ...
    'reference_pixels_inserted',false,'row_scale',1,'source_size',[H W], ...
    'measured_size',[R N],'training_source_rows_zero_based',ys, ...
    'feature','Magnitude of complex CAF minus frozen B1 white CAF; row and column DC removed in each score.', ...
    'score_definition','Absolute normalized real correlation; best signed correlation also retained.', ...
    'signed_score',best(6),'all_columns_score',fullScore,'all_columns_signed_score',fullSigned, ...
    'coarse_width_range',[min(widths) max(widths)],'coarse_width_step',5, ...
    'coarse_seed_count',size(seeds,1),'refinement_trials',size(trials,1), ...
    'final_origin_step_bins',.25,'final_width_step_bins',.5, ...
    'orientation_best_scores_plus_minus',orientationScores, ...
    'best_competing_candidate',alternative,'peak_margin_outside_local_basin',margin, ...
    'candidate_columns',{{'origin_bins','active_width_bins','row_offset','orientation','absolute_correlation','signed_correlation'}}, ...
    'top_candidates',trials(1:min(20,size(trials,1)),:), ...
    'width_at_search_boundary',best(2)<=500||best(2)>=min(1100,N), ...
    'row_at_search_boundary',abs(best(3)-rowOffset)>=3, ...
    'origin_is_cyclic',true,'row_carry_preserved',true, ...
    'mapping','u=(row_offset+r)*N+origin+width*v; v=(c+.5)/W for +1, 1-(c+.5)/W for -1; measured centers at n+.5.', ...
    'interpolation','Linear complex interpolation on the circular R*N measured raster before magnitude.', ...
    'limitations',{{'Known reference is used to fit display geometry; alignment does not prove a decoded image.', ...
    'One global translation, horizontal width and optional horizontal reversal only; no nonrigid warp.', ...
    'Native full-period display should retain all N bins. Active-width resampling to W is a separate inferred display crop.', ...
    'Correlation margins are heuristic diagnostics, not confidence intervals.'}});
end

function [value,signed]=scoreMap(flat,M,N,rows,columns,W,target,targetNorm,x,width,row,orientation)
v=(columns+.5)/W;if orientation<0,v=1-v;end
u=(row+rows)*N+x+width*v;
z=u-.5;lo=floor(z);fraction=z-lo;
q=flat(mod(lo,M)+1).*(1-fraction)+flat(mod(lo+1,M)+1).*fraction;
q=centerBoth(abs(q));denom=norm(q,'fro')*targetNorm;
if denom<=eps,signed=0;else,signed=sum(q.*target,'all')/denom;end
value=abs(signed);
end

function y=centerBoth(x)
y=x-mean(x,1)-mean(x,2)+mean(x,'all');
end

function d=circularDistance(a,b,N)
d=abs(mod(a-b+N/2,N)-N/2);
end
