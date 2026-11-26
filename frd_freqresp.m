function [magDb, phaseDeg, gdSamples, H] = frd_freqresp(b, a, f, fs)
%FRD_FREQRESP  算频率响应（和 freqz 做的事情一样，但不需要 Signal Processing Toolbox）。
%
%   [magDb, phaseDeg, gdSamples, H] = frd_freqresp(b, a, f, fs)
%
%   f         : 想看的频率（Hz），行向量
%   magDb     : 幅度响应 (dB)      = 20*log10(|H|)
%   phaseDeg  : 展开后的相位 (度)   unwrapped phase
%   gdSamples : 群延迟 (样本数)     group delay；除以 fs 就是秒
%   H         : 复数频率响应
%
%   原理：把 z = e^{jw} 代入传递函数
%       H(e^{jw}) = sum_k b(k+1) e^{-jwk}  /  sum_k a(k+1) e^{-jwk}
%   群延迟 = -d(相位)/dw。对一个多项式 P(w) = sum_k p_k e^{-jwk}，
%       -d(arg P)/dw = Re{ sum_k k p_k e^{-jwk} / P(w) }
%   所以 群延迟 = 分子那一项 - 分母那一项。

f  = f(:).';                       % 保证是行向量
w  = 2*pi*f/fs;                    % 数字角频率
kb = (0:numel(b)-1).';             % 0,1,2,... 列向量
ka = (0:numel(a)-1).';

Eb = exp(-1j * kb * w);            % 每一列是一个频率的 e^{-jwk}
Ea = exp(-1j * ka * w);

B  = b(:).' * Eb;                  % 分子 B(e^{jw})
A  = a(:).' * Ea;                  % 分母 A(e^{jw})
H  = B ./ A;

magDb    = 20*log10(max(abs(H), 1e-6));     % 最低 -120 dB，避免 log(0)
phaseDeg = unwrap(angle(H)) * 180/pi;

Bk = (kb.' .* b(:).') * Eb;        % sum k*b_k*e^{-jwk}
Ak = (ka.' .* a(:).') * Ea;
gdSamples = real(Bk ./ B) - real(Ak ./ A);
gdSamples(abs(B) < 1e-9) = NaN;    % 正好在零点（完全抵消）时群延迟没有定义
end
