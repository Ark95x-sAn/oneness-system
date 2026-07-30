
using Oneness.Web.Models;

namespace Oneness.Web.Services;

public interface IAgentService
{
    List<AgentStatus> ListAgents();
    AgentStatus? TickAgent(string id);
    object? ReadMemory(string path);
}
