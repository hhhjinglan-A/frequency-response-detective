function [y, gainApplied, nClip] = frd_process(x, b, a, normalize)
%FRD_PROCESS  把声音 x 送进滤波器 (b, a)，再处理输出音量。
%
%   [y, gainApplied, nClip] = frd_process(x, b, a, normalize)
%
%   normalize = false : 保持原来的音量（只有超过 -1 dBFS 才压下来，防止爆音）
%                       → 适合公平比较：低通以后声音"变小"也是滤波器的效果
%   normalize = true  : 把输出峰值调到 -1 dBFS
%
%   gainApplied : 最后乘了多少倍（1 = 没改）
%   nClip       : 如果不处理，会有多少个样本超过 ±1（爆音）

if nargin < 4, normalize = false; end
y = filter(b, a, x);                 % 差分方程，一个样本一个样本地算

limit = 10^(-1/20);                  % -1 dBFS
pk    = max(abs(y));
nClip = sum(abs(y) > 1);
if normalize || pk > limit
    gainApplied = limit / pk;
else
    gainApplied = 1;
end
y = y * gainApplied;
end
