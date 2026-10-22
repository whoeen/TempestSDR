function value = powerDb(powerValue)
%POWERDB dB power ratio with an explicit base MATLAB fallback.
if exist('pow2db','file')>0
    value = pow2db(max(powerValue,realmin));
else
    value = 10*log10(max(powerValue,realmin));
end
end
