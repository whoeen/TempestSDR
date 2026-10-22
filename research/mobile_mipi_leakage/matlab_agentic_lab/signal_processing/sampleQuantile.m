function values = sampleQuantile(x, probabilities)
%SAMPLEQUANTILE Linear interpolation of sorted finite samples (base MATLAB).
x = sort(x(isfinite(x)));
assert(~isempty(x),'mobile:EmptyQuantile','No finite samples.');
position = 1+(numel(x)-1)*probabilities;
left = floor(position);
right = ceil(position);
values = reshape(x(left),size(position)).*(right-position) + ...
    reshape(x(right),size(position)).*(position-left);
same = left==right;
values(same) = x(left(same));
end
