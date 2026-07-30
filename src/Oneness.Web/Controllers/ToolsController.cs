using Microsoft.AspNetCore.Mvc;
using Oneness.Web.Models;
using Oneness.Web.Services;

namespace Oneness.Web.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ToolsController : ControllerBase
{
    private readonly AiToolService _tools;

    public ToolsController(AiToolService tools)
    {
        _tools = tools;
    }

    [HttpGet]
    public IActionResult List() => Ok(_tools.DiscoverTools());

    [HttpPost("launch")]
    public IActionResult Launch([FromBody] ToolLaunchRequest req)
    {
        var result = _tools.LaunchTool(req.ToolId);
        return result == null ? BadRequest("Tool not launchable") : Ok(new { status = result });
    }
}
