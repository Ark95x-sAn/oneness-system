
namespace Oneness.Web.Services;

public class AgentBackgroundService : BackgroundService
{
    private readonly ILogger<AgentBackgroundService> _logger;
    private readonly IAgentService _agents;

    public AgentBackgroundService(ILogger<AgentBackgroundService> logger, IAgentService agents)
    {
        _logger = logger;
        _agents = agents;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            foreach (var agent in _agents.ListAgents())
            {
                _agents.TickAgent(agent.Id);
                _logger.LogDebug("Heartbeat {Agent}", agent.Id);
            }
            await Task.Delay(TimeSpan.FromMinutes(1), stoppingToken);
        }
    }
}
