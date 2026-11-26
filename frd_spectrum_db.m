function [P, f] = frd_spectrum_db(x, fs, nfft)
%FRD_SPECTRUM_DB  平均频谱 (dB)：把声音切成很多小段，每段做 FFT，再把能量平均。
%
%   [P, f] = frd_spectrum_db(x, fs, nfft)
%
%   这样得到的是"整段音乐的平均频谱"，比一次大 FFT 更平滑、更好读。
%   用途：比较 dry 和 wet 的频谱。  wet 频谱 - dry 频谱 ≈ 滤波器的幅度响应。

if nargin < 3, nfft = 8192; end
x   = x(:);
hop = nfft/2;                                        % 50% 重叠
win = 0.5 - 0.5*cos(2*pi*(0:nfft-1).'/nfft);         % Hann 窗（手写，不用工具箱）
nSeg = floor((numel(x) - nfft)/hop) + 1;
acc = zeros(nfft/2+1, 1);
for k = 1:nSeg
    seg = x((k-1)*hop + (1:nfft)) .* win;
    S   = fft(seg);
    acc = acc + abs(S(1:nfft/2+1)).^2;
end
P = 10*log10(acc/nSeg + 1e-20);
f = (0:nfft/2).' * fs/nfft;
end
