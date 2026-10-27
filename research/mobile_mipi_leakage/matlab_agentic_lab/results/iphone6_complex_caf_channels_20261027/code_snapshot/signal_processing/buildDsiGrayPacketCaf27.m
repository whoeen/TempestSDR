function packet = buildDsiGrayPacketCaf27(pixelValues,mode,vc,controlKind)
%BUILDDSIGRAYPACKETCAF27 Make a conditional RGB888 3-lane row codeword.
%   P = buildDsiGrayPacketCaf27(PIXELS,MODE,VC,CONTROL)
%   PIXELS is one uint8 row of 750 grayscale values, expanded as R=G=B.
%   MODE: "video", "2C", or "3C". VC: 0..3. CONTROL: "valid",
%   "header-byte-permutation", "header-bit-order-reversed",
%   "shuffled-sync-header", or "geometry".
%
%   One HS starts on lane0, with parallel B8 SoT once. laneValid/hsValid
%   exclude unused end-lane padding. HS prepare/zero/trail, EoTp and clock
%   are omitted exactly as in buildDsi3LaneCodebook27.
%
%   ECC, CRC, byte striping and deterministic controls are copied from the
%   audited buildDsi3LaneCodebook27 implementation. Shuffle seed271003 and
%   chosen positions match that implementation without changing global RNG.
%
%   Returned hsBits/hsValid are authoritative for forward modeling. For a
%   geometry control, packetBytes/header/payload/CRC are reference metadata,
%   not an encoding of the control waveform. Semantic fields on other
%   intentionally invalid headers likewise describe the valid reference.
%
%   Known-reference text rows may test a frozen channel learned from black/
%   white rows. Their predicted waveform is NOT recovered RGB or decoded text.
arguments
    pixelValues (1,750) uint8
    mode (1,1) string {mustBeMember(mode,["video","2C","3C"])} = "video"
    vc (1,1) double {mustBeInteger,mustBeGreaterThanOrEqual(vc,0),mustBeLessThanOrEqual(vc,3)} = 0
    controlKind (1,1) string {mustBeMember(controlKind,["valid", ...
        "header-byte-permutation","header-bit-order-reversed", ...
        "shuffled-sync-header","geometry"])} = "valid"
end
verifyIndependentVectors();
if all(pixelValues==255)
    color="white";
elseif all(pixelValues==0)
    color="black";
else
    color="gray-row";
end
if mode=="video"
    reference=makeLongPacket(pixelValues,62,vc,[],"video-"+color+"-vc"+vc);
else
    command=hex2dec(char(mode));
    label="dcs-"+mode+"-"+color;
    if vc~=0,label=label+"-vc"+vc;end
    reference=makeLongPacket(pixelValues,57,vc,command,label);
end
if controlKind=="valid"
    packet=reference;
elseif controlKind=="geometry"
    packet=reference;
    packet.protocolCandidate=false;
    packet.label="geometry-only-ref-"+reference.label;
    packet.controlKind="constant-level-geometry-only";
    packet.controlReference=reference.label;
    packet.hsBits=reference.hsValid;
    packet.laneBits=reference.laneValid;
    packet.laneBytes=uint8(255)*uint8(reference.laneByteValid);
    packet.phySyncBytes=uint8([255 255 255]);
    packet.note="Geometry-only null: hsBits and hsValid are authoritative. " + ...
        "All valid intervals have logical1, including nominal SoT time; " + ...
        "no SoT/header/payload/CRC structure is transmitted. The packet " + ...
        "bytes and semantic fields describe the valid reference only.";
else
    variants=makeControls(reference);
    kinds=["header-byte-permutation","header-bit-order-reversed","shuffled-sync-header"];
    packet=variants(kinds==controlKind);
    packet.label="control-"+controlKind+"-ref-"+reference.label;
end
assert(isequal(packet.hsValid,reference.hsValid),'DSI:CafControlValidity', ...
    'A control changed the transmitted time support.');
assert(isequal(size(packet.hsBits),size(reference.hsBits)),'DSI:CafControlSize', ...
    'A control changed the HS bit-array size.');
if controlKind=="shuffled-sync-header"
    assert(isequal(sum(packet.hsBits,1),sum(reference.hsBits,1)), ...
        'DSI:CafShuffleCount','Shuffled control changed per-lane bit counts.');
end
end

function packet = makeLongPacket(pixelValues, dataType, vc, command, label)
    pixelValues = uint8(pixelValues(:).');
    rgbPayload = reshape(repmat(pixelValues, 3, 1), 1, []);
    payload = [uint8(command), rgbPayload];
    wordCount = numel(payload);
    identifier = bitor(uint8(dataType), bitshift(uint8(vc), 6));
    header = [identifier, uint8(mod(wordCount, 256)), ...
        uint8(floor(wordCount / 256))];
    header(4) = headerEcc(header);
    checksum = payloadCrc(payload);
    crcBytes = uint8([bitand(checksum, uint16(255)), bitshift(checksum, -8)]);
    packet = struct('label', label, 'dataType', uint8(dataType), ...
        'virtualChannel', uint8(vc), 'wordCount', uint16(wordCount), ...
        'pixelCount', numel(pixelValues), 'pixelValues', pixelValues, ...
        'command', uint8(command), 'header', header, 'payload', payload, ...
        'crc', checksum, 'crcBytes', crcBytes, ...
        'packetBytes', [header, payload, crcBytes], ...
        'firstPacketStartLaneZeroBased', 0, 'protocolCandidate', true, ...
        'controlKind', "", 'controlReference', "", ...
        'note', "First long packet after parallel SoT; no other PHY timing modeled.");
    packet = addBitViews(packet);
end

function packet = addBitViews(packet)
    packetBytes = packet.packetBytes;
    numBytes = numel(packetBytes);
    byteIndex = (0:numBytes-1).';
    laneIndex = mod(byteIndex, 3);
    byteSlot = floor(byteIndex / 3);
    numSlots = ceil(numBytes / 3);
    laneBytes = zeros(numSlots, 3, 'uint8');
    laneByteValid = false(numSlots, 3);
    mapIndex = sub2ind([numSlots, 3], byteSlot+1, laneIndex+1);
    laneBytes(mapIndex) = packetBytes;
    laneByteValid(mapIndex) = true;
    laneBits = false(numSlots*8, 3);
    for lane = 1:3
        laneBits(:, lane) = bytesToLsbBits(laneBytes(:, lane));
    end
    syncBits = repmat(bytesToLsbBits(uint8(184)), 1, 3);
    packet.laneBytes = laneBytes;
    packet.laneByteValid = laneByteValid;
    packet.laneByteLengths = sum(laneByteValid, 1);
    packet.laneBitLengths = 8 * packet.laneByteLengths;
    packet.laneBits = laneBits;
    packet.laneValid = repelem(laneByteValid, 8, 1);
    packet.hsBits = [syncBits; laneBits];
    packet.hsValid = [true(8, 3); packet.laneValid];
    packet.hsBitLengths = packet.laneBitLengths + 8;
    packet.phySyncBytes = uint8([184 184 184]);
    packet.byteMapping = struct('packetByteIndexZeroBased', byteIndex, ...
        'laneZeroBased', laneIndex, 'laneByteSlotZeroBased', byteSlot, ...
        'byteValues', packetBytes(:), 'isHeader', byteIndex < 4, ...
        'isPayload', byteIndex >= 4 & byteIndex < numBytes-2, ...
        'isCrc', byteIndex >= numBytes-2);
end

function bits = bytesToLsbBits(bytes)
    bytes = uint8(bytes(:));
    bitRows = false(numel(bytes), 8);
    for position = 1:8
        bitRows(:, position) = logical(bitget(bytes, position));
    end
    bits = reshape(bitRows.', [], 1);
end

function bytes = lsbBitsToBytes(bits)
    bitRows = reshape(double(bits), 8, []).';
    bytes = uint8(bitRows * (2.^(0:7)).');
end

function controls = makeControls(reference)
    cells = cell(1, 3);
    changed = reference;
    changed.packetBytes(1:4) = reference.header([2 1 3 4]);
    changed.header = changed.packetBytes(1:4);
    changed = addBitViews(changed);
    cells{1} = labelControl(changed, reference, "header-byte-permutation", ...
        "Swaps DI and WC-low without recomputing ECC. Same total length.");

    changed = reference;
    headerBits = reshape(bytesToLsbBits(reference.header), 8, []);
    changed.header = lsbBitsToBytes(reshape(flipud(headerBits), [], 1)).';
    changed.packetBytes(1:4) = changed.header;
    changed = addBitViews(changed);
    cells{2} = labelControl(changed, reference, "header-bit-order-reversed", ...
        "Each header byte is transmitted MSB-first; payload and SoT unchanged.");

    changed = reference;
    shuffledHs = reference.hsBits;
    % Shuffle only known SoT/header positions. Keep the first and final known
    % bit in each lane fixed; the interior shuffle preserves its zero/one count.
    localStream = RandStream('mt19937ar', 'Seed', 271003);
    for lane = 1:3
        headerSlots = reference.byteMapping.laneByteSlotZeroBased( ...
            reference.byteMapping.isHeader & ...
            reference.byteMapping.laneZeroBased == lane-1);
        known = (1:8).';
        for slot = headerSlots.'
            known = [known; (8+slot*8+(1:8)).']; %#ok<AGROW>
        end
        interior = known(2:end-1);
        old = shuffledHs(interior, lane);
        order = randperm(localStream, numel(interior));
        replacement = old(order);
        if isequal(replacement, old)
            replacement = circshift(old, 1);
        end
        shuffledHs(interior, lane) = replacement;
        assert(sum(replacement) == sum(old), ...
            'DSI:ControlCount', 'Shuffled control changed bit counts.');
    end
    changed.laneBits = shuffledHs(9:end, :);
    changed = replacePacketBytesFromLaneBits(changed);
    changed = addBitViews(changed);
    changed.hsBits(1:8, :) = shuffledHs(1:8, :);
    for lane = 1:3
        changed.phySyncBytes(lane) = lsbBitsToBytes(changed.hsBits(1:8, lane));
    end
    cells{3} = labelControl(changed, reference, "shuffled-sync-header", ...
        "Deterministic local-RNG shuffle of known sync/header interior bits; " + ...
        "per-lane counts and total length preserved. Not a legal SoT model.");
    controls = [cells{:}];
end

function packet = replacePacketBytesFromLaneBits(packet)
    for lane = 1:3
        laneByteValues = lsbBitsToBytes(packet.laneBits(:, lane));
        indices = find(packet.byteMapping.laneZeroBased == lane-1);
        slots = packet.byteMapping.laneByteSlotZeroBased(indices)+1;
        packet.packetBytes(indices) = laneByteValues(slots);
    end
    packet.header = packet.packetBytes(1:4);
end

function packet = labelControl(packet, reference, kind, note)
    packet.label = "control-" + kind;
    packet.protocolCandidate = false;
    packet.controlKind = kind;
    packet.controlReference = reference.label;
    packet.note = note + " Original semantic DT/WC/VC fields describe the " + ...
        "reference, not the intentionally invalid transmitted header.";
end

function value = headerEcc(header)
    columns = uint8([7 11 13 14 19 21 22 25 26 28 35 37 ...
        38 41 42 44 49 50 52 56 31 47 55 59]);
    bits = bytesToLsbBits(header(1:3));
    value = uint8(0);
    for index = 1:24
        if bits(index)
            value = bitxor(value, columns(index));
        end
    end
end

function value = payloadCrc(payload)
    value = uint16(65535);
    polynomial = uint16(hex2dec('8408'));
    for byte = payload
        value = bitxor(value, uint16(byte));
        for index = 1:8
            lowBit = bitand(value, uint16(1));
            value = bitshift(value, -1);
            if lowBit ~= 0
                value = bitxor(value, polynomial);
            end
        end
    end
end

function verifyIndependentVectors()
    assert(headerEcc(uint8([8 15 15])) == uint8(1), ...
        'DSI:EccEotp', 'EoTp independent ECC vector failed.');
    assert(headerEcc(uint8([55 240 1])) == uint8(63), ...
        'DSI:EccFigure46', 'DSI Figure 46 independent ECC vector failed.');
    assert(payloadCrc(uint8(1)) == uint16(hex2dec('1E0E')), ...
        'DSI:CrcFigure21', 'DSI Figure 21 independent CRC vector failed.');
    assert(payloadCrc(uint8([])) == uint16(65535), ...
        'DSI:CrcEmpty', 'Empty payload CRC must be FFFF.');
    assert(isequal(bytesToLsbBits(uint8(184)), ...
        logical([0; 0; 0; 1; 1; 1; 0; 1])), ...
        'DSI:SoTOrder', 'SoT time-order bit vector failed.');
end

