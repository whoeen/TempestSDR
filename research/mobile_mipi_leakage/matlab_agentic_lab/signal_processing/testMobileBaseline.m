function tests = testMobileBaseline
%TESTMOBILEBASELINE Format, PSD calibration, fractional timing and filter tests.
tests = functiontests(localfunctions);
end

function testBigEndianReader(testCase)
filePath = string(tempname)+".rIs";
cleanup = onCleanup(@() deleteIfPresent(filePath));
fid = fopen(filePath,'w','ieee-be');
expectedI = int16([1 256 -32768 32767 -17]);
expectedQ = int16([-2 -257 32767 -32768 32]);
fwrite(fid,[expectedI;expectedQ],'int16');
fclose(fid);
[actual,info] = readRisIqBlock(filePath,1,3);
verifyEqual(testCase,actual,complex(single(expectedI(2:4).'),single(expectedQ(2:4).')));
verifyEqual(testCase,info.byte_offset,4);
verifyEqual(testCase,info.byte_count,12);
verifyError(testCase,@() readRisIqBlock(filePath,4,2),'mobile:ShortRead');
end

function testComplexTonePsd(testCase)
fs = 8192;
n = (0:16383).';
amplitude = 3;
toneHz = 1024;
x = amplitude*exp(1j*2*pi*toneHz*n/fs);
[psd,f] = estimateWelchPsd(x,periodicHann(1024),512,1024,fs,"centered");
[~,index] = max(psd);
verifyEqual(testCase,f(index),toneHz,'AbsTol',1e-12);
verifyEqual(testCase,sum(psd)*fs/1024,amplitude^2,'RelTol',1e-10);
[powerDensity,~,~,~] = estimateSpectrogram(x,periodicHann(1024),512,1024,fs);
verifyEqual(testCase,sum(powerDensity,1)*fs/1024, ...
    amplitude^2*ones(1,size(powerDensity,2)),'RelTol',1e-10);
end

function testRealToneOneSided(testCase)
fs = 8192;
n = (0:16383).';
x = 2*cos(2*pi*1024*n/fs);
[psd,~] = estimateWelchPsd(x,periodicHann(1024),512,1024,fs,"onesided");
verifyEqual(testCase,sum(psd)*fs/1024,2,'RelTol',1e-10);
end

function testCubicLinearSignal(testCase)
n = single((0:99).');
x = complex(2*n+3,-0.7*n+2);
positions = (10.25:1:33.25).';
actual = sampleFractionalRaster(x,positions,[4 6],"cubic");
expected = complex(2*positions+3,-0.7*positions+2);
expected = reshape(expected,6,4).';
verifyEqual(testCase,double(actual),expected,'AbsTol',2e-5);
end

function testDdcPreservesComplexPhase(testCase)
fs = 200e3;
t = (0:19999).'/fs;
x = 2*exp(1j*(2*pi*30000*t+0.4));
[actual,info] = conditionIq(x,fs,OffsetHz=30000,Decimation=20);
edge = max(20,info.edge_samples_to_exclude);
interior = actual(edge+1:end-edge);
verifyEqual(testCase,mean(interior),2*exp(1j*0.4),'AbsTol',2e-3);
verifyEqual(testCase,info.output_fs_hz,10000);
end

function testExportLosslessEndian(testCase)
input = string(tempname)+".rIs";
output = string(tempname)+".iq16le";
cleanup = onCleanup(@() deleteExports(input,output));
fid = fopen(input,'w','ieee-be');
samples = int16([1 -32768 2345;256 32767 -2345]);
fwrite(fid,samples,'int16');
fclose(fid);
exportRisForTempest(input,output,1e6,SampleCount=3,BlockSamples=2);
fid = fopen(output,'r','ieee-le');
actual = fread(fid,[2 3],'int16=>int16');
fclose(fid);
verifyEqual(testCase,actual,samples);
verifyError(testCase,@() exportRisForTempest(input,input,1e6,SampleCount=3),'mobile:ImmutableInput');
end

function deleteExports(input,output)
deleteIfPresent(input);
deleteIfPresent(output);
deleteIfPresent(output+".json");
end

function testRejectUninformativeClutterTraining(testCase)
verifyError(testCase,@() learnClutterSubspace(zeros(8,6),1,"independent zero capture"), ...
    'mobile:DegenerateTraining');
end

function testMatchedSubspaceKnownComponents(testCase)
rows = 64;
n = (0:rows-1).';
targetBasis = exp(1j*2*pi*5*n/rows);
nuisanceBasis = exp(1j*2*pi*13*n/rows);
target = targetBasis*[1 2 3];
nuisance = nuisanceBasis*[20 17 25];
[actualTarget,actualNuisance,residual,~] = separateMatchedSubspace(target+nuisance, ...
    targetBasis,NuisanceBasis=nuisanceBasis,TargetProvenance="synthetic known tone 5", ...
    NuisanceProvenance="synthetic known tone 13");
verifyEqual(testCase,actualTarget,target,'AbsTol',1e-10);
verifyEqual(testCase,actualNuisance,nuisance,'AbsTol',1e-10);
verifyLessThan(testCase,norm(residual,'fro'),1e-10);
verifyError(testCase,@() separateMatchedSubspace(target,targetBasis, ...
    NuisanceBasis=targetBasis,TargetProvenance="same synthetic source", ...
    NuisanceProvenance="same synthetic source"),'mobile:NonidentifiableSubspaces');
end

function testRpcaReconstruction(testCase)
randomState = rng();
cleanup = onCleanup(@() rng(randomState));
rng(43,'twister');
lowRank = randn(40,2)*randn(2,36);
sparsePart = zeros(40,36);
indices = randperm(numel(sparsePart),round(0.03*numel(sparsePart)));
sparsePart(indices) = 15*sign(randn(size(indices)));
[estimatedLow,~,residual,metadata] = separateRpca(lowRank+sparsePart, ...
    MaxIterations=500,Tolerance=1e-7,MatrixAxes="synthetic 40 features x 36 observations");
verifyTrue(testCase,metadata.converged);
verifyLessThan(testCase,norm(residual,'fro')/norm(lowRank+sparsePart,'fro'),1.1e-7);
verifyLessThan(testCase,norm(estimatedLow-lowRank,'fro')/norm(lowRank,'fro'),0.1);
end

function deleteIfPresent(filePath)
if isfile(filePath)
    delete(filePath);
end
end
