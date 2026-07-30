
using Microsoft.AspNetCore.Mvc;
using Oneness.Web.Services;

namespace Oneness.Web.Controllers;

[ApiController]
[Route("api/[controller]")]
public class HealthController : ControllerBase
{
    private readonly HealthMonitorService _health;

    public HealthController(HealthMonitorService health)
    {
        _health = health;
    }

    [HttpGet]
    public IActionResult Get() => Ok(_health.GetSnapshot());
}
