function [b, a, info] = frd_design(type, p, fs)
%FRD_DESIGN  做一个滤波器：返回差分方程的系数 b（分子）和 a（分母）。
%
%   [b, a, info] = frd_design(type, p, fs)
%
%   type : 'lowpass' | 'highpass' | 'peak' | 'comb'
%   p    : 参数结构体（不同滤波器用不同的字段）
%            lowpass / highpass : p.f0 (截止频率 Hz), p.Q
%            peak               : p.f0 (中心频率 Hz), p.Q, p.gainDb (增益 dB)
%            comb               : p.distCm (两个麦克风的距离差, 厘米), p.g (麦克风2的音量 0~1)
%   fs   : 采样率 (Hz)
%
%   差分方程（所有滤波器都是这个形式）：
%       a(1)*y[n] = b(1)*x[n] + b(2)*x[n-1] + ... - a(2)*y[n-1] - a(3)*y[n-2] ...
%   传递函数：
%       H(z) = (b(1) + b(2) z^-1 + b(3) z^-2 + ...) / (a(1) + a(2) z^-1 + ...)
%
%   低通 / 高通 / peaking EQ 用的是 Robert Bristow-Johnson 的 "Audio EQ Cookbook"
%   双二阶 (biquad) 公式。梳状滤波器用"两个麦克风相加"的模型。

info = struct('name', '', 'expect', '', 'delaySamples', 0, 'delaySec', 0);

switch type
    case {'lowpass', 'highpass', 'peak'}
        w0    = 2*pi*p.f0/fs;          % 把 Hz 换成"数字角频率"（弧度/样本）
        cw    = cos(w0);
        alpha = sin(w0)/(2*p.Q);       % Q 越大 → alpha 越小 → 共振峰越尖

        switch type
            case 'lowpass'
                b = [(1-cw)/2, 1-cw, (1-cw)/2];
                a = [1+alpha, -2*cw, 1-alpha];
                info.name   = sprintf('Low-pass  %.0f Hz', p.f0);
                info.expect = 'Keeps low frequencies, removes highs: sound gets darker / muffled.';
            case 'highpass'
                b = [(1+cw)/2, -(1+cw), (1+cw)/2];
                a = [1+alpha, -2*cw, 1-alpha];
                info.name   = sprintf('High-pass  %.0f Hz', p.f0);
                info.expect = 'Removes low frequencies, keeps highs: sound gets thin / bright.';
            case 'peak'
                A = 10^(p.gainDb/40);  % 增益：dB → 线性（cookbook 定义，用 /40）
                b = [1+alpha*A, -2*cw, 1-alpha*A];
                a = [1+alpha/A, -2*cw, 1-alpha/A];
                info.name   = sprintf('Peaking EQ  %.0f Hz, %+.1f dB', p.f0, p.gainDb);
                if p.gainDb >= 0
                    info.expect = 'Boosts a band around the center frequency.';
                else
                    info.expect = 'Cuts a band around the center frequency (deep cut = notch).';
                end
        end
        % 让 a(1) = 1（标准形式）
        b = b / a(1);
        a = a / a(1);

    case 'comb'
        % 两个麦克风：麦克风1 离琴近，麦克风2 远 distCm 厘米。
        % 声音在空气里每秒走 343 米，所以麦克风2 收到的声音晚了 tau 秒。
        c   = 343;                         % 声速 m/s
        tau = (p.distCm/100) / c;          % 延迟时间（秒）
        D   = max(1, round(tau*fs));       % 延迟多少个样本（取整数）
        % 混音：y[n] = 0.5*x[n] + 0.5*g*x[n-D]   （0.5 是为了不爆音）
        b = zeros(1, D+1);
        b(1)   = 0.5;
        b(D+1) = 0.5*p.g;
        a = 1;                             % 没有反馈 → FIR，永远稳定
        info.delaySamples = D;
        info.delaySec     = D/fs;
        info.name   = sprintf('Two-mic comb  %.0f cm (%.2f ms)', p.distCm, 1000*D/fs);
        info.expect = sprintf(['Notches at %.0f Hz, %.0f Hz, %.0f Hz ... (odd multiples of 1/(2*delay)). ' ...
                               'Sound gets hollow / phasey.'], ...
                              fs/(2*D), 3*fs/(2*D), 5*fs/(2*D));
    otherwise
        error('frd_design: unknown type "%s"', type);
end
end
