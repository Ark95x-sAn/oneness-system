namespace Oneness.Web.Models;

public class VsProject
{
    public string Path { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
    public string Type { get; set; } = string.Empty;
    public DateTime LastModified { get; set; }
    public string? LastBuildStatus { get; set; }
}
