
using System.Diagnostics;
using Oneness.Web.Models;

namespace Oneness.Web.Services;

public class AgentRuntime
{
    private readonly ILogger<AgentRuntime> _logger;
    private readonly string _pythonPath;
    private readonly string _orchPath;

    public AgentRuntime(ILogger<AgentRuntime> logger, OnenessConfig config)
    {
        _logger = logger;
        _pythonPath = Path.Combine(config.SystemRoot, "venv", "Scripts", "python.exe");
        _orchPath = Path.Combine(config.SystemRoot, "src", "oneness_orchestrator.py");
    }

    public bool IsOrchestratorRunnable => File.Exists(_pythonPath) && File.Exists(_orchPath);

    public Process? StartDemo()
    {
        if (!IsOrchestratorRunnable) return null;
        var psi = new ProcessStartInfo(_pythonPath, _orchPath)
        {
            WorkingDirectory = Path.GetDirectoryName(_orchPath)!,
            EnvironmentVariables = { ["DEMO_MODE"] = "true" },
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        var proc = Process.Start(psi);
        _logger.LogInformation("Started orchestrator PID {Pid}", proc?.Id);
        return proc;
    }
}
