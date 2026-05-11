const ERROR_HINTS = [
  {
    match: /permission denied|operation not permitted|eacces/i,
    summary: '权限不足，Homebrew 无法写入目标文件或应用目录。',
    suggestion: '确认当前用户有权限写入目标路径；必要时修复 Homebrew 权限后重试。'
  },
  {
    match: /already exists|it seems there is already an app|app already exists/i,
    summary: '目标应用已存在，Homebrew Cask 不想覆盖现有 App。',
    suggestion: '退出该应用后，先备份或移除现有 App，再重试；也可以在终端中手动执行 brew reinstall --cask --force。'
  },
  {
    match: /checksum mismatch|sha256 mismatch/i,
    summary: '下载文件校验失败，可能是缓存损坏或上游包已更新。',
    suggestion: '先运行 brew cleanup，并删除对应下载缓存后重试。'
  },
  {
    match: /is currently running|app is running|application is running/i,
    summary: '应用仍在运行，升级器无法替换它。',
    suggestion: '完全退出该应用及后台进程，然后重新升级。'
  },
  {
    match: /no such file or directory|not found/i,
    summary: '升级命令引用的文件或工具不存在。',
    suggestion: '重新扫描后再试；如果仍失败，请确认 Homebrew 和相关 cask 仍然安装。'
  }
];

export function analyzeFailure({ command, code, output, skipped = false }) {
  const cleanCommand = String(command || '').trim() || '未知命令';
  const cleanOutput = String(output || '').trim();

  if (skipped) {
    const summary = '这个步骤未开始执行。任务可能被取消、应用退出，或旧版本执行器提前结束。';
    const suggestion = `重新点击该软件的“升级”，或在终端手动执行：${cleanCommand}`;
    return buildAnalysis({ summary, suggestion, command: cleanCommand, output: cleanOutput });
  }

  const errorLine = extractErrorLine(cleanOutput);
  const hinted = ERROR_HINTS.find((hint) => hint.match.test(cleanOutput));
  const codeText = code === null || code === undefined ? '未知退出码' : `退出码 ${code}`;

  let summary = hinted?.summary;
  if (!summary && errorLine) {
    summary = `${codeText}：${errorLine}`;
  }
  if (!summary) {
    summary = `${codeText}，但最近输出里没有捕获到明确错误行。`;
  }

  const suggestion = hinted?.suggestion
    ?? `点击“查看日志”查看完整任务日志；也可以在终端手动执行并复制完整输出：${cleanCommand}`;

  return buildAnalysis({
    summary,
    suggestion,
    command: cleanCommand,
    output: cleanOutput
  });
}

function extractErrorLine(output) {
  const lines = output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.find((line) => /(^|\b)(error|failed|failure|permission denied|already exists|checksum|not found)(\b|:)/i.test(line)) ?? '';
}

function buildAnalysis({ summary, suggestion, command, output }) {
  const copyParts = [
    `失败原因：${summary}`,
    `解决方案：${suggestion}`,
    `命令：${command}`
  ];
  if (output) {
    copyParts.push(`最近输出：\n${output}`);
  }
  return {
    summary,
    suggestion,
    copyText: copyParts.join('\n')
  };
}
