
namespace Oneness.Web.Models;

public class AgentStatus
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public bool Healthy { get; set; }
    public DateTime LastHeartbeat { get; set; }
    public string? LastAction { get; set; }
    public Dictionary<string, object> State { get; set; } = new();
}
