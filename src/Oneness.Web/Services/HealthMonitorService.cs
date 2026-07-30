using System.Diagnostics;
using System.Management;
using System.ServiceProcess;
using Oneness.Web.Models;

namespace Oneness.Web.Services;

public class HealthMonitorService
{
    private readonly ILogger<HealthMonitorService> _logger;

    public HealthMonitorService(ILogger<HealthMonitorService> logger)
    {
        _logger = logger;
    }

    public HealthSnapshot GetSnapshot()
    {
        var snapshot = new HealthSnapshot();

        using var searcher = new ManagementObjectSearcher("SELECT * FROM Win32_LogicalDisk");
        foreach (var disk in searcher.Get().Cast<ManagementObject>())
        {
            var size = Convert.ToUInt64(disk["Size"]);
            var free = Convert.ToUInt64(disk["FreeSpace"]);
            snapshot.Disks.Add(new DiskInfo
            {
                Drive = disk["DeviceID"]?.ToString() ?? "?",
                SizeGb = Math.Round(size / (1024.0 * 1024 * 1024), 2),
                FreeGb = Math.Round(free / (1024.0 * 1024 * 1024), 2),
                UsedPercent = size == 0 ? 0 : Math.Round((size - free) / (double)size * 100, 1)
            });
        }

        var proc = Process.GetCurrentProcess();
        snapshot.MemoryUsedGb = Math.Round(proc.WorkingSet64 / (1024.0 * 1024 * 1024), 2);
        snapshot.MemoryTotalGb = Math.Round(GetTotalPhysicalMemoryGb(), 2);

        var critical = new[] { "wuauserv", "bits", "wscsvc", "WinDefend", "Spooler", "Dhcp", "Dnscache", "NlaSvc", "TermService", "WSearch" };
        foreach (var name in critical)
        {
            try
            {
                using var sc = new ServiceController(name);
                snapshot.Services.Add(new ServiceStatus
                {
                    Name = name,
                    Status = sc.Status.ToString(),
                    StartType = sc.StartType.ToString()
                });
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not query service {Name}", name);
            }
        }

        try
        {
            snapshot.RecentErrors = EventLog.GetEventLogs()
                .SelectMany(l =>
                {
                    try { return l.Entries.Cast<System.Diagnostics.EventLogEntry>().Where(e => e.TimeGenerated > DateTime.Now.AddHours(-24) && e.EntryType == EventLogEntryType.Error).Take(5); }
                    catch { return Enumerable.Empty<System.Diagnostics.EventLogEntry>(); }
                })
                .Select(e => new Models.EventLogEntry
                {
                    TimeCreated = e.TimeGenerated,
                    Level = e.EntryType.ToString(),
                    Id = (int)e.InstanceId,
                    Provider = e.Source,
                    Message = e.Message?.Substring(0, Math.Min(200, e.Message?.Length ?? 0)) ?? ""
                })
                .OrderByDescending(e => e.TimeCreated)
                .Take(10)
                .ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Could not read event logs");
        }

        return snapshot;
    }

    private static double GetTotalPhysicalMemoryGb()
    {
        using var mc = new ManagementClass("Win32_ComputerSystem");
        foreach (var mo in mc.GetInstances().Cast<ManagementObject>())
        {
            var total = Convert.ToUInt64(mo["TotalPhysicalMemory"]);
            return Math.Round(total / (1024.0 * 1024 * 1024), 2);
        }
        return 0;
    }
}
