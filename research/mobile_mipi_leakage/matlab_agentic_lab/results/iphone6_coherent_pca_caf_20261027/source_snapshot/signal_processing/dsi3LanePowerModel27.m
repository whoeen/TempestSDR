function model = dsi3LanePowerModel27(packet, rateHz, f0Hz, nGrid)
%DSI3LANEPOWERMODEL27 Generate three idealized positive-RF lane waveforms.
%   MODEL = dsi3LanePowerModel27(PACKET,RATEHZ,F0HZ,NGRID) treats each row
%   of PACKET.hsBits as one simultaneous bit interval on three lanes.
%   PACKET.hsValid has the same N-by-3 size. Valid bits have NRZ levels
%   -1/+1; invalid positions and the remainder of the period have level 0.
%   The packet starts at t=0 and repeats every 1/F0HZ seconds. PHY HS-zero,
%   HS-prepare, HS-trail and an actual common-mode transfer function are NOT
%   modeled. PACKET must already contain any requested SoT bits.
%
%   MODEL.waveforms is a 1-by-3 cell array. Each cell contains NGRID-by-3
%   complex lane waveforms, with emission names nrz, signed_edge and
%   unsigned_edge. Grid row k corresponds to phase (k-1)/NGRID. Only the
%   positive-frequency Fourier-series part in 40--160 MHz is retained;
%   no factor of two for a conventional analytic signal is applied.
%   A 5 MHz raised-cosine transition is used at each RF band edge.
%
%   The output is a limited forward-model hypothesis, not recovered IQ.
%   Sample/interpolate complex waveforms at the measurement timestamps,
%   then form power and apply the same binning as the measured data.
%   Anti-alias resampling of power alone does not reproduce that operation.

arguments
    packet (1,1) struct
    rateHz (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
    f0Hz (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBePositive}
    nGrid (1,1) {mustBeNumeric, mustBeReal, mustBeFinite, mustBeInteger, mustBePositive} = 16384
end

if ~all(isfield(packet, ["hsBits", "hsValid"]))
    error("dsi3LanePowerModel27:PacketFields", ...
        "packet must contain hsBits and hsValid.");
end
bits = packet.hsBits;
valid = packet.hsValid;
if ~(isnumeric(bits) || islogical(bits)) || ~isreal(bits) || ...
        ~ismatrix(bits) || isempty(bits) || size(bits, 2) ~= 3 || ...
        any(~isfinite(bits), "all") || any((bits ~= 0) & (bits ~= 1), "all")
    error("dsi3LanePowerModel27:Bits", ...
        "hsBits must be a nonempty, finite, binary N-by-3 matrix.");
end
if ~(isnumeric(valid) || islogical(valid)) || ~isreal(valid) || ...
        ~isequal(size(valid), size(bits)) || any(~isfinite(valid), "all") || ...
        any((valid ~= 0) & (valid ~= 1), "all")
    error("dsi3LanePowerModel27:Validity", ...
        "hsValid must be a binary matrix with the same size as hsBits.");
end

rateHz = double(rateHz);
f0Hz = double(f0Hz);
nGrid = double(nGrid);
periodSeconds = 1/f0Hz;
packetSeconds = size(bits, 1)/rateHz;
if packetSeconds > periodSeconds + 32*eps(periodSeconds)
    error("dsi3LanePowerModel27:PacketTooLong", ...
        "Packet duration %.12g s exceeds the period %.12g s.", ...
        packetSeconds, periodSeconds);
end

bandHz = [40e6, 160e6];
taperHz = 5e6;
edgeReferenceHz = 100e6;
firstHarmonic = ceil(bandHz(1)/f0Hz);
lastHarmonic = floor(bandHz(2)/f0Hz);
if firstHarmonic > lastHarmonic || lastHarmonic >= nGrid/2
    error("dsi3LanePowerModel27:GridBandwidth", ...
        "nGrid must resolve all positive RF harmonics through 160 MHz.");
end
harmonics = (firstHarmonic:lastHarmonic).';
frequencyHz = harmonics*f0Hz;
bandWeights = ones(size(frequencyHz));
lowerEdge = frequencyHz < bandHz(1) + taperHz;
upperEdge = frequencyHz > bandHz(2) - taperHz;
bandWeights(lowerEdge) = 0.5*(1 - cos(pi* ...
    (frequencyHz(lowerEdge)-bandHz(1))/taperHz));
bandWeights(upperEdge) = 0.5*(1 - cos(pi* ...
    (bandHz(2)-frequencyHz(upperEdge))/taperHz));

% Including both boundary edges makes this the exact periodic NRZ integral.
levels = (2*double(bits) - 1).*double(valid);
levelChanges = diff([zeros(1, 3); levels; zeros(1, 3)], 1, 1);
edgeRows = find(any(levelChanges ~= 0, 2));
edgeTimesSeconds = (edgeRows - 1)/rateHz;
edgeChanges = levelChanges(edgeRows, :);
signedSums = complex(zeros(numel(harmonics), 3));
unsignedSums = complex(zeros(numel(harmonics), 3));
edgeBlockSize = 256;
for firstEdge = 1:edgeBlockSize:numel(edgeRows)
    indices = firstEdge:min(firstEdge+edgeBlockSize-1, numel(edgeRows));
    edgePhasors = exp((-1i*2*pi*frequencyHz)*edgeTimesSeconds(indices).');
    signedSums = signedSums + edgePhasors*edgeChanges(indices, :);
    unsignedSums = unsignedSums + edgePhasors*(abs(edgeChanges(indices, :))/2);
end

% d/dt normalized by 2*pi*fRef gives signed_edge = j*f/fRef * nrz.
nrzCoefficients = signedSums./(1i*2*pi*frequencyHz*periodSeconds);
signedCoefficients = signedSums/(2*pi*edgeReferenceHz*periodSeconds);
unsignedCoefficients = unsignedSums/(2*pi*edgeReferenceHz*periodSeconds);
coefficients = {nrzCoefficients, signedCoefficients, unsignedCoefficients};
waveforms = cell(1, 3);
for emissionIndex = 1:3
    coefficients{emissionIndex} = coefficients{emissionIndex}.*bandWeights;
    gridCoefficients = complex(zeros(nGrid, 3));
    gridCoefficients(harmonics + 1, :) = coefficients{emissionIndex};
    waveforms{emissionIndex} = ifft(gridCoefficients, [], 1)*nGrid;
end

model = struct();
model.waveforms = waveforms;
model.emissionNames = ["nrz", "signed_edge", "unsigned_edge"];
model.coefficients = coefficients;
model.harmonics = harmonics;
model.frequencyHz = frequencyHz;
model.bandWeights = bandWeights;
model.phaseGrid = (0:nGrid-1).'/nGrid;
model.rateHz = rateHz;
model.f0Hz = f0Hz;
model.periodSeconds = periodSeconds;
model.packetSeconds = packetSeconds;
model.packetDuty = packetSeconds/periodSeconds;
model.nGrid = nGrid;
model.bandHz = bandHz;
model.taperHz = taperHz;
model.edgeReferenceHz = edgeReferenceHz;
model.packetStartSeconds = 0;
model.activeLevelConvention = "Valid bits 0/1 map to -1/+1; invalid/off is 0.";
model.unsignedEdgeConvention = "abs(delta level)/2; a full NRZ transition has weight 1.";
model.frequencyConvention = "Positive RF Fourier-series part only; no factor two.";
model.assumptions = [ ...
    "One supplied packet repeats at f0; this does not establish a physical packet/row rate.", ...
    "SoT and packet fields must already be provided in hsBits; no protocol fields are inferred here.", ...
    "Bit intervals are ideal rectangular NRZ; receiver passband uses an assumed cosine edge taper.", ...
    "PHY HS-prepare, HS-zero, HS-trail, LP signaling and clock-lane emission are omitted.", ...
    "Lane skew, lane coupling, common-mode conversion and the actual RF channel are unknown.", ...
    "Packet boundaries produce modeled transitions between NRZ levels and zero idle.", ...
    "Outputs are synthetic diagnostics, not recovered bits or measured common-mode emission."];
end
