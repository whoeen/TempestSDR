function raster = sampleFractionalRaster(iq, positions, shape, method)
%SAMPLEFRACTIONALRASTER Evaluate IQ at fractional sample positions (zero based).
%   This interpolation is a time-grid correction, not new measurement data or
%   an anti-aliasing filter. Receiver passband must fit the output time grid.
arguments
    iq (:,1) {mustBeNumeric}
    positions (:,1) double
    shape (1,2) double {mustBeInteger,mustBePositive}
    method (1,1) string {mustBeMember(method,["nearest","cubic"])} = "cubic"
end
assert(prod(shape)==numel(positions),'mobile:BadRasterShape','Position count does not fit raster.');
if method=="nearest"
    indices = round(positions)+1;
    assert(all(indices>=1 & indices<=numel(iq)),'mobile:RasterBounds','Nearest samples outside input.');
    sampled = iq(indices);
else
    base = floor(positions);
    fraction = single(positions-base);
    assert(all(base>=1 & base+3<=numel(iq)),'mobile:RasterBounds','Cubic support outside input.');
    p0 = iq(base);
    p1 = iq(base+1);
    p2 = iq(base+2);
    p3 = iq(base+3);
    sampled = 0.5*(2*p1+(-p0+p2).*fraction + ...
        (2*p0-5*p1+4*p2-p3).*fraction.^2 + ...
        (-p0+3*p1-3*p2+p3).*fraction.^3);
end
raster = reshape(sampled,shape(2),shape(1)).';
end
