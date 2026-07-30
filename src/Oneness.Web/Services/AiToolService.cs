using System.Diagnostics;
using Oneness.Web.Models;

namespace Oneness.Web.Services;

public class AiToolService
{
    private readonly string _scriptsDir;

    public AiToolService(OnenessConfig config)
    {
        _scriptsDir = Path.Combine(config.SystemRoot, "scripts", "integrations");
    }

    public List<AiTool> DiscoverTools()
    {
        var tools = new List<AiTool>
        {
            new() { Id = "claude-desktop", Name = "Claude Desktop", Type = "desktop", ExecutablePath = FindOnPath("claude.exe"), LaunchScript = "launch_claude_desktop.ps1", Notes = "Anthropic desktop app" },
            new() { Id = "claude-code", Name = "Claude Code CLI", Type = "cli", ExecutablePath = FindOnPath("npx"), LaunchScript = "launch_claude_code.ps1", Notes = "Terminal AI coding agent (npx @anthropic-ai/claude-code)" },
            new() { Id = "openclaw", Name = "OpenClaw", Type = "cli", ExecutablePath = FindOnPath("openclaw"), LaunchScript = "launch_openclaw.ps1", Notes = "Open-source agentic coding" },
            new() { Id = "openai-codex", Name = "Codex CLI", Type = "cli", ExecutablePath = FindOnPath("npx"), LaunchScript = "launch_codex_cli.ps1", Notes = "OpenAI Codex in terminal (npx openai-codex)" },
            new() { Id = "github-copilot", Name = "GitHub Copilot CLI", Type = "cli", ExecutablePath = FindOnPath("gh.exe"), LaunchScript = "launch_github_copilot.ps1", Notes = "gh copilot commands" },
            new() { Id = "perplexity", Name = "Perplexity AI", Type = "web", WebUrl = "https://www.perplexity.ai", LaunchScript = "launch_perplexity_playwright.ps1", Notes = "AI search via Playwright (bot guard may require human browser)" },
            new() { Id = "blackbox", Name = "Blackbox AI", Type = "web", WebUrl = "https://www.blackbox.ai", LaunchScript = "launch_blackbox_playwright.ps1", Notes = "Coding agent platform via Playwright" },
            new() { Id = "vscode", Name = "Visual Studio Code", Type = "desktop", ExecutablePath = FindOnPath("code.cmd"), LaunchScript = "", Notes = "Editor with Copilot/Codex extensions" },
        };

        foreach (var tool in tools)
        {
            tool.Detected = !string.IsNullOrEmpty(tool.ExecutablePath) || !string.IsNullOrEmpty(tool.WebUrl);
            tool.Status = tool.Detected ? "ready" : "not installed";
        }
        return tools;
    }

    public string? LaunchTool(string id)
    {
        var tool = DiscoverTools().FirstOrDefault(t => t.Id == id);
        if (tool == null || string.IsNullOrEmpty(tool.LaunchScript)) return null;
        var script = Path.Combine(_scriptsDir, tool.LaunchScript);
        if (!File.Exists(script)) return null;
        var psi = new ProcessStartInfo("powershell.exe", $"-ExecutionPolicy Bypass -File \"{script}\"")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        var proc = Process.Start(psi);
        return $"started pid {proc?.Id}";
    }

    private static string? FindOnPath(string name)
    {
        var paths = Environment.GetEnvironmentVariable("PATH")?.Split(Path.PathSeparator) ?? Array.Empty<string>();
        foreach (var dir in paths)
        {
            var full = Path.Combine(dir, name);
            if (File.Exists(full)) return full;
        }
        return null;
    }
}

