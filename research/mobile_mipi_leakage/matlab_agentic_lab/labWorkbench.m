%% Smartphone TEMPEST research workbench
% Keep this visible beside the Codex terminal.
% Fixed source evidence, hypotheses and measured results live in knowledge/.
labRoot = fileparts(mfilename("fullpath"));
addpath(fullfile(labRoot,"signal_processing"));
disp(version);
disp(ver);

%% Start or refresh the shared MATLAB session
% The official MCP Server Toolbox is installed by startLab.
shareMATLABSession();

%% Inspect available analysis entry points
help runMobileBaseline

%% Execute the bounded three-device baseline
% Run only after inspecting signal_processing/mobileBaselineConfig.m.
% The baseline records endian, sample ranges, settings, numerical results,
% figures and skipped/unavailable functions. It does not overwrite source IQ.
% results = runtests("signal_processing/testMobileBaseline.m");
% assert(all([results.Passed]),"Baseline tests failed.");
% summary = runMobileBaseline();

%% Research interpretation rules
% 1) Receiver bandwidth is not equal to sample rate.
% 2) Pixel clock is not lane bit rate; DSI bursts need measured timing.
% 3) Phase is relative to the receiver and chosen reference.
% 4) HSV hue is an RF phase display, not recovered RGB colour.
% 5) Low matrix rank does not identify the physical radiator.
% 6) Retain the no-subtraction baseline for every clutter-removal experiment.
