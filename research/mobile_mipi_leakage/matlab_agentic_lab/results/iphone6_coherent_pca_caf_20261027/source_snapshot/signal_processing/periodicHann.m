function window = periodicHann(lengthWindow)
%PERIODICHANN Periodic Hann window, requiring only base MATLAB.
arguments
    lengthWindow (1,1) double {mustBeInteger,mustBePositive}
end
window = 0.5 - 0.5*cos(2*pi*(0:lengthWindow-1).'/lengthWindow);
end
