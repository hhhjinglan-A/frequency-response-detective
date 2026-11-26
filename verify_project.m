%VERIFY_PROJECT  自动检查：数字对不对？滤波器稳定吗？导出的 WAV 正常吗？
%
%   在 MATLAB 里输入  verify_project
%   每一项会打印 PASS 或 FAIL。全部 PASS 说明程序的计算是对的。

here = fileparts(mfilename('fullpath'));
fs   = 48000;
nPass = 0;  nFail = 0;

add = @(ok, msg) fprintf('%s  %s\n', ternary(ok), msg);

fprintf('\n===== Frequency Response Detective: verification =====\n\n');

%% 1. 低通：DC 0 dB，截止频率 -3 dB，10 倍频率处 < -40 dB
[b, a] = frd_design('lowpass', struct('f0', 1000, 'Q', 1/sqrt(2)), fs);
m = frd_freqresp(b, a, [20 1000 10000], fs);
ok = abs(m(1)) < 0.1 && abs(m(2) + 3.01) < 0.05 && m(3) < -40;
add(ok, sprintf('Low-pass 1 kHz: %.2f dB @20 Hz, %.2f dB @1 kHz (expect -3.01), %.1f dB @10 kHz', m));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 2. 高通：和低通相反
[b, a] = frd_design('highpass', struct('f0', 1000, 'Q', 1/sqrt(2)), fs);
m = frd_freqresp(b, a, [100 1000 20000], fs);
ok = m(1) < -35 && abs(m(2) + 3.01) < 0.05 && abs(m(3)) < 0.1;
add(ok, sprintf('High-pass 1 kHz: %.1f dB @100 Hz, %.2f dB @1 kHz (expect -3.01), %.2f dB @20 kHz', m));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 3. Peaking EQ：中心频率正好是 +12 dB，远处是 0 dB
[b, a] = frd_design('peak', struct('f0', 3000, 'Q', 1.4, 'gainDb', 12), fs);
m = frd_freqresp(b, a, [20 3000 20000], fs);
ok = abs(m(2) - 12) < 0.01 && abs(m(1)) < 0.1 && abs(m(3)) < 1;
add(ok, sprintf('Peaking EQ 3 kHz +12 dB: %.2f dB @20 Hz, %.2f dB @3 kHz (expect 12), %.2f dB @20 kHz', m));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 4. 梳状滤波：34.3 cm → 1 ms → 48 样本 → 凹口在 500, 1500, 2500 Hz
[b, a, info] = frd_design('comb', struct('distCm', 34.3, 'g', 1), fs);
mN = frd_freqresp(b, a, [500 1500 2500], fs);
mP = frd_freqresp(b, a, [1000 2000], fs);
ok = info.delaySamples == 48 && all(mN < -60) && all(abs(mP) < 0.01);
add(ok, sprintf('Comb 34.3 cm: delay = %d samples (expect 48); notches %.0f/%.0f/%.0f dB; peaks %.2f/%.2f dB', ...
    info.delaySamples, mN, mP));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 5. 梳状滤波 g = 1 是"线性相位"：群延迟到处都等于 D/2 = 24 样本
fTest = linspace(100, 20000, 997);
[~, ~, gd] = frd_freqresp(b, a, fTest, fs);
gd = gd(isfinite(gd));
ok = max(abs(gd - 24)) < 1e-6;
add(ok, sprintf('Comb g = 1 group delay is constant: %.4f ... %.4f samples (expect 24)', min(gd), max(gd)));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 6. 自己写的频率响应 = 冲激响应的 FFT（证明 frd_freqresp 和 freqz 一样对）
N = 65536;  k = (10:4000).';  fk = (k-1)*fs/N;
worst = 0;
tests = {'lowpass', struct('f0', 300, 'Q', 3); 'highpass', struct('f0', 2000, 'Q', 0.6); ...
         'peak', struct('f0', 800, 'Q', 2, 'gainDb', -15); 'comb', struct('distCm', 80, 'g', 0.6)};
for t = 1:size(tests, 1)
    [b, a] = frd_design(tests{t, 1}, tests{t, 2}, fs);
    h  = filter(b, a, [1; zeros(N-1, 1)]);
    Hf = fft(h);
    m1 = frd_freqresp(b, a, fk, fs);
    worst = max(worst, max(abs(m1(:) - 20*log10(abs(Hf(k))))));
end
ok = worst < 1e-6;
add(ok, sprintf('frd_freqresp matches FFT of impulse response (max error %.1e dB)', worst));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 7. 群延迟公式 = 相位的数值导数
[b, a] = frd_design('lowpass', struct('f0', 1000, 'Q', 2), fs);
fT = linspace(50, 10000, 4000);
[~, ph, gd] = frd_freqresp(b, a, fT, fs);
w  = 2*pi*fT/fs;
gdNum = -diff(ph*pi/180) ./ diff(w);
gdMid = (gd(1:end-1) + gd(2:end))/2;
err = max(abs(gdNum - gdMid));
ok = err < 1e-3;
add(ok, sprintf('Group delay formula matches -d(phase)/dw (max error %.1e samples)', err));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 8. 稳定性：所有设置下，极点都在单位圆里面（|pole| < 1）
maxPole = 0;
for f0 = [50 100 500 1000 5000 10000 15000]
    for Q = [0.5 0.707 2 8]
        for g = [-24 0 18]
            for ty = {'lowpass', 'highpass', 'peak'}
                [~, a] = frd_design(ty{1}, struct('f0', f0, 'Q', Q, 'gainDb', g), fs);
                maxPole = max(maxPole, max(abs(roots(a))));
            end
        end
    end
end
ok = maxPole < 1;
add(ok, sprintf('All biquads are stable: largest |pole| = %.4f (must be < 1)', maxPole));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 9. 用白噪声"测量"：wet - dry 频谱 ≈ 理论曲线（在通带里误差 < 1 dB）
rs = RandStream('mt19937ar', 'Seed', 1);
n  = randn(rs, 20*fs, 1) * 0.1;
[b, a] = frd_design('peak', struct('f0', 2000, 'Q', 1, 'gainDb', 9), fs);
[Pd, fS] = frd_spectrum_db(n, fs);
Pw = frd_spectrum_db(filter(b, a, n), fs);
sel = fS > 200 & fS < 15000;
mT = frd_freqresp(b, a, fS(sel).', fs);
dev = Pw(sel) - Pd(sel) - mT(:);
ok = max(abs(dev)) < 1;
add(ok, sprintf('Measured (noise wet - dry) matches theory: max deviation %.2f dB', max(abs(dev))));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 10. 处理小提琴：长度不变，没有 NaN，不爆音
[x, fsV] = frd_load_wav(fullfile(here, 'audio', 'violin_XiaoPeng.wav'), -6);
[b, a] = frd_design('peak', struct('f0', 3000, 'Q', 1.4, 'gainDb', 18), fsV);
[y, g, nClip] = frd_process(x, b, a, false);
ok = numel(y) == numel(x) && all(isfinite(y)) && max(abs(y)) <= 10^(-1/20) + 1e-12;
add(ok, sprintf('Violin through +18 dB EQ: peak %.2f dBFS (limit -1), gain %.3f, would-clip samples %d', ...
    20*log10(max(abs(y))), g, nClip));
nPass = nPass + ok;  nFail = nFail + ~ok;

%% 11. 导出 WAV 再读回来，内容一样
tmpDir = tempname;
p = frd_export_wav(y, fsV, tmpDir, 'verify_test');
[z, fsZ] = audioread(p);
ok = fsZ == fsV && numel(z) == numel(y) && max(abs(z - y)) < 2^-22;
add(ok, sprintf('WAV export/read-back: fs %d, max difference %.1e (24-bit step %.1e)', fsZ, max(abs(z - y)), 2^-23));
nPass = nPass + ok;  nFail = nFail + ~ok;
delete(p);  rmdir(tmpDir);

fprintf('\n%d PASS, %d FAIL\n', nPass, nFail);

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end
