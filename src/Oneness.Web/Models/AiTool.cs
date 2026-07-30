namespace Oneness.Web.Models;

public class AiTool
{
    public string Id { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public string? ExecutablePath { get; set; }
    public string? WebUrl { get; set; }
    public bool Detected { get; set; }
    public string Status { get; set; } = "unknown";
    public string LaunchScript { get; set; } = string.Empty;
    public string Notes { get; set; } = string.Empty;
}

public class ToolLaunchRequest
{
    public string ToolId { get; set; } = string.Empty;
}
