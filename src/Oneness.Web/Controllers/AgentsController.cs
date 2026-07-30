
using Microsoft.AspNetCore.Mvc;
using Oneness.Web.Models;
using Oneness.Web.Services;

namespace Oneness.Web.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AgentsController : ControllerBase
{
    private readonly IAgentService _agents;
    private readonly AgentRuntime _runtime;

    public AgentsController(IAgentService agents, AgentRuntime runtime)
    {
        _agents = agents;
        _runtime = runtime;
    }

    [HttpGet]
    public IActionResult List() => Ok(_agents.ListAgents());

    [HttpPost("{id}/tick")]
    public IActionResult Tick(string id)
    {
        var agent = _agents.TickAgent(id);
        return agent == null ? NotFound() : Ok(agent);
    }

    [HttpPost("start-demo")]
    public IActionResult StartDemo()
    {
        var proc = _runtime.StartDemo();
        return proc == null ? BadRequest("Orchestrator not runnable") : Ok(new { pid = proc.Id });
    }
}
