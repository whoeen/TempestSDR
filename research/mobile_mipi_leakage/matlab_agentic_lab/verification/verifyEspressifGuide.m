function result = verifyEspressifGuide()
%VERIFYESPRESSIFGUIDE Check arithmetic and packet examples from user capture.
% Source screenshot/guide: Espressif MIPI DSI LCD Detailed Guide, 2026-10-22.
% ECC: user-supplied DSI v1.3 PDF98-99, P0..P5 equations.
% CRC: DSI v1.3 section9.6/AnnexB, initFFFF, reflected polynomial8408.
% Synthetic arithmetic only. No IQ or ESP32 hardware input.
result = struct("kind","document_example_verification","matlab",string(version));
result.horizontal_total = 800+20+20+4;
result.vertical_total = 1280+20+20+4;
result.pixel_clock_for_60Hz_hz = result.horizontal_total*result.vertical_total*60;
result.raster_rgb888_equivalent_bps = result.pixel_clock_for_60Hz_hz*24;
result.raster_equivalent_per_lane_bps = result.raster_rgb888_equivalent_bps/2;
result.active_payload_per_lane_bps = 800*1280*60*24/2;
result.active_plus_one_packet_per_row_per_lane_bps = ((800*3+6)*1280*60*8)/2;
result.refresh_at_60MHz_hz = 60e6/(result.horizontal_total*result.vertical_total);
result.paper_1497p6_times_1p25_times_1p15_Mbps = 1497.6*1.25*1.15;
result.ui_range_ns = [2,12.5];
result.bit_rate_from_ui_range_Mbps = [1/(12.5e-9),1/(2e-9)]/1e6;
result.config_1300Mbps = struct("lane_rate_bps",1300e6, ...
    "forwarded_ddr_hz",650e6,"byte_clock_hz",162.5e6);
inputHeaders = uint8([hex2dec('37'),3,0; hex2dec('39'),3,0; ...
    hex2dec('21'),hex2dec('45'),0; hex2dec('1C'),5,0; ...
    hex2dec('37'),hex2dec('F0'),1; 8,15,15]);
expectedEcc = uint8([1,9,1,hex2dec('29'),hex2dec('3F'),1]);
for k = 1:size(inputHeaders,1)
    actual = ecc24(inputHeaders(k,:));
    result.header_checks(k) = struct( ...
        "header3_hex",join(string(dec2hex(inputHeaders(k,:),2))," "), ...
        "calculated_ecc_hex",string(dec2hex(actual,2)), ...
        "shown_ecc_hex",string(dec2hex(expectedEcc(k),2)), ...
        "matches",actual==expectedEcc(k));
end
payloads = {uint8([hex2dec('B6'),hex2dec('B2'),hex2dec('B2')]), ...
    uint8([hex2dec('89'),hex2dec('23'),hex2dec('12'),hex2dec('A2'),hex2dec('E2')])};
shownCrc = uint16([hex2dec('FAEF'),hex2dec('2959')]);
for k = 1:numel(payloads)
    crc = payloadCrc(payloads{k});
    low = uint8(bitand(crc,uint16(255)));
    high = uint8(bitshift(crc,-8));
    result.crc_checks(k) = struct("payload_hex",join(string(dec2hex(payloads{k},2))," "), ...
        "crc_low_high_hex",join(string(dec2hex([low high],2))," "), ...
        "matches",crc==shownCrc(k));
end
result.caveat = "Raster equivalents are not exact required DSI bitrates. Actual mode, packet schedule, lane tail, HS/LP timing and panel limits must be budgeted.";
result.byte_clock_relation = "Forwarded-clock D-PHY uses8bits/byte and2bits/clock; no generic8b/10b multiplier.";
assert(all([result.header_checks.matches]),"Header example mismatch");
assert(all([result.crc_checks.matches]),"CRC example mismatch");
outDir = fullfile(fileparts(mfilename("fullpath")),"espressif_20261022");
if ~isfolder(outDir); mkdir(outDir); end
fileId = fopen(fullfile(outDir,"guide_verification.json"),"w","n","UTF-8");
assert(fileId>=0);
cleanup=onCleanup(@() fclose(fileId));
fprintf(fileId,"%s\n",jsonencode(result,PrettyPrint=true));
disp(jsonencode(result,PrettyPrint=true));
end

function ecc=ecc24(bytes)
word=uint32(bytes(1))+bitshift(uint32(bytes(2)),8)+bitshift(uint32(bytes(3)),16);
bits=double(bitget(word,1:24));
p={ [0 1 2 4 5 7 10 11 13 16 20 21 22 23], ...
 [0 1 3 4 6 8 10 12 14 17 20 21 22 23], ...
 [0 2 3 5 6 9 11 12 15 18 20 21 22], ...
 [1 2 3 7 8 9 13 14 15 19 20 21 23], ...
 [4 5 6 7 8 9 16 17 18 19 20 22 23], ...
 [10 11 12 13 14 15 16 17 18 19 21 22 23]};
ecc=uint8(0);
for k=1:6; ecc=bitset(ecc,k,mod(sum(bits(p{k}+1)),2)); end
end

function crc=payloadCrc(bytes)
crc=uint16(65535);
for dataByte=bytes
    for bitIndex=1:8
        feedback=xor(logical(bitget(crc,1)),logical(bitget(dataByte,bitIndex)));
        crc=bitshift(crc,-1);
        if feedback; crc=bitxor(crc,uint16(hex2dec('8408'))); end
    end
end
end
