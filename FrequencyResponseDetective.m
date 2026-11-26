function varargout = FrequencyResponseDetective
%FREQUENCYRESPONSEDETECTIVE  交互界面：选一个滤波器，拖滑块，边看频率响应边听小提琴。
%
%   启动：在 MATLAB 命令行输入  FrequencyResponseDetective
%   不需要任何工具箱（Signal Processing Toolbox 也不需要）。
%
%   结构说明（给初学者）：
%   - 这是一个"函数 + 嵌套函数"写成的界面。最上面定义的变量（x, y, b, a ...）
%     是共享状态，下面所有嵌套函数都能直接读写它们。
%   - 每个控件只做一件事：
%       换音源                   → loadSource()   重新准备 x（dry）
%       拖滑块（拖的过程中）       → updateResponse()  只重画响应曲线（很快）
%       放开滑块 / 换滤波器        → process()      重新算 y = filter(b, a, x)（wet）
%       播放 / A-B 切换 / 导出     → playSource() / switchAB() / exportCurrent()
%       Mystery 模式              → newMystery() / checkGuess() / reveal()
%
%   [fig, api] = FrequencyResponseDetective  还会返回一个 api 结构体，
%   让别的脚本（demo_tour.m）可以"遥控"这个界面：换滤波器、移动滑块、播放、显示字幕……

%% ===== 共享状态 =====
here    = fileparts(mfilename('fullpath'));
outDir  = fullfile(here, 'exports');
fs      = 48000;     % 采样率
x       = [];        % dry（原始声音）
y       = [];        % wet（处理后的声音）
b       = 1;         % 当前滤波器分子系数
a       = 1;         % 当前滤波器分母系数
fInfo   = struct();  % 当前滤波器的说明（名字、预期效果、延迟）
gainOut = 1;         % 输出音量调整（防止爆音）
srcName = '';        % 音源名字（用在导出的文件名里）
wavPath = '';        % 导入的音频路径（选 Imported WAV 时才用）
Pdry    = [];        % dry 的平均频谱 (dB)
fSpec   = [];        % 频谱的频率轴
player  = [];        % audioplayer（要一直保存，否则声音会被中断）
nowPlaying = '';     % 'dry' / 'wet' / ''
loopPlay   = false;  % true = 播放到结尾自动从头再播（演示用）

fPlot = logspace(log10(20), log10(23900), 4000);   % 画图用的频率（对数间隔；点要密，梳状滤波的凹口才画得准）

% 每种滤波器记住自己的参数（切换滤波器再切回来，参数还在）
types  = {'lowpass', 'highpass', 'peak', 'comb'};
params = struct( ...
    'lowpass',  struct('f0', 1000, 'Q', 0.707), ...
    'highpass', struct('f0', 1000, 'Q', 0.707), ...
    'peak',     struct('f0', 3000, 'Q', 1.4, 'gainDb', 12), ...
    'comb',     struct('distCm', 34.3, 'g', 0.9));
curType = 'lowpass';

% Mystery 模式
mystery     = false;
mysteryType = '';
mysteryP    = struct();
mysteryAns  = '';

colDry = [0.55 0.55 0.55];
colWet = [0.00 0.45 0.74];
colRefLight = [0.95 0.65 0.55];   % 浅一点的橙色（实测曲线）

%% ===== 界面布局 =====
scr = get(groot, 'ScreenSize');                  % 屏幕大小：窗口不要比屏幕高
figH = min(900, scr(4) - 140);
fig = uifigure('Name', 'Frequency Response Detective — Violin', 'Position', [40 90 1440 figH]);
fig.CloseRequestFcn = @(~, ~) onClose();
main = uigridlayout(fig, [1 2]);
main.ColumnWidth = {340, '1x'};

% ---- 左边：控制面板 ----
cg = uigridlayout(main, [27 3]);
cg.ColumnWidth = {95, '1x', 70};
cg.RowHeight   = {22, 26, 26, 22, 26, 22, 40, 22, 40, 22, 40, 60, 22, 26, 26, 22, 30, 30, 26, 22, 30, 22, 30, 26, 30, 44, '1x'};
cg.RowSpacing  = 5;
cg.Scrollable  = 'on';                            % 窗口太小时，左边可以上下滚动

header(1, '1. Source');
ddSource = uidropdown(cg, 'Items', {'Violin: 小蓬又泛曾行路', 'White noise (test signal)', 'Imported WAV'}, ...
    'ItemsData', {'violin', 'noise', 'wav'}, 'ValueChangedFcn', @(~, ~) onSourceChanged());
span(ddSource, 2);
btnLoad = uibutton(cg, 'Text', 'Load WAV…', 'ButtonPushedFcn', @(~, ~) pickWav());
span(btnLoad, 3);

header(4, '2. Filter');
ddType = uidropdown(cg, 'Items', {'Low-pass', 'High-pass', 'Peaking EQ', 'Two-mic comb'}, ...
    'ItemsData', types, 'ValueChangedFcn', @(~, ~) onTypeChanged());
span(ddType, 5);

% 三个参数滑块（不同滤波器用的意思不同，标签会自动改）
lbl = gobjects(1, 3);  sl = gobjects(1, 3);  val = gobjects(1, 3);
for k = 1:3
    r = 4 + 2*k;                         % 行 6, 8, 10 放名字；7, 9, 11 放滑块
    lbl(k) = uilabel(cg, 'Text', '', 'FontWeight', 'bold');
    lbl(k).Layout.Row = r;  lbl(k).Layout.Column = [1 2];
    val(k) = uilabel(cg, 'Text', '', 'HorizontalAlignment', 'right');
    val(k).Layout.Row = r;  val(k).Layout.Column = 3;
    sl(k) = uislider(cg, 'Limits', [0 1], 'Value', 0.5);
    sl(k).Layout.Row = r + 1;  sl(k).Layout.Column = [1 3];
    sl(k).ValueChangingFcn = @(~, evt) onSliderMoving(k, evt.Value);
    sl(k).ValueChangedFcn  = @(~, ~) onSliderDone();
end

lblExpect = uilabel(cg, 'Text', '', 'WordWrap', 'on', 'FontAngle', 'italic', 'VerticalAlignment', 'top');
span(lblExpect, 12);

header(13, '3. View');
label(14, '2nd plot');
ddPlot2 = uidropdown(cg, 'Items', {'Unwrapped phase', 'Group delay'}, ...
    'ItemsData', {'phase', 'gd'}, 'Value', 'gd', 'ValueChangedFcn', @(~, ~) updateResponse());
place(ddPlot2, 14, [2 3]);
cbMeasured = uicheckbox(cg, 'Text', 'Show measured response (wet − dry spectrum)', ...
    'Value', true, 'ValueChangedFcn', @(~, ~) updateMeasured());
span(cbMeasured, 15);

header(16, '4. Listen');
btnDry  = uibutton(cg, 'Text', '▶ Dry',  'ButtonPushedFcn', @(~, ~) playSource('dry'));
place(btnDry, 17, 1);
btnWet  = uibutton(cg, 'Text', '▶ Wet',  'ButtonPushedFcn', @(~, ~) playSource('wet'));
place(btnWet, 17, 2);
btnStop = uibutton(cg, 'Text', '■ Stop', 'ButtonPushedFcn', @(~, ~) stopAudio());
place(btnStop, 17, 3);
btnAB = uibutton(cg, 'Text', '⇄  A/B switch (same position)', 'ButtonPushedFcn', @(~, ~) switchAB());
span(btnAB, 18);
cbNorm = uicheckbox(cg, 'Text', 'Normalize wet to −1 dBFS peak', 'Value', false, ...
    'ValueChangedFcn', @(~, ~) process());
place(cbNorm, 19, [1 2]);
lblPlaying = uilabel(cg, 'Text', '', 'HorizontalAlignment', 'right', 'FontWeight', 'bold');
place(lblPlaying, 19, 3);

header(20, '5. Export');
btnExport = uibutton(cg, 'Text', 'Export wet WAV', 'ButtonPushedFcn', @(~, ~) exportCurrent());
span(btnExport, 21);

header(22, '6. Mystery mode (detective game)');
btnMystery = uibutton(cg, 'Text', '🔍 New mystery filter', 'ButtonPushedFcn', @(~, ~) newMystery());
span(btnMystery, 23);
ddGuess = uidropdown(cg, 'Items', {'Low-pass', 'High-pass', 'Peaking EQ (boost)', 'Peaking EQ (cut)', 'Comb filter'}, ...
    'ItemsData', {'lowpass', 'highpass', 'peakBoost', 'peakCut', 'comb'}, 'Enable', 'off');
place(ddGuess, 24, [1 2]);
btnCheck = uibutton(cg, 'Text', 'Check', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) checkGuess());
place(btnCheck, 24, 3);
btnReveal = uibutton(cg, 'Text', 'Reveal answer', 'Enable', 'off', 'ButtonPushedFcn', @(~, ~) reveal());
span(btnReveal, 25);
lblMystery = uilabel(cg, 'Text', '', 'WordWrap', 'on', 'FontWeight', 'bold');
span(lblMystery, 26);

% ---- 右边：三张图 ----
pg = uigridlayout(main, [4 1]);
pg.RowHeight = {0, '1.2x', '1x', '1x'};    % 第 1 行是字幕（平时高度 0，看不到）

lblCaption = uilabel(pg, 'Text', '', 'FontSize', 20, 'FontWeight', 'bold', ...
    'WordWrap', 'on', 'HorizontalAlignment', 'center', 'BackgroundColor', [1 0.96 0.82]);

axMag = uiaxes(pg);
hold(axMag, 'on');  grid(axMag, 'on');  box(axMag, 'on');
hMeas = plot(axMag, NaN, NaN, '-', 'Color', colRefLight, 'LineWidth', 6);   % 粗的浅橙色线放在下面，和蓝线重合时也看得见
hMag  = plot(axMag, NaN, NaN, '-', 'Color', colWet, 'LineWidth', 2);
hMark = plot(axMag, NaN, NaN, '--', 'Color', [0.3 0.3 0.3], 'LineWidth', 1);
axMag.XScale = 'log';  axMag.XLim = [20 24000];  axMag.YLim = [-60 24];
xlabel(axMag, 'Frequency (Hz)');  ylabel(axMag, 'Magnitude (dB)');
legend(axMag, [hMag hMeas], {'Filter magnitude response |H(f)|', 'Measured: wet − dry spectrum'}, ...
    'Location', 'southwest');

ax2 = uiaxes(pg);
hold(ax2, 'on');  grid(ax2, 'on');  box(ax2, 'on');
h2 = plot(ax2, NaN, NaN, '-', 'Color', colWet, 'LineWidth', 1.5);
ax2.XScale = 'log';  ax2.XLim = [20 24000];
xlabel(ax2, 'Frequency (Hz)');

axSpec = uiaxes(pg);
hold(axSpec, 'on');  grid(axSpec, 'on');  box(axSpec, 'on');
hDry = plot(axSpec, NaN, NaN, '-', 'Color', colDry, 'LineWidth', 3);      % 粗的灰线放在下面，被蓝线盖住时也看得见
hWet = plot(axSpec, NaN, NaN, '-', 'Color', colWet, 'LineWidth', 1);
axSpec.XScale = 'log';  axSpec.XLim = [20 24000];
xlabel(axSpec, 'Frequency (Hz)');  ylabel(axSpec, 'Level (dB)');
title(axSpec, 'Average spectrum of the audio: dry vs wet');
legend(axSpec, [hDry hWet], {'Dry (original)', 'Wet (filtered)'}, 'Location', 'southwest');

%% ===== 启动 =====
writeSliders();
loadSource();

if nargout > 0, varargout{1} = fig; end
if nargout > 1
    % 给 demo_tour.m 用的"遥控器"：每一项都是一个函数
    api = struct( ...
        'setSource',  @apiSetSource, ...      % api.setSource('violin' / 'noise')
        'setType',    @apiSetType, ...        % api.setType('lowpass', struct(...))
        'moveParam',  @apiMoveParam, ...      % api.moveParam('f0', 800, 6)  慢慢移动滑块
        'setPlot2',   @apiSetPlot2, ...       % api.setPlot2('phase' / 'gd')
        'play',       @playSource, ...        % api.play('dry' / 'wet')
        'switchAB',   @switchAB, ...
        'stop',       @stopAudio, ...
        'setLoop',    @apiSetLoop, ...
        'newMystery', @newMystery, ...        % api.newMystery('peak', struct(...))
        'guess',      @apiGuess, ...          % api.guess('peakCut')
        'reveal',     @reveal, ...
        'export',     @exportCurrent, ...
        'caption',    @apiCaption);           % api.caption('text')  显示字幕；'' = 隐藏
    varargout{2} = api;
end

%% =====================================================================
%  音源
%% =====================================================================
    function onSourceChanged()
        if strcmp(ddSource.Value, 'wav') && (isempty(wavPath) || ~isfile(wavPath))
            pickWav();
        else
            loadSource();
        end
    end

    function pickWav()
        [fn, fp] = uigetfile({'*.wav;*.m4a;*.mp3;*.aiff;*.flac', 'Audio files'}, 'Choose an audio file');
        figure(fig);            % 选完文件后把界面拿回前台
        if isequal(fn, 0)                       % 取消了：回到小提琴
            if isempty(wavPath), ddSource.Value = 'violin'; loadSource(); end
            return
        end
        wavPath = fullfile(fp, fn);
        ddSource.Value = 'wav';
        loadSource();
    end

    function loadSource()
        stopAudio();
        switch ddSource.Value
            case 'violin'
                p = fullfile(here, 'audio', 'violin_XiaoPeng.wav');
                [x, fsIn, srcName] = frd_load_wav(p, -6);
                fs = fsIn;
            case 'noise'
                fs = 48000;
                rs = RandStream('mt19937ar', 'Seed', 2026);   % 固定种子：每次一样的噪声
                n  = randn(rs, 6*fs, 1);
                x  = n / max(abs(n)) * 10^(-6/20);
                srcName = 'whitenoise';
            case 'wav'
                [x, fsIn, srcName] = frd_load_wav(wavPath, -6);
                fs = fsIn;
        end
        [Pdry, fSpec] = frd_spectrum_db(x, fs);
        fPlot = logspace(log10(20), log10(0.498*fs), 4000);
        axMag.XLim = [20 fs/2];  ax2.XLim = [20 fs/2];  axSpec.XLim = [20 fs/2];
        process();
    end

%% =====================================================================
%  参数 ↔ 滑块
%% =====================================================================
    function onTypeChanged()
        curType = ddType.Value;
        writeSliders();
        process();
    end

    function writeSliders()
        % 把 params.(curType) 的数字写到三个滑块上
        p = params.(curType);
        logTicks  = log10([50 100 200 500 1000 2000 5000 10000 15000]);
        logLabels = {'50', '100', '200', '500', '1k', '2k', '5k', '10k', '15k'};
        switch curType
            case {'lowpass', 'highpass', 'peak'}
                if strcmp(curType, 'peak'), n1 = 'Center frequency'; else, n1 = 'Cutoff frequency'; end
                setSlider(1, n1, [log10(50) log10(15000)], log10(p.f0), logTicks, logLabels);
                setSlider(2, 'Q (sharpness / resonance)', [0.5 8], p.Q, [0.5 1 2 4 6 8], {});
                if strcmp(curType, 'peak')
                    setSlider(3, 'Gain', [-24 18], p.gainDb, -24:6:18, {});
                else
                    setSlider(3, '', [], [], [], {});
                end
            case 'comb'
                setSlider(1, 'Mic 2 is farther by (distance)', [5 300], p.distCm, [5 50 100 150 200 250 300], {});
                setSlider(2, 'Mic 2 level (g)', [0 1], p.g, 0:0.25:1, {});
                setSlider(3, '', [], [], [], {});
        end
        showValues();
    end

    function setSlider(k, name, lim, v, ticks, tickLabels)
        if isempty(lim)                      % 这个滤波器不用第 k 个滑块
            lbl(k).Text = '';  val(k).Text = '';
            sl(k).Visible = 'off';
            return
        end
        sl(k).Visible = 'on';
        lbl(k).Text = name;
        % 先放宽范围再设值，避免"值不在范围里"的错误
        sl(k).Limits = [min(lim(1), sl(k).Value) max(lim(2), sl(k).Value)];
        sl(k).Value  = v;
        sl(k).Limits = lim;
        sl(k).MajorTickLabelsMode = 'auto';   % 先恢复自动，再换刻度，避免数量不一致
        sl(k).MajorTicks = ticks;
        if ~isempty(tickLabels)
            sl(k).MajorTickLabels = tickLabels;
        end
        sl(k).MinorTicks = [];
    end

    function readSlider(k, v)
        % 把第 k 个滑块的值 v 写回 params.(curType)
        switch curType
            case {'lowpass', 'highpass', 'peak'}
                if k == 1, params.(curType).f0 = 10^v; end
                if k == 2, params.(curType).Q  = v;    end
                if k == 3, params.(curType).gainDb = v; end
            case 'comb'
                if k == 1, params.comb.distCm = v; end
                if k == 2, params.comb.g      = v; end
        end
    end

    function showValues()
        if mystery
            for kk = 1:3
                if strcmp(sl(kk).Visible, 'on'), val(kk).Text = '???'; end
            end
            return
        end
        p = params.(curType);
        switch curType
            case {'lowpass', 'highpass', 'peak'}
                val(1).Text = sprintf('%.0f Hz', p.f0);
                val(2).Text = sprintf('%.2f', p.Q);
                if strcmp(curType, 'peak'), val(3).Text = sprintf('%+.1f dB', p.gainDb); end
            case 'comb'
                val(1).Text = sprintf('%.0f cm', p.distCm);
                val(2).Text = sprintf('%.2f', p.g);
        end
    end

    function onSliderMoving(k, v)
        % 拖的过程中：只更新曲线（很快），不处理音频
        readSlider(k, v);
        showValues();
        updateResponse();
    end

    function onSliderDone()
        for kk = 1:3
            if strcmp(sl(kk).Visible, 'on'), readSlider(kk, sl(kk).Value); end
        end
        showValues();
        process();
    end

%% =====================================================================
%  滤波 + 画图
%% =====================================================================
    function design()
        if mystery
            [b, a, fInfo] = frd_design(mysteryType, mysteryP, fs);
        else
            [b, a, fInfo] = frd_design(curType, params.(curType), fs);
        end
    end

    function process()
        % 重新设计滤波器 → 处理整段音频 → 更新所有图
        design();
        wasPlaying = nowPlaying;
        if ~isempty(player) && isplaying(player), pos = player.CurrentSample; else, pos = 1; end
        stopAudio();
        [y, gainOut] = frd_process(x, b, a, cbNorm.Value);
        updateResponse();
        Pwet = frd_spectrum_db(y, fs);
        hDry.XData = fSpec;  hDry.YData = Pdry;
        hWet.XData = fSpec;  hWet.YData = Pwet;
        top = max(Pdry);
        axSpec.YLim = [top-90 top+10];
        updateMeasured();
        if ~isempty(wasPlaying)              % 如果刚才在播放，就从同一个位置继续
            startPlayer(wasPlaying, pos);
        end
    end

    function updateResponse()
        design();
        [m, ph, gd] = frd_freqresp(b, a, fPlot, fs);
        hMag.XData = fPlot;  hMag.YData = m;

        % 标记：低通/高通/EQ 画一条竖线在 f0；梳状滤波画出预测的凹口位置
        if strcmp(currentType(), 'comb')
            D  = fInfo.delaySamples;
            fn = (1:2:200) * fs/(2*D);
            fn = fn(fn < fs/2);
            [xx, yy] = vlines(fn, -60, -50);
        else
            p = currentParams();
            [xx, yy] = vlines(p.f0, -60, 24);
        end
        hMark.XData = xx;  hMark.YData = yy;

        if mystery
            title(axMag, 'Magnitude response — MYSTERY FILTER  (what is it?)');
        else
            title(axMag, ['Magnitude response — ' fInfo.name]);
        end

        if strcmp(ddPlot2.Value, 'phase')
            h2.XData = fPlot;  h2.YData = ph;
            ylabel(ax2, 'Phase (degrees)');
            title(ax2, 'Unwrapped phase response');
            ax2.YLimMode = 'auto';
        else
            gdMs = gd / fs * 1000;               % 样本 → 毫秒
            h2.XData = fPlot;  h2.YData = gdMs;
            ylabel(ax2, 'Group delay (ms)');
            title(ax2, 'Group delay  (how late each frequency arrives)');
            ok = gdMs(isfinite(gdMs));
            lo = min(0, prctile_(ok, 1));  hi = max(0.05, prctile_(ok, 99));
            ax2.YLim = [lo - 0.1*(hi-lo), hi + 0.1*(hi-lo)];
        end

        if mystery
            lblExpect.Text = 'Mystery! Look at the plots and listen, then make a guess below.';
        else
            lblExpect.Text = ['Expect: ' fInfo.expect];
        end
    end

    function updateMeasured()
        % 实测响应 = wet 频谱 − dry 频谱（再去掉我们加的输出音量）
        if cbMeasured.Value && ~isempty(y)
            Pwet = hWet.YData(:);
            meas = Pwet - Pdry - 20*log10(gainOut);
            meas(Pdry < max(Pdry) - 70) = NaN;     % 太安静的频率不可靠，不画
            hMeas.XData = fSpec;  hMeas.YData = meas;
        else
            hMeas.XData = NaN;  hMeas.YData = NaN;
        end
    end

    function t = currentType()
        if mystery, t = mysteryType; else, t = curType; end
    end

    function p = currentParams()
        if mystery, p = mysteryP; else, p = params.(curType); end
    end

%% =====================================================================
%  播放
%% =====================================================================
    function playSource(which)
        stopAudio();
        startPlayer(which, 1);
    end

    function startPlayer(which, pos)
        if strcmp(which, 'dry'), s = x; else, s = y; end
        player = audioplayer(s, fs);
        player.StopFcn = @(~, ~) onPlayerStopped();
        play(player, max(1, min(pos, numel(s))));
        nowPlaying = which;
        lblPlaying.Text = upper(which);
    end

    function switchAB()
        % 在同一个时间位置，从 dry 切到 wet（或者反过来）。最适合比较！
        if isempty(nowPlaying)
            playSource('dry');
            return
        end
        pos = player.CurrentSample;
        if strcmp(nowPlaying, 'dry'), nxt = 'wet'; else, nxt = 'dry'; end
        stopAudio();
        startPlayer(nxt, pos);
    end

    function stopAudio()
        if ~isempty(player)
            player.StopFcn = [];
            stop(player);
        end
        nowPlaying = '';
        if isvalid(lblPlaying), lblPlaying.Text = ''; end
    end

    function onPlayerStopped()
        % 播放到结尾时会来到这里（按 Stop 不会，因为 stopAudio 先关掉了 StopFcn）
        if loopPlay && ~isempty(nowPlaying) && isvalid(fig)
            startPlayer(nowPlaying, 1);           % 循环播放
            return
        end
        nowPlaying = '';
        if isvalid(lblPlaying), lblPlaying.Text = ''; end
    end

%% =====================================================================
%  遥控器（api）：给 demo_tour.m 用
%% =====================================================================
    function apiSetSource(src)
        ddSource.Value = src;
        loadSource();
    end

    function apiSetType(t, p)
        if nargin >= 2, params.(t) = p; end
        ddType.Value = t;
        onTypeChanged();
    end

    function apiMoveParam(name, target, secs)
        % 像用手拖一样，慢慢把滑块移到 target。拖的时候图在变；最后"放开"→ 重新处理音频
        switch name
            case 'f0',     kS = 1;  target = log10(target);   % 频率滑块用的是 log10(Hz)
            case 'distCm', kS = 1;
            case {'Q', 'g'}, kS = 2;
            case 'gainDb', kS = 3;
        end
        v0 = sl(kS).Value;
        n  = max(2, round(secs * 20));
        for i = 1:n
            v = v0 + (target - v0) * i/n;
            sl(kS).Value = v;
            onSliderMoving(kS, v);
            drawnow;
            pause(secs/n);
        end
        onSliderDone();
    end

    function apiSetPlot2(mode)
        ddPlot2.Value = mode;
        updateResponse();
    end

    function apiSetLoop(tf)
        loopPlay = tf;
    end

    function apiGuess(g)
        ddGuess.Value = g;
        checkGuess();
    end

    function apiCaption(txt)
        lblCaption.Text = txt;
        if isempty(txt), pg.RowHeight{1} = 0; else, pg.RowHeight{1} = 90; end
        drawnow;
    end

%% =====================================================================
%  导出
%% =====================================================================
    function exportCurrent()
        if mystery
            uialert(fig, 'Reveal the mystery filter first, then export.', 'Export');
            return
        end
        p = params.(curType);
        switch curType
            case 'lowpass',  tag = sprintf('lowpass_%dHz', round(p.f0));
            case 'highpass', tag = sprintf('highpass_%dHz', round(p.f0));
            case 'peak',     tag = sprintf('peakEQ_%dHz_%+ddB', round(p.f0), round(p.gainDb));
            case 'comb',     tag = sprintf('comb_%dcm', round(p.distCm));
        end
        out = frd_export_wav(y, fs, outDir, [srcName '_' tag]);
        uialert(fig, sprintf('Saved:\n%s', out), 'Export', 'Icon', 'success');
    end

%% =====================================================================
%  Mystery 模式：随机滤波器，先猜，再揭晓
%% =====================================================================
    function newMystery(fixedType, fixedP)
        % 不给参数 → 随机一个滤波器；给参数（演示用）→ 用指定的滤波器
        mystery = true;
        if nargin >= 2
            mysteryType = fixedType;
            mysteryP    = fixedP;
        else
            mysteryType = types{randi(4)};
            switch mysteryType
                case {'lowpass', 'highpass'}
                    mysteryP = struct('f0', round(10^(log10(300) + rand*log10(3000/300))), 'Q', 0.707);
                case 'peak'
                    g = (9 + rand*6) * sign(rand - 0.5);
                    mysteryP = struct('f0', round(10^(log10(400) + rand*log10(5000/400))), 'Q', 1.5, 'gainDb', g);
                case 'comb'
                    mysteryP = struct('distCm', round(20 + rand*130), 'g', 0.9);
            end
        end
        switch mysteryType
            case 'peak'
                if mysteryP.gainDb > 0, mysteryAns = 'peakBoost'; else, mysteryAns = 'peakCut'; end
            otherwise
                mysteryAns = mysteryType;
        end
        ddType.Enable = 'off';
        for kk = 1:3                       % 藏起滑块：不能偷看答案
            sl(kk).Enable = 'off';  sl(kk).Visible = 'off';
            lbl(kk).Text = '';  val(kk).Text = '';
        end
        btnExport.Enable = 'off';
        ddGuess.Enable = 'on';  btnCheck.Enable = 'on';  btnReveal.Enable = 'on';
        lblMystery.Text = 'A new mystery filter is loaded. Play Dry / Wet and study the plots.';
        showValues();
        process();
    end

    function checkGuess()
        if strcmp(ddGuess.Value, mysteryAns)
            lblMystery.Text = '✅ Correct! Press "Reveal answer" to see the exact settings.';
            lblMystery.FontColor = [0.1 0.55 0.1];
        else
            lblMystery.Text = '❌ Not quite. Look again: where does the curve go up or down?';
            lblMystery.FontColor = [0.8 0.1 0.1];
        end
    end

    function reveal()
        % 把 mystery 的设置交给正常模式，界面恢复
        params.(mysteryType) = mysteryP;
        curType = mysteryType;
        mystery = false;
        ddType.Value = curType;
        ddType.Enable = 'on';
        for kk = 1:3, sl(kk).Enable = 'on'; end
        btnExport.Enable = 'on';
        ddGuess.Enable = 'off';  btnCheck.Enable = 'off';  btnReveal.Enable = 'off';
        writeSliders();
        design();
        lblMystery.FontColor = [0 0 0];
        lblMystery.Text = ['Answer: ' fInfo.name];
        process();
    end

%% =====================================================================
%  小工具
%% =====================================================================
    function onClose()
        stopAudio();
        delete(fig);
    end

    function header(r, txt)
        h = uilabel(cg, 'Text', txt, 'FontWeight', 'bold', 'FontSize', 13);
        h.Layout.Row = r;  h.Layout.Column = [1 3];
    end

    function label(r, txt)
        h = uilabel(cg, 'Text', txt);
        h.Layout.Row = r;  h.Layout.Column = 1;
    end

    function span(h, r)
        h.Layout.Row = r;  h.Layout.Column = [1 3];
    end

    function place(h, r, c)
        h.Layout.Row = r;  h.Layout.Column = c;
    end
end

%% ===== 文件里的普通小函数（不是嵌套函数）=====
function [xx, yy] = vlines(f, y1, y2)
% 画很多条竖线：用 NaN 把每条线隔开，一个 line 对象就能画完
n  = numel(f);
xx = reshape([f(:) f(:) nan(n, 1)].', 1, []);
yy = reshape([repmat([y1 y2], n, 1) nan(n, 1)].', 1, []);
end

function v = prctile_(x, p)
% 简单的百分位数（不需要 Statistics Toolbox）
x = sort(x(:));
if isempty(x), v = 0; return; end
i = max(1, min(numel(x), round(p/100 * numel(x))));
v = x(i);
end
