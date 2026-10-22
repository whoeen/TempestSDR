function results = studyMipiRgb888Protocol()
%STUDYMIPIRGB888PROTOCOL Verify source examples and illustrate lane mapping.
% Synthetic protocol calculation; not a phone measurement or RF decoder.
% Sources: user-supplied DSI v1.3 DRAFT 23-Mar-2015:
% sections 6, 8.5, 8.8.2, 8.8.23, 9.3-9.4; PDF 31-35,58,64,77,98-99.
% All header values below assume VC=0 and uncompressed RGB888.
outDir = fullfile(fileparts(mfilename("fullpath")), "mipi_protocol_20261022");
if ~isfolder(outDir)
    mkdir(outDir);
end

% Independent source vectors: Figure 46 and the fixed EoTp.
assert(headerEcc(uint8([hex2dec('37'), hex2dec('F0'), 1])) == hex2dec('3F'));
assert(headerEcc(uint8([8, 15, 15])) == 1);
results = struct();
results.kind = "synthetic_protocol_calculation";
results.matlab_version = string(version);
results.source = "DSI v1.3 DRAFT 23-Mar-2015; source-based A7 PLL example";
results.independent_ecc_vectors_passed = 2;
results.sot_lsb_first_bits = double(bitget(uint8(hex2dec('B8')), 1:8));

widths = [720, 750, 1080];
for k = 1:numel(widths)
    width = widths(k);
    packet = struct();
    packet.width_pixels = width;
    packet.video_wc_bytes = 3*width;
    packet.video_header_hex = join(string(dec2hex(makeHeader(hex2dec('3E'), 3*width), 2)), " ");
    packet.video_packet_bytes = 3*width+6;
    packet.video_start_lanes_first_four = mod((0:3)*packet.video_packet_bytes, 4);
    packet.video_lane_cycle_packets = 4/gcd(packet.video_packet_bytes, 4);
    packet.dcs_wc_bytes = 3*width+1;
    packet.dcs_header_hex = join(string(dec2hex(makeHeader(hex2dec('39'), 3*width+1), 2)), " ");
    packet.dcs_packet_bytes = 3*width+7;
    packet.dcs_start_lanes_first_four = mod((0:3)*packet.dcs_packet_bytes, 4);
    packet.dcs_lane_cycle_packets = 4/gcd(packet.dcs_packet_bytes, 4);
    results.packet_examples(k) = packet;
end
results.packet_conditions = "One row per packet; identical lengths; no intervening packets, padding, LP or HS restart. DCS case assumes one command byte plus RGB888.";
results.a7_assumed_applied_pll = struct( ...
    "reference_hz", 26e6, "p", 3, "m", 230, "s", 1, ...
    "lanes", 4, "kind", "source_configuration_derivation_not_measurement");
results.a7_lane_bit_rate_bps = 26e6*230/(3*2);
results.a7_forwarded_clock_hz = results.a7_lane_bit_rate_bps/2;
results.a7_byte_clock_hz = results.a7_lane_bit_rate_bps/8;
results.a7_rgb888_payload_pixel_rate = 4*results.a7_lane_bit_rate_bps/24;
results.a7_component_mapping_rate_hz = results.a7_byte_clock_hz/3;
results.a7_header_duration_aligned_4lane_s = 8/results.a7_lane_bit_rate_bps;
results.assumed_rx_bw_hz = 120e6;
results.inverse_assumed_bw_s = 1/results.assumed_rx_bw_hz;
results.bandwidth_caution = "1/B is a response-time scale, not a hard detection or timing-estimation limit. RX bandwidth remains unverified.";

% Two 4-pixel video packets concatenated in ONE HS transmission.
% Their 18-byte lengths make packet 2 start on lane 2.
labels = strings(1, 36);
categories = zeros(1, 36);
for packetIndex = 1:2
    offset = (packetIndex-1)*18;
    header = makeHeader(hex2dec('3E'), 12);
    fields = ["DI", "WClo", "WChi", "ECC"];
    for byteIndex = 1:4
        labels(offset+byteIndex) = sprintf("P%d %s\n%02X", packetIndex, fields(byteIndex), header(byteIndex));
        categories(offset+byteIndex) = 2;
    end
    componentNames = ["R", "G", "B"];
    for payloadIndex = 0:11
        position = offset+5+payloadIndex;
        component = mod(payloadIndex, 3)+1;
        labels(position) = sprintf("P%d %s%d", packetIndex, componentNames(component), floor(payloadIndex/3));
        categories(position) = 2+component;
    end
    labels(offset+17:offset+18) = ["P"+packetIndex+" CRClo", "P"+packetIndex+" CRChi"];
    categories(offset+17:offset+18) = 6;
end
labelGrid = [repmat("SoT"+newline+"B8",4,1), reshape(labels,4,[])];
categoryGrid = [ones(4,1), reshape(categories,4,[])];
palette = [0.25 0.30 0.38; 0.63 0.79 0.95; 1.00 0.66 0.66; ...
           0.61 0.87 0.66; 0.64 0.71 1.00; 0.85 0.85 0.85];
fig = figure("Name","MIPI RGB888 lane distribution: synthetic protocol", ...
    "Color","white","Position",[100 100 1320 610]);
ax = axes(fig);
image(ax,ind2rgb(categoryGrid,palette));
axis(ax,"image");
ax.XTick = 1:10;
ax.XTickLabel = ["PHY sync", "0", "1", "2", "3", "4", "5", "6", "7", "8"];
ax.YTick = 1:4;
ax.YTickLabel = ["Lane 0","Lane 1","Lane 2","Lane 3"];
ax.FontSize = 12;
xlabel(ax,"HS protocol byte-clock tick (after parallel SoT)");
title(ax,["Two concatenated RGB888 packets: 4 pixels each, 4 lanes"; ...
    "SYNTHETIC: packet length 18 bytes; packet 2 starts on lane 2"],"FontSize",16);
subtitle(ax,"Header = blue; R/G/B = component bytes; CRC = unknown data-dependent footer");
hold(ax,"on");
xline(ax,0.5:1:10.5,"w-","LineWidth",2);
yline(ax,0.5:1:4.5,"w-","LineWidth",2);
for laneIndex = 1:4
    for tickIndex = 1:10
        if tickIndex == 1
            textColor = [1 1 1];
        else
            textColor = [0.06 0.08 0.12];
        end
        text(ax,tickIndex,laneIndex,labelGrid(laneIndex,tickIndex), ...
            "HorizontalAlignment","center","FontSize",11,"Color",textColor,"Interpreter","none");
    end
end
hold(ax,"off");
exportgraphics(fig,fullfile(outDir,"rgb888_four_lane_packet_map.png"),"Resolution",150);
results.figure = "rgb888_four_lane_packet_map.png";
results.diagram_note = "CRC bytes shown symbolically. SoT occurs once per lane for the HS transmission. No claim that this is the phone packetization.";
fileId = fopen(fullfile(outDir,"protocol_results.json"),"w","n","UTF-8");
assert(fileId >= 0,"Cannot open results file.");
fileCloser = onCleanup(@() fclose(fileId));
fprintf(fileId,"%s\n",jsonencode(results,PrettyPrint=true));
disp(jsonencode(results,PrettyPrint=true));
end

function header = makeHeader(dataType,wordCount)
wordCount = uint16(wordCount);
header = uint8([dataType, double(bitand(wordCount,uint16(255))), double(bitshift(wordCount,-8)), 0]);
header(4) = headerEcc(header(1:3));
end

function ecc = headerEcc(bytes)
% D0..D7=DI LSB-first, D8..D15=WClo, D16..D23=WChi.
word = uint32(bytes(1))+bitshift(uint32(bytes(2)),8)+bitshift(uint32(bytes(3)),16);
bits = double(bitget(word,1:24));
parityIndices = { ...
    [0 1 2 4 5 7 10 11 13 16 20 21 22 23], ...
    [0 1 3 4 6 8 10 12 14 17 20 21 22 23], ...
    [0 2 3 5 6 9 11 12 15 18 20 21 22], ...
    [1 2 3 7 8 9 13 14 15 19 20 21 23], ...
    [4 5 6 7 8 9 16 17 18 19 20 22 23], ...
    [10 11 12 13 14 15 16 17 18 19 21 22 23]};
ecc = uint8(0);
for parityIndex = 1:6
    parity = mod(sum(bits(parityIndices{parityIndex}+1)),2);
    ecc = bitset(ecc,parityIndex,parity);
end
end
