function demo_tour
%DEMO_TOUR  自动演示（大约 3 分半钟）：给录视频用。
%
%   用法：
%     1. 先打开录屏软件（OBS），开始录屏
%     2. 在 MATLAB 命令行输入  demo_tour
%     3. 演示结束后停止录屏
%
%   程序会自动：换滤波器、慢慢移动滑块、播放 dry / wet、A/B 切换、
%   玩一次 Mystery、导出 WAV。每一步在界面上方显示英文字幕。
%   中途想停止：直接关掉界面窗口就可以。

[fig, api] = FrequencyResponseDetective;
fig.WindowState = 'maximized';          % 全屏，录出来更清楚
api.setLoop(true);                       % 声音播完自动从头再播
api.setPlot2('gd');

try
    %% ---- 开场 ----
    say('Get ready... the demo starts in 3 seconds.', 3);
    say('FREQUENCY RESPONSE DETECTIVE  —  Jinglan Huang, MUE 602', 4);
    say('Sound: a violin piece, "小蓬又泛曾行路" (Xiao Peng You Fan Ceng Xing Lu), played by my friend.', 5);
    say('Top: magnitude response (dB).   Middle: group delay.   Bottom: spectrum of the real audio (gray = dry, blue = wet).', 7);

    %% ---- 原声 ----
    api.setType('lowpass', struct('f0', 8000, 'Q', 0.707));
    api.play('dry');
    say('First, the DRY sound: the original violin.', 6);

    %% ---- 1. 低通 ----
    api.play('wet');
    say('Filter 1: LOW-PASS.  I move the cutoff frequency down...', 1);
    api.moveParam('f0', 800, 6);
    say('Frequencies above the cutoff go down.  Listen: the violin sounds darker and muffled.', 6);
    api.switchAB();
    say('A/B switch:  now DRY.  Bright again.', 4);
    api.switchAB();
    say('Now WET.  Dark again.', 4);
    say('The orange line is MEASURED from the real audio (wet − dry).  It sits on the blue theory line, so the plot matches the sound.', 7);
    api.moveParam('Q', 4, 4);
    say('Higher Q:  a peak (resonance) at the cutoff.  The group delay also has a peak, about 1 ms.', 7);

    %% ---- 2. 高通 ----
    api.setType('highpass', struct('f0', 1000, 'Q', 0.707));
    say('Filter 2: HIGH-PASS at 1 kHz.  Low frequencies go down.  The violin sounds thin, with no body.', 7);
    api.switchAB();
    say('DRY:  warm and full.', 4);
    api.switchAB();
    say('WET:  thin.', 4);

    %% ---- 3. Peaking EQ ----
    api.setType('peak', struct('f0', 3000, 'Q', 1.4, 'gainDb', 12));
    say('Filter 3: PEAKING EQ,  +12 dB at 3 kHz.  The violin sounds brighter and sharper.', 7);
    say('Now I change the gain to −24 dB and move it to 660 Hz...', 1);
    api.moveParam('gainDb', -24, 4);
    api.moveParam('f0', 660, 3);
    api.moveParam('Q', 4, 2);
    say('A deep, narrow cut works like a NOTCH filter.  Notes near 660 Hz (E5) get weaker.', 7);

    %% ---- 4. 两个麦克风（梳状滤波）----
    api.setType('comb', struct('distCm', 34.3, 'g', 0.9));
    api.setSource('noise');
    api.play('wet');
    say('Filter 4: TWO MICROPHONES.  Mic 2 is 34 cm farther  →  1 ms delay  →  notches at 500, 1500, 2500 Hz ...  (white noise test signal)', 8);
    api.switchAB();
    say('DRY noise.', 3);
    api.switchAB();
    say('WET:  a hollow, "tube" sound.', 4);
    say('Now I move mic 2 farther away...', 1);
    api.moveParam('distCm', 150, 7);
    say('Farther mic  →  longer delay  →  the notches move lower and closer together.', 6);
    api.setPlot2('phase');
    say('Phase response:  a fast phase swing at every notch.', 6);
    api.setPlot2('gd');
    api.setType('comb', struct('distCm', 34.3, 'g', 0.9));
    api.setSource('violin');
    api.play('wet');
    say('The same comb filter on the violin:  hollow and "phasey".  This happens when two mics record one instrument.', 8);

    %% ---- 5. Mystery ----
    api.newMystery('peak', struct('f0', 1500, 'Q', 1.5, 'gainDb', -10));
    api.play('wet');
    say('MYSTERY MODE:  the filter name is hidden.  Let''s be detectives!', 5);
    say('Evidence 1:  low and high frequencies stay at 0 dB,  so it is NOT a low-pass or a high-pass.', 7);
    say('Evidence 2:  only ONE dip, about −10 dB near 1.5 kHz,  so it is NOT a comb filter.', 7);
    api.switchAB();
    say('DRY', 3);
    api.switchAB();
    say('WET:  a little softer in the middle.', 4);
    api.guess('peakCut');
    say('My guess:  PEAKING EQ (cut).', 4);
    api.reveal();
    say('Correct!  Peaking EQ,  1500 Hz,  −10 dB.', 5);

    %% ---- 6. 导出 ----
    api.stop();
    api.setType('lowpass', struct('f0', 1000, 'Q', 0.707));
    say('Finally, I export the wet sound as a WAV file.', 3);
    api.export();
    pause(4);
    say('All 11 automatic tests in verify_project pass.   Thank you!', 5);

    api.setLoop(false);
    api.stop();
catch ME
    if ~isvalid(fig) || strcmp(ME.identifier, 'demo:closed')
        fprintf('Demo stopped (window closed).\n');
    else
        rethrow(ME);
    end
end

%% ---- 小工具：显示字幕，然后等几秒 ----
    function say(txt, secs)
        if ~isvalid(fig), error('demo:closed', 'Window closed'); end
        api.caption(txt);
        t0 = tic;
        while toc(t0) < secs
            if ~isvalid(fig), error('demo:closed', 'Window closed'); end
            pause(0.1);
        end
    end
end
