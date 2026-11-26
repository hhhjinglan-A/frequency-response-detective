%RUN_EXPERIMENTS  一次性做完所有"固定设置"的实验：导出 WAV + 保存图片。
%
%   在 MATLAB 里把 Current Folder 设到这个文件夹，然后输入  run_experiments
%   结果都保存在 exports/ 文件夹。
%
%   实验内容：
%     A. 四个滤波器（低通、高通、peaking EQ 提升、peaking EQ 深切）处理小提琴
%     B. 两个麦克风的梳状滤波：距离差 10 cm / 34 cm / 100 cm，看凹口怎么移动
%     C. 用白噪声"测量"低通滤波器：实测曲线应该和理论曲线重合

here   = fileparts(mfilename('fullpath'));
outDir = fullfile(here, 'exports');
if ~exist(outDir, 'dir'), mkdir(outDir); end

[x, fs, srcName] = frd_load_wav(fullfile(here, 'audio', 'violin_XiaoPeng.wav'), -6);
f = logspace(log10(20), log10(0.498*fs), 1500);

%% ---- A. 四个滤波器 ----
filters = {
    'lowpass',  struct('f0', 1000, 'Q', 0.707),               'lowpass_1000Hz'
    'highpass', struct('f0', 1000, 'Q', 0.707),               'highpass_1000Hz'
    'peak',     struct('f0', 3000, 'Q', 1.4, 'gainDb', 12),   'peakEQ_3000Hz_+12dB'
    'peak',     struct('f0', 660,  'Q', 4,   'gainDb', -24),  'peakEQ_660Hz_-24dB'
};
cols = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.47 0.67 0.19; 0.49 0.18 0.56];

frd_export_wav(x, fs, outDir, [srcName '_dry']);     % 原声也导出一份，方便比较

figA = figure('Name', 'Magnitude', 'Position', [50 50 1000 760], 'Color', 'w');
axM = subplot(2, 1, 1);  hold(axM, 'on');  grid(axM, 'on');
axG = subplot(2, 1, 2);  hold(axG, 'on');  grid(axG, 'on');
names = cell(1, size(filters, 1));
fprintf('\n%-28s %10s %10s %8s\n', 'Filter', 'peak in', 'peak out', 'gain');
for k = 1:size(filters, 1)
    [b, a, info] = frd_design(filters{k, 1}, filters{k, 2}, fs);
    [m, ~, gd] = frd_freqresp(b, a, f, fs);
    plot(axM, f, m, 'LineWidth', 1.8, 'Color', cols(k, :));
    plot(axG, f, gd/fs*1000, 'LineWidth', 1.5, 'Color', cols(k, :));
    names{k} = info.name;

    [y, g] = frd_process(x, b, a, false);
    frd_export_wav(y, fs, outDir, [srcName '_' filters{k, 3}]);
    fprintf('%-28s %8.1f dB %8.1f dB %8.2f\n', filters{k, 3}, ...
        20*log10(max(abs(x))), 20*log10(max(abs(y))), g);
end
set(axM, 'XScale', 'log', 'XLim', [20 fs/2], 'YLim', [-60 18]);
set(axG, 'XScale', 'log', 'XLim', [20 fs/2]);
xlabel(axM, 'Frequency (Hz)');  ylabel(axM, 'Magnitude (dB)');
title(axM, 'Magnitude response of the four filters');
legend(axM, names, 'Location', 'southwest');
xlabel(axG, 'Frequency (Hz)');  ylabel(axG, 'Group delay (ms)');
title(axG, 'Group delay of the four filters');
saveas(figA, fullfile(outDir, 'fig1_filters_magnitude_groupdelay.png'));

%% ---- B. 两个麦克风：凹口随距离移动 ----
% 麦克风2 远一点，所以声音也小一点：g = 0.9（g = 1 的话凹口会变成完全的 0）
dists = [10 34.3 100];
gMic2 = 0.9;
fLin  = linspace(1, 3000, 6000);      % 相位用线性频率轴、很密的点，才能正确展开
figB = figure('Name', 'Comb', 'Position', [80 80 1000 760], 'Color', 'w');
axC  = subplot(2, 1, 1);  hold(axC, 'on');  grid(axC, 'on');
axP  = subplot(2, 1, 2);  hold(axP, 'on');  grid(axP, 'on');
names = cell(1, numel(dists));
fprintf('\n%-12s %8s %10s %14s\n', 'Distance', 'Delay', 'Samples', 'First notch');
for k = 1:numel(dists)
    [b, a, info] = frd_design('comb', struct('distCm', dists(k), 'g', gMic2), fs);
    m = frd_freqresp(b, a, f, fs);
    [~, ph] = frd_freqresp(b, a, fLin, fs);
    plot(axC, f, m, 'LineWidth', 1.5, 'Color', cols(k, :));
    plot(axP, fLin, ph, 'LineWidth', 1.5, 'Color', cols(k, :));
    names{k} = info.name;
    y = frd_process(x, b, a, false);
    frd_export_wav(y, fs, outDir, sprintf('%s_comb_%dcm', srcName, round(dists(k))));
    fprintf('%8.1f cm %7.2f ms %8d %12.0f Hz\n', dists(k), info.delaySec*1000, ...
        info.delaySamples, fs/(2*info.delaySamples));
end
set(axC, 'XScale', 'log', 'XLim', [20 fs/2], 'YLim', [-40 6]);
set(axP, 'XLim', [0 3000]);
xlabel(axC, 'Frequency (Hz)');  ylabel(axC, 'Magnitude (dB)');
title(axC, 'Two-mic comb filter: farther mic 2 \rightarrow notches move lower and closer together');
legend(axC, names, 'Location', 'southwest');
xlabel(axP, 'Frequency (Hz)');  ylabel(axP, 'Phase (degrees)');
title(axP, 'Unwrapped phase (0-3 kHz): a fast phase swing at every notch; farther mic 2 = more swings');
saveas(figB, fullfile(outDir, 'fig2_comb_two_mics.png'));

%% ---- C. 用白噪声测量低通滤波器 ----
rs = RandStream('mt19937ar', 'Seed', 2026);
n  = randn(rs, 10*fs, 1);  n = n / max(abs(n)) * 0.5;
[b, a] = frd_design('lowpass', struct('f0', 1000, 'Q', 0.707), fs);
yn = filter(b, a, n);
[Pd, fS] = frd_spectrum_db(n, fs);
Pw       = frd_spectrum_db(yn, fs);
mTheory  = frd_freqresp(b, a, fS(2:end).', fs);

figC = figure('Name', 'Measured', 'Position', [110 110 1000 420], 'Color', 'w');
axT = axes(figC);  hold(axT, 'on');  grid(axT, 'on');
plot(axT, fS(2:end), Pw(2:end) - Pd(2:end), 'LineWidth', 5, 'Color', [0.95 0.65 0.55]);
plot(axT, fS(2:end), mTheory, '--', 'LineWidth', 1.5, 'Color', [0 0.30 0.60]);
set(axT, 'XScale', 'log', 'XLim', [20 fs/2], 'YLim', [-80 6]);
xlabel(axT, 'Frequency (Hz)');  ylabel(axT, 'Magnitude (dB)');
title(axT, 'Low-pass 1 kHz: measured with white noise (wet - dry) vs theory  ->  the two curves overlap');
legend(axT, {'Measured: wet spectrum - dry spectrum', 'Theory: |H(f)|'}, 'Location', 'southwest');
saveas(figC, fullfile(outDir, 'fig3_measured_vs_theory.png'));

fprintf('\nDone. Files are in: %s\n', outDir);
