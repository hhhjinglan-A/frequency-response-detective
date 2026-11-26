function outPath = frd_export_wav(y, fs, outDir, fileName)
%FRD_EXPORT_WAV  保存 WAV（24 bit）。文件夹不存在就自动建立。

if ~exist(outDir, 'dir'), mkdir(outDir); end
fileName = regexprep(fileName, '[^\w\-\.\+]', '_');   % 文件名里只留安全的字符
if ~endsWith(fileName, '.wav'), fileName = [fileName '.wav']; end
outPath = fullfile(outDir, fileName);
audiowrite(outPath, y, fs, 'BitsPerSample', 24);
end
