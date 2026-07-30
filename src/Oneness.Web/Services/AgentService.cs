
using System.Collections.Concurrent;
using Oneness.Web.Models;

namespace Oneness.Web.Services;

public class AgentService : IAgentService
{
    private readonly ConcurrentDictionary<string, AgentStatus> _agents;

    public AgentService()
    {
        _agents = new ConcurrentDictionary<string, AgentStatus>(
            new[]
            {
                "ORACLEVAULT", "MARKETSCRYER", "SIGNALFORGE", "TRADEWEAVER",
                "RISKWARDEN", "PROX", "CASEBLADE", "SENTINEL", "SYNAPSE"
            }.ToDictionary(
                id => id,
                id => new AgentStatus { Id = id, Name = id, Healthy = true, LastHeartbeat = DateTime.UtcNow }
            )
        );
    }

    public List<AgentStatus> ListAgents() => _agents.Values.ToList();

    public AgentStatus? TickAgent(string id)
    {
        if (!_agents.TryGetValue(id, out var agent)) return null;
        agent.LastHeartbeat = DateTime.UtcNow;
        agent.LastAction = $"Ticked at {agent.LastHeartbeat:O}";
        return agent;
    }

    public object? ReadMemory(string path)
    {
        var full = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "OneDrive", "Desktop", "OnenessSystem", "memory", path.Replace('/', '\\'));
        if (!File.Exists(full)) return null;
        var ext = Path.GetExtension(full).ToLowerInvariant();
        if (ext is ".json")
            return System.Text.Json.JsonSerializer.Deserialize<object>(File.ReadAllText(full));
        return File.ReadAllText(full);
    }
}
