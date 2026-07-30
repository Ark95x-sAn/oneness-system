using Oneness.Web.Models;
using Microsoft.AspNetCore.Mvc;
using Oneness.Web.Services;

namespace Oneness.Web.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProjectsController : ControllerBase
{
    private readonly VsProjectService _projects;
    private readonly string _scanOutputPath;

    public ProjectsController(VsProjectService projects, OnenessConfig config)
    {
        _projects = projects;
        _scanOutputPath = Path.Combine(config.SystemRoot, "memory", "logs", "vs_projects.json");
    }

    [HttpGet]
    public IActionResult List() => Ok(_projects.ScanProjects(_scanOutputPath));

    [HttpPost("scan")]
    public IActionResult Scan()
    {
        var psi = new System.Diagnostics.ProcessStartInfo("powershell.exe",
            $"-ExecutionPolicy Bypass -File \"C:\\Users\\ArcXN\\OneDrive\\Desktop\\OnenessSystem\\scripts\\integrations\\scan_vs_projects.ps1\"")
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            CreateNoWindow = true
        };
        var proc = System.Diagnostics.Process.Start(psi);
        return Ok(new { started = proc?.Id, output = _scanOutputPath });
    }

    [HttpPost("build")]
    public async Task<IActionResult> Build([FromQuery] string path, [FromQuery] string config = "Release")
    {
        var result = await _projects.BuildAsync(path, config);
        return Ok(new { project = path, result });
    }
}

