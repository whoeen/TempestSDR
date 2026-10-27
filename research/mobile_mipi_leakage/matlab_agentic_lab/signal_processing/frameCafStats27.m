function [target,cafImage,powerImage]=frameCafStats27(Z,labels,N,lags,orders)
%FRAMECAFSTATS27 Midpoint cyclic statistics; columns are incoherently summed branches.
arguments
 Z {mustBeNumeric}
 labels (:,1) {mustBeNumeric}
 N (1,1) {mustBeInteger,mustBePositive}
 lags (:,1) {mustBeInteger,mustBeNonnegative}
 orders (:,1) {mustBeInteger,mustBePositive}
end
R=numel(labels);M=N*R;assert(size(Z,1)==M);labels=double(labels);
F=exp(-2i*pi*orders*(0:N-1)/N)/N;
target=complex(zeros(numel(orders),numel(lags),3));
powerImage=reshape(sum(abs(Z).^2,2),N,R).';cafImage=complex(nan(R,N));
for dd=1:numel(lags)
 d=lags(dd);n=(0:M-d-1)';prod=double(sum(Z(1+d:end,:).*conj(Z(1:end-d,:)),2));
 a=labels(floor(n/N)+1);b=labels(floor((n+d)/N)+1);mid=labels(floor((n+d/2)/N)+1);
 phase=mod(n+d/2,N);bin=floor(phase)+1;frac=mod(phase,1);bin2=mod(bin,N)+1;
 for cls=1:3
  keep=a==cls&b==cls&mid==cls;v=prod(keep);i=bin(keep);j=bin2(keep);w=frac(keep);
  su=accumarray(i,v.*(1-w),[N 1])+accumarray(j,v.*w,[N 1]);
  count=accumarray(i,1-w,[N 1])+accumarray(j,w,[N 1]);
  profile=su./max(count,1);target(:,dd,cls)=F*profile;
 end
 if d==1
  values=complex(nan(M,1));values(1:M-d)=prod;cafImage=reshape(values,N,R).';
 end
end
end
