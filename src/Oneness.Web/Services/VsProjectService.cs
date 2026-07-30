using System.Diagnostics;
using Oneness.Web.Models;

namespace Oneness.Web.Services;

public class VsProjectService
{
    private readonly ILogger<VsProjectService> _logger;

    public VsProjectService(ILogger<VsProjectService> logger)
    {
        _logger = logger;
    }

    public List<VsProject> ScanProjects(string scanOutputPath)
    {
        var projects = new List<VsProject>();
        if (!File.Exists(scanOutputPath)) return projects;
        try
        {
            var data = System.Text.Json.JsonSerializer.Deserialize<List<ScanRoot>>(File.ReadAllText(scanOutputPath));
            if (data == null) return projects;
            foreach (var root in data)
            {
                foreach (var s in root.Solutions)
                    projects.Add(new VsProject { Path = s.FullName, Name = Path.GetFileNameWithoutExtension(s.FullName), Type = "sln", LastModified = s.LastWriteTime });
                foreach (var p in root.CSharpProjects)
                    projects.Add(new VsProject { Path = p.FullName, Name = Path.GetFileNameWithoutExtension(p.FullName), Type = "csproj", LastModified = p.LastWriteTime });
                foreach (var n in root.NodeProjects)
                    projects.Add(new VsProject { Path = n.FullName, Name = Path.GetFileName(Path.GetDirectoryName(n.FullName)) ?? "", Type = "node", LastModified = n.LastWriteTime });
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to parse VS project scan");
        }
        return projects;
    }

    public async Task<string> BuildAsync(string projectPath, string configuration = "Release")
    {
        if (!File.Exists(projectPath)) return "not found";
        var psi = new ProcessStartInfo("dotnet", $"build \"{projectPath}\" -c {configuration}")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };
        var proc = Process.Start(psi)!;
        var output = await proc.StandardOutput.ReadToEndAsync();
        var error = await proc.StandardError.ReadToEndAsync();
        await proc.WaitForExitAsync();
        return proc.ExitCode == 0 ? $"ok: {output.Substring(0, Math.Min(200, output.Length))}" : $"failed: {error.Substring(0, Math.Min(400, error.Length))}";
    }

    private class ScanRoot
    {
        public string Root { get; set; } = string.Empty;
        public List<ProjectRef> Solutions { get; set; } = new();
        public List<ProjectRef> CSharpProjects { get; set; } = new();
        public List<ProjectRef> NodeProjects { get; set; } = new();
    }

    private class ProjectRef
    {
        public string FullName { get; set; } = string.Empty;
        public DateTime LastWriteTime { get; set; }
    }
}
