function [x, fs, name] = frd_load_wav(path, peakDb)
%FRD_LOAD_WAV  读入音频 → 变成单声道 → 把峰值调到 peakDb (dBFS)。
%
%   [x, fs, name] = frd_load_wav(path, peakDb)
%
%   默认 peakDb = -6，留 6 dB 的空间，这样 EQ 提升时不容易爆音。

if nargin < 2, peakDb = -6; end
[x, fs] = audioread(path);
x = mean(x, 2);                          % 立体声 → 单声道
x = x / max(abs(x)) * 10^(peakDb/20);    % 峰值归一化
[~, name] = fileparts(path);
end
