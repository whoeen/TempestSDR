function metadata = renderPcaCodebookValidation27(pcaOut)
%RENDERPCACODEBOOKVALIDATION27 Plot frozen held-out codebook tests after PCA.
%   Reads the completed bank and per-method JSON files. No fitting, candidate
%   selection, IQ processing or interpretation as physical decoding occurs.
%   Uniform-state means the stacked black/white CAF target. "Strongest wrong"
%   is the wrong-codeword winner selected on B1, not on B2/B3.
arguments
    pcaOut (1,1) string
end
bankPath=fullfile(pcaOut,"pca_caf_codebook_bank.json");
bank=jsondecode(fileread(bankPath));
assert(string(bank.status)=="complete","Codebook bank is not complete.");
methods=string(bank.methods(:));
numberMethods=numel(methods);
numberRows=2*numberMethods;
uniformNmse=zeros(numberRows,2);textNmse=zeros(numberRows,3);
uniformPhase=zeros(numberRows,2);textPhase=zeros(numberRows,2);
uniformCoherence=zeros(numberRows,2);textCoherence=zeros(numberRows,2);
tickLabels=strings(numberRows,1);
identities=cell(numberMethods,1);
for ii=1:numberMethods
    safeName=regexprep(lower(methods(ii)),"[^a-z0-9_-]","_");
    methodPath=fullfile(pcaOut,"codebook_"+safeName,"pca_caf_codebook.json");
    record=jsondecode(fileread(methodPath));
    assert(string(record.status)=="complete","A method fit is not complete.");
    assert(string(record.reference_text_validation.status)=="complete", ...
        "Known-text forward validation is missing.");
    textValid=findText(record.reference_text_validation,record.valid.name);
    textMatched=findText(record.reference_text_validation,record.matched_control.name);
    textWrong=findText(record.reference_text_validation,record.control.name);
    identities{ii}=struct("method",methods(ii), ...
        "valid",string(record.valid.name), ...
        "same_family_wrong",string(record.matched_control.name), ...
        "strongest_wrong",string(record.control.name), ...
        "valid_rate_hypothesis_hz",record.valid.rate_hz, ...
        "wrong_rate_hypothesis_hz",record.control.rate_hz);
    for block=2:3
        row=2*(ii-1)+block-1;
        tickLabels(row)=methods(ii)+" B"+block;
        a=record.valid.blocks(block);b=record.control.blocks(block);
        uniformNmse(row,:)=[a.nmse,b.nmse];
        uniformPhase(row,:)=[a.phase_deg,b.phase_deg];
        uniformCoherence(row,:)=[a.abs_coherence,b.abs_coherence];
        va=textValid.blocks(block);ma=textMatched.blocks(block);
        wa=textWrong.blocks(block);
        textNmse(row,:)=[va.nmse,ma.nmse,wa.nmse];
        textPhase(row,:)=[va.phase_deg,wa.phase_deg];
        textCoherence(row,:)=[va.abs_coherence,wa.abs_coherence];
    end
end
wrongBetter=uniformNmse(:,2)<uniformNmse(:,1);
textWorseThanZero=textNmse>1;
blue=[0.12 0.38 0.70];red=[0.77 0.16 0.18];orange=[0.88 0.52 0.15];
figureHandle=figure("Name","PCA codebook held-out validation", ...
    "Color","w","Position",[100 60 1560 1180]);
layout=tiledlayout(figureHandle,3,2,"TileSpacing","compact","Padding","compact");
title(layout,{"Frame-PCA codebook validation: B2 / B3 held-out tests"; ...
    "Complex CAF model fit is not physical packet or character decoding"}, ...
    "FontSize",18,"FontWeight","bold","Interpreter","none");

ax=nexttile(layout);
drawBars(ax,uniformNmse,tickLabels,[blue;red], ...
    ["Valid-form candidate","Strongest wrong (B1 selected)"]);
yline(ax,1,"k--","Zero predictor = 1","LineWidth",1.3, ...
    "LabelHorizontalAlignment","left","HandleVisibility","off");
ylim(ax,[0,max(1.12,1.13*max(uniformNmse,[],"all"))]);
ylabel(ax,"Weighted complex NMSE (lower is better)");
title(ax,sprintf("Black / white: wrong codeword wins %d / %d tests", ...
    nnz(wrongBetter),numel(wrongBetter)),"Interpreter","none");

ax=nexttile(layout);
drawBars(ax,textNmse,tickLabels,[blue;orange;red], ...
    ["Valid form","Same-family wrong","Strongest wrong"]);
yline(ax,1,"k--","Zero predictor = 1","LineWidth",1.3, ...
    "LabelHorizontalAlignment","left","HandleVisibility","off");
ylim(ax,[0,1.14*max([1;textNmse(:)])]);
ylabel(ax,"Known-text forward NMSE");
title(ax,"Text: all shown predictions worse than zero", ...
    "Interpreter","none","Color",red);

ax=nexttile(layout);
drawPhases(ax,uniformPhase,tickLabels,blue,red);
phaseLimit=max(8,1.3*max(abs(uniformPhase),[],"all"));
ylim(ax,[-phaseLimit,phaseLimit]);
title(ax,"Black / white: aggregate CAF model phase","Interpreter","none");
ylabel(ax,"arg(sum w conj(R_{obs}) R_{model}) [deg]");

ax=nexttile(layout);
drawPhases(ax,textPhase,tickLabels,blue,red);
ylim(ax,[-180,180]);yticks(ax,-180:60:180);
title(ax,"Text phase: mismatched prediction, not RF carrier phase", ...
    "Interpreter","none");
ylabel(ax,"Aggregate CAF phase [deg]");

ax=nexttile(layout);
axis(ax,"off");
title(ax,"Codeword identities selected on B1","Interpreter","none");
identityLines=strings(3*numberMethods+3,1);
for ii=1:numberMethods
    r=identities{ii};
    identityLines(3*ii-2)=r.method+": "+r.valid;
    identityLines(3*ii-1)="    wrong: "+r.strongest_wrong;
    identityLines(3*ii)="    same-family: "+r.same_family_wrong;
end
identityLines(end-2)="B1 selects channels and candidates; B2/B3 remain frozen.";
identityLines(end-1)="All methods use the same rawgrid B1 precision weights.";
identityLines(end)="Rate, timing and emission hypotheses are inherited; no full new search.";
text(ax,0,0.96,join(identityLines,newline),"Units","normalized", ...
    "VerticalAlignment","top","FontName","Consolas","FontSize",10, ...
    "Interpreter","none");

ax=nexttile(layout);
axis(ax,"off");
title(ax,"Interpretation of these tests","Color",red,"Interpreter","none");
if all(wrongBetter)
    failure1="The strongest wrong codeword fits every held-out black/white target better.";
else
    failure1=sprintf("A wrong codeword fits better in %d/%d held-out black/white tests.", ...
        nnz(wrongBetter),numel(wrongBetter));
end
if all(textWorseThanZero,"all")
    failure2="All known-text forward NMSE values exceed 1: worse than predicting zero.";
else
    failure2="Inspect the NMSE=1 line; values above it fail the zero-prediction baseline.";
end
selectedIndex=find(lower(methods)=="selected",1);
if isempty(selectedIndex)
    selectedLine="Known-text patterns were never used to refit the channels.";
else
    selectedRows=2*selectedIndex-1:2*selectedIndex;
    selectedLine=sprintf("CAF-selected PC, valid text NMSE: B2 %.4f; B3 %.4f.", ...
        textNmse(selectedRows(1),1),textNmse(selectedRows(2),1));
end
notes=[string(failure1);"";string(failure2);"";string(selectedLine); ...
    "Known screenshot patterns provide a forward test only; no decoding claim.";""; ...
    sprintf("Valid text |coherence| range: %.3f to %.3f.", ...
        min(textCoherence(:,1)),max(textCoherence(:,1))); ...
    "Small coherence makes aggregate phase weak evidence."; ...
    "The phase panels do not show an absolute RF or pixel-color phase.";""; ...
    "Changing NMSE across methods is not an SNR measurement."; ...
    "High-order grid alias mixing remains outside this forward model."];
text(ax,0,0.97,join(notes,newline),"Units","normalized", ...
    "VerticalAlignment","top","FontSize",11,"Interpreter","none");

pngPath=fullfile(pcaOut,"pca_05_codebook_validation.png");
figPath=fullfile(pcaOut,"pca_05_codebook_validation.fig");
exportgraphics(figureHandle,pngPath,"Resolution",180);
savefig(figureHandle,figPath);
metadata=struct("status","complete","methods",methods, ...
    "row_order",tickLabels,"blocks",[2,3], ...
    "uniform_nmse_columns",["valid","strongest_wrong"], ...
    "uniform_nmse",uniformNmse, ...
    "text_nmse_columns",["valid","same_family_wrong","strongest_wrong"], ...
    "text_nmse",textNmse, ...
    "uniform_phase_deg",uniformPhase,"text_phase_deg",textPhase, ...
    "uniform_abs_coherence",uniformCoherence,"text_abs_coherence",textCoherence, ...
    "wrong_better_uniform",wrongBetter, ...
    "text_worse_than_zero",textWorseThanZero, ...
    "candidate_identities",[identities{:}], ...
    "selection_scope","Candidates and channels selected on B1 only.", ...
    "phase_scope","Weighted complex inner-product phase; not RF absolute phase.", ...
    "known_reference_scope","Text forward prediction only.", ...
    "packet_decoded",false,"physical_lane_channels_identified",false, ...
    "png_path",pngPath,"fig_path",figPath);
writeJson(fullfile(pcaOut,"pca_codebook_render_summary.json"),metadata);
end

function candidate=findText(report,name)
names=string({report.candidates.candidate});
index=find(names==string(name));
assert(isscalar(index),"Missing or duplicate text candidate: %s",string(name));
candidate=report.candidates(index);
end

function drawBars(ax,values,tickLabels,colors,legendNames)
colororder(ax,colors);
bars=bar(ax,1:size(values,1),values,"grouped");
hold(ax,"on");
for ii=1:numel(bars)
    label=compose("%.3f",bars(ii).YData);
    offset=0.012*max(1,max(values,[],"all"));
    text(ax,bars(ii).XEndPoints,bars(ii).YEndPoints+offset,label, ...
        "HorizontalAlignment","center","VerticalAlignment","bottom", ...
        "FontSize",8,"Color",colors(ii,:),"Interpreter","none");
end
hold(ax,"off");
xticks(ax,1:numel(tickLabels));xticklabels(ax,tickLabels);xtickangle(ax,15);
grid(ax,"on");ax.FontSize=10;
legend(ax,bars,legendNames,"Location","northoutside", ...
    "Orientation","horizontal","FontSize",9,"Interpreter","none");
end

function drawPhases(ax,values,tickLabels,blue,red)
x=(1:size(values,1)).';
h1=plot(ax,x-0.07,values(:,1),"o","Color",blue, ...
    "MarkerFaceColor",blue,"MarkerSize",7,"LineStyle","none");
hold(ax,"on");
h2=plot(ax,x+0.07,values(:,2),"s","Color",red, ...
    "MarkerFaceColor",red,"MarkerSize",7,"LineStyle","none");
yline(ax,0,"k:","HandleVisibility","off");
hold(ax,"off");
xlim(ax,[0.5,numel(tickLabels)+0.5]);
xticks(ax,1:numel(tickLabels));xticklabels(ax,tickLabels);xtickangle(ax,15);
grid(ax,"on");ax.FontSize=10;
legend(ax,[h1,h2],["Valid form","Strongest wrong"], ...
    "Location","northoutside","Orientation","horizontal", ...
    "FontSize",9,"Interpreter","none");
end

function writeJson(path,value)
fid=fopen(path,"w","n","UTF-8");assert(fid>=0);
cleanup=onCleanup(@()fclose(fid));
fwrite(fid,jsonencode(value,"PrettyPrint",true),"char");
end
