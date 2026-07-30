
namespace Oneness.Web.Services;

public class HealthBackgroundService : BackgroundService
{
    private readonly ILogger<HealthBackgroundService> _logger;
    private readonly HealthMonitorService _health;

    public HealthBackgroundService(ILogger<HealthBackgroundService> logger, HealthMonitorService health)
    {
        _logger = logger;
        _health = health;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            var snap = _health.GetSnapshot();
            _logger.LogInformation("PC health: C: {UsedPct}% used, {Errors} recent errors",
                snap.Disks.FirstOrDefault(d => d.Drive == "C:")?.UsedPercent,
                snap.RecentErrors.Count);
            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }
}
