
namespace Oneness.Web.Models;

public class HealthSnapshot
{
    public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    public double CpuPercent { get; set; }
    public double MemoryUsedGb { get; set; }
    public double MemoryTotalGb { get; set; }
    public List<DiskInfo> Disks { get; set; } = new();
    public List<ServiceStatus> Services { get; set; } = new();
    public List<EventLogEntry> RecentErrors { get; set; } = new();
}

public class DiskInfo
{
    public string Drive { get; set; } = string.Empty;
    public double SizeGb { get; set; }
    public double FreeGb { get; set; }
    public double UsedPercent { get; set; }
}

public class ServiceStatus
{
    public string Name { get; set; } = string.Empty;
    public string Status { get; set; } = string.Empty;
    public string StartType { get; set; } = string.Empty;
}

public class EventLogEntry
{
    public DateTime TimeCreated { get; set; }
    public string Level { get; set; } = string.Empty;
    public int Id { get; set; }
    public string Provider { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}
