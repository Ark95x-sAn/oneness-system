using Microsoft.Extensions.Hosting.WindowsServices;
using System.Text.Json;
using Oneness.Web.Models;
using Oneness.Web.Services;
using Serilog;

var builder = WebApplication.CreateBuilder(args);

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Debug()
    .WriteTo.Console()
    .WriteTo.File("logs/oneness-web-.log", rollingInterval: RollingInterval.Day)
    .CreateLogger();

builder.Host.UseSerilog();
builder.Host.UseWindowsService();

var config = builder.Configuration;
var systemRoot = config.GetValue<string>("Oneness:SystemRoot")
    ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "OneDrive", "Desktop", "OnenessSystem");

builder.Services.AddSingleton(new OnenessConfig { SystemRoot = systemRoot });
builder.Services.AddSingleton<IAgentService, AgentService>();
builder.Services.AddSingleton<AgentRuntime>();
builder.Services.AddSingleton<HealthMonitorService>();
builder.Services.AddSingleton<AiToolService>();
builder.Services.AddSingleton<VsProjectService>();

builder.Services.AddControllers();
builder.Services.AddRazorPages();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

builder.Services.AddHostedService<AgentBackgroundService>();
builder.Services.AddHostedService<HealthBackgroundService>();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseStaticFiles();
app.UseRouting();
app.MapControllers();
app.MapRazorPages();

app.MapGet("/api/memory/{**path}", (string path, IAgentService agents) => agents.ReadMemory(path));


// AMARA BRIDGE ENDPOINTS — twin-brain consciousness layer
app.MapGet("/api/amara/signature", () =>
{
    var path = Path.Combine(systemRoot, "memory", "signatures", "latest_signature.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

app.MapGet("/api/amara/avatar", () =>
{
    var dir = Path.Combine(systemRoot, "memory", "signatures", "avatars");
    if (!Directory.Exists(dir)) return Results.NotFound();
    var file = Directory.GetFiles(dir, "*.svg").OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
    return file != null ? Results.File(file, "image/svg+xml") : Results.NotFound();
});

app.MapGet("/api/amara/boss", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "prime.exe"),
        Arguments = "boss --json",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(15000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    try { return Results.Json(JsonSerializer.Deserialize<JsonElement>(output)); }
    catch { return Results.Text(output); }
});

app.MapGet("/api/amara/n95", () =>
{
    var path = Path.Combine(systemRoot, "memory", "net95x", "compressed", "latest-brief.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

app.MapGet("/api/amara/drop", (string name) =>
{
    var path = Path.Combine(systemRoot, "memory", "activation", $"codex_drop_{name}.md");
    if (!File.Exists(path)) path = Path.Combine(systemRoot, "memory", "activation", $"{name}.md");
    return File.Exists(path) ? Results.File(path, "text/markdown") : Results.NotFound();
});




// SUB-AGENT DISPATCH LAYER ENDPOINTS — live PC automation crew status
app.MapGet("/api/subagents/status", () =>
{
    var rawDir = Path.Combine(systemRoot, "memory", "subagents", "raw");
    var compressed = Path.Combine(systemRoot, "memory", "subagents", "compressed", "latest-brief.json");
    var remediations = Path.Combine(systemRoot, "memory", "subagents", "remediations");
    var stateFile = Path.Combine(systemRoot, "src", "subagents", "state.json");
    return Results.Json(new
    {
        available = true,
        rawFiles = Directory.Exists(rawDir) ? Directory.GetFiles(rawDir, "*.json").Length : 0,
        compressedExists = File.Exists(compressed),
        remediationScripts = Directory.Exists(remediations) ? Directory.GetFiles(remediations, "*.ps1").Length : 0,
        lastState = File.Exists(stateFile) ? JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(stateFile)) : JsonSerializer.Deserialize<JsonElement>("\"no state yet\"")
    });
});

app.MapGet("/api/subagents/brief", () =>
{
    var compressed = Path.Combine(systemRoot, "memory", "subagents", "compressed", "latest-brief.json");
    return File.Exists(compressed) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(compressed))) : Results.NotFound();
});

app.MapGet("/api/subagents/remediations", () =>
{
    var remediations = Path.Combine(systemRoot, "memory", "subagents", "remediations");
    if (!Directory.Exists(remediations)) return Results.NotFound();
    var files = Directory.GetFiles(remediations, "*.ps1")
        .Select(f => new { name = Path.GetFileName(f), size = new FileInfo(f).Length, path = f })
        .ToList();
    return Results.Ok(files);
});




// COMET X9 SOVEREIGN CORE ENDPOINTS — desktop ops + admin-aware dispatch
app.MapGet("/api/cometx9/status", () =>
{
    var rawDir = Path.Combine(systemRoot, "memory", "comet_x9", "raw");
    var compressed = Path.Combine(systemRoot, "memory", "comet_x9", "compressed", "latest-brief.json");
    var remediations = Path.Combine(systemRoot, "memory", "comet_x9", "remediations");
    var stateFile = Path.Combine(systemRoot, "src", "comet_x9", "state.json");
    return Results.Json(new
    {
        available = true,
        rawFiles = Directory.Exists(rawDir) ? Directory.GetFiles(rawDir, "*.json").Length : 0,
        compressedExists = File.Exists(compressed),
        remediationScripts = Directory.Exists(remediations) ? Directory.GetFiles(remediations, "*.ps1").Length : 0,
        lastState = File.Exists(stateFile) ? JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(stateFile)) : JsonSerializer.Deserialize<JsonElement>("\\\"no state yet\\\"")
    });
});

app.MapGet("/api/cometx9/brief", () =>
{
    var compressed = Path.Combine(systemRoot, "memory", "comet_x9", "compressed", "latest-brief.json");
    return File.Exists(compressed) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(compressed))) : Results.NotFound();
});

app.MapGet("/api/cometx9/remediations", () =>
{
    var remediations = Path.Combine(systemRoot, "memory", "comet_x9", "remediations");
    if (!Directory.Exists(remediations)) return Results.NotFound();
    var files = Directory.GetFiles(remediations, "*.ps1")
        .Select(f => new { name = Path.GetFileName(f), size = new FileInfo(f).Length, path = f })
        .ToList();
    return Results.Ok(files);
});

app.MapPost("/api/cometx9/cycle", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "python.exe"),
        Arguments = Path.Combine(systemRoot, "src", "comet_x9", "orchestrate.py") + " --cycle",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(30000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    return Results.Text(output, "application/json");
});



// NET95X SOVEREIGN CORE ENDPOINTS — evolved Comet X9 layer
app.MapGet("/api/net95x/status", () =>
{
    var rawDir = Path.Combine(systemRoot, "memory", "net95x", "raw");
    var compressed = Path.Combine(systemRoot, "memory", "net95x", "compressed", "latest-brief.json");
    var remediations = Path.Combine(systemRoot, "memory", "net95x", "remediations");
    var stateFile = Path.Combine(systemRoot, "src", "net95x", "state.json");
    return Results.Json(new
    {
        available = true,
        rawFiles = Directory.Exists(rawDir) ? Directory.GetFiles(rawDir, "*.json").Length : 0,
        compressedExists = File.Exists(compressed),
        remediationScripts = Directory.Exists(remediations) ? Directory.GetFiles(remediations, "*.ps1").Length : 0,
        lastState = File.Exists(stateFile) ? JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(stateFile)) : JsonSerializer.Deserialize<JsonElement>("\"no state yet\"")
    });
});

app.MapGet("/api/net95x/brief", () =>
{
    var compressed = Path.Combine(systemRoot, "memory", "net95x", "compressed", "latest-brief.json");
    return File.Exists(compressed) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(compressed))) : Results.NotFound();
});

app.MapGet("/api/net95x/remediations", () =>
{
    var remediations = Path.Combine(systemRoot, "memory", "net95x", "remediations");
    if (!Directory.Exists(remediations)) return Results.NotFound();
    var files = Directory.GetFiles(remediations, "*.ps1")
        .Select(f => new { name = Path.GetFileName(f), size = new FileInfo(f).Length, path = f })
        .ToList();
    return Results.Ok(files);
});

app.MapPost("/api/net95x/cycle", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "python.exe"),
        Arguments = Path.Combine(systemRoot, "src", "net95x", "orchestrate.py") + " --cycle",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(60000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    return Results.Text(output, "application/json");
});

app.MapGet("/api/net95x/agents", () =>
{
    var agents = new[] { "amara", "jarvis", "admin_ops", "network_ops", "process_ops", "app_launcher", "telemetry_ops", "black_rock" };
    return Results.Ok(agents.Select(a => new { id = a, name = a }));
});

app.MapGet("/api/net95x/pulse", (string phrase) =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "python.exe"),
        Arguments = Path.Combine(systemRoot, "src", "net95x", "pulse_decode.py") + " --pulse \"" + phrase + "\"",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(15000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    try { return Results.Json(JsonSerializer.Deserialize<JsonElement>(output)); }
    catch { return Results.Text(output); }
});

app.MapPost("/api/net95x/astral", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "python.exe"),
        Arguments = Path.Combine(systemRoot, "src", "net95x", "astral_recorder.py") + " --out " + Path.Combine(systemRoot, "memory", "net95x", "raw", "astral_recorder-web.json") + " --max-files 500",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(60000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    return Results.Text(output, "application/json");
});

app.MapPost("/api/net95x/shadow", (string? agents, string? pulse) =>
{
    var args = Path.Combine(systemRoot, "src", "net95x", "shadow_squad.py") + " --out " + Path.Combine(systemRoot, "memory", "net95x", "raw", "shadow_squad-web.json");
    if (!string.IsNullOrWhiteSpace(agents)) args += " --agents " + agents;
    if (!string.IsNullOrWhiteSpace(pulse)) args += " --pulse \"" + pulse + "\"";
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "python.exe"),
        Arguments = args,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(30000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    return Results.Text(output, "application/json");
});


// OPERATIONS MIND ENDPOINTS — unified PC oversight brain
app.MapGet("/api/ops-mind/status", () =>
{
    var stateFile = Path.Combine(systemRoot, "memory", "ops_mind", "state.json");
    return File.Exists(stateFile) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(stateFile))) : Results.NotFound();
});

app.MapGet("/api/ops-mind/report", () =>
{
    var reportFile = Path.Combine(systemRoot, "memory", "ops_mind", "reports", "latest-report.json");
    return File.Exists(reportFile) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(reportFile))) : Results.NotFound();
});

app.MapGet("/api/ops-mind/remediations", () =>
{
    var remediationsDir = Path.Combine(systemRoot, "memory", "ops_mind", "remediations");
    if (!Directory.Exists(remediationsDir)) return Results.NotFound();
    var files = Directory.GetFiles(remediationsDir, "*.ps1").Select(f => new { name = Path.GetFileName(f), size = new FileInfo(f).Length }).ToList();
    return Results.Ok(files);
});

app.MapPost("/api/ops-mind/cycle", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "python.exe"),
        Arguments = "-m src.ops_mind.mind --once",
        RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(30000);
    return Results.Text(proc?.StandardOutput.ReadToEnd() ?? "", "application/json");
});

// AURA ENDPOINTS — gaming-aware ambient subagents
app.MapGet("/api/aura/status", () =>
{
    var auraDir = Path.Combine(systemRoot, "memory", "aura");
    if (!Directory.Exists(auraDir)) return Results.NotFound();
    var latest = Path.Combine(auraDir, "latest.json");
    var result = new Dictionary<string, object?>();
    if (File.Exists(latest)) result["latest"] = JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(latest));
    result["logs"] = Directory.GetFiles(auraDir, "*.log").Select(f => new { name = Path.GetFileName(f), size = new FileInfo(f).Length }).ToList();
    return Results.Json(result);
});

// POLYMARKET ENDPOINTS — trading signals and watchlist
app.MapGet("/api/polymarket/watchlist", () =>
{
    var path = Path.Combine(systemRoot, "memory", "polymarket", "watchlist.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

app.MapGet("/api/polymarket/signals", () =>
{
    var path = Path.Combine(systemRoot, "memory", "polymarket", "signals.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

app.MapGet("/api/polymarket/trades", () =>
{
    var path = Path.Combine(systemRoot, "memory", "polymarket", "paper_trades.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

// LEGAL ENDPOINTS — active case management
app.MapGet("/api/legal/cases", () =>
{
    var legalDir = Path.Combine(systemRoot, "cases");
    if (!Directory.Exists(legalDir)) return Results.NotFound();
    var cases = Directory.GetDirectories(legalDir).Select(d => new { id = Path.GetFileName(d), files = Directory.GetFiles(d).Select(f => Path.GetFileName(f)).ToList() }).ToList();
    return Results.Ok(cases);
});

app.MapGet("/api/legal/brief", () =>
{
    var path = Path.Combine(systemRoot, "memory", "legal", "cases");
    if (!Directory.Exists(path)) return Results.NotFound();
    var files = Directory.GetDirectories(path).Select(d => new { id = Path.GetFileName(d), files = Directory.GetFiles(d, "*.md").Select(f => Path.GetFileName(f)).ToList() }).ToList();
    return Results.Ok(files);
});

// INCOME OPS ENDPOINTS — passive income play ranking
app.MapGet("/api/income/plays", () =>
{
    var briefPath = Path.Combine(systemRoot, "memory", "comet_x9", "compressed", "latest-brief.json");
    if (!File.Exists(briefPath)) return Results.NotFound();
    var brief = JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(briefPath));
    var plays = brief.TryGetProperty("all_findings", out var findings) ? findings.EnumerateArray().Where(f => f.TryGetProperty("type", out var t) && t.GetString() == "income_play").ToList() : new List<JsonElement>();
    return Results.Ok(plays);
});

// ORCHESTRATOR ENDPOINTS — main SYNAPSE 24/7 loop
app.MapGet("/api/orchestrator/status", () =>
{
    var statePath = Path.Combine(systemRoot, "config", "system_state.json");
    return File.Exists(statePath) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(statePath))) : Results.NotFound();
});

app.MapGet("/api/orchestrator/risk-state", () =>
{
    var path = Path.Combine(systemRoot, "memory", "risk_state.json");
    return File.Exists(path) ? Results.Json(JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(path))) : Results.NotFound();
});

app.MapPost("/api/orchestrator/cycle", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "python.exe"),
        Arguments = "src/oneness_orchestrator.py --once",
        RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(30000);
    return Results.Text(proc?.StandardOutput.ReadToEnd() ?? "", "application/json");
});

// PROGRESSION ENDPOINTS — gates and bosses
app.MapGet("/api/progression/gates", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "prime.exe"),
        Arguments = "gates --json",
        RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(10000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    try { return Results.Json(JsonSerializer.Deserialize<JsonElement>(output)); }
    catch { return Results.Text(output); }
});

app.MapGet("/api/progression/sabotage", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = Path.Combine(systemRoot, "venv", "Scripts", "prime.exe"),
        Arguments = "sabotage --json",
        RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(10000);
    var output = proc?.StandardOutput.ReadToEnd() ?? "";
    try { return Results.Json(JsonSerializer.Deserialize<JsonElement>(output)); }
    catch { return Results.Text(output); }
});

// SWARM ENDPOINTS — CPU/RAM/Disk/Service bots
app.MapGet("/api/swarm/report", () =>
{
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = "powershell.exe",
        Arguments = "-ExecutionPolicy Bypass -File \"" + Path.Combine(systemRoot, "run-swarm.ps1") + "\"",
        RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(30000);
    return Results.Text(proc?.StandardOutput.ReadToEnd() ?? "", "text/plain");
});

// CHROME ENDPOINT — launch free web browser
app.MapPost("/api/chrome/launch", () =>
{
    var script = Path.Combine(systemRoot, "scripts", "integrations", "launch_chrome.ps1");
    if (!File.Exists(script)) return Results.NotFound("Chrome launcher script not found");
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = "powershell.exe",
        Arguments = "-ExecutionPolicy Bypass -File \"" + script + "\"",
        RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false,
        WorkingDirectory = systemRoot
    };
    using var proc = System.Diagnostics.Process.Start(psi);
    proc?.WaitForExit(5000);
    return Results.Text(proc?.StandardOutput.ReadToEnd() ?? "Chrome launched", "text/plain");
});

// CONFIG ENDPOINTS — system configuration
app.MapGet("/api/config/agents", () =>
{
    var path = Path.Combine(systemRoot, "config", "agents.yaml");
    return File.Exists(path) ? Results.File(path, "text/yaml") : Results.NotFound();
});

app.Run();
