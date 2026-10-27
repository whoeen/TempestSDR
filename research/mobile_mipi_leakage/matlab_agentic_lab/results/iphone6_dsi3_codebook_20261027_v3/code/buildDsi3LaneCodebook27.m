function book = buildDsi3LaneCodebook27(outputDir)
%buildDsi3LaneCodebook27 Build conditional RGB888 three-lane DSI codewords.
%   BOOK = buildDsi3LaneCodebook27() returns protocol hypotheses only.
%   BOOK = buildDsi3LaneCodebook27(OUTPUTDIR) also saves codebook.mat and
%   book_summary.json. This function requires base MATLAB only.
%
%   videoWhite and videoBlack are 1-by-4 arrays indexed by VC+1. dcs is
%   [2C-white, 2C-black, 3C-white, 3C-black], all with VC=0.
%   matchedControls contains 3 wrong codewords per valid candidate (36).
%   geometryControls contains 12 constant-level, length-matched null models;
%   their hsBits are authoritative, while packetBytes describe the reference.
%   contexts has
%   WW, WB, BW, BB fields, each containing a 16-pixel video long packet.
%
%   Each packet has uint8 packetBytes/header/payload, uint16 crc, and logical
%   laneBits (chronological bit rows, three lane columns). laneValid marks
%   genuine transmitted bits; false padding is NOT transmitted zero data.
%   hsBits adds one parallel B8 SoT byte per lane. hsValid is its valid mask.
%   The model starts the FIRST packet of an HS burst on lane 0. It does not
%   reset striping at an arbitrary internal packet boundary. Physical HS-zero,
%   prepare/trail timings, LP states, clock, skew and RF channels are absent.
%
%   Sources: local DSI v1.3 draft sections 6, 8.3, 8.8.9.3, 8.8.23 and 9.6;
%   Keysight M8085-91040 pp. 68 and 116. See the source-audit note at
%   knowledge/mipi_dphy/codebook_three_lane_source_audit_20261027.md.

    arguments
        outputDir (1,1) string = ""
    end

    verifyIndependentVectors();
    book = struct();
    book.metadata = makeMetadata();
    book.phy = struct('sotByte', uint8(hex2dec('B8')), ...
        'sotBitsTimeOrder', logical([0; 0; 0; 1; 1; 1; 0; 1]), ...
        'modeledHsZeroPrepareTrail', false, 'numberDataLanes', 3);
    white = repmat(uint8(255), 1, 750);
    black = zeros(1, 750, 'uint8');
    videoWhite = cell(1, 4);
    videoBlack = cell(1, 4);
    for vc = 0:3
        videoWhite{vc+1} = makeLongPacket(white, 62, vc, [], ...
            "video-white-vc" + vc);
        videoBlack{vc+1} = makeLongPacket(black, 62, vc, [], ...
            "video-black-vc" + vc);
    end
    book.videoWhite = [videoWhite{:}];
    book.videoBlack = [videoBlack{:}];
    book.dcs = [makeLongPacket(white, 57, 0, 44, "dcs-2C-white"), ...
        makeLongPacket(black, 57, 0, 44, "dcs-2C-black"), ...
        makeLongPacket(white, 57, 0, 60, "dcs-3C-white"), ...
        makeLongPacket(black, 57, 0, 60, "dcs-3C-black")];
    book.contexts = makeContexts();
    book.eotp = struct('packetBytes', uint8([8 15 15 1]), ...
        'optional', true, 'isPhyEot', false, ...
        'note', "DSI short packet: distribute at current stream lane phase; " + ...
        "not appended to these candidate HS bursts.");
    book.controls = makeControls(book.videoWhite(1));
    validPackets = [book.videoWhite, book.videoBlack, book.dcs];
    [book.matchedControls, book.geometryControls] = makeMatchedControls(validPackets);
    verifyMapping(book);
    book.summary = makeSummary(book);
    if strlength(outputDir) > 0
        if ~isfolder(outputDir)
            mkdir(outputDir);
        end
        save(fullfile(outputDir, "codebook.mat"), 'book', '-v7');
        writeSummary(fullfile(outputDir, "book_summary.json"), book.summary);
    end
end

function metadata = makeMetadata()
    metadata = struct('version', "2026-10-27", ...
        'status', "protocol hypothesis, not measured packet decode", ...
        'colorFormat', "RGB888", 'assumedDataLanes', 3, ...
        'firstPacketStartLaneZeroBased', 0, ...
        'bitOrder', "LSB first within every byte", ...
        'multiByteOrder', "least significant byte first", ...
        'initialSoT', "parallel 0xB8 on all three data lanes once", ...
        'physicalTimingsIncluded', false, ...
        'payloadPeriodicityAsserted', false, ...
        'actualIphoneLaneCountVerified', false, ...
        'sourceNote', "knowledge/mipi_dphy/codebook_three_lane_source_audit_20261027.md", ...
        'cautions', ["750 pixels per long packet is an assumption."; ...
        "An arbitrary interior packet starts at cumulative byte count mod 3."; ...
        "A repeated constant white/black NRZ run has no internal bit edges."; ...
        "No HS-zero, HS-prepare, HS-trail, EoTp, clock, LP or RF response included."; ...
        "Invalid matrix padding must be excluded using the valid masks."]);
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

function contexts = makeContexts()
    names = ["WW", "WB", "BW", "BB"];
    colors = uint8([255 255; 255 0; 0 255; 0 0]);
    contexts = struct();
    for index = 1:numel(names)
        pixels = [repmat(colors(index, 1), 1, 8), ...
            repmat(colors(index, 2), 1, 8)];
        packet = makeLongPacket(pixels, 62, 0, [], "context-" + names(index));
        packet.note = "Synthetic 16-pixel packet: 8 pixels before and after " + ...
            "a color boundary. Header offset is 4 bytes; not a periodic-bit claim.";
        contexts.(names(index)) = packet;
    end
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

function [matchedControls, geometryControls] = makeMatchedControls(references)
    wrongCells = cell(1, 3*numel(references));
    geometryCells = cell(1, numel(references));
    for index = 1:numel(references)
        reference = references(index);
        wrong = makeControls(reference);
        for variant = 1:3
            wrong(variant).label = "control-" + wrong(variant).controlKind + ...
                "-ref-" + reference.label;
            wrongCells{3*(index-1)+variant} = wrong(variant);
        end
        geometry = reference;
        geometry.protocolCandidate = false;
        geometry.label = "geometry-only-ref-" + reference.label;
        geometry.controlKind = "constant-level-geometry-only";
        geometry.controlReference = reference.label;
        % A rectangular +1 active level, zero outside the original valid
        % burst duration. Deliberately remove all SoT/header/payload/CRC bits.
        % The false tail padding of an uneven DCS ending remains invalid.
        geometry.hsBits = reference.hsValid;
        geometry.laneBits = reference.laneValid;
        geometry.laneBytes = uint8(255)*uint8(reference.laneByteValid);
        geometry.phySyncBytes = uint8([255 255 255]);
        geometry.note = "Geometry-only null: hsBits and hsValid are authoritative. " + ...
            "All valid intervals have logical 1, including nominal SoT time; " + ...
            "no SoT, header, payload or CRC bit structure is transmitted. " + ...
            "packetBytes/header/payload/CRC and decoded fields are retained " + ...
            "ONLY as reference metadata and do not encode this null waveform.";
        geometryCells{index} = geometry;
    end
    matchedControls = [wrongCells{:}];
    geometryControls = [geometryCells{:}];
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

function verifyMapping(book)
    video = book.videoWhite(1);
    assert(isequal(video.header, uint8([62 202 8 9])), ...
        'DSI:VideoHeader', '750-pixel VC0 RGB888 header mismatch.');
    assert(isequal(video.laneByteLengths, [752 752 752]), ...
        'DSI:VideoLength', 'Video long packet must use 752 bytes/lane.');
    assert(isequal(book.dcs(1).laneByteLengths, [753 752 752]), ...
        'DSI:DcsLength', 'DCS long packet end-lane validity mismatch.');
    assert(isequal(video.byteMapping.laneZeroBased(5:7), [1; 2; 0]), ...
        'DSI:PayloadLane', 'Header offset must map first RGB bytes to lanes 1,2,0.');
    assert(~any(book.dcs(1).laneValid(end-7:end, 2:3), 'all'), ...
        'DSI:Padding', 'DCS padding must not be marked as transmitted bits.');
    for index = 1:numel(book.controls)
        assert(isequal(size(book.controls(index).hsBits), size(video.hsBits)), ...
            'DSI:ControlSize', 'A control changed HS matrix size.');
        assert(isequal(book.controls(index).hsValid, video.hsValid), ...
            'DSI:ControlValidity', 'A control changed transmission validity.');
    end
    assert(isequal(sum(book.controls(3).hsBits, 1), sum(video.hsBits, 1)), ...
        'DSI:ControlCount', 'Shuffle must preserve each lane bit count.');
    references = [book.videoWhite, book.videoBlack, book.dcs];
    assert(numel(book.matchedControls) == 36 && numel(book.geometryControls) == 12, ...
        'DSI:MatchedBankSize', 'Expected 36 matched and 12 geometry controls.');
    for index = 1:numel(references)
        reference = references(index);
        geometry = book.geometryControls(index);
        assert(isequal(geometry.hsBits, reference.hsValid) && ...
            isequal(geometry.hsValid, reference.hsValid), ...
            'DSI:GeometryControl', 'Geometry null changed validity or active level.');
        for variant = 1:3
            control = book.matchedControls(3*(index-1)+variant);
            assert(control.controlReference == reference.label && ...
                isequal(control.hsValid, reference.hsValid), ...
                'DSI:MatchedControl', 'Control is not matched to its reference.');
        end
        assert(isequal(sum(book.matchedControls(3*index).hsBits, 1), ...
            sum(reference.hsBits, 1)), 'DSI:MatchedControlCount', ...
            'Matched shuffle changed per-lane bit counts.');
    end
end

function summary = makeSummary(book)
    summary = struct('metadata', book.metadata, ...
        'independentAssertionsPassed', true, ...
        'bitArrayOrientation', "chronological bit rows by lane columns", ...
        'paddingPolicy', "Always exclude laneValid/hsValid=false positions", ...
        'eotp', book.eotp);
    allPackets = [book.videoWhite, book.videoBlack, book.dcs, ...
        book.contexts.WW, book.contexts.WB, book.contexts.BW, book.contexts.BB, ...
        book.controls, book.matchedControls, book.geometryControls];
    summaries = cell(1, numel(allPackets));
    for index = 1:numel(allPackets)
        packet = allPackets(index);
        summaries{index} = struct('label', packet.label, ...
            'protocolCandidate', packet.protocolCandidate, ...
            'virtualChannel', double(packet.virtualChannel), ...
            'dataTypeHex', string(dec2hex(packet.dataType, 2)), ...
            'wordCount', double(packet.wordCount), 'pixelCount', packet.pixelCount, ...
            'headerHex', strjoin(string(dec2hex(packet.header, 2)), " "), ...
            'crcHex', string(dec2hex(packet.crc, 4)), ...
            'packetByteCount', numel(packet.packetBytes), ...
            'laneByteLengths', packet.laneByteLengths, ...
            'hsBitLengths', packet.hsBitLengths, 'note', packet.note);
    end
    summary.packets = [summaries{:}];
end

function writeSummary(path, summary)
    [fileId, message] = fopen(path, 'w', 'n', 'UTF-8');
    if fileId < 0
        error('DSI:WriteSummary', 'Cannot write summary: %s', message);
    end
    cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>
    fprintf(fileId, '%s\n', jsonencode(summary, PrettyPrint=true));
end
